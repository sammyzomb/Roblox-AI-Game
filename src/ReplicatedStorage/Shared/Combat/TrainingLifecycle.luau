--!strict
-- Training-ground lifecycle orchestration (Task #23 corrective increment).
--
-- This module is the actual production decision logic that
-- TrainingGroundService.luau drives from real Roblox events
-- (Player.CharacterRemoving / Players.PlayerRemoving / CombatService.Killed).
-- It is Roblox-API-free so it can be unit tested
-- directly, but it is NOT a re-implemented/copied state machine: it is the
-- one place that decides whether a ruleset restore is allowed to happen, and
-- TrainingGroundService contains no parallel copy of this logic. It wraps
-- TrainingSession (membership bookkeeping) and adds the two pieces of state
-- that session alone cannot express:
--
--   1. Which *character generation* currently owns a training session, so a
--      stale/delayed removal callback for an OLD character can never clear a
--      session that a NEWER character already (re-)entered.
--   2. Whether a player has *departed* (PlayerRemoving fired), so that any
--      callback arriving after disconnect - in either cleanup order, and
--      regardless of how late a delayed CharacterRemoving/Killed callback
--      fires - can never call back into CombatService:SetRuleset and
--      recreate playerRuleset state for a player who is gone.
--
-- A thin "combat" dependency (SetRuleset/ResetVitals/GetRuleset/
-- GetCombatant/ApplyDefaultTrainingPreset/RestoreSavedLoadout) is injected
-- so tests can supply a fake without any Roblox services;
-- TrainingGroundService injects the real CombatService. This module does
-- not store a second copy of the chosen preset: the live combatant loadout
-- is the only copy, and a re-entry while the session is already active does
-- not apply the default preset again.
--
-- Dual-environment load (production correction): this module is required
-- both by Roblox (TrainingGroundService.luau, via `script.Parent`) and by
-- the standalone Luau test runner (`tests/run.luau`, via the Luau CLI's
-- path-based `require("../src/...")`), which has no `script` global at all.
-- Referencing the undefined global `script` itself is safe in plain Luau
-- (globals that were never assigned simply read as nil); only *indexing*
-- a nil `script` (e.g. `script.Parent`) would error. So the require below
-- branches on that, instead of duplicating TrainingSession's logic or
-- maintaining a second copy for tests.
local TrainingSession
if script then
	TrainingSession = require(script.Parent.TrainingSession)
else
	TrainingSession = require("./TrainingSession")
end

-- Keys used by this module (player, character) are opaque identities: in
-- Roblox they are real Player/Model instances; in tests they may be plain
-- fake tables. Either way they must never be converted to a display name or
-- `tostring`-ed for use as a table key: two different players can share a
-- display Name (or a renamed-mid-session Player keeps the same identity but
-- a different Name), and `tostring` on a Roblox Instance returns its Name,
-- not a stable unique id. All bookkeeping below is therefore keyed by the
-- player/character value itself (object identity), exactly like
-- CombatService's own byPlayer/playerRuleset tables. This module has no
-- Roblox-only `Instance` type dependency: identities are typed `unknown` so
-- the module stays loadable where tests pass in plain fake tables.
export type PlayerId = unknown
export type CharacterId = unknown

export type CombatAdapter = {
	GetCombatant: (model: CharacterId) -> { Alive: boolean }?,
	GetRuleset: (player: PlayerId) -> string,
	SetRuleset: (player: PlayerId, rulesetId: string) -> (),
	ResetVitals: (model: CharacterId) -> boolean,
	-- First successful entry only. Must be called after membership is claimed
	-- so CombatService's training predicate can see the session.
	ApplyDefaultTrainingPreset: (player: PlayerId) -> (boolean, string?),
	-- Live manual exit, and rollback when the initial preset fails.
	-- Death, respawn, and disconnect must not call this.
	RestoreSavedLoadout: (player: PlayerId) -> (boolean, string?),
}

export type Lifecycle = {
	-- The dual require binds TrainingSession from two paths, so Luau will not
	-- read the exported name `TrainingSession.Session` off that union.
	-- `new` is annotated to return that same Session type.
	_session: typeof(TrainingSession.new()),
	_combat: CombatAdapter,
	_generation: { [PlayerId]: CharacterId }, -- player -> character that currently owns any session
	_departed: { [PlayerId]: boolean }, -- weak-keyed: see Lifecycle.new
}

local TrainingLifecycle = {}
TrainingLifecycle.__index = TrainingLifecycle

local TRAINING_RULESET = "Training"

function TrainingLifecycle.new(combat: CombatAdapter): Lifecycle
	return setmetatable({
		_session = TrainingSession.new(),
		_combat = combat,
		_generation = {},
		-- Weak-keyed tombstone set: once a Player object becomes otherwise
		-- unreferenced (normal Roblox teardown after disconnect), this entry
		-- can be collected instead of retaining every departed Player for
		-- the lifetime of the server. A departed id is only ever consulted
		-- while callbacks for that same player instance could still be in
		-- flight (shortly after PlayerRemoving); once nothing else holds the
		-- instance, there is nothing left that could call back in, so
		-- collection is safe. `__mode = "k"` works for both Roblox Instances
		-- and plain tables used as fake ids in tests.
		_departed = setmetatable({}, { __mode = "k" }) :: any,
	}, TrainingLifecycle) :: any
end

function TrainingLifecycle.IsTraining(self: Lifecycle, player: PlayerId): boolean
	return self._session:IsTraining(player)
end

-- Entry requires: player has not departed, has a character, and the
-- character resolves to a registered, living combatant. Vitals are reset
-- BEFORE training membership is claimed; a reset failure must never leave
-- the player flagged as training. On success, the character that just
-- entered becomes the one and only owner of the session (its "generation"),
-- so a later removal of a *different* (older or already-replaced) character
-- can never tear this session down.
function TrainingLifecycle.Enter(self: Lifecycle, player: PlayerId, character: CharacterId?): (boolean, string?)
	if self._departed[player] then
		return false, "Departed"
	end
	if character == nil then
		return false, "NoCharacter"
	end
	local combatant = self._combat.GetCombatant(character)
	if combatant == nil or not combatant.Alive then
		return false, "NotRegisteredOrDead"
	end

	local alreadyTraining = self._session:IsTraining(player)
	local priorRuleset = if alreadyTraining then nil else self._combat.GetRuleset(player)

	local resetOk = self._combat.ResetVitals(character)
	if not resetOk then
		return false, "ResetFailed"
	end

	if not alreadyTraining then
		self._session:Enter(player, priorRuleset :: string)
	end
	-- Rebind ownership to the character that is entering right now, even if
	-- this is a re-entry under the same session: only the current character
	-- may ever trigger a restore for this player.
	self._generation[player] = character
	self._combat.SetRuleset(player, TRAINING_RULESET)
	if not alreadyTraining then
		-- Membership is already claimed, so the combat service can see an
		-- active training session. A later Enter in this same session must
		-- not apply the default preset again.
		local applied, applyWhy = self._combat.ApplyDefaultTrainingPreset(player)
		if not applied then
			local prior = self._session:Exit(player)
			self._generation[player] = nil
			if not self._departed[player] then
				if prior ~= nil then
					self._combat.SetRuleset(player, prior)
				end
				self._combat.RestoreSavedLoadout(player)
			end
			return false, applyWhy or "PresetFailed"
		end
	end
	return true, nil
end

-- Restores the ruleset captured on Enter, unless the player has departed
-- (in which case restoring would recreate state CombatService just tore
-- down). Always clears local bookkeeping regardless of departed state so no
-- stale generation/membership can linger.
local function restore(self: Lifecycle, player: PlayerId): (boolean, string?)
	local priorRuleset = self._session:Exit(player)
	self._generation[player] = nil
	if priorRuleset == nil then
		return false, "NotTraining"
	end
	if self._departed[player] then
		-- Do not call back into CombatService for a player who is gone.
		return true, nil
	end
	self._combat.SetRuleset(player, priorRuleset)
	return true, nil
end

-- Manual/zone exit: also resets vitals so no temporary state leaks back to
-- the normal world. No-op (returns false, "NotTraining") if the player was
-- not training. If the ruleset/session cleanup already completed but the
-- vitals reset itself fails (e.g. the character was removed/unregistered in
-- the same instant), this reports a distinct "ResetFailed" failure instead
-- of silently claiming success, while leaving the already-completed
-- restore/session cleanup in place (it is not safe or necessary to undo).
function TrainingLifecycle.Exit(self: Lifecycle, player: PlayerId, character: CharacterId?): (boolean, string?)
	local wasTraining = self._session:IsTraining(player)
	-- A live manual exit restores the saved loadout before the session is
	-- dropped. If that restore fails, membership and the Training ruleset
	-- stay in place so play does not resume on training gear. Death and
	-- disconnect do not use Exit; they leave the fresh character on the
	-- existing saved-loadout spawn path.
	if wasTraining and character ~= nil and not self._departed[player] then
		local resetOk = self._combat.ResetVitals(character)
		if resetOk then
			local restored, restoreWhy = self._combat.RestoreSavedLoadout(player)
			if not restored then
				return false, restoreWhy or "RestoreFailed"
			end
		end
	end
	local ok, why = restore(self, player)
	if not ok then
		return false, why
	end
	if character and not self._departed[player] then
		local resetOk = self._combat.ResetVitals(character)
		if not resetOk then
			return false, "ResetFailed"
		end
	end
	return wasTraining, nil
end

-- Called when `character` is removed (death, respawn, teleport-out) for
-- `player`. Only restores/clears if `character` is still the generation
-- that owns the current session; a removal callback for an old character
-- that already lost ownership (because a newer character entered, or the
-- session was already exited) is a safe no-op.
function TrainingLifecycle.OnCharacterRemoved(self: Lifecycle, player: PlayerId, character: CharacterId)
	if self._generation[player] ~= character then
		return
	end
	restore(self, player)
end

-- Called once from Players.PlayerRemoving. Marks the player departed BEFORE
-- dropping session/generation state so any callback that is already queued
-- or arrives later (delayed CharacterRemoving, a Killed event racing
-- disconnect, duplicate PlayerRemoving-style cleanup) sees `_departed` and
-- takes the no-callback path in `restore`, instead of recreating
-- playerRuleset after CombatService has already cleared it. Safe to call
-- more than once (idempotent) and safe regardless of whether CombatService's
-- own PlayerRemoving handler has already run. `_departed` is weak-keyed (see
-- Lifecycle.new) so this does not retain the Player object for the whole
-- server lifetime once nothing else references it.
function TrainingLifecycle.OnPlayerRemoving(self: Lifecycle, player: PlayerId)
	self._departed[player] = true
	self._session:Exit(player) -- drop membership, discard the prior ruleset: never restored for a departed player
	self._generation[player] = nil
end

return TrainingLifecycle
