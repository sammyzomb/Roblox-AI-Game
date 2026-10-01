--!strict
-- Shared combat type definitions. No runtime logic.
--
-- Everything combat-related is described by data that follows these shapes.
-- The combat core only ever reads these fields; it never branches on a
-- specific weapon id, family or name. New weapon classes are added by writing
-- new definitions, not by changing the core.

-- Damage type ids are strings so new types can be added in DamageTypes.luau
-- without touching any type here.
export type DamageTypeId = string

-- Broad combat style of a weapon. Used for balance knobs (ruleset
-- multipliers, UI grouping), never for hard-coded behavior.
export type Archetype = "Melee" | "RangedPhysical" | "Magic" | "Defense" | "Hybrid"

-- How an attack reaches its target. This is the only thing that decides
-- which server code path delivers the hit.
--   Melee      : instant check in a cone in front of the attacker at impact time
--   Projectile : server-simulated projectile, hits the first valid combatant
--   Area       : everything inside Radius around a point (self or aim point)
--   Self       : no target; applies effects to the user (defensive magic, stances)
export type Delivery = "Melee" | "Projectile" | "Area" | "Self"

export type ResourcePoolId = string -- "Stamina", "Mana", ... see Config.Combat.Pools

export type ResourceCost = {
	Pool: ResourcePoolId,
	Amount: number,
}

export type DamageComponent = {
	Type: DamageTypeId,
	Amount: number,
}

export type StatusApplication = {
	Id: string, -- StatusEffect id
	Chance: number?, -- 0..1, default 1
	Duration: number?, -- overrides the effect's default duration
}

export type ProjectileSpec = {
	Speed: number, -- studs per second
	Gravity: number?, -- studs per second^2 downward, default 0
	Radius: number, -- hit radius in studs
	MaxRange: number, -- projectile is removed after travelling this far
	Pierce: number?, -- extra combatants it can pass through, default 0
}

export type AmmoSpec = {
	Capacity: number, -- shots before a reload is needed
	ReloadTime: number, -- seconds
}

export type AttackDef = {
	Delivery: Delivery,
	Damage: { DamageComponent }?, -- may be empty for pure utility attacks
	Range: number?, -- Melee reach / Area cast range (studs)
	Arc: number?, -- Melee cone width in degrees, default 90
	Radius: number?, -- Area radius
	Projectile: ProjectileSpec?,
	Windup: number, -- seconds before impact (interruptible if Interruptible)
	Recovery: number, -- seconds after impact before the user can act again
	Cooldown: number?, -- seconds between uses of this attack, default 0
	Cost: ResourceCost?,
	Ammo: AmmoSpec?,
	ArmorPenetration: number?, -- 0..1 fraction of target armor ignored
	Interruptible: boolean?, -- can Interrupt statuses cancel the windup
	-- Risk knob for heavy attacks: damage-taken multiplier applied to the
	-- user from impact until the end of Recovery. 1 = no extra risk.
	RecoveryVulnerability: number?,
	Blockable: boolean?, -- default true
	OnHit: { StatusApplication }?, -- applied to each target hit
	OnSelf: { StatusApplication }?, -- applied to the user on use (defensive magic)
	Heal: number?, -- flat heal to the user on use
}

-- Values an item or effect adds to a combatant's defense.
export type DefenseProfile = {
	Armor: number?, -- flat, reduces physical-category damage
	Resist: { [DamageTypeId]: number }?, -- fraction 0..1 (negative = weakness)
}

export type BlockSpec = {
	Reduction: number, -- 0..1 fraction of blockable damage prevented
	Arc: number, -- degrees in front of the blocker that are protected
	StaminaPerDamage: number, -- stamina drained per point of damage blocked
	MoveSpeedMultiplier: number?, -- while blocking (presentation / movement layer)
}

-- An unlock rule. Every field present must be satisfied.
export type UnlockGate = {
	Level: number?,
	Milestones: { string }?,
}

export type Slot = "MainHand" | "OffHand" | "Head" | "Body" | "Cloak" | "Talisman"

-- Weapons, shields and staves. A shield is a weapon with Block and
-- (usually) no attacks.
export type WeaponDef = {
	Id: string,
	Name: string,
	Family: string, -- "LightMelee", "HeavyMelee", "Bow", ... free-form, for UI/balance
	Archetype: Archetype,
	Slot: Slot, -- MainHand or OffHand
	TwoHanded: boolean?,
	Tier: number,
	Unlock: UnlockGate?,
	Tags: { string }?,
	Attacks: { [string]: AttackDef },
	Block: BlockSpec?,
	Defense: DefenseProfile?, -- passive defense while equipped
}

