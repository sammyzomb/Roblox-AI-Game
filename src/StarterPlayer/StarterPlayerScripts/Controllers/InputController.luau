--!strict
-- Maps player input to action requests. Keyboard: E. Gamepad: X.
-- Touch: an on-screen button created by ContextActionService.
-- The client-side cooldown only avoids wasted requests; the server enforces it.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local ACTION_ID = "Collect"

local InputController = {}

local requestAction: RemoteEvent
local lastSentAt = -math.huge

local function onCollect(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local now = os.clock()
	if now - lastSentAt >= Config.Actions.Collect.Cooldown then
		lastSentAt = now
		requestAction:FireServer(ACTION_ID)
	end
	return Enum.ContextActionResult.Sink
end

function InputController:Init()
	requestAction = Net.event(Net.Names.RequestAction)
end

function InputController:Start()
	ContextActionService:BindAction(ACTION_ID, onCollect, true, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle(ACTION_ID, "Collect")
end

return InputController
