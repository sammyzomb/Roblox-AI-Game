--!strict
-- Minimal HUD: coins, level and an xp bar. Display only; all values come
-- from the server via StateChanged / GetState.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

type ClientState = { Coins: number, Xp: number, Level: number, XpToNext: number }

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	instance.Parent = parent
	return instance
end

local gui = make("ScreenGui", { Name = "HUD", ResetOnSpawn = false, IgnoreGuiInset = false }, nil)

local panel = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 12),
	Size = UDim2.new(0, 260, 0, 84),
	BackgroundColor3 = Color3.fromRGB(20, 22, 28),
	BackgroundTransparency = 0.25,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, panel)
make("UIPadding", {
	PaddingTop = UDim.new(0, 8),
	PaddingBottom = UDim.new(0, 8),
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
}, panel)
make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, panel)

local function label(order: number, textSize: number): TextLabel
	return make("TextLabel", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, textSize + 4),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = textSize,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	}, panel)
end

local statsLabel = label(1, 18)
local xpTrack = make("Frame", {
	LayoutOrder = 2,
	Size = UDim2.new(1, 0, 0, 10),
	BackgroundColor3 = Color3.fromRGB(60, 64, 76),
}, panel)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, xpTrack)
local xpFill = make("Frame", {
	Size = UDim2.new(0, 0, 1, 0),
	BackgroundColor3 = Color3.fromRGB(88, 200, 120),
}, xpTrack)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, xpFill)
local hintLabel = label(3, 14)
hintLabel.TextColor3 = Color3.fromRGB(190, 195, 205)
hintLabel.Text = if UserInputService.TouchEnabled then "Tap Collect to earn coins" else "Press E to collect"

statsLabel.Text = "Loading..."
gui.Parent = playerGui

local function render(state: ClientState?)
	if state == nil then
		return
	end
	statsLabel.Text = `Coins: {state.Coins}    Level {state.Level}`
	local ratio = if state.XpToNext > 0 then math.clamp(state.Xp / state.XpToNext, 0, 1) else 1
	xpFill.Size = UDim2.new(ratio, 0, 1, 0)
end

Net.event(Net.Names.StateChanged).OnClientEvent:Connect(render)
render(Net.func(Net.Names.GetState):InvokeServer())
