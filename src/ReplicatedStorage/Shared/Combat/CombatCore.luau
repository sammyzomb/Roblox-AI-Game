--!strict
-- Weapon-agnostic combat rules shared by PvE and PvP.
--
-- Pure module: no Roblox APIs, no clocks, no randomness of its own. The server
-- (CombatService) owns time, geometry and networking and calls into this.
-- Every function reads only data fields (AttackDef, StatusEffectDef, ...);
-- nothing here knows about specific weapons, families or modes.
--
-- Lifecycle of an attack:
--   1. beginAttack   validate + pay costs, returns a plan with ImpactAt
--   2. (server waits until ImpactAt; interrupts may cancel the plan)
--   3. isPlanValid   is the plan still current?
--   4. checkReach    is each candidate target valid and in reach? (geometry passed in)
--   5. applyHit      damage + effects on each target, or applySelf for Self attacks
--
-- See docs/COMBAT_API.md for the full public API and extension points.

local Types = require("./Types")
local Definitions = require("./Definitions")
local DamageCalculator = require("./DamageCalculator")
local Resources = require("./Resources")
local StatusEffects = require("./StatusEffects")
local Rulesets = require("./Rulesets")
local ProgressionGates = require("../ProgressionGates")

type Combatant = Types.Combatant
type WeaponDef = Types.WeaponDef
type ArmorDef = Types.ArmorDef
type AttackDef = Types.AttackDef
type Ruleset = Types.Ruleset
type HitResult = Types.HitResult
type Slot = Types.Slot
type StatusApplication = Types.StatusApplication
type Defs = Definitions.Defs

export type PoolSettings = { Max: number, Regen: number, RegenDelay: number }

export type Settings = DamageCalculator.Settings & {
	Pools: { [string]: PoolSettings },
	MeleeRangeTolerance: number, -- extra studs allowed for latency
	MeleeArcTolerance: number, -- extra degrees allowed for latency
	BlockStartDelay: number, -- seconds before a raised guard counts (anti-spam)
}

export type CombatantSpec = {
	Id: string,
	Kind: Types.CombatantKind,
	Team: string?,
	Level: number,
	MaxHealth: number,
	Pools: { [string]: PoolSettings }?, -- defaults to Settings.Pools
	BaseDefense: Types.DefenseProfile?,
}

export type Plan = {
	Token: number,
	Weapon: WeaponDef,
	AttackId: string,
	Attack: AttackDef,
	StartedAt: number,
	ImpactAt: number,
}

-- Geometry measured by the server at impact time.
export type Reach = {
	Distance: number, -- studs from attacker to target edge (Melee) or from impact point (Area)
	Angle: number?, -- degrees between attacker facing and direction to target (Melee)
}

export type HitOptions = {
	Random: (() -> number)?, -- returns [0,1); defaults to math.random
	-- Degrees between the TARGET's facing and the direction to the attacker.
	-- Needed for blocking; nil means "unknown" and the hit is not blockable.
	AngleFromTargetFacing: number?,
}

export type TickResult = {
	Damage: number,
	Healed: number,
	Expired: { string },
	Killed: boolean,
	KillerId: string?,
}

local CombatCore = {}
CombatCore.__index = CombatCore

local function defaultRandom(): number
	return math.random()
end

export type Engine = typeof(setmetatable({} :: { Defs: Defs, Settings: Settings }, CombatCore))

local function emptyResult(reason: string?): HitResult
	return {
		Hit = false,
		Reason = reason,
		Raw = 0,
		Damage = 0,
		Absorbed = 0,
		Blocked = 0,
		Reflected = 0,
		Killed = false,
		GuardBroken = false,
		AppliedStatuses = {},
	}
end

function CombatCore.new(defs: Defs, settings: Settings): Engine
	return setmetatable({ Defs = defs, Settings = settings }, CombatCore)
end

---------------------------------------------------------------------------
-- Combatants
---------------------------------------------------------------------------

