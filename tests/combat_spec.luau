-- Unit tests for the combat + progression core (pure modules only).
-- Loaded by tests/run.luau, which passes in the shared test helpers.

local Config = require("../src/ReplicatedStorage/Shared/Config")
local Definitions = require("../src/ReplicatedStorage/Shared/Combat/Definitions")
local CombatCore = require("../src/ReplicatedStorage/Shared/Combat/CombatCore")
local DamageCalculator = require("../src/ReplicatedStorage/Shared/Combat/DamageCalculator")
local Rulesets = require("../src/ReplicatedStorage/Shared/Combat/Rulesets")
local StatusEffects = require("../src/ReplicatedStorage/Shared/Combat/StatusEffects")
local Projectile = require("../src/ReplicatedStorage/Shared/Combat/Projectile")
local ProgressionGates = require("../src/ReplicatedStorage/Shared/ProgressionGates")
local PlayerDataModel = require("../src/ReplicatedStorage/Shared/PlayerDataModel")

return function(test: (string, () -> ()) -> (), eq: (any, any, string?) -> ())
	local defs = Definitions.get()
	local settings = Config.Combat :: any
	local engine = CombatCore.new(defs, settings)
	local PvE, PvP = Rulesets.get("PvE"), Rulesets.get("PvP")

	local function near(actual: number, expected: number, what: string?)
		if math.abs(actual - expected) > 1e-6 then
			error(`{what or "value"}: expected {expected}, got {actual}`, 2)
		end
	end
	local function always() return 0 end -- rng that makes every chance succeed
	local function never() return 0.999 end

	local function player(id: string, level: number?, team: string?)
		return engine:newCombatant({ Id = id, Kind = "Player", Level = level or 1, MaxHealth = 1000, Team = team })
	end
	local function npc(id: string, level: number?)
		return engine:newCombatant({ Id = id, Kind = "NPC", Level = level or 1, MaxHealth = 1000 })
	end
	local function armed(c, weaponId: string)
		local ok, why = engine:equipWeapon(c, weaponId)
		assert(ok, why)
		return c
	end
	-- Starts an attack and returns (weapon, attack) ready for applyHit.
	local function swing(c, slot, attackId, now)
		local plan, why = engine:beginAttack(c, slot, attackId, now)
		assert(plan, why)
		return plan
	end

	-- Definitions -------------------------------------------------------
	test("combat data validates and ids are stamped from keys", function()
		eq(defs.Weapons.iron_greatsword.Id, "iron_greatsword")
		eq(defs.StatusEffects.Burn.Id, "Burn")
		eq(table.isfrozen(defs.Weapons.iron_greatsword.Attacks.Heavy), true, "frozen")
	end)

	test("invalid weapon data is rejected with readable errors", function()
		local bad = {
			Name = "Bad", Family = "X", Archetype = "Melee", Slot = "MainHand", Tier = 1,
			Attacks = {
				A = { Delivery = "Melee", Damage = { { Type = "Plasma", Amount = 5 } }, Windup = 0, Recovery = 0 },
				B = { Delivery = "Projectile", Damage = { { Type = "Fire", Amount = 5 } }, Windup = 0, Recovery = 0, OnHit = { { Id = "Nope" } } },
			},
		}
		local result, errors = Definitions.build({ Weapons = { bad = bad }, Armor = {}, Consumables = {}, StatusEffects = {} })
		eq(result, nil, "result")
		local text = table.concat(errors, "\n")
		assert(text:find("unknown damage type \"Plasma\""), text)
		assert(text:find("Melee attacks need Range"), text)
		assert(text:find("Projectile attacks need"), text)
		assert(text:find("unknown status effect \"Nope\""), text)
	end)

	test("a brand-new weapon class works from data alone", function()
		local raw = {
			Weapons = {
				chain_whip = {
					Name = "Chain Whip", Family = "Whip", Archetype = "Melee", Slot = "MainHand", Tier = 1,
					Unlock = { Level = 1 },
					Attacks = {
						Lash = {
							Delivery = "Melee", Damage = { { Type = "Slash", Amount = 10 }, { Type = "Lightning", Amount = 5 } },
							Range = 14, Arc = 30, Windup = 0.3, Recovery = 0.3,
							OnHit = { { Id = "Shock" } },
						},
					},
				},
			},
			Armor = {}, Consumables = {},
			StatusEffects = { Shock = { Duration = 2, Stacking = "Refresh", Tags = { "Debuff" }, DamageTakenMultiplier = 1.1 } },
		}
		local newDefs = assert(Definitions.build(raw))
		local e = CombatCore.new(newDefs, settings)
		local a = e:newCombatant({ Id = "a", Kind = "Player", Level = 1, MaxHealth = 100 })
		local t = e:newCombatant({ Id = "t", Kind = "NPC", Level = 1, MaxHealth = 100 })
		assert(e:equipWeapon(a, "chain_whip"))
		local plan = assert(e:beginAttack(a, "MainHand", "Lash", 0))
		eq(e:checkReach(a, t, plan.Attack, PvE, { Distance = 13, Angle = 10 }), true, "reach 13")
		local hit = e:applyHit(a, t, plan.Weapon, plan.Attack, PvE, plan.ImpactAt, { Random = always })
		eq(hit.Damage, 15, "damage")
		eq(hit.AppliedStatuses[1], "Shock", "status")
	end)

	-- Progression gates --------------------------------------------------
	test("gates check level and milestones", function()
		local profile = { Level = 12, Milestones = {} }
		eq((ProgressionGates.check({ Level = 12 }, profile)), true, "level ok")
		eq((ProgressionGates.check({ Level = 13 }, profile)), false, "level low")
		local ok, why = ProgressionGates.check(defs.Armor.warding_talisman.Unlock, profile)
		eq(ok, false, "milestone missing"); eq(why, "Requires milestone boss_forest_warden")
		profile.Milestones.boss_forest_warden = true
		eq((ProgressionGates.check(defs.Armor.warding_talisman.Unlock, profile)), true, "milestone ok")
		eq((ProgressionGates.check(nil, profile)), true, "no gate")
	end)

	test("weapons unlock gradually by level", function()
		local at1 = ProgressionGates.unlocked(defs.Weapons, { Level = 1, Milestones = {} })
		local at20 = ProgressionGates.unlocked(defs.Weapons, { Level = 20, Milestones = {} })
		eq(#at1, 1, "level 1 count"); eq(at1[1], "training_sword")
		eq(#at20, 12, "level 20 count")
		eq(ProgressionGates.newAtLevel(defs.Weapons, 5)[1], "iron_greatsword")
	end)

	test("equipping enforces gates for players and hand rules", function()
		local c = player("p")
		local ok, why = engine:equipWeapon(c, "iron_greatsword", { Level = 4, Milestones = {} })
		eq(ok, false); eq(why, "Requires level 5")
		assert(engine:equipWeapon(c, "iron_greatsword", { Level = 5, Milestones = {} }))
		ok, why = engine:equipWeapon(c, "wooden_shield", { Level = 5, Milestones = {} })
		eq(ok, false, "two-handed blocks offhand"); eq(why, "HandsFull")
		assert(engine:equipWeapon(c, "training_sword"))
		assert(engine:equipWeapon(c, "wooden_shield"))
		eq(c.Loadout.OffHand.Id, "wooden_shield")
		assert(engine:equipWeapon(c, "hunting_bow"))
		eq(c.Loadout.OffHand, nil, "two-handed clears offhand")
		eq(engine:equipWeapon(c, "nope"), false, "unknown")
	end)

	test("armor replaces the piece in the same slot", function()
		local c = player("p")
		assert(engine:equipArmor(c, "leather_vest"))
		assert(engine:equipArmor(c, "chain_hauberk"))
		assert(engine:equipArmor(c, "leather_cap"))
		eq(#c.Loadout.Armor, 2, "pieces")
		eq(engine:defenseProfile(c).Armor, 25, "armor sum")
	end)

	-- Attack lifecycle ---------------------------------------------------
	test("beginAttack pays costs, sets busy and cooldown", function()
		local c = armed(player("p"), "training_sword")
		local plan = swing(c, "MainHand", "Thrust", 0)
		near(c.Pools.Stamina.Current, 86, "stamina")
		near(plan.ImpactAt, 0.35, "impact")
		local _, why = engine:beginAttack(c, "MainHand", "Primary", 0.1)
		eq(why, "Busy")
		engine:finishAttack(c, plan)
		_, why = engine:beginAttack(c, "MainHand", "Thrust", 1)
		eq(why, "Cooldown", "thrust cooldown")
		assert(engine:beginAttack(c, "MainHand", "Primary", 1))
	end)

	test("failed validation pays nothing", function()
		local c = armed(player("p"), "ember_staff")
		c.Pools.Mana.Current = 10
		local _, why = engine:beginAttack(c, "MainHand", "Fireball", 0)
		eq(why, "Not enough Mana")
		eq(c.Pools.Mana.Current, 10, "mana untouched")
		eq(c.Pending, nil, "no pending")
		_, why = engine:beginAttack(c, "OffHand", "Primary", 0)
		eq(why, "NoWeapon")
	end)

	test("ammo weapons need reloads", function()
		local c = armed(player("p"), "heavy_crossbow")
		local plan = swing(c, "MainHand", "Primary", 0)
		engine:finishAttack(c, plan)
		local _, why = engine:beginAttack(c, "MainHand", "Primary", 1)
		eq(why, "Reloading")
		assert(engine:beginAttack(c, "MainHand", "Primary", 0.25 + 1.6))
	end)

	test("stunned combatants cannot act", function()
		local c = armed(player("p"), "training_sword")
		StatusEffects.apply(c, defs.StatusEffects.Stun, 0)
		local _, why = engine:beginAttack(c, "MainHand", "Primary", 0.5)
		eq(why, "Stunned")
	end)

	-- Close-range power: highest damage, balanced by risk ------------------
	test("heavy melee has the highest single-hit damage of all attacks", function()
		local best, bestId = 0, ""
		for weaponId, weapon in defs.Weapons do
			for attackId, attack in weapon.Attacks do
				local total = 0
				for _, component in attack.Damage or {} do
					total += component.Amount
				end
				if total > best then
					best, bestId = total, `{weaponId}.{attackId}`
				end
			end
		end
		eq(bestId, "iron_greatsword.Heavy")
	end)

	test("heavy attacks pay for damage with commitment and risk", function()
		local heavy = defs.Weapons.iron_greatsword.Attacks.Heavy
		local light = defs.Weapons.training_sword.Attacks.Primary
		assert(heavy.Windup + heavy.Recovery > 3 * (light.Windup + light.Recovery), "commitment")
		assert(heavy.Cost.Amount > 3 * light.Cost.Amount, "stamina")

		-- extra damage taken during recovery
		local attacker = armed(player("a"), "iron_greatsword")
		local enemy = armed(npc("e"), "training_sword")
		local plan = swing(attacker, "MainHand", "Heavy", 0)
		local punish = swing(enemy, "MainHand", "Primary", plan.ImpactAt)
		local during = engine:applyHit(enemy, attacker, punish.Weapon, punish.Attack, PvE, plan.ImpactAt + 0.5)
		local fresh = armed(player("b"), "iron_greatsword")
		local normal = engine:applyHit(enemy, fresh, punish.Weapon, punish.Attack, PvE, 10)
		eq(during.Damage, math.floor(normal.Damage * 1.35 + 0.5), "vulnerable")
	end)

	test("staggering an interruptible windup cancels it", function()
		local heavy = armed(player("h"), "iron_greatsword")
		local basher = armed(armed(npc("b"), "training_sword"), "wooden_shield")
		local plan = swing(heavy, "MainHand", "Heavy", 0)
		local bash = swing(basher, "OffHand", "Bash", 0)
		engine:applyHit(basher, heavy, bash.Weapon, bash.Attack, PvE, 0.3, { Random = always })
		eq(engine:isPlanValid(heavy, plan), false, "interrupted")
		-- non-interruptible attacks keep going
		local light = armed(player("l"), "training_sword")
		local lplan = swing(light, "MainHand", "Primary", 0)
		engine:applyHit(basher, light, bash.Weapon, bash.Attack, PvE, 0.1, { Random = always })
		eq(engine:isPlanValid(light, lplan), true, "light not interrupted")
	end)

	-- Targeting / rulesets ------------------------------------------------
	test("PvE and PvP share the same core with different targeting", function()
		local a, b, n = armed(player("a"), "training_sword"), player("b"), npc("n")
		local plan = swing(a, "MainHand", "Primary", 0)
		eq(engine:applyHit(a, b, plan.Weapon, plan.Attack, PvE, 0.2).Reason, "TargetNotAllowed", "PvE pvp")
		eq(engine:applyHit(a, n, plan.Weapon, plan.Attack, PvE, 0.2).Hit, true, "PvE npc")
		eq(engine:applyHit(a, b, plan.Weapon, plan.Attack, PvP, 0.2).Hit, true, "PvP pvp")
		eq(engine:applyHit(a, n, plan.Weapon, plan.Attack, PvP, 0.2).Reason, "TargetNotAllowed", "PvP npc")
		local mate = player("m", 1, "red"); a.Team = "red"
		eq(engine:applyHit(a, mate, plan.Weapon, plan.Attack, PvP, 0.2).Reason, "SameTeam")
		eq(engine:applyHit(a, a, plan.Weapon, plan.Attack, PvP, 0.2).Reason, "Self")
	end)

	test("PvP caps level scaling and armor so PvE progress cannot dominate", function()
		local weapon = defs.Weapons.training_sword
		local attack = weapon.Attacks.Primary
		local function hit(level, ruleset, armorId)
			local a = armed(player("a", level), "training_sword")
			local t = if ruleset == PvE then npc("t") else player("t")
			if armorId then engine:equipArmor(t, armorId) end
			return engine:applyHit(a, t, weapon, attack, ruleset, 0).Raw
		end
		assert(hit(100, PvE) > hit(30, PvE), "PvE rewards levels")
		eq(hit(100, PvP), hit(30, PvP), "PvP bracket cap")
		near(DamageCalculator.armorReduction(1000, 0, PvP, settings), 40 / 140, "armor cap")
		near(DamageCalculator.resist({ Armor = 0, Resist = { Fire = 0.9 } }, "Fire", PvP), 0.5, "resist cap")
	end)

	test("checkReach enforces melee range, arc and area radius", function()
		local a, t = armed(player("a"), "training_sword"), npc("t")
		local attack = defs.Weapons.training_sword.Attacks.Primary -- range 7, arc 100
		eq(engine:checkReach(a, t, attack, PvE, { Distance = 9, Angle = 0 }), true, "within tolerance")
		eq(select(2, engine:checkReach(a, t, attack, PvE, { Distance = 9.5, Angle = 0 })), "OutOfRange")
		eq(select(2, engine:checkReach(a, t, attack, PvE, { Distance = 3, Angle = 70 })), "OutOfArc")
		eq(select(2, engine:checkReach(a, t, attack, PvE, { Distance = 3 })), "OutOfArc", "unknown angle")
		local fireball = defs.Weapons.ember_staff.Attacks.Fireball
		eq(engine:checkReach(a, t, fireball, PvE, { Distance = 8 }), true, "area edge")
		eq(select(2, engine:checkReach(a, t, fireball, PvE, { Distance = 8.1 })), "OutOfRange")
	end)

	-- Damage math -----------------------------------------------------------
	test("armor reduces physical damage only; true damage ignores defense", function()
		local defense = { Armor = 100, Resist = { Fire = 0.5 } }
		local function final(type_)
			return DamageCalculator.compute({
				Components = { { Type = type_, Amount = 100 } }, AttackerLevel = 1, Defense = defense, Ruleset = PvE,
			}, settings).Final
		end
		near(final("Slash"), 50, "slash halved by 100 armor")
		near(final("Fire"), 50, "fire halved by resist")
		near(final("Frost"), 100, "frost unresisted")
		near(final("True"), 100, "true")
	end)

	test("armor penetration and minimum damage", function()
		local r = DamageCalculator.compute({
			Components = { { Type = "Slash", Amount = 100 } }, AttackerLevel = 1, ArmorPenetration = 0.5,
			Defense = { Armor = 200, Resist = {} }, Ruleset = PvE,
		}, settings)
		near(r.Final, 50, "pen")
		local tiny = DamageCalculator.compute({
			Components = { { Type = "Fire", Amount = 1 } }, AttackerLevel = 1,
			Defense = { Armor = 0, Resist = { Fire = 0.75 } }, Ruleset = PvE,
		}, settings)
		eq(tiny.Final, 1, "min damage")
	end)

	-- Defense systems -------------------------------------------------------
	test("shields block frontal hits and drain stamina", function()
		local a = armed(npc("a"), "iron_greatsword")
		local d = armed(armed(player("d"), "training_sword"), "wooden_shield")
		assert(engine:setBlocking(d, true, 0))
		local w, atk = defs.Weapons.iron_greatsword, defs.Weapons.iron_greatsword.Attacks.Primary
		local front = engine:applyHit(a, d, w, atk, PvE, 1, { AngleFromTargetFacing = 10 })
		assert(front.Blocked > 0, "blocked")
		assert(d.Pools.Stamina.Current < 100, "stamina drained")
		local back = engine:applyHit(a, d, w, atk, PvE, 1, { AngleFromTargetFacing = 170 })
		eq(back.Blocked, 0, "from behind")
		assert(front.Damage < back.Damage, "block helps")
	end)

	test("guard breaks when stamina runs out and staggers the blocker", function()
		local a = armed(npc("a"), "iron_greatsword")
		local d = armed(armed(player("d"), "training_sword"), "wooden_shield")
		engine:setBlocking(d, true, 0)
		d.Pools.Stamina.Current = 1
		local r = engine:applyHit(a, d, defs.Weapons.iron_greatsword, defs.Weapons.iron_greatsword.Attacks.Heavy, PvE, 1, { AngleFromTargetFacing = 0, Random = always })
		eq(r.GuardBroken, true, "broken"); eq(d.Blocking, false, "guard down")
		assert(d.Statuses.Stagger, "staggered")
	end)

	test("a guard raised just now does not block yet", function()
		local a = armed(npc("a"), "training_sword")
		local d = armed(armed(player("d"), "training_sword"), "wooden_shield")
		engine:setBlocking(d, true, 1)
		local r = engine:applyHit(a, d, defs.Weapons.training_sword, defs.Weapons.training_sword.Attacks.Primary, PvE, 1.05, { AngleFromTargetFacing = 0 })
		eq(r.Blocked, 0)
	end)

	test("barrier magic absorbs damage and expires when used up", function()
		local mage = armed(player("m"), "ember_staff")
		local plan = swing(mage, "MainHand", "Ward", 0)
		eq(engine:applySelf(mage, plan, PvE, plan.ImpactAt)[1], "Barrier")
		local e = armed(npc("e"), "iron_greatsword")
		local r = engine:applyHit(e, mage, defs.Weapons.iron_greatsword, defs.Weapons.iron_greatsword.Attacks.Heavy, PvE, 1, { Random = never })
		eq(r.Absorbed, 40, "absorbed")
		eq(StatusEffects.totalAbsorb(mage), 0, "barrier empty")
		engine:tick(mage, 1.1, 0.1, PvE)
		eq(mage.Statuses.Barrier, nil, "barrier removed")
	end)

	test("reflect punishes melee but not projectiles", function()
		local d = armed(player("d"), "runeblade")
		local plan = swing(d, "MainHand", "Resolve", 0)
		engine:applySelf(d, plan, PvE, plan.ImpactAt)
		local melee = armed(npc("m"), "training_sword")
		local r = engine:applyHit(melee, d, defs.Weapons.training_sword, defs.Weapons.training_sword.Attacks.Primary, PvE, 1)
		assert(r.Reflected > 0, "reflected melee")
		local archer = armed(npc("a"), "hunting_bow")
		local r2 = engine:applyHit(archer, d, defs.Weapons.hunting_bow, defs.Weapons.hunting_bow.Attacks.Primary, PvE, 1)
		eq(r2.Reflected, 0, "no reflect on projectile")
	end)

	test("crowd-control protection blocks stuns", function()
		local c = player("c")
		StatusEffects.apply(c, defs.StatusEffects.Steadfast, 0)
		eq(StatusEffects.apply(c, defs.StatusEffects.Stun, 1), false, "stun blocked")
		eq(StatusEffects.apply(c, defs.StatusEffects.Burn, 1), true, "burn still applies")
	end)

	test("evasion can avoid a hit entirely", function()
		local a, t = armed(npc("a"), "training_sword"), player("t")
		StatusEffects.apply(t, defs.StatusEffects.Evasive, 0)
		local w = defs.Weapons.training_sword
		eq(engine:applyHit(a, t, w, w.Attacks.Primary, PvE, 1, { Random = always }).Reason, "Evaded")
		eq(engine:applyHit(a, t, w, w.Attacks.Primary, PvE, 1, { Random = never }).Hit, true)
	end)

	test("burn stacks and ticks once per second", function()
		local c = npc("c")
		for _ = 1, 5 do
			StatusEffects.apply(c, defs.StatusEffects.Burn, 0)
		end
		eq(c.Statuses.Burn.Stacks, 3, "max stacks")
		local r = engine:tick(c, 2, 2, PvE)
		eq(r.Damage, 24, "2 ticks x 4 dps x 3 stacks")
		engine:tick(c, 10, 8, PvE)
		eq(c.Statuses.Burn, nil, "expired")
	end)

	test("defensive items: cleanse, shared potion cooldown, PvP healing reduced", function()
		local c = player("c", 20)
		StatusEffects.apply(c, defs.StatusEffects.Burn, 0)
		StatusEffects.apply(c, defs.StatusEffects.Chill, 0)
		StatusEffects.apply(c, defs.StatusEffects.Barrier, 0)
		assert(engine:useConsumable(c, "cleansing_salts", 0))
		eq(c.Statuses.Burn, nil, "burn cleansed"); eq(c.Statuses.Chill, nil, "chill cleansed")
		assert(c.Statuses.Barrier, "buff kept")

		c.Health = 500
		assert(engine:useConsumable(c, "health_potion", 1, nil, PvP))
		eq(c.Health, 520, "PvP half healing")
		local ok, why = engine:useConsumable(c, "fortifying_draught", 2)
		eq(ok, false); eq(why, "Cooldown", "shared potion group")
		assert(engine:useConsumable(c, "barrier_scroll", 2), "different group")
		ok, why = engine:useConsumable(c, "smoke_bomb", 3, { Level = 5, Milestones = {} })
		eq(ok, false); eq(why, "Requires level 11")
	end)

	test("stunned players can still use a CC cleanse escape item", function()
		local c = player("c", 20)
		StatusEffects.apply(c, defs.StatusEffects.Stun, 0)
		eq(select(2, engine:useConsumable(c, "health_potion", 0.1)), "Stunned")
		assert(engine:useConsumable(c, "smoke_bomb", 0.1))
		eq(c.Statuses.Stun, nil)
	end)

	test("kills and revive", function()
		local a = armed(npc("a"), "iron_greatsword")
		local t = player("t")
		t.Health = 5
		local r = engine:applyHit(a, t, defs.Weapons.iron_greatsword, defs.Weapons.iron_greatsword.Attacks.Primary, PvE, 0)
		eq(r.Killed, true); eq(r.Damage, 5, "no overkill"); eq(t.Alive, false)
		eq(engine:applyHit(a, t, defs.Weapons.iron_greatsword, defs.Weapons.iron_greatsword.Attacks.Primary, PvE, 0).Reason, "TargetDead")
		engine:revive(t)
		eq(t.Alive, true); eq(t.Health, 1000)
	end)

	test("stamina regenerates after a delay but not while blocking", function()
		local c = armed(armed(player("c"), "training_sword"), "wooden_shield")
		c.Pools.Stamina.Current = 50; c.Pools.Stamina.LastSpent = 0
		engine:tick(c, 0.5, 0.5, PvE)
		eq(c.Pools.Stamina.Current, 50, "delay")
		engine:tick(c, 1.5, 1, PvE)
		eq(c.Pools.Stamina.Current, 75, "regen")
		engine:setBlocking(c, true, 1.5)
		engine:tick(c, 2.5, 1, PvE)
		eq(c.Pools.Stamina.Current, 75, "no regen while blocking")
	end)

	-- Projectiles -------------------------------------------------------------
	test("projectiles travel, clip at max range and detect sphere hits", function()
		local spec = { Speed = 100, Radius = 0.5, MaxRange = 150 }
		local p = assert(Projectile.new(vector.create(0, 0, 0), vector.create(0, 0, -2), spec, "a"))
		local from, to = Projectile.step(p, 1)
		near(to.z, -100, "first step"); eq(p.Done, false)
		local hit, t = Projectile.sweepSphere(from, to, vector.create(1, 0, -50), 1.5)
		eq(hit, true, "hit"); near(t, 0.5, "t")
		eq((Projectile.sweepSphere(from, to, vector.create(3, 0, -50), 1.5)), false, "miss")
		_, to = Projectile.step(p, 1)
		near(to.z, -150, "clipped"); eq(p.Done, true, "done")
		eq(Projectile.new(vector.create(0, 0, 0), vector.create(0, 0, 0), spec, "a"), nil, "zero dir")
		eq(Projectile.new(vector.create(0, 0, 0), vector.create(0 / 0, 0, 0), spec, "a"), nil, "nan dir")
	end)

	test("projectile gravity and pierce", function()
		local p = assert(Projectile.new(vector.create(0, 0, 0), vector.create(1, 0, 0), { Speed = 10, Gravity = 10, Radius = 1, MaxRange = 100, Pierce = 1 }, "a"))
		local _, to = Projectile.step(p, 1)
		assert(to.y < 0, "falls")
		eq(Projectile.registerHit(p, "x"), true, "pierces first")
		eq(Projectile.registerHit(p, "y"), false, "stops second")
		eq(p.Done, true)
	end)

	-- Player data v2 -------------------------------------------------------------
	test("player data v1 migrates to v2 with starter gear", function()
		local starter = { Loadout = { MainHand = "training_sword" }, Consumables = { health_potion = 3 } }
		local data = PlayerDataModel.reconcile({ Version = 1, Coins = 7, Level = 4 }, starter)
		eq(data.Version, 2); eq(data.Coins, 7); eq(data.Level, 4)
		eq(data.Loadout.MainHand, "training_sword", "starter weapon")
		eq(data.Consumables.health_potion, 3, "starter potions")
	end)

	test("player data v2 keeps valid gear and drops corrupt entries", function()
		local data = PlayerDataModel.reconcile({
			Version = 2,
			Loadout = { MainHand = "iron_greatsword", OffHand = 5, Bogus = "x" },
			Milestones = { boss_forest_warden = true, weird = "yes" },
			Consumables = { health_potion = 2, mana_potion = -1, [""] = 3 },
		})
		eq(data.Loadout.MainHand, "iron_greatsword"); eq(data.Loadout.OffHand, nil, "bad offhand")
		eq((data.Loadout :: any).Bogus, nil, "unknown slot")
		eq(data.Milestones.boss_forest_warden, true); eq(data.Milestones.weird, nil)
		eq(data.Consumables.health_potion, 2); eq(data.Consumables.mana_potion, nil)
	end)
end
