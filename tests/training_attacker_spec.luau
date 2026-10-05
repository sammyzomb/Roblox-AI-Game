-- Pure tests for the scene dummy's development attack cadence.
-- The production module is src/ReplicatedStorage/Shared/Combat/TrainingAttacker.luau.
-- These tests do not construct Roblox instances.

local TrainingAttacker = require("../src/ReplicatedStorage/Shared/Combat/TrainingAttacker")

return function(test: (string, () -> ()) -> (), eq: (any, any, string?) -> ())
	local INTERVAL = TrainingAttacker.DEVELOPMENT_INTERVAL_SECONDS
	local RANGE = TrainingAttacker.DEVELOPMENT_PRACTICE_RANGE

	local function candidate(id: string, tieKey: string, position: { number }?, flags: { Training: boolean?, Registered: boolean?, Alive: boolean? }?)
		local options = flags or {}
		return {
			Id = id,
			TieKey = tieKey,
			Training = if options.Training == nil then true else options.Training,
			Registered = if options.Registered == nil then true else options.Registered,
			Alive = if options.Alive == nil then true else options.Alive,
			Root = if position then { X = position[1], Y = position[2], Z = position[3] } else nil,
		}
	end

	local function probe(attackerId: unknown, now: number, candidates, alive: boolean?, origin)
		return {
			Now = now,
			AttackerId = attackerId,
			AttackerAlive = if alive == nil then true else alive,
			Origin = if origin == nil then { X = 0, Y = 3, Z = 0 } else origin,
			Candidates = candidates,
		}
	end

	local function bound(attackerId: unknown, now: number)
		return TrainingAttacker.adopt(TrainingAttacker.initial(now), attackerId, now)
	end

	test("development cadence and practice range are explicit constants", function()
		eq(INTERVAL, 2.5, "interval")
		eq(RANGE, 10, "range")
		eq(TrainingAttacker.DEVELOPMENT_BYSTANDER_CLEARANCE, 12, "clearance")
	end)

	test("non-training, dead, unregistered, and missing-root targets are not selected", function()
		local state = bound("scene", 0)
		local cases = {
			candidate("away", "a", { 1, 3, 0 }, { Training = false }),
			candidate("dead", "b", { 1, 3, 0 }, { Alive = false }),
			candidate("unregistered", "c", { 1, 3, 0 }, { Registered = false }),
			candidate("nobody", "d", nil),
		}
		for _, one in cases do
			local decision, nextState = TrainingAttacker.step(state, probe("scene", 0, { one }))
			eq(decision.Action, "Skip", tostring(one.Id))
			eq(nextState, state, "a skip does not commit the interval")
		end
	end)

	test("a target outside the horizontal practice range is not selected", function()
		local state = bound("scene", 0)
		local outside = candidate("far", "a", { RANGE + 0.01, 3, 0 })
		local decision, nextState = TrainingAttacker.step(state, probe("scene", 0, { outside }))
		eq(decision.Action, "Skip")
		eq(nextState, state)
		local edge = candidate("edge", "e", { RANGE, 3, 0 })
		local edgeDecision = TrainingAttacker.step(state, probe("scene", 0, { edge }))
		eq(edgeDecision.Action, "Attack", "the marked range is inclusive")
		eq(edgeDecision.TargetId, "edge")
		local above = candidate("high", "b", { 0, 100, 0 })
		local highDecision = TrainingAttacker.step(state, probe("scene", 0, { above }))
		eq(highDecision.Action, "Attack", "height alone does not leave the horizontal range")
		eq(highDecision.TargetId, "high")
	end)

	test("the sole clearance occupant is selected, ignoring non-occupants", function()
		local state = bound("scene", 0)
		local clearance = TrainingAttacker.DEVELOPMENT_BYSTANDER_CLEARANCE
		local deadCloser = candidate("dead", "a", { 1, 3, 0 }, { Alive = false })
		local unregisteredCloser = candidate("ghost", "b", { 1, 3, 0 }, { Registered = false })
		local outside = candidate("far", "c", { clearance + 1, 3, 0 })
		local near = candidate("near", "z", { 3, 3, 0 })
		local decision, nextState = TrainingAttacker.step(state, probe("scene", 0, {
			deadCloser,
			outside,
			near,
			unregisteredCloser,
		}))
		eq(decision.Action, "Attack")
		eq(decision.TargetId, "near")
		eq(decision.Aim.X, 3)
		eq(decision.Aim.Y, 3)
		eq(decision.Aim.Z, 0)
		eq(nextState.NextDue, INTERVAL)

		local reversed = TrainingAttacker.step(state, probe("scene", 0, {
			unregisteredCloser,
			near,
			outside,
			deadCloser,
		}))
		eq(reversed.TargetId, "near", "input order does not replace the only occupant")
	end)

	test("a non-training bystander inside the clearance suppresses the swing", function()
		local state = bound("scene", 0)
		local clearance = TrainingAttacker.DEVELOPMENT_BYSTANDER_CLEARANCE
		local target = candidate("player", "p", { 2, 3, 0 })
		local bystander = candidate("watch", "w", { 4, 3, 0 }, { Training = false })
		local decision, nextState = TrainingAttacker.step(state, probe("scene", 0, { target, bystander }))
		eq(decision.Action, "Skip")
		eq(decision.TargetId, nil)
		eq(nextState, state, "a bystander suppression does not advance NextDue")

		local onTheEdge = candidate("edge", "e", { clearance, 3, 0 }, { Training = false })
		local edgeDecision, edgeState = TrainingAttacker.step(state, probe("scene", 0, { target, onTheEdge }))
		eq(edgeDecision.Action, "Skip", "the safety buffer is inclusive")
		eq(edgeState, state)

		local overhead = candidate("high", "h", { 0, 100, 0 }, { Training = false })
		local highDecision, highState = TrainingAttacker.step(state, probe("scene", 0, { target, overhead }))
		eq(highDecision.Action, "Skip", "clearance is horizontal, so height does not exempt a bystander")
		eq(highState, state)
	end)

	test("a second training player inside the clearance also suppresses the swing", function()
		local state = bound("scene", 0)
		local clearance = TrainingAttacker.DEVELOPMENT_BYSTANDER_CLEARANCE
		local target = candidate("player", "p", { 2, 3, 0 })
		local outsidePractice = candidate("other", "o", { clearance, 3, 0 })
		local decision, nextState = TrainingAttacker.step(state, probe("scene", 0, { target, outsidePractice }))
		eq(decision.Action, "Skip", "a second trainee inside the buffer suppresses even outside practice range")
		eq(nextState, state)

		local alsoPracticing = candidate("close", "c", { 6, 3, 0 })
		local crowded, held = TrainingAttacker.step(state, probe("scene", 0, { target, alsoPracticing }))
		eq(crowded.Action, "Skip")
		eq(crowded.TargetId, nil)
		eq(held, state)
	end)

	test("a bystander outside the clearance does not suppress a valid solo target", function()
		local state = bound("scene", 0)
		local clearance = TrainingAttacker.DEVELOPMENT_BYSTANDER_CLEARANCE
		local target = candidate("player", "p", { 2, 3, 0 })
		local outside = candidate("watch", "w", { clearance + 0.01, 3, 0 }, { Training = false })
		local decision, nextState = TrainingAttacker.step(state, probe("scene", 0, { outside, target }))
		eq(decision.Action, "Attack")
		eq(decision.TargetId, "player")
		eq(nextState.NextDue, INTERVAL)

		local dead = candidate("dead", "d", { 1, 3, 0 }, { Alive = false })
		local unregistered = candidate("ghost", "g", { 1, 3, 0 }, { Registered = false })
		local missing = candidate("nobody", "n", nil)
		local nonFinite = candidate("nan", "nan", { 1, 3, 0 }, { Training = false })
		nonFinite.Root = { X = 0, Y = 0, Z = 0 / 0 }
		local still = TrainingAttacker.step(state, probe("scene", 0, { target, dead, unregistered, missing, nonFinite }))
		eq(still.Action, "Attack")
		eq(still.TargetId, "player")
	end)

	test("a suppressed bystander decision does not advance NextDue", function()
		local state = bound("scene", 5)
		local target = candidate("player", "p", { 2, 3, 0 })
		local bystander = candidate("watch", "w", { 3, 3, 0 }, { Training = false })
		local decision, nextState = TrainingAttacker.step(state, probe("scene", 5, { target, bystander }))
		eq(decision.Action, "Skip")
		eq(nextState.NextDue, state.NextDue)
		eq(TrainingAttacker.isDue(nextState, "scene", 5), true)
		local later, still = TrainingAttacker.step(nextState, probe("scene", 5 + INTERVAL, { target, bystander }))
		eq(later.Action, "Skip")
		eq(still.NextDue, state.NextDue)
		local alone, committed = TrainingAttacker.step(still, probe("scene", 5 + INTERVAL, { target }))
		eq(alone.Action, "Attack")
		eq(alone.TargetId, "player")
		eq(committed.NextDue, 5 + INTERVAL * 2)
	end)

	test("a due attacker attempts once and does not retry before the next interval", function()
		local state = bound("scene", 0)
		local target = candidate("player", "p", { 2, 3, 0 })
		local first, committed = TrainingAttacker.step(state, probe("scene", 0, { target }))
		eq(first.Action, "Attack")
		eq(committed.NextDue, INTERVAL)
		local again, held = TrainingAttacker.step(committed, probe("scene", 0, { target }))
		eq(again.Action, "Wait")
		eq(held, committed, "the same timestamp cannot spend another attempt")
		local early, still = TrainingAttacker.step(committed, probe("scene", INTERVAL - 0.01, { target }))
		eq(early.Action, "Wait")
		eq(still, committed)
		eq(TrainingAttacker.isDue(committed, "scene", INTERVAL - 0.01), false)
		local nextSwing, later = TrainingAttacker.step(committed, probe("scene", INTERVAL, { target }))
		eq(nextSwing.Action, "Attack")
		eq(later.NextDue, INTERVAL * 2)
	end)

	test("a skipped due check can still make the one attempt once a target is eligible", function()
		local state = bound("scene", 0)
		local skipped, waiting = TrainingAttacker.step(state, probe("scene", 0, {}))
		eq(skipped.Action, "Skip")
		eq(waiting, state)
		local decision, committed = TrainingAttacker.step(state, probe("scene", 0, {
			candidate("player", "p", { 1, 3, 0 }),
		}))
		eq(decision.Action, "Attack")
		eq(committed.NextDue, INTERVAL)
	end)

	test("a dead or removed attacker does not commit the interval", function()
		local state = bound("scene", 0)
		local target = candidate("player", "p", { 1, 3, 0 })
		local dead, afterDead = TrainingAttacker.step(state, probe("scene", 0, { target }, false))
		eq(dead.Action, "Skip")
		eq(afterDead, state)
		local removedProbe = probe("scene", 0, { target })
		removedProbe.Origin = nil
		local removed, afterRemoved = TrainingAttacker.step(state, removedProbe)
		eq(removed.Action, "Skip")
		eq(afterRemoved, state)
	end)

	test("replacing the attacker leaves the old attacker inactive", function()
		local oldId = { Name = "old" }
		local newId = { Name = "new" }
		local state = bound(oldId, 0)
		local target = candidate("player", "p", { 1, 3, 0 })
		local _, committed = TrainingAttacker.step(state, probe(oldId, 0, { target }))
		local replaced = TrainingAttacker.adopt(committed, newId, 5)
		local stale, afterStale = TrainingAttacker.step(replaced, probe(oldId, 5, { target }))
		eq(stale.Action, "Inactive")
		eq(afterStale, replaced, "the old id cannot move the replacement schedule")
		eq(afterStale.AttackerId, newId)
		local fresh, nextState = TrainingAttacker.step(replaced, probe(newId, 5, { target }))
		eq(fresh.Action, "Attack")
		eq(fresh.TargetId, "player")
		eq(nextState.AttackerId, newId)

		local retiredEarly = TrainingAttacker.retire(replaced, oldId)
		eq(retiredEarly, replaced, "retiring the old id does not clear the replacement")
		local retired = TrainingAttacker.retire(committed, oldId)
		local ghost, afterGhost = TrainingAttacker.step(retired, probe(oldId, 1, { target }))
		eq(ghost.Action, "Inactive")
		eq(afterGhost.AttackerId, nil)
		local adopted = TrainingAttacker.adopt(retired, newId, 4)
		local onlyNew = TrainingAttacker.step(adopted, probe(newId, 4, { target }))
		eq(onlyNew.Action, "Attack")
		eq(onlyNew.TargetId, "player")
	end)
end
