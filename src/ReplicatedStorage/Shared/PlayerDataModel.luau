--!strict
-- Player data shape, defaults and validation of stored data.
-- Pure module: no Roblox APIs, unit tested with the Luau CLI.

export type PlayerData = {
	Version: number,
	Coins: number,
	Xp: number,
	Level: number,
	Stats: {
		Actions: number,
	},
}

-- What the client is allowed to see. Built by the server, never trusted back.
export type ClientState = {
	Coins: number,
	Xp: number,
	Level: number,
	XpToNext: number,
}

local PlayerDataModel = {}

PlayerDataModel.CURRENT_VERSION = 1

function PlayerDataModel.new(): PlayerData
	return {
		Version = PlayerDataModel.CURRENT_VERSION,
		Coins = 0,
		Xp = 0,
		Level = 1,
		Stats = {
			Actions = 0,
		},
	}
end

local function nonNegativeInteger(value: unknown, default: number): number
	if type(value) == "number" and value == value and value >= 0 and value ~= math.huge then
		return math.floor(value)
	end
	return default
end

-- Turns whatever came out of the DataStore into a valid PlayerData.
-- Missing or corrupt fields fall back to defaults.
-- The second return value is true when the stored data was written by a newer
-- data version; callers must not save such a session, or they would downgrade it.
function PlayerDataModel.reconcile(raw: unknown): (PlayerData, boolean)
	local data = PlayerDataModel.new()
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

	-- Future migrations go here, keyed on storedVersion.

	return data, storedVersion > PlayerDataModel.CURRENT_VERSION
end

return PlayerDataModel