function CombatCore.newCombatant(self: Engine, spec: CombatantSpec): Combatant
	local pools = {}
	for id, p in spec.Pools or self.Settings.Pools do
		pools[id] = Resources.newPool(p.Max, p.Regen, p.RegenDelay)
	end
	return {
		Id = spec.Id,
		Kind = spec.Kind,
		Team = spec.Team,
		Level = spec.Level,
		Alive = true,
		Health = spec.MaxHealth,
		MaxHealth = spec.MaxHealth,
		Pools = pools,
		Loadout = { Armor = {} },
		BaseDefense = spec.BaseDefense or {},
		Statuses = {},
		Cooldowns = {},
		Ammo = {},
		BusyUntil = 0,
		VulnerableFrom = 0,
		VulnerableUntil = 0,
		VulnerabilityMultiplier = 1,
		Blocking = false,
		BlockSince = 0,
		Pending = nil,
		NextToken = 1,
	} :: any
end

-- Combined defense from base stats, equipped weapons/shields, armor and statuses.
function CombatCore.defenseProfile(_self: Engine, c: Combatant): DamageCalculator.DefenseProfile
	local armor = 0
	local resist: { [string]: number } = {}
	local function add(profile: Types.DefenseProfile?)
		if profile == nil then
			return
		end
		armor += profile.Armor or 0
		if profile.Resist then
			for damageType, value in profile.Resist do
				resist[damageType] = (resist[damageType] or 0) + value
			end
		end
	end
	add(c.BaseDefense)
	add(c.Loadout.MainHand and c.Loadout.MainHand.Defense)
	add(c.Loadout.OffHand and c.Loadout.OffHand.Defense)
	for _, piece in c.Loadout.Armor do
		add(piece.Defense)
	end
	local mods = StatusEffects.modifiers(c)
	armor += mods.Armor
	for damageType, value in mods.Resist do
		resist[damageType] = (resist[damageType] or 0) + value
	end
	return { Armor = armor, Resist = resist }
end

---------------------------------------------------------------------------
-- Equipment and progression gates
---------------------------------------------------------------------------

-- Equips a weapon or shield by id. `profile` is the player's progression
-- (nil for NPCs, which skip gates). Handles two-handed rules.
function CombatCore.equipWeapon(self: Engine, c: Combatant, weaponId: string, profile: ProgressionGates.Profile?): (boolean, string?)
	local def = self.Defs.Weapons[weaponId]
	if def == nil then
		return false, "UnknownItem"
	end
	if profile then
		local ok, reason = ProgressionGates.check(def.Unlock, profile)
		if not ok then
			return false, reason
		end
	end
	if c.Pending or c.Blocking then
		return false, "Busy"
	end
	if def.Slot == "MainHand" then
		c.Loadout.MainHand = def
		if def.TwoHanded then
			c.Loadout.OffHand = nil
		end
	else
		if c.Loadout.MainHand and c.Loadout.MainHand.TwoHanded then
			return false, "HandsFull"
		end
		c.Loadout.OffHand = def
	end
	return true, nil
end

function CombatCore.unequip(_self: Engine, c: Combatant, slot: Slot)
	if slot == "MainHand" then
		c.Loadout.MainHand = nil
	elseif slot == "OffHand" then
		c.Loadout.OffHand = nil
		c.Blocking = false
	else
		for i = #c.Loadout.Armor, 1, -1 do
			if c.Loadout.Armor[i].Slot == slot then
				table.remove(c.Loadout.Armor, i)
			end
		end
	end
end

-- Equips armor by id, replacing whatever is in the same slot.
function CombatCore.equipArmor(self: Engine, c: Combatant, armorId: string, profile: ProgressionGates.Profile?): (boolean, string?)
	local def = self.Defs.Armor[armorId]
	if def == nil then
		return false, "UnknownItem"
	end
	if profile then
		local ok, reason = ProgressionGates.check(def.Unlock, profile)
		if not ok then
			return false, reason
		end
	end
	self:unequip(c, def.Slot)
	table.insert(c.Loadout.Armor, def)
	return true, nil
