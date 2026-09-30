--!strict
-- Increment A (+ correction pass) of Task #23 (training ground first
-- playable slice).
--
-- Owns only: player entry/exit into the training area, temporary session
-- state, HP/MP/Stamina resets, and cleanup on death/respawn/disconnect.
-- Everything else in the full #23 spec (attack dummies with server damage
-- display, timed practice source, training potions, class presets, rifles /
-- shields) is OUT OF SCOPE for this increment and is not implemented here.
--
-- Design constraints this file must satisfy:
--   * No second combat core: all damage/ruleset logic stays in CombatCore /
--     CombatService. This service only toggles ruleset + resets vitals,
--     using the shared pure TrainingSession state machine for bookkeeping.
--   * No persistent-data writes: PlayerDataService is never called from
--     here, in either direction. Training is purely an in-memory session.
--   * Restores the player's *actual prior* ruleset (not a hardcoded "PvE")
--     on exit, death, CharacterRemoving, and disconnect, so a player who was
--     e.g. already in a "PvP" arena ruleset before wandering into training
--     is put back the way they were, not force-switched to PvE.
--   * Enter requires a registered, living combatant and a successful vitals
--     reset BEFORE the session is allowed to claim training membership.
--   * Safe repeat entry/exit and disconnect: a player who enters, leaves,
--     re-enters, dies inside, or disconnects mid-session must never end up
--     with leftover Training ruleset state or partially-applied resets.
--
-- World hookup (data-driven, no scripting required per zone):
--   Tag a Part (or the whole region trigger) in Workspace with
--   CollectionService tag "TrainingEntrance" to mark the zone volume; any
--   BasePart tagged "TrainingExit" teleports/returns a player to the world.
--   If a map does not yet have these parts, this service simply stays idle
--   (documented as a dependency below and in the smoke test doc).
--
-- Public API:
--   TrainingGroundService:IsTraining(player) -> boolean
--   TrainingGroundService:Enter(player) -> (boolean, string?)
--   TrainingGroundService:Exit(player) -> (boolean, string?)
--   TrainingGroundService:ResetSupplies(player) -> boolean   HP/MP/Stamina only

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TrainingSession = require(ReplicatedStorage.Shared.Combat.TrainingSession)

local TrainingGroundService = {
	Priority = 20, -- after CombatService (0) and TrainingDummyService (10)
}

local ENTRANCE_TAG = "TrainingEntrance"
local EXIT_TAG = "TrainingExit"
local EXIT_SPAWN_TAG = "TrainingReturnSpawn" -- optional BasePart; world entry point on exit
local TOUCH_DEBOUNCE = 1 -- seconds, per player per trigger kind
local TRAINING_RULESET = "Training"

local combat: any -- CombatService, resolved in Init

-- Session bookkeeping lives in the shared pure module (unit-tested directly
-- in tests/training_ground_spec.luau against this same module, not a copy).
local session = TrainingSession.new()
local lastTouch: { [Player]: { Enter: number, Exit: number } } = {}
local characterConnections: { [Player]: { RBXScriptConnection } } = {}

local function playerId(player: Player): string
	return tostring(player.UserId)
end

local function now(): number
	return os.clock()
end

local function debounced(player: Player, kind: "Enter" | "Exit"): boolean
	local record = lastTouch[player]
	if record == nil then
		record = { Enter = 0, Exit = 0 }
		lastTouch[player] = record
	end
	local t = now()
	if t - record[kind] < TOUCH_DEBOUNCE then
		return false
	end
	record[kind] = t
	return true
end

local function findTaggedSpawn(tag: string): BasePart?
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsA("BasePart") then
			return instance
		end
	end
	return nil
end

function TrainingGroundService:IsTraining(player: Player): boolean
	return session:IsTraining(playerId(player))
end

-- Resets only HP/MP/Stamina (the combat vitals). Does not change ruleset or
-- training membership; safe to call any time the player has a live combatant.
function TrainingGroundService:ResetSupplies(player: Player): boolean
	local character = player.Character
	if character == nil then
		return false
	end
	return combat:ResetVitals(character)
end

-- Enters the training ground: requires a registered, living combatant;
-- resets vitals FIRST, and only claims training membership (and switches
-- the ruleset) once that reset succeeds. Captures the player's current
-- ruleset so Exit/death/disconnect can restore it exactly, instead of
-- assuming "PvE". Idempotent: entering while already training just
-- refreshes the reset and leaves the originally captured prior ruleset
-- untouched.
function TrainingGroundService:Enter(player: Player): (boolean, string?)
	local character = player.Character
	if character == nil then
		return false, "NoCharacter"
	end
	local combatant = combat:GetCombatant(character)
	if combatant == nil or not combatant.Alive then
		return false, "NotRegisteredOrDead"
	end

	local alreadyTraining = session:IsTraining(playerId(player))
	local priorRuleset = if alreadyTraining then nil else combat:GetRuleset(player)

	-- Reset BEFORE claiming training membership: if this somehow fails
	-- (e.g. race with death/unregister), do not leave the player flagged
	-- as training with a stale ruleset.
	local resetOk = combat:ResetVitals(character)
	if not resetOk then
		return false, "ResetFailed"
	end

	if not alreadyTraining then
		session:Enter(playerId(player), priorRuleset :: string)
	end
	combat:SetRuleset(player, TRAINING_RULESET)
	return true, nil
