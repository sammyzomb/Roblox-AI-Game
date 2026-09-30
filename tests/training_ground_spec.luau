-- Unit tests for the training-ground session state machine (Task #23,
-- correction increment). These tests exercise the actual production module
-- src/ReplicatedStorage/Shared/Combat/TrainingSession.luau - the same module
-- TrainingGroundService.luau requires - not a re-implemented copy. The
-- Roblox-only parts of TrainingGroundService (CollectionService touch
-- hooks, CombatService wiring, character teleport) still cannot run outside
-- Studio and are covered by the smoke test checklist instead.
--
-- Loaded by tests/run.luau, which passes in the shared test helpers.

local TrainingSession = require("../src/ReplicatedStorage/Shared/Combat/TrainingSession")

return function(test: (string, () -> ()) -> (), eq: (any, any, string?) -> ())
	test("entering captures the prior ruleset and reports training", function()
		local session = TrainingSession.new()
		eq(session:IsTraining("p1"), false, "not training yet")
		session:Enter("p1", "PvE")
		eq(session:IsTraining("p1"), true, "flag set")
		eq(session:PriorRuleset("p1"), "PvE", "captured prior ruleset")
	end)

	test("entering captures whatever ruleset the player actually had, not a hardcoded PvE", function()
		local session = TrainingSession.new()
		session:Enter("p1", "PvP")
		eq(session:PriorRuleset("p1"), "PvP", "captured PvP, not assumed PvE")
	end)

	test("exit returns the captured prior ruleset and clears membership", function()
		local session = TrainingSession.new()
		session:Enter("p1", "PvE")
		local restored = session:Exit("p1")
		eq(restored, "PvE", "restores captured ruleset")
		eq(session:IsTraining("p1"), false, "flag cleared")
		eq(session:PriorRuleset("p1"), nil, "no prior ruleset once exited")
	end)

	test("exit without a prior enter is a safe no-op", function()
		local session = TrainingSession.new()
		local restored = session:Exit("ghost")
		eq(restored, nil, "nothing to restore")
	end)

	test("repeated enter/exit cycles never leave stale training state", function()
		local session = TrainingSession.new()
		for _ = 1, 5 do
			session:Enter("p1", "PvE")
			eq(session:IsTraining("p1"), true)
			local restored = session:Exit("p1")
			eq(restored, "PvE")
			eq(session:IsTraining("p1"), false)
		end
	end)

	test("re-entering while already training is idempotent and keeps the original prior ruleset", function()
		local session = TrainingSession.new()
		session:Enter("p1", "PvP") -- player was in a PvP ruleset before training
		session:Enter("p1", "Training") -- e.g. a second Enter call/touch while already training;
		-- even if callers mistakenly pass the *current* (Training) ruleset on
		-- a second call, the already-captured PvP prior must not be lost.
		eq(session:IsTraining("p1"), true)
		eq(session:PriorRuleset("p1"), "PvP", "original prior ruleset preserved, not overwritten with Training")
	end)

	test("death/disconnect path (OnDeathOrDisconnect) restores prior ruleset like Exit", function()
		local session = TrainingSession.new()
		session:Enter("p1", "PvE")
		local restored = session:OnDeathOrDisconnect("p1")
		eq(restored, "PvE", "same restoration contract as Exit")
		eq(session:IsTraining("p1"), false, "cleared on death/disconnect")
	end)

	test("sessions are isolated per player id", function()
		local session = TrainingSession.new()
		session:Enter("p1", "PvE")
		eq(session:IsTraining("p2"), false, "other player unaffected")
		eq(session:PriorRuleset("p2"), nil, "never touched")
		session:Exit("p1")
	end)

	test("two different players can hold two different prior rulesets simultaneously", function()
		local session = TrainingSession.new()
		session:Enter("p1", "PvE")
		session:Enter("p2", "PvP")
		eq(session:PriorRuleset("p1"), "PvE")
		eq(session:PriorRuleset("p2"), "PvP")
		eq(session:Exit("p1"), "PvE")
		eq(session:Exit("p2"), "PvP")
	end)
end
