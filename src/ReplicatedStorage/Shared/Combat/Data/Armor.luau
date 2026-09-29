--!strict
-- Defensive equipment (data only). Validated by Definitions.luau.
-- Slots: Head, Body, Cloak, Talisman. Shields live in Weapons.luau (OffHand).

return {
	leather_cap = {
		Name = "Leather Cap",
		Slot = "Head",
		Tier = 1,
		Unlock = { Level = 1 },
		Defense = { Armor = 3 },
	},
	leather_vest = {
		Name = "Leather Vest",
		Slot = "Body",
		Tier = 1,
		Unlock = { Level = 1 },
		Defense = { Armor = 8 },
	},
	mage_robe = {
		Name = "Mage Robe",
		Slot = "Body",
		Tier = 2,
		Unlock = { Level = 6 },
		Defense = { Armor = 4, Resist = { Fire = 0.1, Frost = 0.1, Arcane = 0.1, Lightning = 0.1 } },
	},
	chain_hauberk = {
		Name = "Chain Hauberk",
		Slot = "Body",
		Tier = 2,
		Unlock = { Level = 10 },
		Defense = { Armor = 22, Resist = { Lightning = -0.1 } }, -- metal conducts
	},
	traveler_cloak = {
		Name = "Traveler's Cloak",
		Slot = "Cloak",
		Tier = 1,
		Unlock = { Level = 3 },
		Defense = { Armor = 2, Resist = { Frost = 0.1 } },
	},
	warding_talisman = {
		Name = "Warding Talisman",
		Slot = "Talisman",
		Tier = 3,
		Unlock = { Level = 12, Milestones = { "boss_forest_warden" } },
		Defense = { Resist = { Arcane = 0.15, Fire = 0.05, Frost = 0.05 } },
	},
}