end

---------------------------------------------------------------------------
-- Attacks
---------------------------------------------------------------------------

local function weaponIn(c: Combatant, slot: Slot): WeaponDef?
	if slot == "MainHand" then
		return c.Loadout.MainHand
	elseif slot == "OffHand" then
		return c.Loadout.OffHand
	end
	return nil
end

local function cooldownKey(weapon: WeaponDef, attackId: string): string
	return `{weapon.Id}:{attackId}`
end

function CombatCore.canAct(_self: Engine, c: Combatant, now: number): (boolean, string?)
	if not c.Alive then
		return false, "Dead"
	end
	if StatusEffects.modifiers(c).PreventsActions then
		return false, "Stunned"
	end
	if c.Pending or now < c.BusyUntil then
		return false, "Busy"
	end
	return true, nil
end

-- Validates and starts an attack: checks state, cooldown, ammo and resources,
-- pays the costs and returns a plan. Nothing is paid if validation fails.
function CombatCore.beginAttack(self: Engine, c: Combatant, slot: Slot, attackId: string, now: number): (Plan?, string?)
	local weapon = weaponIn(c, slot)
	if weapon == nil then
		return nil, "NoWeapon"
	end
	local attack = weapon.Attacks[attackId]
	if attack == nil then
		return nil, "UnknownAttack"
	end
	local canAct, why = self:canAct(c, now)
	if not canAct then
		return nil, why
	end
	if c.Blocking then
		return nil, "Blocking"
	end

	local key = cooldownKey(weapon, attackId)
	if now < (c.Cooldowns[key] or 0) then
		return nil, "Cooldown"
	end

	local ammo = nil
	if attack.Ammo then
		ammo = c.Ammo[key]
		if ammo == nil then
			ammo = { Loaded = attack.Ammo.Capacity, ReloadUntil = 0 }
			c.Ammo[key] = ammo
		end
		if ammo.Loaded <= 0 then
			if now < ammo.ReloadUntil then
				return nil, "Reloading"
			end
			ammo.Loaded = attack.Ammo.Capacity
		end
	end

	local cost = attack.Cost
	if cost and not Resources.canSpend(c.Pools[cost.Pool], cost.Amount) then
		return nil, `Not enough {cost.Pool}`
	end

	-- Everything validated: pay.
	if cost then
		Resources.spend(c.Pools[cost.Pool], cost.Amount, now)
	end
	if ammo and attack.Ammo then
		ammo.Loaded -= 1
		if ammo.Loaded <= 0 then
			ammo.ReloadUntil = now + attack.Windup + attack.Ammo.ReloadTime
		end
	end
	c.Cooldowns[key] = now + (attack.Cooldown or 0)

	local impactAt = now + attack.Windup
	c.BusyUntil = impactAt + attack.Recovery
	if attack.RecoveryVulnerability and attack.RecoveryVulnerability > 1 then
		c.VulnerableFrom = impactAt
		c.VulnerableUntil = c.BusyUntil
		c.VulnerabilityMultiplier = attack.RecoveryVulnerability
	end

	local token = c.NextToken
	c.NextToken += 1
	c.Pending = { Token = token, WeaponSlot = slot, AttackId = attackId, ImpactAt = impactAt }

	return {
		Token = token,
		Weapon = weapon,
		AttackId = attackId,
		Attack = attack,
		StartedAt = now,
		ImpactAt = impactAt,
	}, nil
end

-- True if `plan` is still the combatant's current attack (not interrupted, not dead).
function CombatCore.isPlanValid(_self: Engine, c: Combatant, plan: Plan): boolean
	return c.Alive and c.Pending ~= nil and c.Pending.Token == plan.Token
end

-- Call at impact time, after the hits (or the Self effect) are resolved.
function CombatCore.finishAttack(_self: Engine, c: Combatant, plan: Plan)
	if c.Pending and c.Pending.Token == plan.Token then
		c.Pending = nil
	end
end

