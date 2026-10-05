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

	-- Combat tuning. Weapon/armor/item numbers live in Shared/Combat/Data.
	Combat = {
		DefaultRuleset = "PvE", -- zones/arenas switch players to other rulesets
		ArmorConstant = 100, -- armor / (armor + this) = physical reduction
		LevelDamageScaling = 0.02, -- +2% damage per level above 1 (capped by ruleset)
		MinDamage = 1,
		MeleeRangeTolerance = 2, -- studs of latency slack for melee reach
		MeleeArcTolerance = 15, -- degrees of latency slack for melee arcs
		BlockStartDelay = 0.1, -- a guard must be up this long before it blocks
		Health = { Base = 100, PerLevel = 5 },
		Pools = {
			Stamina = { Max = 100, Regen = 25, RegenDelay = 0.8 },
			Mana = { Max = 100, Regen = 6, RegenDelay = 1.5 },
		},
		-- Per-player combat request budget (on top of per-attack cooldowns).
		RateLimit = { MaxRequests = 12, WindowSeconds = 1 },
		-- Starting gear for brand new players (must be unlocked at level 1).
		StarterLoadout = { MainHand = "training_sword", Body = "leather_vest" },
		StarterConsumables = { health_potion = 3 },
		-- Development configuration only. The Product Owner has not approved
		-- a release quantity, limit, price, or final balance. TrainingSupplies
		-- copies this into an in-memory session. It is not StarterConsumables
		-- and it must never be written into PlayerData.
		DevelopmentTrainingStock = { health_potion = 2 },
		-- Studio play-testing only, and only with the in-memory DataStore:
		-- players start at this level so every level-gated weapon can be tried.
		StudioStartLevel = 20,
	},
}

-- Deep freeze so no script can change tuning at runtime by accident.
local function deepFreeze(t: any)
	for _, v in t do
		if type(v) == "table" then
			deepFreeze(v)
		end
	end
	table.freeze(t)
end
deepFreeze(Config)

return Config
