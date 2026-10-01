-- Service/integration-level tests for the training-ground lifecycle
-- orchestration (Task #23 corrective increment, Grok/Technical-Lead defects
-- 1-3). These exercise the actual production module
-- src/ReplicatedStorage/Shared/Combat/TrainingLifecycle.luau - the same
-- orchestration logic TrainingGroundService.luau calls from real Player/
-- CombatService events - through a small fake CombatAdapter, not a second
-- copied state machine. This is distinct from training_ground_spec.luau,
-- which only covers the pure bookkeeping module (TrainingSession) and does
-- not exercise entry validation, character-generation ownership, or
-- disconnect ordering at all.
--
-- The fake adapter plays the role of CombatService: it tracks a registered/
-- living combatant per character, a current ruleset per player, and records
-- every SetRuleset call so tests can assert "no SetRuleset happened after
-- departure" - the exact defect being corrected.
--
-- Loaded by tests/run.luau, which passes in the shared test helpers.

local TrainingLifecycle = require("../src/ReplicatedStorage/Shared/Combat/TrainingLifecycle")

return function(test: (string, () -> ()) -> (), eq: (any, any, string?) -> ())
	local function newFakeCombat()
		local combatants: { [Instance]: { Alive: boolean } } = {}
		local rulesets: { [Instance]: string } = {}
		local resetOk: { [Instance]: boolean } = {}
		local setRulesetLog: { { Player: Instance, Ruleset: string } } = {}

		local adapter: TrainingLifecycle.CombatAdapter = {
			GetCombatant = function(model: Instance)
				return combatants[model]
			end,
			GetRuleset = function(player: Instance)
				return rulesets[player] or "PvE"
			end,
			SetRuleset = function(player: Instance, rulesetId: string)
				rulesets[player] = rulesetId
				table.insert(setRulesetLog, { Player = player, Ruleset = rulesetId })
			end,
			ResetVitals = function(model: Instance)
				if resetOk[model] == nil then
					return combatants[model] ~= nil and combatants[model].Alive
				end
				return resetOk[model]
			end,
		}

		return {
			Adapter = adapter,
			Register = function(character: Instance, alive: boolean?)
				combatants[character] = { Alive = if alive == nil then true else alive }
			end,
			Kill = function(character: Instance)
				if combatants[character] then
					combatants[character].Alive = false
				end
			end,
			SetResetWillFail = function(character: Instance, willFail: boolean)
				resetOk[character] = not willFail
			end,
			RulesetOf = function(player: Instance)
				return rulesets[player]
			end,
			SetRulesetCallsFor = function(player: Instance): number
				local n = 0
				for _, entry in setRulesetLog do
					if entry.Player == player then
						n += 1
					end
				end
				return n
			end,
			SetRulesetLogAfter = function(index: number)
				local out = {}
				for i = index + 1, #setRulesetLog do
					table.insert(out, setRulesetLog[i])
				end
				return out
			end,
			LogLength = function()
				return #setRulesetLog
			end,
		}
	end

	test("Enter rejects an unregistered character and claims no membership", function()
		local fake = newFakeCombat()
		local lifecycle = TrainingLifecycle.new(fake.Adapter)
		local player, character = "p1", "char1"

		local ok, why = lifecycle:Enter(player, character)
		eq(ok, false, "unregistered character must be rejected")
		eq(why, "NotRegisteredOrDead")
		eq(lifecycle:IsTraining(player), false, "no membership claimed on rejection")
	end)

	test("Enter rejects a dead combatant and claims no membership", function()
		local fake = newFakeCombat()
		local lifecycle = TrainingLifecycle.new(fake.Adapter)
		local player, character = "p1", "char1"
		fake.Register(character, false)

		local ok, why = lifecycle:Enter(player, character)
		eq(ok, false)
		eq(why, "NotRegisteredOrDead")
		eq(lifecycle:IsTraining(player), false)
		eq(fake.LogLength(), 0, "SetRuleset must never be called for a rejected entry")
	end)

	test("Enter rejects a reset failure without claiming membership (no ruleset switch)", function()
		local fake = newFakeCombat()
		local lifecycle = TrainingLifecycle.new(fake.Adapter)
		local player, character = "p1", "char1"
		fake.Register(character, true)
		fake.SetResetWillFail(character, true)

		local ok, why = lifecycle:Enter(player, character)
		eq(ok, false)
		eq(why, "ResetFailed")
		eq(lifecycle:IsTraining(player), false, "reset failure must not leave training membership claimed")
		eq(fake.LogLength(), 0, "SetRuleset must never run before a successful reset")
	end)

	test("original PvP ruleset is restored when the character is replaced (death/respawn)", function()
		local fake = newFakeCombat()
		local lifecycle = TrainingLifecycle.new(fake.Adapter)
		local player, oldCharacter, newCharacter = "p1", "charA", "charB"
		fake.Register(oldCharacter, true)

		-- Player was in a PvP ruleset before wandering into training.
		local adapterAny: any = fake.Adapter
		adapterAny.GetRuleset = function() return "PvP" end

		local ok = lifecycle:Enter(player, oldCharacter)
		eq(ok, true, "enter should succeed")
		eq(fake.RulesetOf(player), "Training")

		-- The old character is removed (death). This must restore PvP, not
		-- silently clear a flag and leave a stale ruleset for whatever
		-- character reads it next.
		lifecycle:OnCharacterRemoved(player, oldCharacter)
		eq(lifecycle:IsTraining(player), false, "membership cleared on character removal")
		eq(fake.RulesetOf(player), "PvP", "original PvP ruleset restored, not hardcoded PvE")

		-- A respawned character is unrelated to the old training session.
		fake.Register(newCharacter, true)
		eq(lifecycle:IsTraining(player), false, "new character does not inherit training")
	end)

	test("stale removal of an OLD character cannot clear a session owned by a NEWER character", function()
		local fake = newFakeCombat()
		local lifecycle = TrainingLifecycle.new(fake.Adapter)
		local player, oldCharacter, newCharacter = "p1", "charA", "charB"
		fake.Register(oldCharacter, true)
		fake.Register(newCharacter, true)

		lifecycle:Enter(player, oldCharacter)
		-- Player re-enters (e.g. respawned and walked back in) under a new
		-- character while still "training" conceptually; the new character
		-- becomes the current generation.
		lifecycle:Enter(player, newCharacter)
		eq(lifecycle:IsTraining(player), true)

		-- A delayed/out-of-order removal callback for the OLD character
		-- arrives after the new one already owns the session.
		lifecycle:OnCharacterRemoved(player, oldCharacter)

		eq(lifecycle:IsTraining(player), true, "session for the new character must survive a stale old-character removal")
	end)

	test("disconnect drops the session without restoring ruleset for a departed player", function()
		local fake = newFakeCombat()
		local lifecycle = TrainingLifecycle.new(fake.Adapter)
		local player, character = "p1", "char1"
		fake.Register(character, true)

		lifecycle:Enter(player, character)
		local callsBeforeDisconnect = fake.SetRulesetCallsFor(player)
		eq(callsBeforeDisconnect, 1, "one SetRuleset call for entering Training")

		lifecycle:OnPlayerRemoving(player)

		eq(lifecycle:IsTraining(player), false, "membership dropped on disconnect")
		eq(
			fake.SetRulesetCallsFor(player),
			callsBeforeDisconnect,
			"no additional SetRuleset call on disconnect itself"
		)
	end)

	test("disconnect-then-character-removed order: no SetRuleset after departure", function()
		local fake = newFakeCombat()
		local lifecycle = TrainingLifecycle.new(fake.Adapter)
		local player, character = "p1", "char1"
		fake.Register(character, true)
		lifecycle:Enter(player, character)
		local logIndex = fake.LogLength()

		-- Disconnect fires first...
		lifecycle:OnPlayerRemoving(player)
		-- ...then a delayed CharacterRemoving callback for the same
		-- character arrives afterward. This must NOT call SetRuleset and
		-- recreate ruleset state for a player who is gone.
		lifecycle:OnCharacterRemoved(player, character)

		eq(
			#fake.SetRulesetLogAfter(logIndex),
			0,
			"no SetRuleset call may happen after PlayerRemoving, regardless of callback order"
		)
	end)

	test("character-removed-then-disconnect order: no SetRuleset after departure either", function()
		local fake = newFakeCombat()
		local lifecycle = TrainingLifecycle.new(fake.Adapter)
		local player, character = "p1", "char1"
		fake.Register(character, true)
		lifecycle:Enter(player, character)
		local logIndex = fake.LogLength()

		-- CharacterRemoving fires first (restores ruleset normally)...
		lifecycle:OnCharacterRemoved(player, character)
		eq(#fake.SetRulesetLogAfter(logIndex), 1, "normal character removal does restore once")

		-- ...then PlayerRemoving fires. Since the session was already
		-- exited, this must be a safe no-op with no further SetRuleset call.
		lifecycle:OnPlayerRemoving(player)

		eq(
			#fake.SetRulesetLogAfter(logIndex),
			1,
			"PlayerRemoving after an already-completed exit must not call SetRuleset again"
		)
	end)

	test("Enter after disconnect is rejected (no reviving a departed player's session)", function()
		local fake = newFakeCombat()
		local lifecycle = TrainingLifecycle.new(fake.Adapter)
		local player, character = "p1", "char1"
		fake.Register(character, true)

		lifecycle:OnPlayerRemoving(player)
		local ok, why = lifecycle:Enter(player, character)
		eq(ok, false)
		eq(why, "Departed")
	end)

	test("repeat enter/exit cycles leave no residual membership or generation state", function()
		local fake = newFakeCombat()
		local lifecycle = TrainingLifecycle.new(fake.Adapter)
		local player, character = "p1", "char1"
		fake.Register(character, true)

		for _ = 1, 4 do
			local enterOk = lifecycle:Enter(player, character)
			eq(enterOk, true)
			eq(lifecycle:IsTraining(player), true)
			local exitOk = lifecycle:Exit(player, character)
			eq(exitOk, true)
			eq(lifecycle:IsTraining(player), false)
		end
		eq(fake.RulesetOf(player), "PvE", "restored to the original ruleset after the final exit")

		-- A removal callback after the final exit must be a safe no-op.
		lifecycle:OnCharacterRemoved(player, character)
		eq(lifecycle:IsTraining(player), false)
	end)
end