end

local function restoreRuleset(player: Player, priorRuleset: string?)
	if priorRuleset == nil then
		return
	end
	combat:SetRuleset(player, priorRuleset)
end

-- Exits the training ground: restores the player's *actual prior* ruleset
-- (captured on Enter) and resets vitals again so no temporary training
-- buff/debuff or resource state leaks back into the normal world. Safe to
-- call even if the player already left (e.g. via death cleanup racing a
-- manual exit trigger).
function TrainingGroundService:Exit(player: Player): (boolean, string?)
	local priorRuleset = session:Exit(playerId(player))
	if priorRuleset == nil then
		return false, "NotTraining"
	end
	restoreRuleset(player, priorRuleset)
	local character = player.Character
	if character then
		combat:ResetVitals(character)
		local spawn = findTaggedSpawn(EXIT_SPAWN_TAG)
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if spawn and root then
			root.CFrame = spawn.CFrame + Vector3.new(0, 3, 0)
		end
	end
	return true, nil
end

local function onEntranceTouched(hit: BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	if character == nil then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if player == nil or TrainingGroundService:IsTraining(player) then
		return
	end
	if not debounced(player, "Enter") then
		return
	end
	TrainingGroundService:Enter(player)
end

local function onExitTouched(hit: BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	if character == nil then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if player == nil or not TrainingGroundService:IsTraining(player) then
		return
	end
	if not debounced(player, "Exit") then
		return
	end
	TrainingGroundService:Exit(player)
end

local function hookZonePart(instance: Instance, handler: (BasePart) -> ())
	if instance:IsA("BasePart") then
		instance.Touched:Connect(handler)
	end
end

-- Clears training membership and restores the prior ruleset without any
-- character/vitals work, for paths (CharacterRemoving, disconnect) where the
-- old Model/Humanoid may already be gone or on the way out.
local function forceExit(player: Player)
	local priorRuleset = session:Exit(playerId(player))
	if priorRuleset then
		restoreRuleset(player, priorRuleset)
	end
end

local function disconnectCharacterListeners(player: Player)
	local connections = characterConnections[player]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
		characterConnections[player] = nil
	end
end

-- Hooks CharacterRemoving for a player so that death or respawn while
-- training always restores the prior ruleset instead of merely clearing a
-- flag (the prior bug: Training survived respawn because only the flag was
-- cleared and the *new* character re-read playerRuleset, which was never
-- reset away from "Training"). Safe to call multiple times per player; old
-- listeners are disconnected first.
local function hookCharacterRemoving(player: Player)
	disconnectCharacterListeners(player)
	local connections: { RBXScriptConnection } = {}
	characterConnections[player] = connections
	local character = player.Character
	if character then
		table.insert(
			connections,
			character:GetPropertyChangedSignal("Parent"):Connect(function() end)
		)
		table.insert(
			connections,
			character.AncestryChanged:Connect(function(_, parent)
				if parent == nil and TrainingGroundService:IsTraining(player) then
					forceExit(player)
				end
			end)
		)
	end
end

function TrainingGroundService:Init(registry)
	combat = registry.CombatService
	combat:SetTrainingPredicate(function(player: Player): boolean
		return TrainingGroundService:IsTraining(player)
	end)
end

function TrainingGroundService:Start()
	for _, instance in CollectionService:GetTagged(ENTRANCE_TAG) do
		hookZonePart(instance, onEntranceTouched)
	end
	CollectionService:GetInstanceAddedSignal(ENTRANCE_TAG):Connect(function(instance)
		hookZonePart(instance, onEntranceTouched)
	end)

	for _, instance in CollectionService:GetTagged(EXIT_TAG) do
		hookZonePart(instance, onExitTouched)
	end
	CollectionService:GetInstanceAddedSignal(EXIT_TAG):Connect(function(instance)
		hookZonePart(instance, onExitTouched)
	end)

	-- Death inside the training ground must restore the prior ruleset, not
	-- just clear the flag: the respawned character reads whatever ruleset
	-- CombatService currently has stored for the player, so if that is left
	-- as "Training" the new character silently stays in training rules.
	combat.Killed:Connect(function(victimModel: Model)
		local player = Players:GetPlayerFromCharacter(victimModel)
		if player and TrainingGroundService:IsTraining(player) then
			forceExit(player)
		end
	end)

	-- Track CharacterRemoving per player (covers death-without-Killed-event
	-- edge cases, and respawn/teleport) so training never survives past the
	-- character that was actually in the zone. Handles both already-present
	-- players and ones who join later.
	local function onPlayerAdded(player: Player)
		hookCharacterRemoving(player)
		player.CharacterAdded:Connect(function()
			hookCharacterRemoving(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	-- Disconnect cleanup: no persistent writes ever happened, so all that is
	-- needed is dropping the in-memory flags to avoid leaking session state,
	-- and restoring the prior ruleset in case CombatService keeps the
	-- playerRuleset entry alive for any reason during teardown ordering.
	Players.PlayerRemoving:Connect(function(player)
		forceExit(player)
		disconnectCharacterListeners(player)
		lastTouch[player] = nil
	end)
end

return TrainingGroundService
