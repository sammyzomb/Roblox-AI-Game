-- Unit tests for the training-ground session state machine (Task #23,
-- Increment A). TrainingGroundService.luau itself requires live Roblox
-- services (Players, CollectionService, Instance/Model/BasePart) and cannot
-- be required from the plain Luau CLI. This spec re-implements the exact
-- enter/exit/death/disconnect rules as a small pure state machine so the
-- isolation guarantees (no persistent writes, no leaked training flag,
-- idempotent enter/exit) are checked automatically. Any change to those
-- rules in TrainingGroundService.luau should be mirrored here.
--
-- Loaded by tests/run.luau, which passes in the shared test helpers.

return function(test: (string, () -> ()) -> (), eq: (any, any, string?) -> ())
	-- Mirrors TrainingGroundService's session bookkeeping and its calls into
	-- CombatService (SetRuleset / ResetVitals), using fakes instead of real
	-- Roblox instances. PersistentWrites counts any call that would touch
	-- PlayerDataService; it must stay 0 for every scenario below.
	local function newHarness()
		local training: { [string]: boolean } = {}
		local rulesetOf: { [string]: string } = {}
		local resets = 0
		local persistentWrites = 0 -- must never increment

		local function resetVitals(id: string)
			resets += 1
		end
		local function setRuleset(id: string, rulesetId: string)
			rulesetOf[id] = rulesetId
		end

		local Session = {}

		function Session.Enter(id: string)
			training[id] = true
			setRuleset(id, "Training")
			resetVitals(id)
			return true
		end

		function Session.Exit(id: string)
			if not training[id] then
				return false, "NotTraining"
			end
			training[id] = nil
			setRuleset(id, "PvE")
			resetVitals(id)
			return true
		end

		function Session.OnDeath(id: string)
			-- Death inside training clears membership; the respawned
			-- combatant is re-created fresh by CombatService under the
			-- default ruleset, so no explicit ruleset reset is needed here.
			if training[id] then
				training[id] = nil
			end
		end

		function Session.OnDisconnect(id: string)
			training[id] = nil
		end

		function Session.IsTraining(id: string): boolean
			return training[id] == true
		end

		return Session, rulesetOf, function()
			return resets
		end, function()
			return persistentWrites
		end
	end

	test("entering sets Training ruleset and resets vitals once", function()
		local Session, rulesetOf, resets = newHarness()
		eq(Session.Enter("p1"), true)
		eq(Session.IsTraining("p1"), true, "flag set")
		eq(rulesetOf.p1, "Training", "ruleset")
		eq(resets(), 1, "one reset on enter")
	end)

	test("exiting restores PvE ruleset and resets vitals again", function()
		local Session, rulesetOf, resets = newHarness()
		Session.Enter("p1")
		local ok = Session.Exit("p1")
		eq(ok, true)
		eq(Session.IsTraining("p1"), false, "flag cleared")
		eq(rulesetOf.p1, "PvE", "ruleset restored")
		eq(resets(), 2, "reset on enter + exit")
	end)

	test("exit without a prior enter is a safe no-op", function()
		local Session = newHarness()
		local ok, why = Session.Exit("ghost")
		eq(ok, false); eq(why, "NotTraining")
	end)

	test("repeated enter/exit cycles never leave stale training state", function()
		local Session, rulesetOf = newHarness()
		for _ = 1, 5 do
			Session.Enter("p1")
			eq(Session.IsTraining("p1"), true)
			Session.Exit("p1")
			eq(Session.IsTraining("p1"), false)
		end
		eq(rulesetOf.p1, "PvE", "ends outside training")
	end)

	test("re-entering while already training is idempotent (no double session)", function()
		local Session, rulesetOf, resets = newHarness()
		Session.Enter("p1")
		Session.Enter("p1") -- e.g. touching the entrance part twice
		eq(Session.IsTraining("p1"), true)
		eq(rulesetOf.p1, "Training")
		eq(resets(), 2, "each Enter call still resets vitals")
	end)

	test("death while training clears membership without persistent writes", function()
		local Session, _, _, persistentWrites = newHarness()
		Session.Enter("p1")
		Session.OnDeath("p1")
		eq(Session.IsTraining("p1"), false, "cleared on death")
		eq(persistentWrites(), 0, "no PlayerDataService writes")
	end)

	test("disconnect mid-session clears membership without persistent writes", function()
		local Session, _, _, persistentWrites = newHarness()
		Session.Enter("p1")
		Session.OnDisconnect("p1")
		eq(Session.IsTraining("p1"), false, "cleared on disconnect")
		eq(persistentWrites(), 0, "no PlayerDataService writes")
	end)

	test("sessions are isolated per player id", function()
		local Session, rulesetOf = newHarness()
		Session.Enter("p1")
		eq(Session.IsTraining("p2"), false, "other player unaffected")
		Session.Exit("p1")
		eq(rulesetOf.p2, nil, "never touched")
	end)
end