-- Cancels a pending attack. Costs are not refunded; recovery is shortened.
function CombatCore.interrupt(_self: Engine, c: Combatant, now: number): boolean
	if c.Pending == nil then
		return false
	end
	c.Pending = nil
	c.BusyUntil = math.min(c.BusyUntil, now + 0.25)
	c.VulnerableUntil = math.min(c.VulnerableUntil, now)
	return true
end

-- Target + geometry validation at impact time.
function CombatCore.checkReach(self: Engine, attacker: Combatant, target: Combatant, attack: AttackDef, ruleset: Ruleset, reach: Reach): (boolean, string?)
	local ok, reason = Rulesets.canTarget(ruleset, attacker, target)
	if not ok then
		return false, reason
	end
	local s = self.Settings
	if attack.Delivery == "Melee" then
		if reach.Distance > (attack.Range or 0) + s.MeleeRangeTolerance then
			return false, "OutOfRange"
		end
		local halfArc = (attack.Arc or 90) / 2 + s.MeleeArcTolerance
		if reach.Angle == nil or reach.Angle > halfArc then
			return false, "OutOfArc"
		end
	elseif attack.Delivery == "Area" then
		if reach.Distance > (attack.Radius or 0) then
			return false, "OutOfRange"
		end
	elseif attack.Delivery == "Self" then
		return false, "SelfOnly"
	end
	-- Projectile reach is decided by the projectile simulation itself.
	return true, nil
end

local function applyStatuses(self: Engine, target: Combatant, list: { StatusApplication }?, now: number, sourceId: string?, random: () -> number): { string }
	local applied = {}
	if list == nil then
		return applied
	end
	for _, application in list do
		local def = self.Defs.StatusEffects[application.Id]
		if def and random() < (application.Chance or 1) then
			if StatusEffects.apply(target, def, now, application.Duration, sourceId) then
				table.insert(applied, def.Id)
				if def.Interrupts and target.Pending then
					local pendingWeapon = weaponIn(target, target.Pending.WeaponSlot)
					local pendingAttack = pendingWeapon and pendingWeapon.Attacks[target.Pending.AttackId]
					if pendingAttack and pendingAttack.Interruptible then
						self:interrupt(target, now)
					end
				end
			end
		end
	end
	return applied
end

local function kill(c: Combatant)
	c.Health = 0
	c.Alive = false
	c.Pending = nil
	c.Blocking = false
end

-- Heals respecting the ruleset's healing multiplier. Returns amount healed.
function CombatCore.heal(_self: Engine, c: Combatant, amount: number, ruleset: Ruleset?): number
	if not c.Alive or amount <= 0 then
		return 0
	end
	local scaled = amount * (if ruleset and ruleset.HealingMultiplier then ruleset.HealingMultiplier else 1)
	local before = c.Health
	c.Health = math.min(c.MaxHealth, c.Health + scaled)
	return c.Health - before
end

