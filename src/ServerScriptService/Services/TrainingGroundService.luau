--!strict
-- Increment A (+ corrective pass) of Task #23 (training ground first
-- playable slice).
--
-- Owns only: player entry/exit into the training area, temporary session
-- state, HP/MP/Stamina resets, cleanup on death/respawn/disconnect, and
-- asking CombatService (through TrainingLifecycle) to apply or restore the
-- temporary training hands. This service does not keep a second preset or
-- session record. Rifles, training potions, and the preset picker UI are
-- still not implemented here.
-- Scene hookup (actual entrance/exit zone parts in a published place) is
-- explicitly deferred to the next increment; CollectionService tag wiring
-- below is idle until a map provides tagged parts.
--
-- Design constraints this file must satisfy:
--   * No second combat core: all damage/ruleset logic stays in CombatCore /
--     CombatService. This service only toggles ruleset + resets vitals.
--   * No persistent-data writes: PlayerDataService is never called from
--     here, in either direction. Training is purely an in-memory session.
--   * Lifecycle correctness (the subject of this corrective increment) is
--     delegated to the Roblox-API-free TrainingLifecycle module so the exact
--     rules are unit-tested against the real production logic, not a copy:
--       - Enter rejects a departed player, a missing character, or a
--         character that is not a registered, living combatant; vitals are
--         reset BEFORE training membership is claimed.
--       - Only the character that most recently entered owns the session
--         ("generation"); a removal callback for an older/already-replaced
--         character can never clear a newer session.
--       - Once a player has disconnected (PlayerRemoving), no later
--         callback (delayed CharacterRemoving, a race with CombatService's
--         own PlayerRemoving handler, repeated calls) can call back into
--         CombatService:SetRuleset and recreate ruleset state for them.
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

local TrainingLifecycle = require(ReplicatedStorage.Shared.Combat.TrainingLifecycle)
local TrainingLoadouts = require(ReplicatedStorage.Shared.Combat.TrainingLoadouts)

local TrainingGroundService = {
	Priority = 20, -- after CombatService (0) and TrainingDummyService (10)
}

local ENTRANCE_TAG = "TrainingEntrance"
local EXIT_TAG = "TrainingExit"
local EXIT_SPAWN_TAG = "TrainingReturnSpawn" -- optional BasePart; world entry point on exit
local TOUCH_DEBOUNCE = 1 -- seconds, per player per trigger kind

local combat: any -- CombatService, resolved in Init
local lifecycle: TrainingLifecycle.Lifecycle

local lastTouch: { [Player]: { Enter: number, Exit: number } } = {}
local playerConnections: { [Player]: { RBXScriptConnection } } = {}

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
	return lifecycle:IsTraining(player)
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

-- Enters the training ground: delegates all admission/ownership rules to
-- TrainingLifecycle (see module header). Idempotent re-entry refreshes the
-- reset and keeps the originally captured prior ruleset.
function TrainingGroundService:Enter(player: Player): (boolean, string?)
	return lifecycle:Enter(player, player.Character)
end

-- Exits the training ground: restores the player's actual prior ruleset and
-- resets vitals again so no temporary training state leaks back into the
-- normal world. Safe to call even if the player already left.
function TrainingGroundService:Exit(player: Player): (boolean, string?)
	local ok, why = lifecycle:Exit(player, player.Character)
	if not ok then
		return false, why
	end
	local character = player.Character
	if character then
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

local function disconnectPlayerListeners(player: Player)
	local connections = playerConnections[player]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
		playerConnections[player] = nil
	end
end

-- Hooks the REAL Player.CharacterRemoving signal (the prior version of this
-- file connected a no-op Parent-changed listener and AncestryChanged
-- instead, which never fired on ordinary death/respawn). This service does
-- not need CharacterAdded: entry is driven by the entrance zone touch
-- handler (onEntranceTouched) reading player.Character at touch time, not by
-- a join/respawn hook. CharacterRemoving still has the removed character as
-- its argument, so it is passed straight to
-- TrainingLifecycle:OnCharacterRemoved, which only acts if that exact
-- character still owns the current session - a stale callback for an old
-- character can never clear a newer one. Connections are tracked per player
-- and fully torn down on disconnect.
local function hookPlayer(player: Player)
	disconnectPlayerListeners(player)
	local connections: { RBXScriptConnection } = {}
	playerConnections[player] = connections

	table.insert(
		connections,
		player.CharacterRemoving:Connect(function(character: Model)
			lifecycle:OnCharacterRemoved(player, character)
		end)
	)
end

function TrainingGroundService:Init(registry)
	combat = registry.CombatService
	-- Adapter closures are typed `unknown` at the parameter to exactly match
	-- TrainingLifecycle.CombatAdapter (kept Roblox-API-free for the
	-- standalone test runner); the real values passed in here from
	-- TrainingGroundService's own Player/Model-typed API are always actual
	-- Roblox Instances, cast back immediately at this one boundary.
	lifecycle = TrainingLifecycle.new({
		GetCombatant = function(model: unknown)
			return combat:GetCombatant(model :: Model)
		end,
		GetRuleset = function(player: unknown)
			return combat:GetRuleset(player :: Player)
		end,
		SetRuleset = function(player: unknown, rulesetId: string)
			combat:SetRuleset(player :: Player, rulesetId)
		end,
		ResetVitals = function(model: unknown)
			return combat:ResetVitals(model :: Model)
		end,
		ApplyDefaultTrainingPreset = function(player: unknown)
			return combat:ApplyTrainingPreset(player :: Player, TrainingLoadouts.DEFAULT_PRESET_ID)
		end,
		RestoreSavedLoadout = function(player: unknown)
			return combat:RestorePersistentLoadout(player :: Player)
		end,
	})
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
	-- just clear the flag. CharacterRemoving (hooked below) also covers this
	-- for the common case; Killed is kept as a second, idempotent path since
	-- it carries the exact victim model and may fire before CharacterRemoving
	-- in some teardown orders.
	combat.Killed:Connect(function(victimModel: Model)
		local player = Players:GetPlayerFromCharacter(victimModel)
		if player then
			lifecycle:OnCharacterRemoved(player, victimModel)
		end
	end)

	Players.PlayerAdded:Connect(hookPlayer)
	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end

	-- Disconnect cleanup: mark the player departed in TrainingLifecycle
	-- FIRST (before disconnecting listeners), so any already-queued or
	-- in-flight callback (delayed CharacterRemoving, a Killed event racing
	-- disconnect) sees the departed flag and takes the no-op-restore path
	-- instead of calling CombatService:SetRuleset after CombatService's own
	-- PlayerRemoving handler has cleared playerRuleset for this player. This
	-- is correct regardless of which PlayerRemoving handler (this service's
	-- or CombatService's) happens to run first.
	Players.PlayerRemoving:Connect(function(player)
		lifecycle:OnPlayerRemoving(player)
		disconnectPlayerListeners(player)
		lastTouch[player] = nil
	end)
end

return TrainingGroundService
