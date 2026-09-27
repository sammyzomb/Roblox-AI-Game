--!strict
-- Shared, tunable game configuration. Read by both server and client.
-- The server is the only authority: client copies are for display/UX only.

local Config = {
	DataStore = {
		Name = "PlayerData_v1",
		MaxRetries = 3,
		AutosaveInterval = 120, -- seconds
	},

	-- Remote request budget per player (all actions combined).
	RateLimit = {
		MaxRequests = 10,
		WindowSeconds = 1,
	},

	-- Repeatable gameplay actions. Keys are the action ids clients send.
	-- Theme is not decided yet, so "Collect" is a placeholder action.
	Actions = {
		Collect = {
			Cooldown = 0.5, -- seconds between accepted requests per player
			Reward = { Coins = 1, Xp = 5 },
		},
	},

	Progression = {
		BaseXp = 50, -- xp needed to go from level 1 to 2
		Growth = 1.25, -- each level needs Growth times more xp
		MaxLevel = 100,
	},
}

return table.freeze(Config)
