--!strict
-- Player data shape, defaults and validation of stored data.
-- Pure module: no Roblox APIs, unit tested with the Luau CLI.
--
-- Version history:
--   1: Coins, Xp, Level, Stats
--   2: + Loadout (equipped item ids), Milestones (progression unlocks),
--        Consumables (item id -> count)

export type Loadout = {
	MainHand: string?,
	OffHand: string?,
	Head: string?,
	Body: string?,
	Cloak: string?,
	Talisman: string?,
}

export type PlayerData = {
	Version: number,
	Coins: number,
	Xp: number,
	Level: number,
	Stats: {
		Actions: number,
	},
	Loadout: Loadout,
	Milestones: { [string]: boolean },
	Consumables: { [string]: number },
}

-- What the client is allowed to see. Built by the server, never trusted back.
export type ClientState = {
	Coins: number,
	Xp: number,
	Level: number,
	XpToNext: number,
	Loadout: Loadout,
	Consumables: { [string]: number },
}

local PlayerDataModel = {}

PlayerDataModel.CURRENT_VERSION = 2

PlayerDataModel.LOADOUT_SLOTS = table.freeze({ "MainHand", "OffHand", "Head", "Body", "Cloak", "Talisman" })

export type Starter = {
	Loadout: { [string]: string }?,
	Consumables: { [string]: number }?,
}

function PlayerDataModel.new(starter: Starter?): PlayerData
	local loadout: Loadout = {}
	local consumables: { [string]: number } = {}
	if starter then
		if starter.Loadout then
			for slot, id in starter.Loadout do
				(loadout :: any)[slot] = id
			end
		end
		if starter.Consumables then
			for id, count in starter.Consumables do
				consumables[id] = count
			end
		end
	end
	return {
		Version = PlayerDataModel.CURRENT_VERSION,
		Coins = 0,
		Xp = 0,
		Level = 1,
		Stats = {
			Actions = 0,
		},
		Loadout = loadout,
		Milestones = {},
		Consumables = consumables,
	}
end

local function nonNegativeInteger(value: unknown, default: number): number
	if type(value) == "number" and value == value and value >= 0 and value ~= math.huge then
		return math.floor(value)
	end
	return default
end

local function validId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= 64
end

-- Turns whatever came out of the DataStore into a valid PlayerData.
-- Missing or corrupt fields fall back to defaults (`starter` for new players
-- and for data from version 1, which had no equipment).
-- The second return value is true when the stored data was written by a newer
-- data version; callers must not save such a session, or they would downgrade it.
-- Item ids are only shape-checked here; the server drops ids that no longer exist.
function PlayerDataModel.reconcile(raw: unknown, starter: Starter?): (PlayerData, boolean)
	local data = PlayerDataModel.new(starter)
	if type(raw) ~= "table" then
		return data, false
	end

	local stored = raw :: any
	local storedVersion = nonNegativeInteger(stored.Version, 0)

	data.Coins = nonNegativeInteger(stored.Coins, data.Coins)
	data.Xp = nonNegativeInteger(stored.Xp, data.Xp)
	data.Level = math.max(1, nonNegativeInteger(stored.Level, data.Level))
	if type(stored.Stats) == "table" then
		data.Stats.Actions = nonNegativeInteger(stored.Stats.Actions, data.Stats.Actions)
	end

	-- Version 2 fields. Version 1 data keeps the starter defaults (migration).
	if storedVersion >= 2 then
		if type(stored.Loadout) == "table" then
			local loadout: Loadout = {}
			for _, slot in PlayerDataModel.LOADOUT_SLOTS do
				local id = stored.Loadout[slot]
				if validId(id) then
					(loadout :: any)[slot] = id
				end
			end
			data.Loadout = loadout
		end
		if type(stored.Milestones) == "table" then
			for id, value in stored.Milestones do
				if validId(id) and value == true then
					data.Milestones[id] = true
				end
			end
		end
		if type(stored.Consumables) == "table" then
			local consumables = {}
			for id, count in stored.Consumables do
				local n = nonNegativeInteger(count, 0)
				if validId(id) and n > 0 then
					consumables[id] = n
				end
			end
			data.Consumables = consumables
		end
	end

	return data, storedVersion > PlayerDataModel.CURRENT_VERSION
end

return PlayerDataModel
