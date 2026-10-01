--!strict
-- Loads, validates and indexes all combat data (weapons, armor, consumables,
-- status effects). Invalid data fails loudly at boot with every problem listed,
-- instead of misbehaving later in a fight.
--
-- Public API:
--   Definitions.get() -> Defs                       validated default data (cached)
--   Definitions.build(raw) -> (Defs?, { string })   validate arbitrary data (tests, tools)
--   Definitions.validateWeapon(id, def, statuses) -> { string }  errors for one weapon

local Types = require("./Types")
local DamageTypes = require("./DamageTypes")

type WeaponDef = Types.WeaponDef
type ArmorDef = Types.ArmorDef
type ConsumableDef = Types.ConsumableDef
type StatusEffectDef = Types.StatusEffectDef
type AttackDef = Types.AttackDef

export type Defs = {
	Weapons: { [string]: WeaponDef },
	Armor: { [string]: ArmorDef },
	Consumables: { [string]: ConsumableDef },
	StatusEffects: { [string]: StatusEffectDef },
}

export type Raw = {
	Weapons: { [string]: any },
	Armor: { [string]: any },
	Consumables: { [string]: any },
	StatusEffects: { [string]: any },
}

local DELIVERIES = { Melee = true, Projectile = true, Area = true, Self = true }
local ARCHETYPES = { Melee = true, RangedPhysical = true, Magic = true, Defense = true, Hybrid = true }
local HAND_SLOTS = { MainHand = true, OffHand = true }
local ARMOR_SLOTS = { Head = true, Body = true, Cloak = true, Talisman = true }
local STACKING = { Refresh = true, Stack = true, Ignore = true }

local Definitions = {}

local function isNumber(v: any, min: number?, max: number?): boolean
	if type(v) ~= "number" or v ~= v then
		return false
	end
	if min and v < min then
		return false
	end
	if max and v > max then
		return false
	end
	return true
end

local function checkGate(errors: { string }, where: string, gate: any)
	if gate == nil then
		return
	end
	if type(gate) ~= "table" then
		table.insert(errors, `{where}: Unlock must be a table`)
		return
	end
	if gate.Level ~= nil and not isNumber(gate.Level, 1) then
		table.insert(errors, `{where}: Unlock.Level must be a number >= 1`)
	end
	if gate.Milestones ~= nil and type(gate.Milestones) ~= "table" then
		table.insert(errors, `{where}: Unlock.Milestones must be a list of strings`)
	end
end

local function checkDefense(errors: { string }, where: string, defense: any)
	if defense == nil then
		return
	end
	if type(defense) ~= "table" then
		table.insert(errors, `{where}: Defense must be a table`)
		return
	end
	if defense.Armor ~= nil and not isNumber(defense.Armor, 0) then
		table.insert(errors, `{where}: Defense.Armor must be >= 0`)
	end
	if defense.Resist ~= nil then
		for damageType, value in defense.Resist do
			if not DamageTypes.exists(damageType) then
				table.insert(errors, `{where}: unknown resist type "{damageType}"`)
			elseif not isNumber(value, -1, 1) then
				table.insert(errors, `{where}: Resist.{damageType} must be between -1 and 1`)
			end
		end
	end
end

local function checkStatusList(errors: { string }, where: string, list: any, statuses: { [string]: any })
	if list == nil then
		return
	end
	for i, application in list do
		if type(application) ~= "table" or statuses[application.Id] == nil then
			table.insert(errors, `{where}[{i}]: unknown status effect "{application and application.Id}"`)
		elseif application.Chance ~= nil and not isNumber(application.Chance, 0, 1) then
			table.insert(errors, `{where}[{i}]: Chance must be between 0 and 1`)
		end
	end
end

local function checkPoolCost(errors: { string }, where: string, cost: any)
	if cost == nil then
		return
	end
	if type(cost) ~= "table" or type(cost.Pool) ~= "string" or not isNumber(cost.Amount, 0) then
		table.insert(errors, where .. ": must be { Pool = string, Amount = number >= 0 }")
	end
end

