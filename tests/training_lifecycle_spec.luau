-- Service/integration-level tests for the training-ground lifecycle
-- orchestration (Task #23 corrective increment, Grok/Technical-Lead defects
-- 1-4). These exercise the actual production module
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
-- departure" - the exact defect being corrected. Identities (player/
-- character) are opaque `unknown` values, exactly as the production module
-- expects: most tests use plain strings, but the identity-regression tests
-- below use plain tables with a `.Name` field to prove membership is keyed
-- by object identity, never by a display Name/tostring.
--
-- Loaded by tests/run.luau, which passes in the shared test helpers.

local TrainingLifecycle = require("../src/ReplicatedStorage/Shared/Combat/TrainingLifecycle")

return function(test: (string, () -> ()) -> (), eq: (any, any, string?) -> ())
	local function newFakeCombat()
		local combatants: { [unknown]: { Alive: boolean } } = {}
		local rulesets: { [unknown]: string } = {}
		local resetOk: { [unknown]: boolean } = {}
		local setRulesetLog: { { Player: unknown, Ruleset: string } } = {}
		local presetCalls = 0
		local restoreCalls = 0
		local failPreset = false
		local failRestore = false
		local chosenPreset: string? = nil

		local adapter: TrainingLifecycle.CombatAdapter = {
			GetCombatant = function(model: unknown)
				return combatants[model]
			end,
			GetRuleset = function(player: unknown)
				return rulesets[player] or "PvE"
			end,
			SetRuleset = function(player: unknown, rulesetId: string)
				rulesets[player] = rulesetId
				table.insert(setRulesetLog, { Player = player, Ruleset = rulesetId })
			end,
			ResetVitals = function(model: unknown)
				if resetOk[model] == nil then
					return combatants[model] ~= nil and combatants[model].Alive
				end
				return resetOk[model]
			end,
			ApplyDefaultTrainingPreset = function(_player: unknown)
				presetCalls += 1
				if failPreset then
					return false, "PresetFailed"
				end
				chosenPreset = "Swordsman"
				return true, nil
			end,
			RestoreSavedLoadout = function(_player: unknown)
				restoreCalls += 1
				if failRestore then
					return false, "RestoreFailed"
				end
				chosenPreset = nil
				return true, nil
			end,
		}

		return {
			Adapter = adapter,
			Register = function(character: unknown, alive: boolean?)
				combatants[character] = { Alive = if alive == nil then true else alive }
			end,
			Kill = function(character: unknown)
				if combatants[character] then
					combatants[character].Alive = false
				end
			end,
			SetResetWillFail = function(character: unknown, willFail: boolean)
				resetOk[character] = not willFail
			end,
			RulesetOf = function(player: unknown)
				return rulesets[player]
			end,
			SetRulesetCallsFor = function(player: unknown): number
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
			PresetCalls = function()
				return presetCalls
			end,
			RestoreCalls = function()
				return restoreCalls
			end,
			Chosen = function()
				return chosenPreset
			end,
			SetChosen = function(presetId: string)
				chosenPreset = presetId
			end,
			FailPreset = function(fail: boolean)
				failPreset = fail
			end,
			FailRestore = function(fail: boolean)
				failRestore = fail
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
		eq(fake.PresetCalls(), 0, "a failed reset must not apply a training preset")
		eq(fake.RestoreCalls(), 0)
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

	-- Identity regressions (Technical Lead correction #2): membership must be
	-- keyed by object identity, never by a display Name / tostring. Fake
	-- "Player" objects here are plain tables with a mutable .Name field,
	-- mirroring how a real Roblox Player exposes Name without it being a
	-- stable or unique key.
	test("two distinct players sharing the same display Name have fully isolated sessions", function()
		local fake = newFakeCombat()
		local lifecycle = TrainingLifecycle.new(fake.Adapter)
		local playerA = { Name = "Rookie" }
		local playerB = { Name = "Rookie" } -- same display name, distinct identity
		local charA, charB = { Name = "Char" }, { Name = "Char" }
		fake.Register(charA, true)
		fake.Register(charB, true)

		local okA = lifecycle:Enter(playerA, charA)
		eq(okA, true, "player A enters")
		eq(lifecycle:IsTraining(playerB), false, "player B must not appear trained via shared Name")

		local okB = lifecycle:Enter(playerB, charB)
		eq(okB, true, "player B enters independently")
		eq(lifecycle:IsTraining(playerA), true, "player A membership untouched by B's entry")
		eq(lifecycle:IsTraining(playerB), true)

		-- Exiting one must not affect the other.
		lifecycle:Exit(playerA, charA)
		eq(lifecycle:IsTraining(playerA), false)
		eq(lifecycle:IsTraining(playerB), true, "B still training after A's independent exit")
	end)

	test("renaming a player mid-session does not lose or merge its session", function()
		local fake = newFakeCombat()
		local lifecycle = TrainingLifecycle.new(fake.Adapter)
		local player = { Name = "Before" }
		local character = { Name = "Char" }
		fake.Register(character, true)

		eq(lifecycle:Enter(player, character), true)
		eq(lifecycle:IsTraining(player), true)

		-- Rename, as a real Player's .Name can change mid-session.
		player.Name = "After"
		eq(lifecycle:IsTraining(player), true, "session survives a Name change (keyed by identity, not Name)")

		local ok = lifecycle:Exit(player, character)
		eq(ok, true, "exit still works after rename")
		eq(lifecycle:IsTraining(player), false)
	end)

	test("reconnect as a new player object is fully isolated from the old, departed one", function()
		local fake = newFakeCombat()
		local lifecycle = TrainingLifecycle.new(fake.Adapter)
		local firstSession = { Name = "Same" }
		local character1 = { Name = "Char" }
		fake.Register(character1, true)

		eq(lifecycle:Enter(firstSession, character1), true)
		lifecycle:OnPlayerRemoving(firstSession) -- disconnect

		-- A reconnect creates a brand-new Player instance even if the Name
		-- is identical; it must not inherit departed/generation state from
		-- the old object, and must be able to enter training fresh.
		local secondSession = { Name = "Same" }
		local character2 = { Name = "Char" }
		fake.Register(character2, true)

		eq(lifecycle:IsTraining(secondSession), false, "new object starts with no membership")
		local ok, why = lifecycle:Enter(secondSession, character2)
		eq(ok, true, "new object is not treated as departed")
		eq(why, nil)
		eq(lifecycle:IsTraining(secondSession), true)

		-- The old, departed object must still reject entry.
		local oldOk, oldWhy = lifecycle:Enter(firstSession, character1)
		eq(oldOk, false, "old departed object still rejected")
		eq(oldWhy, "Departed")
	end)

	-- Reset-failure regression (Technical Lead correction #4): Exit must
	-- report a distinct failure when the post-restore vitals reset fails,
	-- instead of unconditionally reporting success.
	test("Exit reports ResetFailed when vitals reset fails after a successful restore", function()
		local fake = newFakeCombat()
		local lifecycle = TrainingLifecycle.new(fake.Adapter)
		local player, character = "p1", "char1"
		fake.Register(character, true)

		eq(lifecycle:Enter(player, character), true)
		eq(fake.RulesetOf(player), "Training")

		-- Simulate the character becoming unavailable for a vitals reset
		-- (e.g. removed/unregistered) right at Exit time, after the
		-- ruleset/session restore logic has already completed.
		fake.SetResetWillFail(character, true)
		local logIndex = fake.LogLength()

		local ok, why = lifecycle:Exit(player, character)
		eq(ok, false, "Exit must not report success when the reset fails")
		eq(why, "ResetFailed")

		-- The ruleset restore itself must still have happened and must not
		-- be re-attempted or undone: session/ownership cleanup is already
		-- complete and safe, and is not rolled back by a reset failure.
		eq(lifecycle:IsTraining(player), false, "session cleanup still completed")
		eq(#fake.SetRulesetLogAfter(logIndex), 1, "ruleset was restored exactly once despite reset failure")
		eq(fake.RulesetOf(player), "PvE", "prior ruleset was restored")

		-- Idempotent: calling Exit again now is a safe NotTraining no-op,
		-- not a repeated ResetFailed.
		local ok2, why2 = lifecycle:Exit(player, character)
		eq(ok2, false)
		eq(why2, "NotTraining")
	end)

	test("first Enter applies the default preset only after training membership exists", function()
		local fake = newFakeCombat()
		local player, character = "p1", "char1"
		fake.Register(character, true)
		local lifecycle
		local sawTraining: boolean? = nil
		fake.Adapter.ApplyDefaultTrainingPreset = function(who: unknown)
			sawTraining = lifecycle:IsTraining(who)
			return true, nil
		end
		lifecycle = TrainingLifecycle.new(fake.Adapter)

		local ok = lifecycle:Enter(player, character)
		eq(ok, true)
		eq(sawTraining, true, "default preset runs only once the session is active")
		eq(fake.RulesetOf(player), "Training")
		eq(fake.RestoreCalls(), 0, "a successful enter does not restore the saved loadout")
	end)

	test("re-entry during the same session does not apply the default preset again", function()
		local fake = newFakeCombat()
		local lifecycle = TrainingLifecycle.new(fake.Adapter)
		local player, firstCharacter, secondCharacter = "p1", "charA", "charB"
		fake.Register(firstCharacter, true)
		fake.Register(secondCharacter, true)

		eq(lifecycle:Enter(player, firstCharacter), true)
		eq(fake.PresetCalls(), 1)
		eq(fake.Chosen(), "Swordsman")
		fake.SetChosen("Mage")

		eq(lifecycle:Enter(player, secondCharacter), true)
		eq(lifecycle:IsTraining(player), true)
		eq(fake.PresetCalls(), 1, "re-entry must not silently reapply Swordsman")
		eq(fake.Chosen(), "Mage")
		eq(fake.RestoreCalls(), 0)
	end)

	test("failed initial preset rolls back membership, ruleset, generation, and asks for the saved loadout", function()
		local fake = newFakeCombat()
		local lifecycle = TrainingLifecycle.new(fake.Adapter)
		local player, character = "p1", "char1"
		fake.Register(character, true)
		fake.FailPreset(true)

		local ok, why = lifecycle:Enter(player, character)
		eq(ok, false)
		eq(why, "PresetFailed")
		eq(lifecycle:IsTraining(player), false, "membership rolled back")
		eq(fake.RulesetOf(player), "PvE", "prior ruleset restored")
		eq(fake.PresetCalls(), 1)
		eq(fake.RestoreCalls(), 1, "saved loadout restored after the failed apply")

		lifecycle:OnCharacterRemoved(player, character)
		eq(lifecycle:IsTraining(player), false)
		eq(fake.RestoreCalls(), 1, "a stale removal after rollback does not restore again")
		eq(fake.RulesetOf(player), "PvE")
	end)

	test("manual Exit restores the saved loadout before leaving training", function()
		local fake = newFakeCombat()
		local player, character = "p1", "char1"
		fake.Register(character, true)
		local lifecycle
		local stillTraining: boolean? = nil
		lifecycle = TrainingLifecycle.new(fake.Adapter)
		fake.Adapter.RestoreSavedLoadout = function(who: unknown)
			stillTraining = lifecycle:IsTraining(who)
			return true, nil
		end

		eq(lifecycle:Enter(player, character), true)
		local ok = lifecycle:Exit(player, character)
		eq(ok, true)
		eq(stillTraining, true, "saved loadout is restored before the session is dropped")
		eq(lifecycle:IsTraining(player), false)
		eq(fake.RulesetOf(player), "PvE")
	end)

	test("manual Exit stays in training when the saved loadout cannot be restored", function()
		local fake = newFakeCombat()
		local lifecycle = TrainingLifecycle.new(fake.Adapter)
		local player, character = "p1", "char1"
		fake.Register(character, true)
		eq(lifecycle:Enter(player, character), true)
		fake.FailRestore(true)

		local ok, why = lifecycle:Exit(player, character)
		eq(ok, false)
		eq(why, "RestoreFailed")
		eq(lifecycle:IsTraining(player), true, "failed restore must not return the player to normal play")
		eq(fake.RulesetOf(player), "Training")
	end)

	test("death and respawn do not restore or persist a training preset from this module", function()
		local fake = newFakeCombat()
		local lifecycle = TrainingLifecycle.new(fake.Adapter)
		local player, oldCharacter, newCharacter = "p1", "charA", "charB"
		fake.Register(oldCharacter, true)
		eq(lifecycle:Enter(player, oldCharacter), true)
		eq(fake.PresetCalls(), 1)
		local restores = fake.RestoreCalls()

		lifecycle:OnCharacterRemoved(player, oldCharacter)
		eq(lifecycle:IsTraining(player), false)
		eq(fake.RestoreCalls(), restores, "character removal must not write or restore training gear")
		eq(fake.RulesetOf(player), "PvE")

		fake.Register(newCharacter, true)
		eq(lifecycle:Enter(player, newCharacter), true)
		eq(fake.PresetCalls(), 2, "a new session after respawn may apply the default preset again")
		eq(fake.RestoreCalls(), restores)
	end)

	test("disconnect does not restore a loadout or call SetRuleset", function()
		local fake = newFakeCombat()
		local lifecycle = TrainingLifecycle.new(fake.Adapter)
		local player, character = "p1", "char1"
		fake.Register(character, true)
		eq(lifecycle:Enter(player, character), true)
		local calls = fake.SetRulesetCallsFor(player)
		local restores = fake.RestoreCalls()

		lifecycle:OnPlayerRemoving(player)
		lifecycle:OnCharacterRemoved(player, character)

		eq(lifecycle:IsTraining(player), false)
		eq(fake.SetRulesetCallsFor(player), calls, "disconnect must not recreate ruleset state")
		eq(fake.RestoreCalls(), restores, "disconnect must not recreate loadout state")
	end)
end
