--!strict
-- Draws the label produced by DamageFloat. Numbers come only from that
-- helper, which reads a server Hit event. This file does not calculate
-- damage, and it does not listen to CombatRequest.
--
-- Studio still has to confirm BillboardGui lifetime. The pure tests do not.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DamageFloat = require(Shared:WaitForChild("Combat"):WaitForChild("DamageFloat"))

local DamageFloatView = {}

type ActiveFloat = {
	gui: BillboardGui,
	connections: { RBXScriptConnection },
	detached: boolean,
}

local active: { ActiveFloat } = {}
local spreadIndex = 0

local SPREAD_X = { -1.2, 0, 1.2, -0.6, 0.6 }

local function colorFor(tone: string): Color3
	local rgb = DamageFloat.toneRgb(tone)
	if rgb == nil then
		return Color3.fromRGB(255, 255, 255)
	end
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function detach(entry: ActiveFloat, fromDestroying: boolean?)
	if entry.detached then
		return
	end
	entry.detached = true
	for _, connection in entry.connections do
		connection:Disconnect()
	end
	table.clear(entry.connections)
	local index = table.find(active, entry)
	if index ~= nil then
		table.remove(active, index)
	end
	if not fromDestroying then
		entry.gui:Destroy()
	end
end

local function usablePart(model: Model, part: Instance?): BasePart?
	if part == nil or not part:IsA("BasePart") then
		return nil
	end
	if not part:IsDescendantOf(model) or not part:IsDescendantOf(Workspace) then
		return nil
	end
	return part
end

local function findAdornee(model: Model): BasePart?
	if not model:IsDescendantOf(Workspace) then
		return nil
	end
	local head = usablePart(model, model:FindFirstChild("Head"))
	if head then
		return head
	end
	local root = usablePart(model, model:FindFirstChild("HumanoidRootPart"))
	if root then
		return root
	end
	return usablePart(model, model.PrimaryPart)
end

local function show(event: unknown, display: DamageFloat.HitDisplay)
	if type(event) ~= "table" then
		return
	end
	local target = (event :: { [string]: unknown }).Target
	if typeof(target) ~= "Instance" or not target:IsA("Model") then
		return
	end
	local adornee = findAdornee(target)
	if adornee == nil then
		return
	end

	local retire = DamageFloat.slotsToRetire(#active)
	if retire == nil then
		return
	end
	for _ = 1, retire do
		local oldest = active[1]
		if oldest == nil then
			break
		end
		detach(oldest)
	end
	if #active >= DamageFloat.MAX_SIMULTANEOUS then
		return
	end

	spreadIndex += 1
	local offsetX = SPREAD_X[((spreadIndex - 1) % #SPREAD_X) + 1]

	local gui = Instance.new("BillboardGui")
	gui.Name = "ServerDamageFloat"
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 80
	gui.Size = UDim2.fromOffset(200, 64)
	gui.StudsOffset = Vector3.new(offsetX, 2.6, 0)
	gui.Adornee = adornee
	gui.ResetOnSpawn = false

	local label = Instance.new("TextLabel")
	label.Name = "Amount"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 32
	label.TextStrokeTransparency = 0.4
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Text = display.Text
	label.TextColor3 = colorFor(display.Tone)
	label.Parent = gui

	local entry: ActiveFloat = {
		gui = gui,
		connections = {},
		detached = false,
	}
	local connected = pcall(function()
		table.insert(entry.connections, gui.Destroying:Connect(function()
			detach(entry, true)
		end))
		table.insert(entry.connections, adornee.AncestryChanged:Connect(function()
			local ok, inWorkspace = pcall(function()
				return adornee:IsDescendantOf(Workspace)
			end)
			if not ok or not inWorkspace then
				detach(entry)
			end
		end))
		table.insert(entry.connections, target.Destroying:Connect(function()
			detach(entry)
		end))
		table.insert(active, entry)
		gui.Parent = adornee
	end)
	if not connected then
		detach(entry)
		return
	end

	task.delay(DamageFloat.LIFETIME_SECONDS, function()
		pcall(detach, entry)
	end)
end

function DamageFloatView.present(event: unknown)
	local display = DamageFloat.normalizeHit(event)
	if display == nil then
		return
	end
	local ok = pcall(show, event, display)
	if not ok then
		return
	end
end

return DamageFloatView
