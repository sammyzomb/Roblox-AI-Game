--!strict
-- Weapon definitions (data only). Validated by Definitions.luau.
--
-- To add a weapon, add an entry here. To add a whole new weapon class
-- (e.g. whips, scythes, firearms if approved), add entries with a new Family
-- and whatever Delivery / Damage / Ammo / Cost combination it needs.
-- The combat core never reads Family or Id.
--
-- Balance notes (see docs/COMBAT_API.md "Balance levers"):
--   * Heavy melee has the highest damage per hit, paid for with long Windup
--     (interruptible), long Recovery, big stamina cost and RecoveryVulnerability.
--   * Ranged physical trades burst for reach; crossbows use Ammo/reload.
--   * Magic costs Mana and has cooldowns on its strongest spells.

return {
	-- Light melee --------------------------------------------------------
	training_sword = {
		Name = "Training Sword",
		Family = "LightMelee",
		Archetype = "Melee",
		Slot = "MainHand",
		Tier = 1,
		Unlock = { Level = 1 },
		Attacks = {
			Primary = {
				Delivery = "Melee",
				Damage = { { Type = "Slash", Amount = 12 } },
				Range = 7, Arc = 100,
				Windup = 0.2, Recovery = 0.3,
				Cost = { Pool = "Stamina", Amount = 8 },
			},
			Thrust = {
				Delivery = "Melee",
				Damage = { { Type = "Pierce", Amount = 17 } },
				Range = 8, Arc = 40,
				Windup = 0.35, Recovery = 0.45, Cooldown = 2,
				Cost = { Pool = "Stamina", Amount = 14 },
			},
		},
	},

	-- Heavy melee (close-range power) ------------------------------------
	iron_greatsword = {
		Name = "Iron Greatsword",
		Family = "HeavyMelee",
		Archetype = "Melee",
		Slot = "MainHand",
		TwoHanded = true,
		Tier = 2,
		Unlock = { Level = 5 },
		Tags = { "Heavy" },
		Attacks = {
			Primary = {
				Delivery = "Melee",
				Damage = { { Type = "Slash", Amount = 24 } },
				Range = 8, Arc = 120,
				Windup = 0.45, Recovery = 0.6,
				Cost = { Pool = "Stamina", Amount = 14 },
			},
			Heavy = {
				Delivery = "Melee",
				Damage = { { Type = "Slash", Amount = 40 }, { Type = "Blunt", Amount = 12 } },
				Range = 7, Arc = 90,
				Windup = 0.9, Recovery = 1.2,
				Cost = { Pool = "Stamina", Amount = 32 },
				ArmorPenetration = 0.25,
				Interruptible = true,
				RecoveryVulnerability = 1.35,
				OnHit = { { Id = "Stagger" } },
			},
		},
	},

	-- Polearm -------------------------------------------------------------
	ash_spear = {
		Name = "Ash Spear",
		Family = "Polearm",
		Archetype = "Melee",
		Slot = "MainHand",
		TwoHanded = true,
		Tier = 2,
		Unlock = { Level = 8 },
		Attacks = {
			Primary = {
				Delivery = "Melee",
				Damage = { { Type = "Pierce", Amount = 19 } },
				Range = 11, Arc = 35,
				Windup = 0.35, Recovery = 0.5,
				Cost = { Pool = "Stamina", Amount = 12 },
			},
			Sweep = {
				Delivery = "Melee",
				Damage = { { Type = "Slash", Amount = 15 } },
				Range = 10, Arc = 170,
				Windup = 0.6, Recovery = 0.7, Cooldown = 4,
				Cost = { Pool = "Stamina", Amount = 22 },
				OnHit = { { Id = "Stagger", Chance = 0.5 } },
			},
		},
	},

	-- Dual wield ------------------------------------------------------------
	twin_daggers = {
		Name = "Twin Daggers",
		Family = "DualWield",
		Archetype = "Melee",
		Slot = "MainHand",
		TwoHanded = true, -- occupies both hands
		Tier = 2,
		Unlock = { Level = 12 },
		Attacks = {
			Primary = {
				Delivery = "Melee",
				Damage = { { Type = "Slash", Amount = 9 } },
				Range = 6, Arc = 90,
				Windup = 0.12, Recovery = 0.18,
				Cost = { Pool = "Stamina", Amount = 5 },
			},
			Flurry = {
				Delivery = "Melee",
				Damage = { { Type = "Slash", Amount = 14 } },
				Range = 6, Arc = 90,
				Windup = 0.25, Recovery = 0.4, Cooldown = 6,
				Cost = { Pool = "Stamina", Amount = 18 },
				OnHit = { { Id = "Bleed" }, { Id = "Bleed" } },
			},
		},
	},

	-- Ranged physical -------------------------------------------------------
	hunting_bow = {
		Name = "Hunting Bow",
		Family = "Bow",
		Archetype = "RangedPhysical",
		Slot = "MainHand",
		TwoHanded = true,
		Tier = 1,
		Unlock = { Level = 3 },
		Attacks = {
			Primary = {
				Delivery = "Projectile",
				Damage = { { Type = "Pierce", Amount = 16 } },
				Projectile = { Speed = 180, Gravity = 20, Radius = 0.6, MaxRange = 160 },
				Windup = 0.5, Recovery = 0.25,
				Cost = { Pool = "Stamina", Amount = 4 },
			},
		},
	},
	heavy_crossbow = {
		Name = "Heavy Crossbow",
		Family = "Crossbow",
		Archetype = "RangedPhysical",
		Slot = "MainHand",
		TwoHanded = true,
		Tier = 3,
		Unlock = { Level = 15 },
		Attacks = {
			Primary = {
				Delivery = "Projectile",
				Damage = { { Type = "Pierce", Amount = 34 } },
				Projectile = { Speed = 260, Radius = 0.5, MaxRange = 200, Pierce = 1 },
				Windup = 0.25, Recovery = 0.3,
				Ammo = { Capacity = 1, ReloadTime = 1.6 },
				ArmorPenetration = 0.3,
			},
		},
	},
	-- Development-only training rifle. Not an approved firearm and not
	-- release balance. Ordinary profiles do not receive the milestone below,
	-- so the public Equip path stays locked while ownership hardening is absent.
	development_training_rifle = {
		Name = "Development Training Rifle",
		Family = "Rifle",
		Archetype = "RangedPhysical",
		Slot = "MainHand",
		TwoHanded = true,
		Tier = 1,
		Unlock = { Milestones = { "development_training_rifle" } },
		Attacks = {
			Primary = {
				Delivery = "Projectile",
				-- Development damage, not approved release balance.
				Damage = { { Type = "Pierce", Amount = 14 } },
				-- Development projectile speed, not approved release balance.
				Projectile = { Speed = 220, Radius = 0.45, MaxRange = 170 },
				Windup = 0.2, Recovery = 0.25,
				-- Development magazine capacity and reload time, not approved release balance.
				Ammo = { Capacity = 6, ReloadTime = 1.4 },
			},
		},
	},
	throwing_knives = {
		Name = "Throwing Knives",
		Family = "Throwing",
		Archetype = "RangedPhysical",
		Slot = "OffHand",
		Tier = 1,
		Unlock = { Level = 6 },
		Attacks = {
			Throw = {
				Delivery = "Projectile",
				Damage = { { Type = "Pierce", Amount = 11 } },
				Projectile = { Speed = 120, Gravity = 30, Radius = 0.5, MaxRange = 70 },
				Windup = 0.15, Recovery = 0.2,
				Ammo = { Capacity = 3, ReloadTime = 2 },
			},
		},
	},

	-- Magic --------------------------------------------------------------------
	ember_staff = {
		Name = "Ember Staff",
		Family = "Staff",
		Archetype = "Magic",
		Slot = "MainHand",
		TwoHanded = true,
		Tier = 1,
		Unlock = { Level = 4 },
		Attacks = {
			Firebolt = {
				Delivery = "Projectile",
				Damage = { { Type = "Fire", Amount = 20 } },
				Projectile = { Speed = 90, Radius = 1, MaxRange = 120 },
				Windup = 0.4, Recovery = 0.35,
				Cost = { Pool = "Mana", Amount = 12 },
			},
			Fireball = {
				Delivery = "Area",
				Damage = { { Type = "Fire", Amount = 26 } },
				Range = 40, Radius = 8,
				Windup = 0.8, Recovery = 0.5, Cooldown = 6,
				Cost = { Pool = "Mana", Amount = 30 },
				Interruptible = true,
				OnHit = { { Id = "Burn" } },
			},
			Ward = {
				Delivery = "Self",
				Windup = 0.3, Recovery = 0.2, Cooldown = 15,
				Cost = { Pool = "Mana", Amount = 25 },
				OnSelf = { { Id = "Barrier" } },
			},
		},
	},
	frost_wand = {
		Name = "Frost Wand",
		Family = "Wand",
		Archetype = "Magic",
		Slot = "MainHand",
		Tier = 2,
		Unlock = { Level = 10 },
		Attacks = {
			Frostbolt = {
				Delivery = "Projectile",
				Damage = { { Type = "Frost", Amount = 14 } },
				Projectile = { Speed = 110, Radius = 0.8, MaxRange = 110 },
				Windup = 0.25, Recovery = 0.25,
				Cost = { Pool = "Mana", Amount = 8 },
				OnHit = { { Id = "Chill" } },
			},
			FrostArmor = {
				Delivery = "Self",
				Windup = 0.4, Recovery = 0.2, Cooldown = 20,
				Cost = { Pool = "Mana", Amount = 20 },
				OnSelf = { { Id = "FrostWard" } },
			},
		},
	},

	-- Hybrid ---------------------------------------------------------------------
	runeblade = {
		Name = "Runeblade",
		Family = "Hybrid",
		Archetype = "Hybrid",
		Slot = "MainHand",
		Tier = 3,
		Unlock = { Level = 18 },
		Attacks = {
			Primary = {
				Delivery = "Melee",
				Damage = { { Type = "Slash", Amount = 15 }, { Type = "Arcane", Amount = 8 } },
				Range = 7, Arc = 100,
				Windup = 0.3, Recovery = 0.4,
				Cost = { Pool = "Stamina", Amount = 10 },
			},
			Resolve = {
				Delivery = "Self",
				Windup = 0.2, Recovery = 0.2, Cooldown = 25,
				Cost = { Pool = "Mana", Amount = 30 },
				OnSelf = { { Id = "Steadfast" }, { Id = "Thornmail" } },
			},
		},
	},

	-- Shields (defensive equipment) ---------------------------------------------
	wooden_shield = {
		Name = "Wooden Shield",
		Family = "Shield",
		Archetype = "Defense",
		Slot = "OffHand",
		Tier = 1,
		Unlock = { Level = 2 },
		Block = { Reduction = 0.6, Arc = 120, StaminaPerDamage = 0.5, MoveSpeedMultiplier = 0.8 },
		Defense = { Armor = 5 },
		Attacks = {
			Bash = {
				Delivery = "Melee",
				Damage = { { Type = "Blunt", Amount = 8 } },
				Range = 5, Arc = 80,
				Windup = 0.25, Recovery = 0.5, Cooldown = 5,
				Cost = { Pool = "Stamina", Amount = 12 },
				OnHit = { { Id = "Stagger" } },
			},
		},
	},
	tower_shield = {
		Name = "Tower Shield",
		Family = "Shield",
		Archetype = "Defense",
		Slot = "OffHand",
		Tier = 3,
		Unlock = { Level = 14 },
		Block = { Reduction = 0.85, Arc = 140, StaminaPerDamage = 0.35, MoveSpeedMultiplier = 0.6 },
		Defense = { Armor = 15 },
		Attacks = {},
	},
}