local function validateAttack(errors: { string }, where: string, attack: any, statuses: { [string]: any })
	if type(attack) ~= "table" then
		table.insert(errors, `{where}: attack must be a table`)
		return
	end
	if not DELIVERIES[attack.Delivery] then
		table.insert(errors, `{where}: unknown Delivery "{attack.Delivery}"`)
	end
	if not isNumber(attack.Windup, 0) then
		table.insert(errors, `{where}: Windup must be >= 0`)
	end
	if not isNumber(attack.Recovery, 0) then
		table.insert(errors, `{where}: Recovery must be >= 0`)
	end
	if attack.Cooldown ~= nil and not isNumber(attack.Cooldown, 0) then
		table.insert(errors, `{where}: Cooldown must be >= 0`)
	end
	if attack.ArmorPenetration ~= nil and not isNumber(attack.ArmorPenetration, 0, 1) then
		table.insert(errors, `{where}: ArmorPenetration must be between 0 and 1`)
	end
	if attack.RecoveryVulnerability ~= nil and not isNumber(attack.RecoveryVulnerability, 1) then
		table.insert(errors, `{where}: RecoveryVulnerability must be >= 1`)
	end
	checkPoolCost(errors, `{where}.Cost`, attack.Cost)

	if attack.Damage ~= nil then
		for i, component in attack.Damage do
			if type(component) ~= "table" or not DamageTypes.exists(component.Type) then
				table.insert(errors, `{where}.Damage[{i}]: unknown damage type "{component and component.Type}"`)
			elseif not isNumber(component.Amount, 0) then
				table.insert(errors, `{where}.Damage[{i}]: Amount must be >= 0`)
			end
		end
	end

	if attack.Delivery == "Melee" and not isNumber(attack.Range, 0) then
		table.insert(errors, `{where}: Melee attacks need Range`)
	elseif attack.Delivery == "Area" and (not isNumber(attack.Radius, 0) or not isNumber(attack.Range, 0)) then
		table.insert(errors, `{where}: Area attacks need Range and Radius`)
	elseif attack.Delivery == "Projectile" then
		local p = attack.Projectile
		if type(p) ~= "table" or not isNumber(p.Speed, 0.001) or not isNumber(p.Radius, 0) or not isNumber(p.MaxRange, 0) then
			table.insert(errors, where .. ": Projectile attacks need Projectile = { Speed, Radius, MaxRange }")
		end
	end
	if attack.Delivery ~= "Self" and (attack.Damage == nil or #attack.Damage == 0) and attack.OnHit == nil then
		table.insert(errors, `{where}: targeted attack has no Damage and no OnHit effects`)
	end
	if attack.Ammo ~= nil and (not isNumber(attack.Ammo.Capacity, 1) or not isNumber(attack.Ammo.ReloadTime, 0)) then
		table.insert(errors, `{where}: Ammo needs Capacity >= 1 and ReloadTime >= 0`)
	end

	checkStatusList(errors, `{where}.OnHit`, attack.OnHit, statuses)
	checkStatusList(errors, `{where}.OnSelf`, attack.OnSelf, statuses)
end

function Definitions.validateWeapon(id: string, def: any, statuses: { [string]: any }): { string }
	local errors = {}
	local where = `Weapons.{id}`
	if type(def) ~= "table" then
		return { `{where}: must be a table` }
	end
	if type(def.Name) ~= "string" then
		table.insert(errors, `{where}: Name must be a string`)
	end
	if type(def.Family) ~= "string" then
		table.insert(errors, `{where}: Family must be a string`)
	end
	if not ARCHETYPES[def.Archetype] then
		table.insert(errors, `{where}: unknown Archetype "{def.Archetype}"`)
	end
	if not HAND_SLOTS[def.Slot] then
		table.insert(errors, `{where}: Slot must be MainHand or OffHand`)
	end
	if not isNumber(def.Tier, 1) then
		table.insert(errors, `{where}: Tier must be >= 1`)
	end
	checkGate(errors, where, def.Unlock)
	checkDefense(errors, where, def.Defense)
	if type(def.Attacks) ~= "table" then
		table.insert(errors, `{where}: Attacks must be a table (can be empty)`)
	else
		for attackId, attack in def.Attacks do
			validateAttack(errors, `{where}.Attacks.{attackId}`, attack, statuses)
		end
	end
	if def.Block ~= nil then
		local b = def.Block
		if not isNumber(b.Reduction, 0, 1) or not isNumber(b.Arc, 0, 360) or not isNumber(b.StaminaPerDamage, 0) then
			table.insert(errors, `{where}: Block needs Reduction 0..1, Arc 0..360, StaminaPerDamage >= 0`)
		end
	end
	return errors
end

local function validateArmor(errors: { string }, id: string, def: any)
	local where = `Armor.{id}`
	if type(def) ~= "table" then
		table.insert(errors, `{where}: must be a table`)
		return
	end
	if not ARMOR_SLOTS[def.Slot] then
		table.insert(errors, `{where}: Slot must be Head, Body, Cloak or Talisman`)
	end
	if not isNumber(def.Tier, 1) then
		table.insert(errors, `{where}: Tier must be >= 1`)
	end
	checkGate(errors, where, def.Unlock)
	if def.Defense == nil then
		table.insert(errors, `{where}: Defense is required`)
	end
	checkDefense(errors, where, def.Defense)
end

local function validateConsumable(errors: { string }, id: string, def: any, statuses: { [string]: any })
	local where = `Consumables.{id}`
	if type(def) ~= "table" then
		table.insert(errors, `{where}: must be a table`)
		return
	end
	if not isNumber(def.Cooldown, 0) then
		table.insert(errors, `{where}: Cooldown must be >= 0`)
	end
	if def.Heal ~= nil and not isNumber(def.Heal, 0) then
		table.insert(errors, `{where}: Heal must be >= 0`)
	end
	if def.Restore ~= nil then
		for i, restore in def.Restore do
			checkPoolCost(errors, `{where}.Restore[{i}]`, restore)
		end
	end
	checkGate(errors, where, def.Unlock)
	checkStatusList(errors, `{where}.Apply`, def.Apply, statuses)
end

local function validateStatus(errors: { string }, id: string, def: any)
	local where = `StatusEffects.{id}`
	if type(def) ~= "table" then
		table.insert(errors, `{where}: must be a table`)
		return
	end
	if not isNumber(def.Duration, 0) then
		table.insert(errors, `{where}: Duration must be >= 0`)
	end
	if not STACKING[def.Stacking] then
		table.insert(errors, `{where}: Stacking must be Refresh, Stack or Ignore`)
	end
	if def.Stacking == "Stack" and not isNumber(def.MaxStacks, 1) then
		table.insert(errors, `{where}: Stack effects need MaxStacks >= 1`)
	end
	if def.Evasion ~= nil and not isNumber(def.Evasion, 0, 1) then
		table.insert(errors, `{where}: Evasion must be between 0 and 1`)
	end
	if def.Reflect ~= nil and not isNumber(def.Reflect, 0, 1) then
		table.insert(errors, `{where}: Reflect must be between 0 and 1`)
	end
	if def.DamagePerSecond ~= nil and not DamageTypes.exists(def.DamagePerSecond.Type) then
		table.insert(errors, `{where}: unknown DamagePerSecond type`)
	end
	checkDefense(errors, where, def.Defense)
end

-- Copies each entry, stamps its Id from the table key, and deep-freezes it.
local function deepFreeze(value: any): any
	if type(value) ~= "table" or table.isfrozen(value) then
		return value
	end
	for _, child in value do
		deepFreeze(child)
	end
	return table.freeze(value)
end

local function stamp(source: { [string]: any }): { [string]: any }
	local out: { [string]: any } = {}
	for id, def in source do
		local copy = table.clone(def)
		copy.Id = id
		out[id] = deepFreeze(copy)
	end
	return table.freeze(out)
end

function Definitions.build(raw: Raw): (Defs?, { string })
	local errors: { string } = {}

	for id, def in raw.StatusEffects do
		validateStatus(errors, id, def)
	end
	for id, def in raw.Weapons do
		for _, e in Definitions.validateWeapon(id, def, raw.StatusEffects) do
			table.insert(errors, e)
		end
	end
	for id, def in raw.Armor do
		validateArmor(errors, id, def)
	end
	for id, def in raw.Consumables do
		validateConsumable(errors, id, def, raw.StatusEffects)
	end

	if #errors > 0 then
		table.sort(errors)
		return nil, errors
	end

	return table.freeze({
		Weapons = stamp(raw.Weapons),
		Armor = stamp(raw.Armor),
		Consumables = stamp(raw.Consumables),
		StatusEffects = stamp(raw.StatusEffects),
	}) :: any, errors
end

local cached: Defs? = nil

function Definitions.get(): Defs
	if cached then
		return cached
	end
	local defs, errors = Definitions.build({
		Weapons = require("./Data/Weapons") :: any,
		Armor = require("./Data/Armor") :: any,
		Consumables = require("./Data/Consumables") :: any,
		StatusEffects = require("./Data/StatusEffects") :: any,
	})
	if defs == nil then
		error("[Combat] Invalid combat data:\n  " .. table.concat(errors, "\n  "))
	end
	cached = defs
	return defs
end

return table.freeze(Definitions)
