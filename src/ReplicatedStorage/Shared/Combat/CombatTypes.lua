--[[
	CombatTypes.lua
	Shared enums/type contracts for the weapon-agnostic combat core.
	PUBLIC API — do not add weapon-specific values here (e.g. no "Katana").
]]

local CombatTypes = {}

CombatTypes.DamageType = {
	Physical  = "Physical", -- generic, no resistance-typing
	Slash     = "Slash",
	Blunt     = "Blunt",
	Pierce    = "Pierce",
	Fire      = "Fire",
	Ice       = "Ice",
	Lightning = "Lightning",
	Poison    = "Poison",
	Holy      = "Holy",
	Dark      = "Dark",
	True      = "True", -- ignores resistance profile entirely
}

CombatTypes.WeaponClass = {
	MeleeLight   = "MeleeLight",
	MeleeHeavy   = "MeleeHeavy",
	Polearm      = "Polearm",
	DualWield    = "DualWield",
	RangedBow    = "RangedBow",
	RangedCross  = "RangedCross",
	RangedThrown = "RangedThrown",
	Magic        = "Magic",
	Defense      = "Defense", -- shields / defensive-only items
	Hybrid       = "Hybrid",
}

CombatTypes.ResourceType = {
	Stamina = "Stamina",
	Mana    = "Mana",
	Energy  = "Energy",
}

CombatTypes.CombatMode = {
	PvE = "PvE",
	PvP = "PvP",
}

CombatTypes.EffectCategory = {
	DamageOverTime = "DamageOverTime",
	CrowdControl   = "CrowdControl",
	Buff           = "Buff",
	Debuff         = "Debuff",
	Shield         = "Shield", -- absorb/reflect/barrier
}

CombatTypes.StackMode = {
	Refresh = "Refresh",
	Stack   = "Stack",
	Ignore  = "Ignore",
}

return CombatTypes
