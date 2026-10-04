-- Pure tests for temporary training presets.
-- The production module is src/ReplicatedStorage/Shared/Combat/TrainingLoadouts.luau.
-- These tests do not construct Roblox instances and do not stand in for CombatService.

local Config = require("../src/ReplicatedStorage/Shared/Config")
local CombatCore = require("../src/ReplicatedStorage/Shared/Combat/CombatCore")
local Definitions = require("../src/ReplicatedStorage/Shared/Combat/Definitions")
local TrainingLoadouts = require("../src/ReplicatedStorage/Shared/Combat/TrainingLoadouts")

return function(test: (string, () -> ()) -> (), eq: (any, any, string?) -> ())
	local defs = Definitions.get()
	local settings = Config.Combat :: any
	local engine = CombatCore.new(defs, settings)

	local function player(id: string, level: number?)
		return engine:newCombatant({
			Id = id,
			Kind = "Player",
			Level = level or 1,
			MaxHealth = 100,
		})
	end

	local function profile(level: number)
		return { Level = level, Milestones = {} }
	end

	local function mainId(combatant): string?
		local weapon = combatant.Loadout.MainHand
		return if weapon then weapon.Id else nil
	end

	local function offId(combatant): string?
		local weapon = combatant.Loadout.OffHand
		return if weapon then weapon.Id else nil
	end

	local function armorId(combatant): string?
		local piece = combatant.Loadout.Armor[1]
		return if piece then piece.Id else nil
	end

	test("approved presets are the three development ids and the default is Swordsman", function()
		eq(TrainingLoadouts.DEFAULT_PRESET_ID, "Swordsman")
		eq(TrainingLoadouts.PRESET_IDS[1], "Swordsman")
		eq(TrainingLoadouts.PRESET_IDS[2], "Mage")
		eq(TrainingLoadouts.PRESET_IDS[3], "Archer")
		eq(#TrainingLoadouts.PRESET_IDS, 3)
		eq(TrainingLoadouts.SELECTION_ACTION, "TrainingPreset")
		eq(type(TrainingLoadouts.MISSING_RIFLE), "string")
		eq(TrainingLoadouts.MISSING_RIFLE == "", false)
		eq(TrainingLoadouts.itemIds("Rifle"), nil)
		local rifleId, rifleWhy = TrainingLoadouts.validatePresetId("Rifle")
		eq(rifleId, nil)
		eq(rifleWhy, "UnknownPreset")
	end)

	test("preset contents are existing hand item ids, not copied weapon stats", function()
		local swordsman = TrainingLoadouts.itemIds("Swordsman")
		local mage = TrainingLoadouts.itemIds("Mage")
		local archer = TrainingLoadouts.itemIds("Archer")
		assert(swordsman and mage and archer, "preset ids must resolve")
		eq(swordsman[1], "training_sword")
		eq(swordsman[2], "wooden_shield")
		eq(#swordsman, 2)
		eq(mage[1], "ember_staff")
		eq(#mage, 1)
		eq(archer[1], "hunting_bow")
		eq(#archer, 1)
		for _, itemId in { swordsman[1], swordsman[2], mage[1], archer[1] } do
			eq(type(itemId), "string")
			eq(string.find(itemId, "rifle", 1, true), nil)
			eq(defs.Weapons[itemId] ~= nil, true, itemId)
		end
		eq(#TrainingLoadouts.compatibilityErrors(defs), 0)
	end)

	test("two-handed plus off-hand development data is rejected", function()
		local errors = TrainingLoadouts.compatibilityErrors({
			Weapons = {
				training_sword = { Slot = "MainHand", TwoHanded = true },
				wooden_shield = { Slot = "OffHand" },
				ember_staff = { Slot = "MainHand", TwoHanded = true },
				hunting_bow = { Slot = "MainHand", TwoHanded = true },
			},
		})
		local found = false
		for _, message in errors do
			if string.find(message, "two-handed", 1, true) then
				found = true
			end
		end
		eq(found, true, "Swordsman must not pair a two-handed weapon with a shield")
		eq(#TrainingLoadouts.compatibilityErrors({ Weapons = {} }) > 0, true)
	end)

	test("selection requests accept only the finite preset ids", function()
		local archer = TrainingLoadouts.validateSelectionRequest({
			Action = "TrainingPreset",
			PresetId = "Archer",
		})
		eq(archer, "Archer")

		local unknownId, unknownWhy = TrainingLoadouts.validateSelectionRequest({
			Action = "TrainingPreset",
			PresetId = "training_sword",
		})
		eq(unknownId, nil)
		eq(unknownWhy, "UnknownPreset")

		local smuggledId, smuggledWhy = TrainingLoadouts.validateSelectionRequest({
			Action = "TrainingPreset",
			PresetId = "Mage",
			ItemId = "iron_greatsword",
		})
		eq(smuggledId, nil)
		eq(smuggledWhy, "MalformedPreset")

		local cases = {
			"Mage",
			{ Action = "Equip", PresetId = "Mage" },
			{ Action = "TrainingPreset" },
			{ Action = "TrainingPreset", PresetId = 1 },
		}
		for _, request in cases do
			local id, why = TrainingLoadouts.validateSelectionRequest(request)
			eq(id, nil)
			eq(why, "MalformedPreset")
		end

		local lowerId, lowerWhy = TrainingLoadouts.validateSelectionRequest({
			Action = "TrainingPreset",
			PresetId = "swordsman",
		})
		eq(lowerId, nil)
		eq(lowerWhy, "UnknownPreset")
	end)

	test("applyPreset swaps the three loadouts and bypasses level gates", function()
		local combatant = player("gates", 1)
		local locked, lockedWhy = engine:equipWeapon(combatant, "ember_staff", profile(1))
		eq(locked, false, lockedWhy)

		local applied, why = TrainingLoadouts.applyPreset(engine, combatant, "Mage", 0)
		eq(applied, true, why)
		eq(mainId(combatant), "ember_staff")
		eq(offId(combatant), nil)

		local swordOk = TrainingLoadouts.applyPreset(engine, combatant, "Swordsman", 0)
		eq(swordOk, true)
		eq(mainId(combatant), "training_sword")
		eq(offId(combatant), "wooden_shield")

		local bowOk = TrainingLoadouts.applyPreset(engine, combatant, "Archer", 0)
		eq(bowOk, true)
		eq(mainId(combatant), "hunting_bow")
		eq(offId(combatant), nil, "two-handed bow clears the shield")
	end)

	test("applyPreset rejects unknown, dead, and busy combatants without changing hands", function()
		local combatant = player("busy", 1)
		assert(engine:equipWeapon(combatant, "frost_wand"))
		assert(engine:equipArmor(combatant, "leather_vest"))

		local unknownOk, unknownWhy = TrainingLoadouts.applyPreset(engine, combatant, "Rifle", 0)
		eq(unknownOk, false)
		eq(unknownWhy, "UnknownPreset")
		eq(mainId(combatant), "frost_wand")

		combatant.BusyUntil = 10
		local busyOk, busyWhy = TrainingLoadouts.applyPreset(engine, combatant, "Swordsman", 0)
		eq(busyOk, false)
		eq(busyWhy, "Busy")
		eq(mainId(combatant), "frost_wand")
		eq(armorId(combatant), "leather_vest")

		combatant.BusyUntil = 0
		combatant.Alive = false
		local deadOk, deadWhy = TrainingLoadouts.applyPreset(engine, combatant, "Swordsman", 0)
		eq(deadOk, false)
		eq(deadWhy, "Dead")
		eq(mainId(combatant), "frost_wand")
	end)

	test("applyPreset rolls back the previous hands when a later equip step fails", function()
		local combatant = player("rollback", 1)
		assert(engine:equipWeapon(combatant, "frost_wand"))
		assert(engine:equipArmor(combatant, "leather_vest"))

		local proxy = {
			Defs = engine.Defs,
		}
		function proxy:canAct(combatantArg, now: number)
			return engine:canAct(combatantArg, now)
		end
		function proxy:unequip(combatantArg, slot)
			return engine:unequip(combatantArg, slot)
		end
		function proxy:equipWeapon(combatantArg, itemId: string, gate)
			if itemId == "wooden_shield" then
				return false, "InjectedFailure"
			end
			return engine:equipWeapon(combatantArg, itemId, gate)
		end

		local ok, why = TrainingLoadouts.applyPreset(proxy :: any, combatant, "Swordsman", 0)
		eq(ok, false)
		eq(why, "InjectedFailure")
		eq(mainId(combatant), "frost_wand", "failed preset must restore the previous main hand")
		eq(offId(combatant), nil)
		eq(armorId(combatant), "leather_vest", "armor is not part of the training preset")
	end)

	test("equipSavedHands clears training weapons and keeps gates on the saved ids", function()
		local combatant = player("saved", 1)
		assert(engine:equipWeapon(combatant, "ember_staff"))
		assert(engine:equipArmor(combatant, "leather_vest"))

		local restored, why = TrainingLoadouts.equipSavedHands(
			engine,
			combatant,
			"training_sword",
			"wooden_shield",
			profile(1),
			0
		)
		eq(restored, true, why)
		eq(mainId(combatant), "training_sword")
		eq(offId(combatant), nil, "level 1 cannot equip the saved shield, and it is not written back")
		eq(armorId(combatant), "leather_vest")

		local high = player("high", 20)
		assert(engine:equipWeapon(high, "training_sword"))
		local highOk = TrainingLoadouts.equipSavedHands(engine, high, "iron_greatsword", "wooden_shield", profile(20), 0)
		eq(highOk, true)
		eq(mainId(high), "iron_greatsword")
		eq(offId(high), nil, "saved off hand stays empty when the saved main hand is two-handed")

		local busy = player("busy-restore", 20)
		assert(engine:equipWeapon(busy, "ember_staff"))
		busy.BusyUntil = 4
		local busyOk, busyWhy = TrainingLoadouts.equipSavedHands(engine, busy, "training_sword", nil, profile(20), 0)
		eq(busyOk, false)
		eq(busyWhy, "Busy")
		eq(mainId(busy), "ember_staff", "a rejected restore does not clear training hands")
	end)

	test("malformed loadout events do not replace the client attack map", function()
		local current = { MainHand = "training_sword", OffHand = "wooden_shield" }
		local kept = TrainingLoadouts.applyPresentedLoadout(current, {
			Kind = "Loadout",
			MainHand = 12,
			OffHand = false,
		})
		eq(kept, current)
		eq(kept.MainHand, "training_sword")

		local unknown = TrainingLoadouts.applyPresentedLoadout(current, {
			Kind = "Loadout",
			MainHand = "not_a_weapon",
			OffHand = false,
		})
		eq(unknown, current)

		local omitted = TrainingLoadouts.applyPresentedLoadout(current, {
			Kind = "Loadout",
			MainHand = "ember_staff",
		})
		eq(omitted, current)

		local hit = TrainingLoadouts.applyPresentedLoadout(current, { Kind = "Hit", Damage = 4 })
		eq(hit, current)

		local presented = TrainingLoadouts.applyPresentedLoadout(current, {
			Kind = "Loadout",
			MainHand = "ember_staff",
			OffHand = false,
		})
		eq(presented.MainHand, "ember_staff")
		eq(presented.OffHand, nil)
		eq(current.MainHand, "training_sword", "the previous map is not mutated")
	end)
end
