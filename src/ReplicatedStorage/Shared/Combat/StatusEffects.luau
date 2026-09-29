--!strict
-- Applies, stacks, ticks, cleanses and aggregates status effects on a combatant.
-- Pure module: callers pass the current time. Effect behavior comes only from
-- the StatusEffectDef fields, never from effect ids.

local Types = require("./Types")

type Combatant = Types.Combatant
type StatusEffectDef = Types.StatusEffectDef
type ActiveStatus = Types.ActiveStatus
type DamageComponent = Types.DamageComponent

export type Modifiers = {
	DamageTaken: number,
	DamageDealt: number,
	MoveSpeed: number,
	Armor: number,
	Resist: { [string]: number },
	Reflect: number,
	Evasion: number,
	PreventsActions: boolean,
	ImmuneTags: { [string]: boolean },
}

export type Tick = {
	Damage: { DamageComponent & { SourceId: string? } },
	Heal: number,
}

local StatusEffects = {}

local function hasTag(def: StatusEffectDef, tag: string): boolean
	return def.Tags ~= nil and table.find(def.Tags, tag) ~= nil
end

function StatusEffects.isImmune(c: Combatant, def: StatusEffectDef): boolean
	if def.Tags == nil then
		return false
	end
	for _, active in c.Statuses do
		local immune = active.Def.ImmuneToTags
		if immune then
			for _, tag in immune do
				if hasTag(def, tag) then
					return true
				end
			end
		end
	end
	return false
end

-- Returns true if the effect was applied (or refreshed / stacked).
function StatusEffects.apply(c: Combatant, def: StatusEffectDef, now: number, duration: number?, sourceId: string?): boolean
	if not c.Alive or StatusEffects.isImmune(c, def) then
		return false
	end
	local length = duration or def.Duration
	local active = c.Statuses[def.Id]

	if active == nil then
		c.Statuses[def.Id] = {
			Def = def,
			Stacks = 1,
			ExpiresAt = now + length,
			SourceId = sourceId,
			NextTickAt = if def.DamagePerSecond or def.HealPerSecond then now + 1 else nil,
			Absorb = def.Absorb,
		}
		return true
	end

	if def.Stacking == "Ignore" then
		return false
	end
	if def.Stacking == "Stack" then
		active.Stacks = math.min(active.Stacks + 1, def.MaxStacks or 1)
	end
	active.ExpiresAt = math.max(active.ExpiresAt, now + length)
	active.SourceId = sourceId or active.SourceId
	if def.Absorb then
		active.Absorb = def.Absorb -- refresh the barrier
	end
	return true
end

function StatusEffects.remove(c: Combatant, id: string)
	c.Statuses[id] = nil
end

-- Removes every active effect having any of `tags`. Returns the removed ids.
function StatusEffects.cleanse(c: Combatant, tags: { string }): { string }
	local removed = {}
	for id, active in c.Statuses do
		for _, tag in tags do
			if hasTag(active.Def, tag) then
				table.insert(removed, id)
				break
			end
		end
	end
	for _, id in removed do
		c.Statuses[id] = nil
	end
	table.sort(removed)
	return removed
end

-- Removes expired effects and effects whose barrier was used up.
function StatusEffects.expire(c: Combatant, now: number): { string }
	local expired = {}
	for id, active in c.Statuses do
		local barrierGone = active.Def.Absorb ~= nil and (active.Absorb or 0) <= 0
		if now >= active.ExpiresAt or barrierGone then
			table.insert(expired, id)
		end
	end
	for _, id in expired do
		c.Statuses[id] = nil
	end
	table.sort(expired)
	return expired
end

-- Collects damage-over-time and heal-over-time due since the last tick.
-- Ticks happen once per second per effect and scale with stacks.
function StatusEffects.collectTicks(c: Combatant, now: number): Tick
	local result: Tick = { Damage = {}, Heal = 0 }
	for _, active in c.Statuses do
		local nextTick = active.NextTickAt
		while nextTick and nextTick <= now and nextTick <= active.ExpiresAt do
			local dps = active.Def.DamagePerSecond
			if dps then
				table.insert(result.Damage, { Type = dps.Type, Amount = dps.Amount * active.Stacks, SourceId = active.SourceId })
			end
			if active.Def.HealPerSecond then
				result.Heal += active.Def.HealPerSecond * active.Stacks
			end
			nextTick += 1
		end
		active.NextTickAt = nextTick
	end
	return result
end

-- Barrier hit points currently available.
function StatusEffects.totalAbsorb(c: Combatant): number
	local total = 0
	for _, active in c.Statuses do
		total += active.Absorb or 0
	end
	return total
end

-- Consumes up to `amount` from barriers (oldest expiry first). Returns amount absorbed.
function StatusEffects.consumeAbsorb(c: Combatant, amount: number): number
	local barriers: { ActiveStatus } = {}
	for _, active in c.Statuses do
		if (active.Absorb or 0) > 0 then
			table.insert(barriers, active)
		end
	end
	table.sort(barriers, function(a: ActiveStatus, b: ActiveStatus): boolean
		return a.ExpiresAt < b.ExpiresAt
	end)
	local absorbed = 0
	for _, active in barriers do
		if amount <= 0 then
			break
		end
		local take = math.min(active.Absorb :: number, amount)
		active.Absorb = (active.Absorb :: number) - take
		amount -= take
		absorbed += take
	end
	return absorbed
end

-- Combined effect of every active status. Multipliers multiply (per stack),
-- flat values add, evasion combines as independent chances, reflect adds (capped at 0.9).
function StatusEffects.modifiers(c: Combatant): Modifiers
	local mods: Modifiers = {
		DamageTaken = 1,
		DamageDealt = 1,
		MoveSpeed = 1,
		Armor = 0,
		Resist = {},
		Reflect = 0,
		Evasion = 0,
		PreventsActions = false,
		ImmuneTags = {},
	}
	local notEvaded = 1
	for _, active in c.Statuses do
		local def, stacks = active.Def, active.Stacks
		if def.DamageTakenMultiplier then
			mods.DamageTaken *= def.DamageTakenMultiplier ^ stacks
		end
		if def.DamageDealtMultiplier then
			mods.DamageDealt *= def.DamageDealtMultiplier ^ stacks
		end
		if def.MoveSpeedMultiplier then
			mods.MoveSpeed *= def.MoveSpeedMultiplier
		end
		if def.Defense then
			mods.Armor += (def.Defense.Armor or 0) * stacks
			if def.Defense.Resist then
				for damageType, value in def.Defense.Resist do
					mods.Resist[damageType] = (mods.Resist[damageType] or 0) + value * stacks
				end
			end
		end
		if def.Reflect then
			mods.Reflect += def.Reflect
		end
		if def.Evasion then
			notEvaded *= 1 - def.Evasion
		end
		if def.PreventsActions then
			mods.PreventsActions = true
		end
		if def.ImmuneToTags then
			for _, tag in def.ImmuneToTags do
				mods.ImmuneTags[tag] = true
			end
		end
	end
	mods.Reflect = math.min(mods.Reflect, 0.9)
	mods.Evasion = 1 - notEvaded
	return mods
end

return table.freeze(StatusEffects)
