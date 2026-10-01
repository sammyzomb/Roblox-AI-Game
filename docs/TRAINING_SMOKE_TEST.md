# Training Ground Smoke Test (Task #23, Increment A + correction pass)

## Second correction pass (this assignment: lifecycle-portability-identity-cleanup)

Bounded correctness-only follow-up to the correction pass below, per
Technical Lead source review (#31) and Grok independent review (#23):
- `TrainingLifecycle.luau` now loads in both Roblox (`require(script.Parent...)`)
  and the standalone Luau test runner (`require("./TrainingSession")`),
  branching on whether the `script` global is present, instead of erroring
  before tests can even run plain Luau has no `script`.
- Player/character identity is no longer converted with `tostring` (which is
  `Player.Name` in Roblox, collision-prone and mutable). `TrainingLifecycle`
  and `TrainingSession` now key every table directly by the opaque
  player/character value (object identity), matching how `CombatService`
  itself keys `byPlayer`/`playerRuleset`. New regressions cover two distinct
  fake players sharing a display Name, a mid-session rename, and
  reconnect-as-a-new-object isolation.
- Disconnect tombstones (`_departed`) are now a weak-keyed table
  (`__mode = "k"`) instead of a strong table that retained every departed
  Player object for the life of the server.
- `TrainingLifecycle:Exit` now returns `(false, "ResetFailed")` if the vitals
  reset fails after the ruleset/session restore already completed, instead
  of unconditionally reporting success; the already-completed restore is not
  rolled back (idempotent: a later `Exit` call reports `NotTraining`).
- `TrainingGroundService`'s `hookPlayer` comment no longer claims a
  `CharacterAdded` hookup that does not exist; it documents the actual
  `CharacterRemoving`-only wiring and notes entry is driven by the entrance
  zone touch handler instead.
- No scene, dummy, preset, economy, balance, runner, workflow, or permission
  changes are included in this pass.

## First correction pass

Fixed actual lifecycle/isolation defects found in the prior increment:
- `TrainingGroundService` no longer hardcodes `PvE` on exit/death/disconnect;
  it now captures the player's actual ruleset at Enter time (via the new
  `CombatService:GetRuleset`) in a shared pure `TrainingSession` module
  (`src/ReplicatedStorage/Shared/Combat/TrainingSession.luau`) and restores
  that exact value.
- `CombatService.onCharacterAdded` no longer blindly reuses
  `playerRuleset[player]`: if it is somehow still `"Training"` when a new
  character spawns (race with death cleanup), it falls back to the
  configured default instead of silently keeping the new character in
  training rules.
- `TrainingGroundService:Enter` now requires a registered, living combatant
  (`CombatService:GetCombatant`) and a successful `ResetVitals` call BEFORE
  claiming training membership; it no longer flags a player as training on a
  bare `player.Character ~= nil` check.
- Death now goes through the same prior-ruleset restoration as a manual
  Exit (`forceExit`), not just a flag clear, closing the "Training survives
  respawn" defect.
- `CombatService:onUseItem` / `onEquip` now reject with a clear reason
  (`TrainingNoPersistentUse` / `TrainingNoPersistentEquip`) whenever
  `CombatService:SetTrainingPredicate`'s predicate (wired to
  `TrainingGroundService:IsTraining`) returns true, so persistent
  stock/loadout cannot be mutated by a raw remote call during training even
  though no training UI currently sends those requests.
- `tests/training_ground_spec.luau` now requires and exercises the actual
  production module (`TrainingSession.luau`) instead of a re-implemented
  copy of the state machine.

Status: **NOT YET RUN IN STUDIO.** No shell/Studio/Rojo tool was available in
this session. This document is the reproducible operation sheet required by
the task; it is not evidence of a passed test. Mark each step Pass/Fail with
the commit SHA and Output panel contents when it is actually run.

## Scope of this increment

Implements ONLY:
- Player entry/exit into a training zone (server-authoritative, via
  CollectionService-tagged parts).
- Temporary session state: an in-memory "is this player training" flag that
  is never written to `PlayerDataService` / DataStore.
