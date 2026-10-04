--!strict
-- Sends combat intent to the server. Weapon-agnostic: the actions below are
-- mapped to whatever attacks the equipped weapons define in data.
--
--   Action         Keyboard/Mouse   Gamepad   Touch
--   Attack         Left click       R2        on-screen button
--   Skill          Q                R1        on-screen button
--   Off-hand       R                L1        on-screen button
--   Block (hold)   F                L2        on-screen button
--   Potion         1                DPad Up   on-screen button
--
-- "Attack" uses the main-hand attack named "Primary" (or the first by name),
-- "Skill" uses the next main-hand attack, "Off-hand" the first off-hand attack.
-- The server validates everything; this only avoids pointless requests.
--
-- Public API:
--   CombatController.equip(slot, itemId | false)
--   CombatController.useItem(itemId)
--   CombatController.selectTrainingPreset(presetId)
--       Sends the existing CombatRequest action "TrainingPreset".
--       There is no selector UI and no extra touch button in this module.
--   CombatController.raycast(origin, direction) -> Vector3
--
-- A validated CombatEvent { Kind = "Loadout", MainHand, OffHand } replaces
-- the local attack map. A malformed Loadout event leaves the map as it was.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Definitions = require(Shared:WaitForChild("Combat"):WaitForChild("Definitions"))
local TrainingLoadouts = require(Shared:WaitForChild("Combat"):WaitForChild("TrainingLoadouts"))
local DamageFloatView = require(script.Parent.Parent:WaitForChild("DamageFloatView"))

local CombatController = {}

local defs = Definitions.get()
local request: RemoteEvent
local loadout: { [string]: string } = {}
local player = Players.LocalPlayer

local AIM_DISTANCE = 300

-- Attack ids of a weapon: "Primary" first, then alphabetical.
local function attackOrder(weaponId: string?): { string }
	local weapon = weaponId and defs.Weapons[weaponId]
	if not weapon then
		return {}
	end
	local ids = {}
	for id in weapon.Attacks do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		if a == "Primary" or b == "Primary" then
			return a == "Primary"
		end
		return a < b
	end)
	return ids
end

-- World point under the mouse / screen center (touch and gamepad).
local function aimPoint(): Vector3?
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local screen: Vector2
	if UserInputService.MouseEnabled and not UserInputService.TouchEnabled then
		screen = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(screen.X, screen.Y)
		return CombatController.raycast(ray.Origin, ray.Direction * AIM_DISTANCE)
	end
	local ray = camera:ViewportPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	return CombatController.raycast(ray.Origin, ray.Direction * AIM_DISTANCE)
end

function CombatController.raycast(origin: Vector3, direction: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if player.Character then { player.Character } else {}
	local result = Workspace:Raycast(origin, direction, params)
	return if result then result.Position else origin + direction
end

local function attack(slot: string, index: number)
	local ids = attackOrder(loadout[slot])
	local attackId = ids[index]
	if attackId then
		request:FireServer({ Action = "Attack", Slot = slot, AttackId = attackId, Aim = aimPoint() })
	end
end

local function onBegin(fn: () -> ())
	return function(_: string, state: Enum.UserInputState): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			fn()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end
end

local function onBlock(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		request:FireServer({ Action = "Block", Active = true })
		return Enum.ContextActionResult.Sink
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		request:FireServer({ Action = "Block", Active = false })
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

-- Public helpers for UI (inventory / equipment screens).
function CombatController.equip(slot: string, itemId: string | false)
	request:FireServer({ Action = "Equip", Slot = slot, ItemId = itemId })
end

function CombatController.useItem(itemId: string)
	request:FireServer({ Action = "UseItem", ItemId = itemId })
end

function CombatController.selectTrainingPreset(presetId: string)
	request:FireServer({ Action = TrainingLoadouts.SELECTION_ACTION, PresetId = presetId })
end

function CombatController:Init()
	request = Net.event(Net.Names.CombatRequest)
end

function CombatController:Start()
	Net.event(Net.Names.StateChanged).OnClientEvent:Connect(function(state)
		if type(state) == "table" and type(state.Loadout) == "table" then
			loadout = state.Loadout
		end
	end)
	task.spawn(function()
		local state = Net.func(Net.Names.GetState):InvokeServer()
		if type(state) == "table" and type(state.Loadout) == "table" then
			loadout = state.Loadout
		end
	end)

	ContextActionService:BindAction("CombatAttack", onBegin(function()
		attack("MainHand", 1)
	end), true, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	ContextActionService:BindAction("CombatSkill", onBegin(function()
		attack("MainHand", 2)
	end), true, Enum.KeyCode.Q, Enum.KeyCode.ButtonR1)
	ContextActionService:BindAction("CombatOffHand", onBegin(function()
		attack("OffHand", 1)
	end), true, Enum.KeyCode.R, Enum.KeyCode.ButtonL1)
	ContextActionService:BindAction("CombatBlock", onBlock, true, Enum.KeyCode.F, Enum.KeyCode.ButtonL2)
	ContextActionService:BindAction("CombatPotion", onBegin(function()
		CombatController.useItem("health_potion")
	end), true, Enum.KeyCode.One, Enum.KeyCode.DPadUp)

	ContextActionService:SetTitle("CombatAttack", "Attack")
	ContextActionService:SetTitle("CombatSkill", "Skill")
	ContextActionService:SetTitle("CombatOffHand", "Off")
	ContextActionService:SetTitle("CombatBlock", "Block")
	ContextActionService:SetTitle("CombatPotion", "Potion")

	Net.event(Net.Names.CombatEvent).OnClientEvent:Connect(function(event)
		-- Presentation hook: animations, VFX and SFX attach here (see docs/COMBAT_API.md).
		-- Hit labels read the server payload only. They do not recompute damage.
		if type(event) == "table" and event.Kind == "Loadout" then
			loadout = TrainingLoadouts.applyPresentedLoadout(loadout, event)
		elseif type(event) == "table" and event.Kind == "Rejected" then
			print(`[Combat] {event.Reason}`)
		end
		DamageFloatView.present(event)
	end)
end

return CombatController
