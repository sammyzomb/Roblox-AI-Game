--!strict
-- Registry of damage types.
--
-- Category decides which defense applies:
--   Physical : reduced by Armor and by the type's own Resist
--   Magical  : reduced only by Resist
--   True     : never reduced (use sparingly: execute effects, falls)
--
-- Extension point: add a line to TYPES. Nothing else changes.

export type Category = "Physical" | "Magical" | "True"

local TYPES: { [string]: Category } = {
	Slash = "Physical",
	Pierce = "Physical",
	Blunt = "Physical",
	Fire = "Magical",
	Frost = "Magical",
	Lightning = "Magical",
	Arcane = "Magical",
	Poison = "Magical",
	True = "True",
}

local DamageTypes = {}

function DamageTypes.exists(id: string): boolean
	return TYPES[id] ~= nil
end

function DamageTypes.category(id: string): Category
	local category = TYPES[id]
	assert(category, `unknown damage type "{id}"`)
	return category :: Category
end

function DamageTypes.all(): { string }
	local ids = {}
	for id in TYPES do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

return table.freeze(DamageTypes)
