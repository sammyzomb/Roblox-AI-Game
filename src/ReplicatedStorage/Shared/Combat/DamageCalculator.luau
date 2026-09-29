--!strict
-- Pure damage math. No state is changed here; CombatCore applies the result.
--
--   raw        = sum(component.Amount) * levelScale * archetype/ruleset multipliers * dealtMultiplier
--   per type   : Physical -> armor reduction then resist, Magical -> resist, True -> none
--   armor      : reduction = armor / (armor + ArmorConstant)   (diminishing returns, never 100%)
--   final      = mitigated * takenMultiplier (statuses, heavy-attack recovery vulnerability)
--
-- Block, barriers and reflect are applied later by CombatCore, in that order.

local Types = require("./Types")
local DamageTypes = require("./DamageTypes")

type DamageComponent = Types.DamageComponent
type Ruleset = Types.Ruleset

export type Settings = {
	ArmorConstant: number,
	LevelDamageScaling: number, -- +x damage per level above 1
	MinDamage: number, -- floor for any hit that dealt >0 raw damage
}

export type DefenseProfile = {
	Armor: number,
	Resist: { [string]: number },
}

export type Input = {
	Components: { DamageComponent },
	AttackerLevel: number,
	Archetype: string?,
	ArmorPenetration: number?,
	DealtMultiplier: number?,
	TakenMultiplier: number?,
	Defense: DefenseProfile,
	Ruleset: Ruleset,
}

export type Breakdown = {
	Raw: number,
	Final: number,
	PerType: { [string]: number },
}

local DamageCalculator = {}

function DamageCalculator.levelScale(level: number, ruleset: Ruleset, settings: Settings): number
	local effective = if ruleset.LevelCap then math.min(level, ruleset.LevelCap) else level
	return 1 + settings.LevelDamageScaling * (math.max(effective, 1) - 1)
end

function DamageCalculator.armorReduction(armor: number, penetration: number, ruleset: Ruleset, settings: Settings): number
	local capped = if ruleset.ArmorCap then math.min(armor, ruleset.ArmorCap) else armor
	local effective = math.max(0, capped * (1 - penetration))
	return effective / (effective + settings.ArmorConstant)
end

function DamageCalculator.resist(defense: DefenseProfile, damageType: string, ruleset: Ruleset): number
	local value = defense.Resist[damageType] or 0
	-- Weakness is limited too, so a -100% resist can't double damage forever.
	return math.clamp(value, -0.5, ruleset.ResistCap)
end

function DamageCalculator.compute(input: Input, settings: Settings): Breakdown
	local ruleset = input.Ruleset
	local scale = DamageCalculator.levelScale(input.AttackerLevel, ruleset, settings)
		* ruleset.DamageMultiplier
		* (input.DealtMultiplier or 1)
	if input.Archetype and ruleset.ArchetypeMultipliers then
		scale *= ruleset.ArchetypeMultipliers[input.Archetype] or 1
	end

	local armorReduction =
		DamageCalculator.armorReduction(input.Defense.Armor, input.ArmorPenetration or 0, ruleset, settings)

	local raw, final = 0, 0
	local perType: { [string]: number } = {}
	for _, component in input.Components do
		local amount = component.Amount * scale
		raw += amount
		local category = DamageTypes.category(component.Type)
		if category == "Physical" then
			amount *= 1 - armorReduction
		end
		if category ~= "True" then
			amount *= 1 - DamageCalculator.resist(input.Defense, component.Type, ruleset)
		end
		perType[component.Type] = (perType[component.Type] or 0) + amount
		final += amount
	end

	final *= input.TakenMultiplier or 1
	if raw > 0 then
		final = math.max(settings.MinDamage, final)
	end
	return { Raw = raw, Final = final, PerType = perType }
end

return table.freeze(DamageCalculator)
