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
-- GetCombatant) is injected so tests can supply a fake without any Roblox
-- services; TrainingGroundService injects the real CombatService.

local TrainingSession = require(script.Parent.TrainingSession)

export type CombatAdapter = {
	GetCombatant: (model: Instance) -> { Alive: boolean }?,
	GetRuleset: (player: Instance) -> string,
	SetRuleset: (player: Instance, rulesetId: string) -> (),
	ResetVitals: (model: Instance) -> boolean,
}

export type Lifecycle = {
	_session: TrainingSession.Session,
	_combat: CombatAdapter,
	_generation: { [Instance]: Instance }, -- player -> character that currently owns any session
	_departed: { [Instance]: boolean },
}

local TrainingLifecycle = {}
TrainingLifecycle.__index = TrainingLifecycle

local TRAINING_RULESET = "Training"

function TrainingLifecycle.new(combat: CombatAdapter): Lifecycle
	return setmetatable({
		_session = TrainingSession.new(),
		_combat = combat,
		_generation = {},
		_departed = {},
	}, TrainingLifecycle) :: any
end

local function id(player: Instance): string
	return tostring(player)
end

function TrainingLifecycle.IsTraining(self: Lifecycle, player: Instance): boolean
	return self._session:IsTraining(id(player))
end

-- Entry requires: player has not departed, has a character, and the
-- character resolves to a registered, living combatant. Vitals are reset
-- BEFORE training membership is claimed; a reset failure must never leave
-- the player flagged as training. On success, the character that just
-- entered becomes the one and only owner of the session (its "generation"),
-- so a later removal of a *different* (older or already-replaced) character
-- can never tear this session down.
function TrainingLifecycle.Enter(self: Lifecycle, player: Instance, character: Instance?): (boolean, string?)
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

	local alreadyTraining = self._session:IsTraining(id(player))
	local priorRuleset = if alreadyTraining then nil else self._combat.GetRuleset(player)

	local resetOk = self._combat.ResetVitals(character)
	if not resetOk then
		return false, "ResetFailed"
	end

	if not alreadyTraining then
		self._session:Enter(id(player), priorRuleset :: string)
	end
	-- Rebind ownership to the character that is entering right now, even if
	-- this is a re-entry under the same session: only the current character
	-- may ever trigger a restore for this player.
	self._generation[player] = character
	self._combat.SetRuleset(player, TRAINING_RULESET)
	return true, nil
end

-- Restores the ruleset captured on Enter, unless the player has departed
-- (in which case restoring would recreate state CombatService just tore
-- down). Always clears local bookkeeping regardless of departed state so no
-- stale generation/membership can linger.
local function restore(self: Lifecycle, player: Instance): (boolean, string?)
	local priorRuleset = self._session:Exit(id(player))
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
-- the normal world. No-op (returns false) if the player was not training.
function TrainingLifecycle.Exit(self: Lifecycle, player: Instance, character: Instance?): (boolean, string?)
	local wasTraining = self._session:IsTraining(id(player))
	local ok, why = restore(self, player)
	if not ok then
		return false, why
	end
	if character and not self._departed[player] then
		self._combat.ResetVitals(character)
	end
	return wasTraining, nil
end

-- Called when `character` is removed (death, respawn, teleport-out) for
-- `player`. Only restores/clears if `character` is still the generation
-- that owns the current session; a removal callback for an old character
-- that already lost ownership (because a newer character entered, or the
-- session was already exited) is a safe no-op.
function TrainingLifecycle.OnCharacterRemoved(self: Lifecycle, player: Instance, character: Instance)
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
-- own PlayerRemoving handler has already run.
function TrainingLifecycle.OnPlayerRemoving(self: Lifecycle, player: Instance)
	self._departed[player] = true
	self._session:Exit(id(player)) -- drop membership, discard the prior ruleset: never restored for a departed player
	self._generation[player] = nil
end

return TrainingLifecycle
