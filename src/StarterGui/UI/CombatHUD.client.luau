--!strict
-- Stamina / mana / barrier bars under the main HUD. Display only: values are
-- attributes the server writes on the character (CombatService sync).
-- Health uses Roblox's built-in health bar.

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local BARS = {
	{ Pool = "Stamina", Color = Color3.fromRGB(235, 190, 60) },
	{ Pool = "Mana", Color = Color3.fromRGB(80, 140, 255) },
}

local gui = Instance.new("ScreenGui")
gui.Name = "CombatHUD"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local holder = Instance.new("Frame")
holder.AnchorPoint = Vector2.new(0.5, 1)
holder.Position = UDim2.new(0.5, 0, 1, -90)
holder.Size = UDim2.new(0, 240, 0, 34)
holder.BackgroundTransparency = 1
holder.Parent = gui

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.Parent = holder

local fills: { [string]: Frame } = {}
for i, bar in BARS do
	local back = Instance.new("Frame")
	back.LayoutOrder = i
	back.Size = UDim2.new(1, 0, 0, 12)
	back.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	back.BackgroundTransparency = 0.2
	back.Parent = holder
	Instance.new("UICorner", back).CornerRadius = UDim.new(0, 6)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = bar.Color
	fill.Parent = back
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 6)
	fills[bar.Pool] = fill
end

local barrierLabel = Instance.new("TextLabel")
barrierLabel.Size = UDim2.new(1, 0, 0, 14)
barrierLabel.LayoutOrder = 99
barrierLabel.BackgroundTransparency = 1
barrierLabel.Font = Enum.Font.GothamBold
barrierLabel.TextSize = 12
barrierLabel.TextColor3 = Color3.fromRGB(170, 220, 255)
barrierLabel.Text = ""
barrierLabel.Parent = holder

local connections: { RBXScriptConnection } = {}

local function watch(character: Model)
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	local function refresh()
		for pool, fill in fills do
			local current = character:GetAttribute(pool)
			local max = character:GetAttribute(`{pool}Max`)
			if type(current) == "number" and type(max) == "number" and max > 0 then
				fill.Size = UDim2.new(math.clamp(current / max, 0, 1), 0, 1, 0)
			end
		end
		local barrier = character:GetAttribute("Barrier")
		barrierLabel.Text = if type(barrier) == "number" and barrier > 0 then `Barrier {barrier}` else ""
	end
	table.insert(connections, character.AttributeChanged:Connect(refresh))
	refresh()
end

if player.Character then
	watch(player.Character)
end
player.CharacterAdded:Connect(watch)
