-- Unit tests for the training preset selector state.
--
-- These tests do not create Instances. They do not cover TextButton input,
-- screen layout, or RemoteEvent delivery. Those remain Studio checks.

return function(test: (string, () -> ()) -> (), eq: (any, any, string?) -> ())
	local TrainingLoadouts = require("../src/ReplicatedStorage/Shared/Combat/TrainingLoadouts")
	local TrainingSceneConfig = require("../src/ReplicatedStorage/Shared/Combat/TrainingSceneConfig")

	local function practiceScene()
		local marker = TrainingSceneConfig.resolve().DummyMarker
		return {
			MarkerName = "TrainingDummyMarker",
			Marker = marker,
			PassiveCount = 3,
		}, marker
	end

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
		}
		for _, event in events do
			local nextState = TrainingLoadouts.applyPresetPresentation(shown, event)
			eq(nextState, shown)
			eq(nextState.Visible, true)
			eq(nextState.SelectedPresetId, "Mage")
		end
		local nilEvent = TrainingLoadouts.applyPresetPresentation(shown, nil)
		eq(nilEvent, shown, "nil event keeps the same presentation")
		eq(nilEvent.Visible, true)
		eq(nilEvent.SelectedPresetId, "Mage")
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
		eq(TrainingLoadouts.selectionIdentity(store.get(), "Archer", true).Confirmed, true)
		eq(TrainingLoadouts.selectionIdentity(store.get(), "Mage", true).Confirmed, false)
		eq(TrainingLoadouts.presetStatus(store.get()).ConfirmedPresetId, "Archer")
		local scene = practiceScene()
		eq(TrainingLoadouts.practiceCue(store.get(), scene).Visible, true)
		eq(TrainingLoadouts.practiceCue(store.get(), scene).MarkerName, "TrainingDummyMarker")

		early()
		late()
		store.applyEvent(presetEvent("Archer", false))
		eq(earlyCalls, 2, "disconnected listener stays quiet")
		eq(lateCalls, 1, "disconnected late listener stays quiet")
		eq(store.get().Visible, false)
		eq(store.get().SelectedPresetId, nil)
		eq(TrainingLoadouts.presetStatus(store.get()).PurposeVisible, false)
		eq(TrainingLoadouts.practiceCue(store.get(), scene).Visible, false)
		eq(TrainingLoadouts.selectionIdentity(store.get(), "Archer", true).ShowCheck, false)

		local after = store.subscribe(function(presentation)
			eq(presentation.Visible, false)
			eq(presentation.SelectedPresetId, nil)
		end)
		after()
	end)

	test("an earlier listener error still delivers the same update", function()
		local store = TrainingLoadouts.createPresetPresentationStore()
		local phase = "subscribe"
		local earlyCalls = 0
		store.subscribe(function(_presentation)
			earlyCalls += 1
			if phase == "update" then
				error("preset listener boom")
			end
		end)
		local lateCalls = 0
		local lateSelection: string? = nil
		store.subscribe(function(presentation)
			lateCalls += 1
			lateSelection = presentation.SelectedPresetId
		end)
		eq(earlyCalls, 1, "healthy subscribe")
		eq(lateCalls, 1, "later subscribe sees the hidden snapshot")
		eq(lateSelection, nil)
		phase = "update"
		local ok = pcall(function()
			store.applyEvent(presetEvent("Mage", true))
		end)
		eq(ok, true, "applyEvent does not throw")
		eq(earlyCalls, 2, "earlier listener still ran")
		eq(lateCalls, 2, "later listener receives this update")
		eq(lateSelection, "Mage")
		eq(store.get().Visible, true, "cached presentation stays the server update")
		eq(store.get().SelectedPresetId, "Mage")
	end)

	test("a failing immediate subscribe callback does not poison later use", function()
		local store = TrainingLoadouts.createPresetPresentationStore()
		local failingCalls = 0
		local disconnect = store.subscribe(function(_presentation)
			failingCalls += 1
			error("preset subscribe boom")
		end)
		eq(failingCalls, 1, "immediate callback ran")
		eq(type(disconnect), "function", "subscribe still returns disconnect")
		eq(store.get().Visible, false, "failed callback leaves the cache hidden")
		eq(store.get().SelectedPresetId, nil)

		local healthyCalls = 0
		local healthySelection: string? = "stale"
		store.subscribe(function(presentation)
			healthyCalls += 1
			healthySelection = presentation.SelectedPresetId
		end)
		eq(healthyCalls, 1, "later subscribe still gets the current snapshot")
		eq(healthySelection, nil)
		store.applyEvent(presetEvent("Archer", true))
		eq(failingCalls, 2, "the failing listener does not stick the store")
		eq(healthyCalls, 2, "later listener receives the next update")
		eq(healthySelection, "Archer")
		eq(store.get().Visible, true)
		eq(store.get().SelectedPresetId, "Archer")
		disconnect()
		store.applyEvent(presetEvent("Archer", false))
		eq(failingCalls, 2, "disconnect removes the failing listener")
		eq(healthyCalls, 3, "the healthy listener still receives the restore")
		eq(store.get().Visible, false)
		eq(store.get().SelectedPresetId, nil)
	end)

	test("pointer leave keeps the confirmed check and border", function()
		local shown = TrainingLoadouts.applyPresetPresentation(
			TrainingLoadouts.emptyPresetPresentation(),
			presetEvent("Mage", true)
		)
		for _, presetId in TrainingLoadouts.PRESET_IDS do
			local hovered = TrainingLoadouts.selectionIdentity(shown, presetId, true)
			local left = TrainingLoadouts.selectionIdentity(shown, presetId, false)
			local confirmed = presetId == "Mage"
			eq(hovered.Confirmed, confirmed, `{presetId} hover`)
			eq(left.Confirmed, confirmed, `{presetId} leave`)
			eq(left.ShowCheck, hovered.ShowCheck, `{presetId} check`)
			eq(left.ShowBorder, hovered.ShowBorder, `{presetId} border`)
			eq(left.ShowCheck, confirmed, `{presetId} check matches confirmation`)
			eq(left.ShowBorder, confirmed, `{presetId} border matches confirmation`)
			eq(left.PresetId, presetId)
		end
		local hidden = TrainingLoadouts.emptyPresetPresentation()
		local idleHover = TrainingLoadouts.selectionIdentity(hidden, "Swordsman", true)
		eq(idleHover.Confirmed, false)
		eq(idleHover.ShowCheck, false)
		eq(idleHover.ShowBorder, false)
	end)

	test("an unconfirmed click does not mark a preset successful", function()
		local hidden = TrainingLoadouts.emptyPresetPresentation()
		local requested = TrainingLoadouts.presentationAfterPresetRequest(hidden, "Archer")
		local hiddenStatus = TrainingLoadouts.presetStatus(requested)
		eq(hiddenStatus.PurposeVisible, false)
		eq(hiddenStatus.ConfirmedPresetId, nil)
		eq(hiddenStatus.AwaitingConfirmation, false)
		eq(hiddenStatus.NextStep, "Choose")
		eq(TrainingLoadouts.selectionIdentity(requested, "Archer", true).Confirmed, false)

		local mage = TrainingLoadouts.applyPresetPresentation(requested, presetEvent("Mage", true))
		local clicked = TrainingLoadouts.presentationAfterPresetRequest(mage, "Archer")
		eq(clicked, mage)
		local status = TrainingLoadouts.presetStatus(clicked)
		eq(status.ConfirmedPresetId, "Mage")
		eq(status.NextStep, "WalkToDummy")
		eq(TrainingLoadouts.selectionIdentity(clicked, "Archer", true).Confirmed, false)
		eq(TrainingLoadouts.selectionIdentity(clicked, "Archer", true).ShowCheck, false)
		eq(TrainingLoadouts.selectionIdentity(clicked, "Mage", false).ShowCheck, true)
		local rejected = TrainingLoadouts.applyPresetPresentation(clicked, { Kind = "Rejected", Reason = "Busy" })
		eq(TrainingLoadouts.presetStatus(rejected).ConfirmedPresetId, "Mage")
		eq(TrainingLoadouts.selectionIdentity(rejected, "Mage", false).ShowBorder, true)
		eq(TrainingLoadouts.selectionIdentity(rejected, "Swordsman", true).Confirmed, false)
	end)

	test("switching presets confirms only the server loadout", function()
		local state = TrainingLoadouts.emptyPresetPresentation()
		for _, presetId in TrainingLoadouts.PRESET_IDS do
			state = TrainingLoadouts.applyPresetPresentation(state, presetEvent(presetId, true))
			local status = TrainingLoadouts.presetStatus(state)
			eq(status.PurposeVisible, true, presetId)
			eq(status.ConfirmedPresetId, presetId, presetId)
			eq(status.AwaitingConfirmation, false, presetId)
			eq(status.NextStep, "WalkToDummy", presetId)
			for _, other in TrainingLoadouts.PRESET_IDS do
				local identity = TrainingLoadouts.selectionIdentity(state, other, other ~= presetId)
				eq(identity.Confirmed, other == presetId, `{presetId}->{other}`)
				eq(identity.ShowCheck, other == presetId, `{presetId}->{other} check`)
				eq(identity.ShowBorder, other == presetId, `{presetId}->{other} border`)
			end
		end
	end)

	test("active training points at the scene marker and exit clears it", function()
		local scene, marker = practiceScene()
		local hiddenCue = TrainingLoadouts.practiceCue(TrainingLoadouts.emptyPresetPresentation(), scene)
		eq(hiddenCue.Visible, false)
		eq(hiddenCue.MarkerName, "")
		eq(hiddenCue.MarkerX, 0)
		eq(hiddenCue.MarkerZ, 0)
		eq(hiddenCue.PassiveCount, 0)
		eq((hiddenCue :: any).Damage, nil)
		eq((hiddenCue :: any).Blocked, nil)

		local shown = TrainingLoadouts.applyPresetPresentation(
			TrainingLoadouts.emptyPresetPresentation(),
			presetEvent("Swordsman", true)
		)
		local cue = TrainingLoadouts.practiceCue(shown, scene)
		eq(cue.Visible, true)
		eq(cue.MarkerName, "TrainingDummyMarker")
		eq(cue.MarkerX, marker.X)
		eq(cue.MarkerY, marker.Y)
		eq(cue.MarkerZ, marker.Z)
		eq(cue.PassiveCount, 3)
		eq((cue :: any).Damage, nil)
		eq((cue :: any).Blocked, nil)
		eq((cue :: any).Success, nil)

		local unknown = TrainingLoadouts.applyPresetPresentation(shown, {
			Kind = "Loadout",
			Temporary = true,
			MainHand = "iron_greatsword",
			OffHand = false,
		})
		local unknownStatus = TrainingLoadouts.presetStatus(unknown)
		eq(unknownStatus.AwaitingConfirmation, true)
		eq(unknownStatus.ConfirmedPresetId, nil)
		eq(unknownStatus.NextStep, "Choose")
		eq(TrainingLoadouts.practiceCue(unknown, scene).Visible, true)
		for _, presetId in TrainingLoadouts.PRESET_IDS do
			eq(TrainingLoadouts.selectionIdentity(unknown, presetId, true).Confirmed, false, presetId)
		end

		local restored = TrainingLoadouts.applyPresetPresentation(unknown, presetEvent("Swordsman", false))
		local cleared = TrainingLoadouts.practiceCue(restored, scene)
		eq(TrainingLoadouts.presetStatus(restored).PurposeVisible, false)
		eq(TrainingLoadouts.presetStatus(restored).ConfirmedPresetId, nil)
		eq(cleared.Visible, false)
		eq(cleared.MarkerName, "")
		eq(cleared.PassiveCount, 0)
		for _, presetId in TrainingLoadouts.PRESET_IDS do
			eq(TrainingLoadouts.selectionIdentity(restored, presetId, true).ShowCheck, false, presetId)
		end
	end)

	test("malformed events do not replace the confirmed identity or the cue", function()
		local scene = practiceScene()
		local shown = TrainingLoadouts.applyPresetPresentation(
			TrainingLoadouts.emptyPresetPresentation(),
			presetEvent("Archer", true)
		)
		local cue = TrainingLoadouts.practiceCue(shown, scene)
		local events = {
			{ Kind = "Hit", Damage = 4, Temporary = true },
			{ Kind = "Rejected", Reason = "Busy" },
			{ Coins = 3, Loadout = { MainHand = "training_sword", OffHand = "wooden_shield" } },
			{ Kind = "Loadout", Temporary = "true", MainHand = "ember_staff", OffHand = false },
			nil,
		}
		for _, event in events do
			local nextState = TrainingLoadouts.applyPresetPresentation(shown, event)
			eq(nextState, shown)
			local status = TrainingLoadouts.presetStatus(nextState)
			eq(status.ConfirmedPresetId, "Archer")
			eq(status.NextStep, "WalkToDummy")
			eq(TrainingLoadouts.selectionIdentity(nextState, "Archer", false).ShowBorder, true)
			eq(TrainingLoadouts.selectionIdentity(nextState, "Mage", true).Confirmed, false)
			local nextCue = TrainingLoadouts.practiceCue(nextState, scene)
			eq(nextCue.Visible, cue.Visible)
			eq(nextCue.MarkerName, cue.MarkerName)
			eq(nextCue.MarkerX, cue.MarkerX)
			eq(nextCue.MarkerZ, cue.MarkerZ)
			eq(nextCue.PassiveCount, cue.PassiveCount)
		end
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
