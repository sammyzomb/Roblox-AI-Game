--!strict
-- Increment A of Task #23 (training ground first playable slice).
--
-- Owns only: player entry/exit into the training area, temporary session
-- state, HP/MP/Stamina resets, and cleanup on death/respawn/disconnect.
-- Everything else in the full #23 spec (attack dummies with server damage
-- display, timed practice source, training potions, class presets, rifles /
-- shields) is OUT OF SCOPE for this increment and is not implemented here.
--
-- Design constraints this file must satisfy:
--   * No second combat core: all damage/ruleset logic stays in CombatCore /
--     CombatService. This service only toggles ruleset + resets vitals.
--   * No persistent-data writes: PlayerDataService is never called from here,
--     in either direction. Training is purely an in-memory session flag.
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

local TrainingGroundService = {
	Priority = 20, -- after CombatService (0) and TrainingDummyService (10)
}

local ENTRANCE_TAG = "TrainingEntrance"
local EXIT_TAG = "TrainingExit"
local EXIT_SPAWN_TAG = "TrainingReturnSpawn" -- optional BasePart; world entry point on exit
local TOUCH_DEBOUNCE = 1 -- seconds, per player per trigger kind

local combat: any -- CombatService, resolved in Init

-- Player -> true while inside the training ground. In-memory only; never
-- persisted, never read by PlayerDataService.
local training: { [Player]: boolean } = {}
local lastTouch: { [Player]: { Enter: number, Exit: number } } = {}

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
	return training[player] == true
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

-- Enters the training ground: switches the player's combat ruleset to
-- "Training" and restores full HP/MP/Stamina so every session starts clean.
-- Idempotent: entering while already training just refreshes the reset.
function TrainingGroundService:Enter(player: Player): (boolean, string?)
	local character = player.Character
	if character == nil then
		return false, "NoCharacter"
	end
	training[player] = true
	combat:SetRuleset(player, "Training")
	combat:ResetVitals(character)
	return true, nil
end

-- Exits the training ground: restores the default (PvE) ruleset and resets
-- vitals again so no temporary training buff/debuff or resource state leaks
-- back into the normal world. Safe to call even if the player already left
-- (e.g. via death cleanup racing a manual exit trigger).
function TrainingGroundService:Exit(player: Player): (boolean, string?)
	if not training[player] then
		return false, "NotTraining"
	end
	training[player] = nil
	combat:SetRuleset(player, "PvE")
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

function TrainingGroundService:Init(registry)
	combat = registry.CombatService
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

	-- Death inside the training ground must not carry any training state
	-- (ruleset, leftover flag) into the respawned character; the respawned
	-- character re-registers with CombatService under the default ruleset,
	-- so it is enough to clear the membership flag and let a fresh Enter
	-- touch re-establish training if the player walks back in.
	combat.Killed:Connect(function(victimModel: Model)
		local player = Players:GetPlayerFromCharacter(victimModel)
		if player and training[player] then
			training[player] = nil
			-- The player's *next* character starts on the default ruleset
			-- because CombatService assigns playerRuleset/DefaultRuleset on
			-- CharacterAdded; nothing further to reset here since the old
			-- combatant is being torn down with the model.
		end
	end)

	-- Disconnect cleanup: no persistent writes ever happened, so all that is
	-- needed is dropping the in-memory flags to avoid leaking session state.
	Players.PlayerRemoving:Connect(function(player)
		training[player] = nil
		lastTouch[player] = nil
	end)
end

return TrainingGroundService
