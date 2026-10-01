--!strict
-- Status effect definitions (data only). Validated by Definitions.luau.
-- Durations in seconds. See Types.StatusEffectDef for every field.

return {
	-- Crowd control ------------------------------------------------------
	Stagger = {
		Duration = 0.4,
		Stacking = "Refresh",
		Tags = { "CrowdControl", "Debuff" },
		Interrupts = true,
	},
	Stun = {
		Duration = 1.2,
		Stacking = "Refresh",
		Tags = { "CrowdControl", "Debuff" },
		Interrupts = true,
		PreventsActions = true,
	},
	Chill = {
		Duration = 3,
		Stacking = "Refresh",
		Tags = { "CrowdControl", "Debuff", "Magic" },
		MoveSpeedMultiplier = 0.7,
	},

	-- Damage over time ---------------------------------------------------
	Burn = {
		Duration = 4,
		Stacking = "Stack",
		MaxStacks = 3,
		Tags = { "Debuff", "Magic" },
		DamagePerSecond = { Type = "Fire", Amount = 4 },
	},
	Bleed = {
		Duration = 5,
		Stacking = "Stack",
		MaxStacks = 5,
		Tags = { "Debuff" },
		DamagePerSecond = { Type = "Slash", Amount = 2 },
	},

	-- Defensive magic / buffs --------------------------------------------
	Barrier = {
		Duration = 8,
		Stacking = "Refresh",
		Tags = { "Buff", "Magic" },
		Absorb = 40,
	},
	FrostWard = {
		Duration = 12,
		Stacking = "Refresh",
		Tags = { "Buff", "Magic" },
		Defense = { Armor = 20, Resist = { Frost = 0.3, Fire = 0.1 } },
	},
	Steadfast = {
		Duration = 6,
		Stacking = "Refresh",
		Tags = { "Buff", "Magic" },
		ImmuneToTags = { "CrowdControl" },
	},
	Thornmail = {
		Duration = 6,
		Stacking = "Refresh",
		Tags = { "Buff", "Magic" },
		Reflect = 0.25,
	},

	-- Item buffs ---------------------------------------------------------
	Fortified = {
		Duration = 10,
		Stacking = "Refresh",
		Tags = { "Buff" },
		DamageTakenMultiplier = 0.8,
	},
	Evasive = {
		Duration = 4,
		Stacking = "Refresh",
		Tags = { "Buff" },
		Evasion = 0.3,
		MoveSpeedMultiplier = 1.25,
	},
	Regeneration = {
		Duration = 5,
		Stacking = "Refresh",
		Tags = { "Buff" },
		HealPerSecond = 6,
	},
	FireResistance = {
		Duration = 30,
		Stacking = "Refresh",
		Tags = { "Buff" },
		Defense = { Resist = { Fire = 0.35 } },
	},
}
