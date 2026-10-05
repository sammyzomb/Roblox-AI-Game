--!strict
-- Placeholder selector for the three temporary training presets.
--
-- Visible only while CombatController's cached presentation says so. That
-- cache is updated from the one CombatEvent listener in CombatController.
-- This script does not listen to CombatEvent and does not send item ids.
-- Activated covers mouse and touch. The click only calls
-- selectTrainingPreset; the highlight waits for the server Loadout.
--
-- Placement: left side, just below the top coin/level HUD (that panel ends
-- near y=96). Width stays on the left so it does not cover the centered
-- bottom stamina/mana bars or the bottom-right ContextActionService combat
-- buttons. Each option is 48 px tall. This is not final art.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TrainingLoadouts = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Combat"):WaitForChild("TrainingLoadouts"))
local CombatController = require(Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Controllers"):WaitForChild("CombatController"))

local BUTTON_HEIGHT = 48
local PANEL_WIDTH = 148
local PANEL_PADDING = 8
local BUTTON_GAP = 6

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "TrainingPresetHUD"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 6
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Presets"
panel.AnchorPoint = Vector2.new(0, 0)
panel.Position = UDim2.fromOffset(12, 108)
panel.Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_PADDING * 2 + BUTTON_HEIGHT * #TrainingLoadouts.PRESET_IDS + BUTTON_GAP * math.max(#TrainingLoadouts.PRESET_IDS - 1, 0))
panel.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel = 0
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, PANEL_PADDING)
padding.PaddingBottom = UDim.new(0, PANEL_PADDING)
padding.PaddingLeft = UDim.new(0, PANEL_PADDING)
padding.PaddingRight = UDim.new(0, PANEL_PADDING)
padding.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, BUTTON_GAP)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = panel

local IDLE_BACKGROUND = Color3.fromRGB(36, 40, 52)
local SELECTED_BACKGROUND = Color3.fromRGB(214, 228, 196)
local IDLE_TEXT = Color3.fromRGB(244, 246, 250)
local SELECTED_TEXT = Color3.fromRGB(20, 28, 18)

local buttons: { [string]: TextButton } = {}
for index, presetId in TrainingLoadouts.PRESET_IDS do
	local button = Instance.new("TextButton")
	button.Name = presetId
	button.LayoutOrder = index
	button.Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT)
	button.BackgroundColor3 = IDLE_BACKGROUND
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBold
	button.TextSize = 18
	button.TextColor3 = IDLE_TEXT
	button.Text = presetId
	button.Parent = panel
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)
	button.Activated:Connect(function()
		CombatController.selectTrainingPreset(presetId)
	end)
	buttons[presetId] = button
end

local function render(presentation: TrainingLoadouts.PresetPresentation)
	gui.Enabled = presentation.Visible
	for presetId, button in buttons do
		local selected = presentation.SelectedPresetId == presetId
		button.BackgroundColor3 = if selected then SELECTED_BACKGROUND else IDLE_BACKGROUND
		button.TextColor3 = if selected then SELECTED_TEXT else IDLE_TEXT
	end
end

CombatController.subscribeTrainingPreset(render)
