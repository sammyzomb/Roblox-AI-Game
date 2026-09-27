--!strict
-- The core repeatable gameplay loop: client requests an action, the server
-- validates it, grants the reward and updates progression.
--
-- Every request is validated server-side: action id type and existence,
-- per-player rate limit, per-action cooldown and loaded data.
-- To add an action, add an entry to Config.Actions; nothing else is needed
-- unless the action has custom rules.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Progression = require(Shared.Progression)
local PlayerDataModel = require(Shared.PlayerDataModel)

local RateLimiter = require(script.Parent.Parent.Systems.RateLimiter)

type Reward = { Coins: number, Xp: number }

local GameLoopService = {}

local playerData: any -- PlayerDataService, resolved in Init
local limiter = RateLimiter.new(Config.RateLimit.MaxRequests, Config.RateLimit.WindowSeconds)
local lastActionAt: { [Player]: { [string]: number } } = {}

local function applyReward(data: PlayerDataModel.PlayerData, reward: Reward)
	data.Coins += reward.Coins
	data.Level, data.Xp = Progression.addXp(data.Level, data.Xp, reward.Xp, Config.Progression)
	data.Stats.Actions += 1
end

local function onRequestAction(player: Player, actionId: unknown)
	if typeof(actionId) ~= "string" then
		return
	end
	local action = (Config.Actions :: any)[actionId]
	if action == nil then
		return
	end

	local now = os.clock()
	if not limiter:allow(player.UserId, now) then
		return
	end

	local cooldowns = lastActionAt[player]
	if cooldowns == nil then
		cooldowns = {}
		lastActionAt[player] = cooldowns
	end
	local last = cooldowns[actionId]
	if last and now - last < action.Cooldown then
		return
	end

	if playerData:Get(player) == nil then
		return -- data not loaded yet
	end

	cooldowns[actionId] = now
	playerData:Update(player, function(data)
		applyReward(data, action.Reward)
	end)
end

function GameLoopService:Init(registry)
	playerData = registry.PlayerDataService
end

function GameLoopService:Start()
	Net.event(Net.Names.RequestAction).OnServerEvent:Connect(onRequestAction)
	Players.PlayerRemoving:Connect(function(player)
		lastActionAt[player] = nil
		limiter:clear(player.UserId)
	end)
end

return GameLoopService