export type ArmorDef = {
	Id: string,
	Name: string,
	Slot: Slot, -- Head, Body, Cloak, Talisman
	Tier: number,
	Unlock: UnlockGate?,
	Defense: DefenseProfile,
	Passive: { StatusApplication }?, -- permanent effects while worn
}

-- Consumables and other "use" items (potions, barrier items, cleanses, escapes).
export type ConsumableDef = {
	Id: string,
	Name: string,
	Unlock: UnlockGate?,
	Cooldown: number, -- seconds, shared by everything in the same CooldownGroup
	CooldownGroup: string?,
	Heal: number?,
	Restore: { ResourceCost }?, -- reuses the shape: pool + amount restored
	Apply: { StatusApplication }?,
	Cleanse: { string }?, -- remove active effects having any of these tags
}

export type StackPolicy = "Refresh" | "Stack" | "Ignore"

export type StatusEffectDef = {
	Id: string,
	Duration: number, -- seconds; math.huge for passives
	Stacking: StackPolicy,
	MaxStacks: number?,
	Tags: { string }?, -- e.g. "CrowdControl", "Debuff", "Buff", "Magic"
	-- Modifiers (all optional; per stack where it makes sense)
	DamageTakenMultiplier: number?,
	DamageDealtMultiplier: number?,
	MoveSpeedMultiplier: number?,
	Defense: DefenseProfile?,
	Absorb: number?, -- barrier hit points granted on apply
	Reflect: number?, -- fraction of post-mitigation damage reflected to melee attackers
	Evasion: number?, -- 0..1 chance to avoid a hit completely
	ImmuneToTags: { string }?, -- block new effects with these tags (e.g. CC immunity)
	Interrupts: boolean?, -- cancels an Interruptible windup when applied
	PreventsActions: boolean?, -- stun
	DamagePerSecond: DamageComponent?, -- damage over time
	HealPerSecond: number?,
}

export type CombatantKind = "Player" | "NPC"

export type PoolState = {
	Current: number,
	Max: number,
	Regen: number, -- per second
	RegenDelay: number, -- seconds after spending before regen resumes
	LastSpent: number,
}

export type ActiveStatus = {
	Def: StatusEffectDef,
	Stacks: number,
	ExpiresAt: number,
	SourceId: string?,
	NextTickAt: number?,
	Absorb: number?, -- remaining barrier hit points granted by this effect
}

export type Loadout = {
	MainHand: WeaponDef?,
	OffHand: WeaponDef?,
	Armor: { ArmorDef },
}

export type PendingAttack = {
	Token: number,
	WeaponSlot: Slot,
	AttackId: string,
	ImpactAt: number,
}

export type Combatant = {
	Id: string,
	Kind: CombatantKind,
	Team: string?,
	Level: number,
	Alive: boolean,
	Health: number,
	MaxHealth: number,
	Pools: { [ResourcePoolId]: PoolState },
	Loadout: Loadout,
	BaseDefense: DefenseProfile, -- innate (NPC stats, class base)
	Statuses: { [string]: ActiveStatus },
	Cooldowns: { [string]: number }, -- key -> time it becomes ready
	Ammo: { [string]: { Loaded: number, ReloadUntil: number } },
	BusyUntil: number,
	VulnerableFrom: number,
	VulnerableUntil: number,
	VulnerabilityMultiplier: number,
	Blocking: boolean,
	BlockSince: number,
	Pending: PendingAttack?,
	NextToken: number,
}

export type TargetingPolicy = {
	PlayerVsPlayer: boolean,
	PlayerVsNPC: boolean,
	NPCVsPlayer: boolean,
	NPCVsNPC: boolean,
	FriendlyFire: boolean, -- same Team can hit each other
}

export type Ruleset = {
	Id: string,
	Targeting: TargetingPolicy,
	DamageMultiplier: number,
	ArchetypeMultipliers: { [string]: number }?,
	-- Levels above this count as this level for damage scaling (PvP brackets).
	LevelCap: number?,
	-- Caps applied to the defender, prevent unbounded PvE gear dominance in PvP.
	ArmorCap: number?,
	ResistCap: number,
	HealingMultiplier: number?,
}

export type HitResult = {
	Hit: boolean,
	Reason: string?, -- why no damage (Evaded, Invalid target...)
	Raw: number, -- before mitigation
	Damage: number, -- health actually removed
	Absorbed: number,
	Blocked: number,
	Reflected: number,
	Killed: boolean,
	GuardBroken: boolean,
	AppliedStatuses: { string },
}

-- Roblox ModuleScripts must return exactly one non-nil value.
return table.freeze({})
