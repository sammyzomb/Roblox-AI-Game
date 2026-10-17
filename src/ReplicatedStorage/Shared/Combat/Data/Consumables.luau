--!strict
-- Defensive items and other consumables (data only). Validated by Definitions.luau.
-- Items sharing a CooldownGroup share one cooldown (e.g. all potions).

return {
	health_potion = {
		Name = "Health Potion",
		Unlock = { Level = 1 },
		Cooldown = 8,
		CooldownGroup = "Potion",
		Heal = 40,
	},
	mana_potion = {
		Name = "Mana Potion",
		Unlock = { Level = 4 },
		Cooldown = 8,
		CooldownGroup = "Potion",
		Restore = { { Pool = "Mana", Amount = 50 } },
	},
	barrier_scroll = {
		Name = "Barrier Scroll",
		Unlock = { Level = 5 },
		Cooldown = 20,
		Apply = { { Id = "Barrier" } },
	},
	fortifying_draught = {
		Name = "Fortifying Draught",
		Unlock = { Level = 8 },
		Cooldown = 30,
		CooldownGroup = "Potion",
		Apply = { { Id = "Fortified" } },
	},
	fire_resist_tonic = {
		Name = "Fire Resist Tonic",
		Unlock = { Level = 7 },
		Cooldown = 30,
		Apply = { { Id = "FireResistance" } },
	},
	cleansing_salts = {
		Name = "Cleansing Salts",
		Unlock = { Level = 9 },
		Cooldown = 25,
		Cleanse = { "Debuff", "CrowdControl" },
	},
	smoke_bomb = {
		Name = "Smoke Bomb",
		Unlock = { Level = 11 },
		Cooldown = 30,
		Apply = { { Id = "Evasive" } },
		Cleanse = { "CrowdControl" },
	},
}
