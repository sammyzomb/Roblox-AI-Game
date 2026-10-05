-- Unit tests for the training preset selector state.
--
-- These tests do not create Instances. They do not cover TextButton input,
-- screen layout, or RemoteEvent delivery. Those remain Studio checks.

return function(test: (string, () -> ()) -> (), eq: (any, any, string?) -> ())
	local TrainingLoadouts = require("../src/ReplicatedStorage/Shared/Combat/TrainingLoadouts")

	local function presetEvent(presetId: string, temporary: boolean)
		local items = TrainingLoadouts.itemIds(presetId)
		assert(items ~= nil, presetId)
		return {
			Kind = "Loadout",
			Temporary = temporary,
			MainHand = items[1],
			OffHand = if items[2] ~= nil then items[2] else false,
		}
	end

	test("temporary loadouts show the matching preset and a restore hides it", function()
		local hidden = TrainingLoadouts.emptyPresetPresentation()
		eq(hidden.Visible, false)
		eq(hidden.SelectedPresetId, nil)
		for _, presetId in TrainingLoadouts.PRESET_IDS do
			local shown = TrainingLoadouts.applyPresetPresentation(hidden, presetEvent(presetId, true))
			eq(shown.Visible, true, presetId)
			eq(shown.SelectedPresetId, presetId, presetId)
			local restored = TrainingLoadouts.applyPresetPresentation(shown, presetEvent(presetId, false))
			eq(restored.Visible, false, `{presetId} hidden`)
			eq(restored.SelectedPresetId, nil, `{presetId} cleared`)
		end
	end)

	test("swapped hand fields still identify the preset from its item ids", function()
		local items = TrainingLoadouts.itemIds("Swordsman")
		assert(items ~= nil and items[2] ~= nil, "Swordsman hands")
		eq(TrainingLoadouts.identifyPreset({ MainHand = items[2], OffHand = items[1] }), "Swordsman")
		eq(TrainingLoadouts.identifyPreset({ OffHand = items[1] }), nil, "one hand is not Swordsman")
	end)

	test("a known weapon that is not a preset shows the selector with no highlight", function()
		local shown = TrainingLoadouts.applyPresetPresentation(TrainingLoadouts.emptyPresetPresentation(), {
			Kind = "Loadout",
			Temporary = true,
			MainHand = "iron_greatsword",
			OffHand = false,
		})
		eq(shown.Visible, true)
		eq(shown.SelectedPresetId, nil)
	end)

	test("malformed and unrelated events keep the visible selection", function()
		local shown = TrainingLoadouts.applyPresetPresentation(
			TrainingLoadouts.emptyPresetPresentation(),
			presetEvent("Mage", true)
		)
		local events = {
			{ Kind = "Hit", Damage = 4, Temporary = true },
			{ Kind = "Rejected", Reason = "Busy" },
			{ Coins = 3, Loadout = { MainHand = "training_sword", OffHand = "wooden_shield" } },
			{ Kind = "Loadout", Temporary = "true", MainHand = "ember_staff", OffHand = false },
			{ Kind = "Loadout", Temporary = true, MainHand = "not_a_weapon", OffHand = false },
			{ Kind = "Loadout", Temporary = true, MainHand = "ember_staff" },
			"Loadout",
			nil,
		}
		for _, event in events do
			local nextState = TrainingLoadouts.applyPresetPresentation(shown, event)
			eq(nextState, shown)
			eq(nextState.Visible, true)
			eq(nextState.SelectedPresetId, "Mage")
		end
	end)

	test("a preset request does not change highlight until the server loadout", function()
		local hidden = TrainingLoadouts.emptyPresetPresentation()
		local requested = TrainingLoadouts.presentationAfterPresetRequest(hidden, "Archer")
		eq(requested, hidden)
		eq(requested.Visible, false)
		eq(requested.SelectedPresetId, nil)
		local mage = TrainingLoadouts.applyPresetPresentation(requested, presetEvent("Mage", true))
		local clicked = TrainingLoadouts.presentationAfterPresetRequest(mage, "Archer")
		eq(clicked, mage)
		eq(clicked.SelectedPresetId, "Mage")
		local confirmed = TrainingLoadouts.applyPresetPresentation(clicked, presetEvent("Archer", true))
		eq(confirmed.Visible, true)
		eq(confirmed.SelectedPresetId, "Archer")
	end)

	test("a late subscriber receives the current snapshot and can disconnect", function()
		local store = TrainingLoadouts.createPresetPresentationStore()
		local earlyCalls = 0
		local earlyVisible = false
		local earlySelection: string? = nil
		local early = store.subscribe(function(presentation)
			earlyCalls += 1
			earlyVisible = presentation.Visible
			earlySelection = presentation.SelectedPresetId
		end)
		eq(earlyCalls, 1, "initial snapshot")
		eq(earlyVisible, false)
		eq(earlySelection, nil)
		store.notePresetRequest("Mage")
		eq(earlyCalls, 1, "request does not publish")
		eq(store.get().SelectedPresetId, nil)
		store.applyEvent(presetEvent("Archer", true))
		eq(earlyCalls, 2, "server confirmation publishes")
		eq(earlyVisible, true)
		eq(earlySelection, "Archer")

		local lateCalls = 0
		local lateSelection: string? = nil
		local lateVisible = false
		local late = store.subscribe(function(presentation)
			lateCalls += 1
			lateVisible = presentation.Visible
			lateSelection = presentation.SelectedPresetId
			presentation.Visible = false
			presentation.SelectedPresetId = "Mage"
		end)
		eq(lateCalls, 1, "late subscriber gets one snapshot")
		eq(lateVisible, true)
		eq(lateSelection, "Archer")
		eq(store.get().Visible, true, "snapshot mutation does not change the cache")
		eq(store.get().SelectedPresetId, "Archer")

		early()
		late()
		store.applyEvent(presetEvent("Archer", false))
		eq(earlyCalls, 2, "disconnected listener stays quiet")
		eq(lateCalls, 1, "disconnected late listener stays quiet")
		eq(store.get().Visible, false)
		eq(store.get().SelectedPresetId, nil)

		local after = store.subscribe(function(presentation)
			eq(presentation.Visible, false)
			eq(presentation.SelectedPresetId, nil)
		end)
		after()
	end)

	test("the selector reducer does not clear a latched training attack map", function()
		local event = presetEvent("Mage", true)
		local latched = TrainingLoadouts.applyLoadoutEvent(TrainingLoadouts.emptyAttackMap(), event)
		local shown = TrainingLoadouts.applyPresetPresentation(TrainingLoadouts.emptyPresetPresentation(), event)
		local later = TrainingLoadouts.applyPersistentAttackMap(latched, {
			Coins = 9,
			Loadout = { MainHand = "training_sword", OffHand = "wooden_shield" },
		})
		local mageItems = TrainingLoadouts.itemIds("Mage")
		assert(mageItems ~= nil, "Mage")
		eq(later.Temporary, true)
		eq(later.Loadout.MainHand, mageItems[1])
		eq(later.Loadout.OffHand, nil)
		eq(shown.Visible, true)
		eq(shown.SelectedPresetId, "Mage")
		eq(latched.Loadout.MainHand, mageItems[1], "presentation does not mutate the attack map")
	end)
end