-- Resolves one hit of `attack` from `attacker` on `target`. Call once per target
-- after checkReach (or after a projectile collision). Mutates both combatants.
function CombatCore.applyHit(self: Engine, attacker: Combatant, target: Combatant, weapon: WeaponDef, attack: AttackDef, ruleset: Ruleset, now: number, options: HitOptions?): HitResult
	local opts: HitOptions = options or {}
	local random = opts.Random or defaultRandom
	local facingAngle = opts.AngleFromTargetFacing

	local ok, reason = Rulesets.canTarget(ruleset, attacker, target)
	if not ok then
		return emptyResult(reason)
	end

	local targetMods = StatusEffects.modifiers(target)
	if targetMods.Evasion > 0 and random() < targetMods.Evasion then
		return emptyResult("Evaded")
	end

	local attackerMods = StatusEffects.modifiers(attacker)
	local taken = targetMods.DamageTaken
	if now >= target.VulnerableFrom and now < target.VulnerableUntil then
		taken *= target.VulnerabilityMultiplier
	end

	local breakdown = DamageCalculator.compute({
		Components = attack.Damage or {},
		AttackerLevel = attacker.Level,
		Archetype = weapon.Archetype,
		ArmorPenetration = attack.ArmorPenetration,
		DealtMultiplier = attackerMods.DamageDealt,
		TakenMultiplier = taken,
		Defense = self:defenseProfile(target),
		Ruleset = ruleset,
	}, self.Settings)

	local result = emptyResult(nil)
	result.Hit = true
	result.Raw = breakdown.Raw
	local remaining = breakdown.Final

	-- Blocking: frontal, blockable hits only, after the guard has been up briefly.
	local shield = target.Loadout.OffHand and target.Loadout.OffHand.Block
		or target.Loadout.MainHand and target.Loadout.MainHand.Block
	if
		shield
		and target.Blocking
		and now - target.BlockSince >= self.Settings.BlockStartDelay
		and attack.Blockable ~= false
		and facingAngle ~= nil
		and facingAngle <= shield.Arc / 2
		and remaining > 0
	then
		local wanted = remaining * shield.Reduction
		local staminaNeeded = wanted * shield.StaminaPerDamage
		local stamina = target.Pools.Stamina
		local drained = Resources.drain(stamina, staminaNeeded, now)
		local blocked = if staminaNeeded > 0 then wanted * (drained / staminaNeeded) else wanted
		if drained < staminaNeeded then
			result.GuardBroken = true
			target.Blocking = false
		end
		result.Blocked = blocked
		remaining -= blocked
	end

	-- Barriers.
	if remaining > 0 then
		local absorbed = StatusEffects.consumeAbsorb(target, remaining)
		result.Absorbed = absorbed
		remaining -= absorbed
	end

	-- Health.
	remaining = math.floor(remaining + 0.5)
	result.Damage = math.min(remaining, target.Health)
	target.Health -= result.Damage
	if target.Health <= 0 then
		kill(target)
		result.Killed = true
	end

	-- Reflect only punishes close-range hits.
	if attack.Delivery == "Melee" and targetMods.Reflect > 0 and result.Damage + result.Absorbed > 0 and attacker.Alive then
		local reflected = math.floor((result.Damage + result.Absorbed) * targetMods.Reflect + 0.5)
		reflected = math.min(reflected, attacker.Health)
		attacker.Health -= reflected
		result.Reflected = reflected
		if attacker.Health <= 0 then
			kill(attacker)
		end
	end

	-- On-hit effects land unless the hit was fully stopped by a guard.
	local fullyBlocked = result.Blocked > 0 and not result.GuardBroken and result.Damage == 0
	if target.Alive and not fullyBlocked then
		result.AppliedStatuses = applyStatuses(self, target, attack.OnHit, now, attacker.Id, random)
	end
	if result.GuardBroken and target.Alive then
		local stagger = self.Defs.StatusEffects.Stagger
		if stagger and StatusEffects.apply(target, stagger, now, nil, attacker.Id) then
			table.insert(result.AppliedStatuses, "Stagger")
		end
	end

	return result
end

-- Resolves the user-side part of an attack: OnSelf effects and Heal.
-- For Delivery == "Self" this is the whole attack; other deliveries may also
-- have OnSelf effects (e.g. a lunge that grants a short buff).
function CombatCore.applySelf(self: Engine, c: Combatant, plan: Plan, ruleset: Ruleset?, now: number, random: (() -> number)?): { string }
	if not c.Alive then
		return {}
	end
	local applied = applyStatuses(self, c, plan.Attack.OnSelf, now, c.Id, random or defaultRandom)
	if plan.Attack.Heal then
		self:heal(c, plan.Attack.Heal, ruleset)
	end
	return applied
end

---------------------------------------------------------------------------
-- Defense actions
---------------------------------------------------------------------------

