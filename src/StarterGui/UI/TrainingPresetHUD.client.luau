--!strict
-- Placeholder selector for the three temporary training presets.
--
-- Loadout path: CombatController is the only CombatEvent listener. A valid
-- Loadout updates TrainingLoadouts preset presentation, and this script
-- renders that cache. Activated only calls selectTrainingPreset. A click
-- does not set the check, the border, or the confirmed line; those wait
-- for SelectedPresetId. presentationAfterPresetRequest returns the same
-- state, so a request is not an equip acknowledgement.
--
-- PO saw the button brighten under the pointer and then go idle. This
-- script used to set AutoButtonColor and to express selection only as a
-- background color. That is a supported code-path explanation, not a
-- Studio-proven root cause: the engine may tint a hovered button even when
-- no Loadout has confirmed it, and a color written during that hover can
-- be restored to the pre-hover color when the pointer leaves. Studio has
-- not been run. Confirmed identity is therefore the check, the gold
-- border, the colors, and the confirmed line together. Pointer enter/leave
-- only changes background transparency and then reapplies that identity.
--
-- The panel stays up after a click so the player can switch among the
-- three presets. Traditional Chinese lines state that the equipment is
-- temporary, which preset is confirmed, and the next step. While the
-- server says training is active, a second line points at the existing
-- TrainingDummyMarker (coordinates from TrainingSceneConfig, not a second
-- layout) and distinguishes that attacking scene dummy from the three
-- passive birth-area dummies. The line does not report damage or a block
-- result. Temporary=false hides the panel and clears the guidance text.
--
-- Placement is the left side, just below the top coin/level HUD (that
-- panel ends near y=96), clear of the centered bottom stamina/mana bars
-- and the bottom-right ContextActionService combat buttons. The panel is
-- taller than the three buttons alone because of the guidance. Each option
-- stays 48 px tall. The panel and its labels are Active so padding, gaps,
-- and text are expected to sink GUI input. That property does not prove
-- ContextActionService will suppress MouseButton1. Studio has not been
-- run. This is not final art.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TrainingLoadouts = require(Shared:WaitForChild("Combat"):WaitForChild("TrainingLoadouts"))
local TrainingSceneConfig = require(Shared:WaitForChild("Combat"):WaitForChild("TrainingSceneConfig"))
local CombatController = require(Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Controllers"):WaitForChild("CombatController"))

local BUTTON_HEIGHT = 48
local PANEL_WIDTH = 280
local PANEL_PADDING = 8
local BUTTON_GAP = 6
local BUTTON_ORDER = 10

-- TrainingSceneBootstrap names the anchor part. The three birth-area
-- dummies are the passive specs in TrainingDummyService; this count is
-- that existing set, not a new spawn list.
local SCENE_FACTS: TrainingLoadouts.PracticeScene = {
	MarkerName = "TrainingDummyMarker",
	Marker = TrainingSceneConfig.resolve().DummyMarker,
	PassiveCount = 3,
}

local PRESET_LABELS: { [string]: string } = {
	Swordsman = "劍士",
	Mage = "法師",
	Archer = "弓手",
}

local IDLE_BACKGROUND = Color3.fromRGB(36, 40, 52)
local SELECTED_BACKGROUND = Color3.fromRGB(214, 228, 196)
local IDLE_TEXT = Color3.fromRGB(244, 246, 250)
local SELECTED_TEXT = Color3.fromRGB(20, 28, 18)
local SELECTED_BORDER = Color3.fromRGB(246, 196, 72)
local BODY_TEXT = Color3.fromRGB(232, 236, 244)

local REST_TRANSPARENCY = 0
local HOVER_TRANSPARENCY = 0.18

local function playerFont(weight: Enum.FontWeight): Font
	local ok, font = pcall(Font.new, "rbxasset://fonts/families/SourceHanSans.json", weight, Enum.FontStyle.Normal)
	if ok then
		return font
	end
	return Font.fromEnum(Enum.Font.GothamBold)
end

local BODY_FONT = playerFont(Enum.FontWeight.Medium)
local BUTTON_FONT = playerFont(Enum.FontWeight.Bold)

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
panel.Size = UDim2.fromOffset(PANEL_WIDTH, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel = 0
panel.Active = true
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

local function bodyLabel(name: string, order: number, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.FontFace = BODY_FONT
	label.TextSize = textSize
	label.TextColor3 = BODY_TEXT
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.Text = ""
	label.Active = true
	label.Parent = panel
	return label
end

local purposeLabel = bodyLabel("Purpose", 1, 16)
local confirmedLabel = bodyLabel("Confirmed", 2, 15)
local nextLabel = bodyLabel("NextStep", 3, 14)
local guidanceLabel = bodyLabel("Guidance", 30, 14)

local function statusLines(status: TrainingLoadouts.PresetStatus): (string, string, string)
	if status.PurposeVisible ~= true then
		return "", "", ""
	end
	local confirmed = "目前選擇：尚未確認"
	local selected = status.ConfirmedPresetId
	if selected ~= nil then
		local label = PRESET_LABELS[selected] or selected
		confirmed = `目前選擇：已確認 {label}（{selected}）`
	end
	local nextStep: string
	if status.NextStep == "WalkToDummy" then
		nextStep = "下一步：走向場景訓練假人。"
	elseif status.NextStep == "Choose" then
		nextStep = "下一步：點一種裝備，等已確認再練習。"
	else
		nextStep = ""
	end
	return "暫時訓練裝備", confirmed, nextStep
end

local function guidanceLine(cue: TrainingLoadouts.PracticeCue): string
	if cue.Visible ~= true then
		return ""
	end
	return `場景假人在 {cue.MarkerName}（X {cue.MarkerX}、Z {cue.MarkerZ}），會攻擊，用來練習格擋。出生區 {cue.PassiveCount} 個假人不會攻擊，是被動目標。左鍵攻擊，按住 F 格擋，走過去。`
end

local buttons: { [string]: TextButton } = {}
local strokes: { [string]: UIStroke } = {}
local lastPresentation = TrainingLoadouts.emptyPresetPresentation()

local function applyButton(presetId: string, presentation: TrainingLoadouts.PresetPresentation, pointerOver: boolean)
	local button = buttons[presetId]
	local stroke = strokes[presetId]
	local identity = TrainingLoadouts.selectionIdentity(presentation, presetId, pointerOver)
	button.AutoButtonColor = false
	button.BackgroundColor3 = if identity.Confirmed then SELECTED_BACKGROUND else IDLE_BACKGROUND
	button.TextColor3 = if identity.Confirmed then SELECTED_TEXT else IDLE_TEXT
	button.Text = if identity.ShowCheck then `✓ {presetId}` else presetId
	stroke.Color = SELECTED_BORDER
	stroke.Thickness = if identity.ShowBorder then 2 else 0
	stroke.Transparency = if identity.ShowBorder then 0 else 1
end

local function render(presentation: TrainingLoadouts.PresetPresentation)
	lastPresentation = presentation
	local status = TrainingLoadouts.presetStatus(presentation)
	local cue = TrainingLoadouts.practiceCue(presentation, SCENE_FACTS)
	local purpose, confirmed, nextStep = statusLines(status)
	purposeLabel.Text = purpose
	confirmedLabel.Text = confirmed
	nextLabel.Text = nextStep
	guidanceLabel.Text = guidanceLine(cue)
	gui.Enabled = presentation.Visible
	for presetId in buttons do
		applyButton(presetId, presentation, false)
	end
end

for index, presetId in TrainingLoadouts.PRESET_IDS do
	local button = Instance.new("TextButton")
	button.Name = presetId
	button.LayoutOrder = BUTTON_ORDER + index
	button.Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT)
	button.BackgroundColor3 = IDLE_BACKGROUND
	button.BackgroundTransparency = REST_TRANSPARENCY
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.FontFace = BUTTON_FONT
	button.TextSize = 18
	button.TextColor3 = IDLE_TEXT
	button.Text = presetId
	button.Parent = panel
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "ConfirmedBorder"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = SELECTED_BORDER
	stroke.Thickness = 0
	stroke.Transparency = 1
	stroke.Parent = button
	buttons[presetId] = button
	strokes[presetId] = stroke
	button.Activated:Connect(function()
		CombatController.selectTrainingPreset(presetId)
	end)
	button.MouseEnter:Connect(function()
		button.BackgroundTransparency = HOVER_TRANSPARENCY
		applyButton(presetId, lastPresentation, true)
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundTransparency = REST_TRANSPARENCY
		applyButton(presetId, lastPresentation, false)
	end)
end

CombatController.subscribeTrainingPreset(render)
