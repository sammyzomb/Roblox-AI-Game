--!strict
-- Owns every player's session data: load on join, autosave, save on leave
-- and on shutdown. All other code reads and changes player data through here.
--
-- Public API:
--   PlayerDataService:Get(player) -> PlayerData?        nil until loaded
--   PlayerDataService:Update(player, mutator) -> boolean mutator(data) must not yield
--   PlayerDataService:GrantMilestone(player, milestoneId) -> boolean  true if newly granted
--   PlayerDataService:GetProfile(player) -> ProgressionGates.Profile?  level + milestones for unlock checks
--   PlayerDataService.Loaded:Connect(function(player, data) end)
--   PlayerDataService.Changed:Connect(function(player, data) end)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local PlayerDataModel = require(Shared.PlayerDataModel)
local Progression = require(Shared.Progression)
local Signal = require(Shared.Signal)

local DataStoreAdapter = require(script.Parent.Parent.Systems.DataStoreAdapter)

type PlayerData = PlayerDataModel.PlayerData

type Session = {
	data: PlayerData,
	canSave: boolean, -- false if loading failed or data is from a newer version
	dirty: boolean,
}

local PlayerDataService = {
	Priority = -10, -- other services depend on player data, so init first
	Loaded = Signal.new(),
	Changed = Signal.new(),
}

local sessions: { [Player]: Session } = {}
local store: DataStoreAdapter.Store
local stateChanged: RemoteEvent

local function keyFor(player: Player): string
	return `player_{player.UserId}`
end

local STARTER: PlayerDataModel.Starter = {
	Loadout = Config.Combat.StarterLoadout,
	Consumables = Config.Combat.StarterConsumables,
}

local function toClient(data: PlayerData): PlayerDataModel.ClientState
	return {
		Coins = data.Coins,
		Xp = data.Xp,
		Level = data.Level,
		XpToNext = Progression.xpToNextLevel(data.Level, Config.Progression),
		Loadout = table.clone(data.Loadout),
		Consumables = table.clone(data.Consumables),
	}
end

local function save(player: Player, session: Session)
	if not session.canSave or not session.dirty then
		return
	end
	session.dirty = false
	if not store:save(keyFor(player), session.data) then
		session.dirty = true
	end
end

local function onPlayerAdded(player: Player)
	local ok, raw = store:load(keyFor(player))
	if player.Parent == nil then
		return -- left while loading
	end

	local data, fromNewerVersion = PlayerDataModel.reconcile(if ok then raw else nil, STARTER)
	if not ok then
		warn(`[PlayerData] Load failed for {player.Name}; this session will not be saved to protect stored data.`)
	elseif fromNewerVersion then
		warn(`[PlayerData] {player.Name} has data from a newer version; this session will not be saved.`)
	end

	-- Studio test sessions (nothing is persisted) start high enough to try all gear.
	if store.isMemory and RunService:IsStudio() and data.Level < Config.Combat.StudioStartLevel then
		data.Level = Config.Combat.StudioStartLevel
	end

	sessions[player] = { data = data, canSave = ok and not fromNewerVersion, dirty = false }
	PlayerDataService.Loaded:Fire(player, data)
	stateChanged:FireClient(player, toClient(data))
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if session then
		save(player, session)
		sessions[player] = nil
	end
end

function PlayerDataService:Init()
	store = DataStoreAdapter.new(Config.DataStore.Name, Config.DataStore.MaxRetries)
	stateChanged = Net.event(Net.Names.StateChanged)

	Net.func(Net.Names.GetState).OnServerInvoke = function(player: Player)
		local session = sessions[player]
		return if session then toClient(session.data) else nil
	end
end

function PlayerDataService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	game:BindToClose(function()
		local pending = 0
		for player, session in sessions do
			pending += 1
			task.spawn(function()
				save(player, session)
				pending -= 1
			end)
		end
		while pending > 0 do
			task.wait()
		end
	end)

	while true do
		task.wait(Config.DataStore.AutosaveInterval)
		for player, session in sessions do
			task.spawn(save, player, session)
		end
	end
end

function PlayerDataService:Get(player: Player): PlayerData?
	local session = sessions[player]
	return if session then session.data else nil
end

function PlayerDataService:Update(player: Player, mutator: (PlayerData) -> ()): boolean
	local session = sessions[player]
	if not session then
		return false
	end
	mutator(session.data)
	session.dirty = true
	PlayerDataService.Changed:Fire(player, session.data)
	stateChanged:FireClient(player, toClient(session.data))
	return true
end

function PlayerDataService:GetProfile(player: Player): { Level: number, Milestones: { [string]: boolean } }?
	local session = sessions[player]
	if not session then
		return nil
	end
	return { Level = session.data.Level, Milestones = session.data.Milestones }
end

function PlayerDataService:GrantMilestone(player: Player, milestoneId: string): boolean
	local session = sessions[player]
	if not session or session.data.Milestones[milestoneId] then
		return false
	end
	return self:Update(player, function(data)
		data.Milestones[milestoneId] = true
	end)
end

return PlayerDataService