- HP/MP/Stamina reset on entry and on exit (`CombatService:ResetVitals`).
- Cleanup on death inside the zone, on manual exit, and on disconnect, so no
  training state or ruleset ever leaks into normal play.

Explicitly OUT of scope for this increment (still open from #23):
- Attackable dummies with visible server-computed damage numbers (dummies
  exist today only via the Studio-only `TrainingDummyService`, unchanged).
- The timed attack-practice source for blocking/shields.
- Training potions (temporary consumable inventory).
- Sword/Mage/Archer preset loadouts.
- Rifle weapon / shield practice (depends on base combat data still being
  extended per #23's own dependency note).

## Files touched (second correction pass: lifecycle-portability-identity-cleanup)

- `src/ReplicatedStorage/Shared/Combat/TrainingLifecycle.luau` (dual-env
  require, object-identity keys, weak-keyed `_departed`, `Exit` ResetFailed
  reporting)
- `src/ReplicatedStorage/Shared/Combat/TrainingSession.luau` (keys typed/used
  as opaque `Id = unknown` instead of `string`)
- `src/ServerScriptService/Services/TrainingGroundService.luau`
  (CharacterRemoving-only doc correction)
- `tests/training_lifecycle_spec.luau` (fake-adapter tables now `unknown`-
  keyed; added identity-collision/rename/reconnect and ResetFailed
  regressions)
- `docs/TRAINING_SMOKE_TEST.md` (this section)

## Files touched (first correction pass)

- `src/ReplicatedStorage/Shared/Combat/TrainingSession.luau` (new: pure
  session state machine, extracted so the service and tests share one
  implementation)
- `src/ServerScriptService/Services/TrainingGroundService.luau` (rewritten:
  prior-ruleset capture/restore, Enter preconditions, CharacterRemoving /
  disconnect cleanup via the shared session module)
- `src/ServerScriptService/Services/CombatService.luau` (added
  `GetRuleset`, `SetTrainingPredicate`; `onCharacterAdded` no longer trusts a
  stale `Training` ruleset; `onUseItem`/`onEquip` reject during training)
- `tests/training_ground_spec.luau` (rewritten to test the real
  `TrainingSession` module)
- `docs/TRAINING_SMOKE_TEST.md` (this file)

Unchanged from the prior increment: `Rulesets.luau` (`Training` ruleset
already existed), `tests/run.luau` wiring.

## Required world setup (not included — a map/Studio dependency)

This service is data-driven and does nothing until a map provides:
1. A `BasePart` tagged `TrainingEntrance` (CollectionService tag) covering the
   training zone's entry point.
2. A `BasePart` tagged `TrainingExit` covering the exit point.
3. Optionally, a `BasePart` tagged `TrainingReturnSpawn` marking where a
   player should reappear in the normal world after exiting. If absent, the
   player's position is left as-is (only ruleset/vitals are reset).

Until these parts exist in the place file, `TrainingGroundService` loads and
idles safely (no errors), but the zone is not enterable. **This is a listed
dependency/gap, not a hidden failure.**

## Pre-conditions

- Base: `claude-dev` at the spec-commit for this assignment.
- PR #4 (combat core) Studio gate: still not passed as of this writing: do
  not treat this smoke test as unblocking that gate.
- Run in a Studio session with at least 2 test accounts (or 1 account run
  twice) to check disconnect cleanup realistically requires a real leave
  event; a single local Studio session can approximate it by using
  `game:BindToClose` behavior or simply removing the character/leaving Play
  mode while training.

## Steps

1. **Baseline load**
   - Start a Play/Studio test session on the commit SHA recorded below.
   - Confirm Output shows `[Server] booted N module(s)` and no errors
     mentioning `TrainingGroundService`, `CombatService`, or `Rulesets`.

2. **Entry**
   - Walk the test character onto the `TrainingEntrance` part.
   - Expected: no errors; combatant's HP/MP/Stamina are at max immediately
     (check HUD attributes / `Model:GetAttribute("Health")`-style pools if
     HUD is wired, otherwise confirm via `CombatService:GetCombatant`).
   - Record: Pass/Fail, Output errors if any.

3. **Combat while training (existing core, PvE-style targeting)**
   - Attack a training dummy (Studio-only `TrainingDummyService` target) with
     melee. Confirm the hit resolves normally (server-authoritative combat
     unchanged).
   - Record: Pass/Fail.

4. **Resource draining and reset**
   - Spend Stamina/Mana (attack, block, cast) so pools are below max.
   - Trigger exit (`TrainingExit` part) then re-enter (`TrainingEntrance`).
   - Expected: HP/MP/Stamina are full again immediately after crossing either
     tagged part.
   - Record: Pass/Fail.

5. **Repeated in/out**
   - Cross entrance -> exit -> entrance -> exit rapidly (within debounce
     window, ~1s apart) several times.
   - Expected: no duplicate session errors, no ruleset stuck on `Training`
     after the final exit. Confirm via `TrainingGroundService:IsTraining`
     returning `false` after the last exit (add a temporary print if no
     inspector is available).
   - Record: Pass/Fail.

6. **Death inside the training zone, entered from a non-default ruleset**
   - Manually set the test player to a non-default ruleset (e.g. call
     `CombatService:SetRuleset(player, "PvP")` from command bar) then enter
     training.
   - While training, take lethal damage.
   - Expected: after respawn, `CombatService:GetRuleset(player)` reports the
     ORIGINAL ruleset (`PvP`), not `PvE` and not `Training`; confirm via
     command bar or a temporary print. No error in Output.
   - Record: Pass/Fail.

6b. **Repeat check with default ruleset**
   - Same as step 6 but entering training from the default ruleset.
   - Expected: after respawn, ruleset is back to the default; no stuck
     `Training` state.
   - Record: Pass/Fail.

7. **Disconnect mid-session**
   - While training, leave the game (or stop Play mode) without exiting via
     the `TrainingExit` part first.
   - Expected: no error in Output on `PlayerRemoving`; no residual state (this
     is best verified by code inspection here since a fresh join after
     reconnect should start untrained — confirm on rejoin that the new
     character is not silently in `Training` ruleset).
   - Record: Pass/Fail.

8. **Persistent-data isolation (critical acceptance check)**
   - Before entering training, note the player's saved `Loadout` and
     `Consumables` (via `PlayerDataService:Get` / `GetState` remote).
   - Enter training, fight, exit (or disconnect and rejoin).
   - Expected: `Loadout` and `Consumables` are byte-for-byte unchanged from
     before entry (no potions consumed from real inventory since none are
     implemented yet in this increment; no equipment change).
   - Record: Pass/Fail.

9. **Server-boundary rejection during training (new)**
   - While training, send a raw `UseItem` and `Equip` `CombatRequest` (e.g.
     via a temporary client-side debug call, bypassing any UI) for an item
     the player actually owns.
   - Expected: `CombatEvent` `Rejected` with reason
     `TrainingNoPersistentUse` / `TrainingNoPersistentEquip`; saved
     `Consumables`/`Loadout` unchanged afterward.
   - Record: Pass/Fail.

Status: Studio-only steps 1-9 remain UNRUN (no Studio/Rojo access in this
session). Steps 6/6b/9 are new in this correction pass and have no prior
execution history either.

## Result template

```
Commit SHA:
Test mode: Studio Play / Studio Team Test / Live server
Step 1: Pass/Fail — Output:
Step 2: Pass/Fail — Output:
Step 3: Pass/Fail — Output:
Step 4: Pass/Fail — Output:
Step 5: Pass/Fail — Output:
Step 6: Pass/Fail — Output:
Step 7: Pass/Fail — Output:
Step 8: Pass/Fail — Output:
Overall: PASS / FAIL / BLOCKED — reason:
```

## Known gaps / dependencies at delivery time

- No map parts (`TrainingEntrance`/`TrainingExit`/`TrainingReturnSpawn`) are
  included in this change; a level designer or follow-up commit must place
  them for the zone to be enterable in Studio.
- No client-facing UI/prompt indicates "you are now training"; this
  increment is server-state only, as scoped.
- Full #23 acceptance items (dummies with damage display, timed attacker,
  training potions, 3 class presets, rifle/shield practice) are not
  implemented and must not be reported as complete.
- This document was written without Studio access; all steps are unexecuted
  and must be run and filled in before this task can be considered to have
  passing Studio evidence.