function CombatCore.setBlocking(self: Engine, c: Combatant, active: boolean, now: number): (boolean, string?)
	if not active then
		c.Blocking = false
		return true, nil
	end
	local shield = (c.Loadout.OffHand and c.Loadout.OffHand.Block) or (c.Loadout.MainHand and c.Loadout.MainHand.Block)
	if shield == nil then
		return false, "NoShield"
	end
	local canAct, why = self:canAct(c, now)
	if not canAct then
		return false, why
	end
	local stamina = c.Pools.Stamina
	if stamina == nil or stamina.Current <= 0 then
		return false, "Not enough Stamina"
	end
	if not c.Blocking then
		c.Blocking = true
		c.BlockSince = now
	end
	return true, nil
end

-- Uses a defensive item / consumable. `profile` gates it for players.
function CombatCore.useConsumable(self: Engine, c: Combatant, itemId: string, now: number, profile: ProgressionGates.Profile?, ruleset: Ruleset?): (boolean, string?)
	local def = self.Defs.Consumables[itemId]
	if def == nil then
		return false, "UnknownItem"
	end
	if not c.Alive then
		return false, "Dead"
	end
	if profile then
		local ok, reason = ProgressionGates.check(def.Unlock, profile)
		if not ok then
			return false, reason
		end
	end
	if StatusEffects.modifiers(c).PreventsActions and not (def.Cleanse and table.find(def.Cleanse, "CrowdControl")) then
		return false, "Stunned"
	end
	local key = `item:{def.CooldownGroup or def.Id}`
	if now < (c.Cooldowns[key] or 0) then
		return false, "Cooldown"
	end
	c.Cooldowns[key] = now + def.Cooldown

	if def.Cleanse then
		StatusEffects.cleanse(c, def.Cleanse)
	end
	if def.Heal then
		self:heal(c, def.Heal, ruleset)
	end
	if def.Restore then
		for _, restore in def.Restore do
			Resources.restore(c.Pools[restore.Pool], restore.Amount)
		end
	end
	applyStatuses(self, c, def.Apply, now, c.Id, defaultRandom)
	return true, nil
end

---------------------------------------------------------------------------
-- Per-frame upkeep
---------------------------------------------------------------------------

-- Regenerates pools (not while blocking), runs damage/heal over time, expires effects.
function CombatCore.tick(self: Engine, c: Combatant, now: number, dt: number, ruleset: Ruleset): TickResult
	local result: TickResult = { Damage = 0, Healed = 0, Expired = {}, Killed = false }
	if not c.Alive then
		return result
	end
	for id, pool in c.Pools do
		if not (id == "Stamina" and c.Blocking) then
			Resources.regen(pool, now, dt)
		end
	end

	local ticks = StatusEffects.collectTicks(c, now)
	if #ticks.Damage > 0 then
		local defense = self:defenseProfile(c)
		local total = 0
		for _, component in ticks.Damage do
			-- DoT ignores armor (it already got through) but respects resists.
			local resist = DamageCalculator.resist(defense, component.Type, ruleset)
			total += component.Amount * ruleset.DamageMultiplier * (1 - resist)
			result.KillerId = component.SourceId
		end
		total = math.floor(total + 0.5)
		local absorbed = StatusEffects.consumeAbsorb(c, total)
		local damage = math.min(total - absorbed, c.Health)
		c.Health -= damage
		result.Damage = damage
		if c.Health <= 0 then
			kill(c)
			result.Killed = true
			return result
		end
	end
	if ticks.Heal > 0 then
		result.Healed = self:heal(c, ticks.Heal, ruleset)
	end
	result.Expired = StatusEffects.expire(c, now)
	return result
end

-- Full reset for respawns / new rounds.
function CombatCore.revive(_self: Engine, c: Combatant, maxHealth: number?)
	c.MaxHealth = maxHealth or c.MaxHealth
	c.Health = c.MaxHealth
	c.Alive = true
	c.Statuses = {}
	c.Cooldowns = {}
	c.Ammo = {}
	c.Pending = nil
	c.Blocking = false
	c.BusyUntil = 0
	c.VulnerableFrom = 0
	c.VulnerableUntil = 0
	for _, pool in c.Pools do
		pool.Current = pool.Max
	end
end

return CombatCore
