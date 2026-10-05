# Training Ground Smoke Test (Task #23, Increment A + correction pass)

## Development training rifle

Archer's main hand is `development_training_rifle` (`Development Training Rifle`).
It is data on the existing projectile path: `Family = Rifle`,
`Archetype = RangedPhysical`, two-handed `MainHand`, attack id `Primary`,
`Delivery = Projectile`, and the existing `Ammo` shape. Damage, projectile
speed, magazine capacity, and reload time in that definition are development
values. They are not approved release balance, and this is not the approved
Magadou rifle.

The unlock is milestone `development_training_rifle` only. Ordinary profiles
do not receive that milestone, so the public Equip path does not equip it.
The training preset still uses the existing gate bypass. Choosing Archer
does not add a fourth preset and does not write `PlayerData`.

Older sections below that say no rifle was added, or that Archer holds
`hunting_bow`, describe those earlier increments.

### Studio steps (NOT YET RUN)

Record the commit SHA, Play mode, and Output for each step. Until that
record exists, every step below is **未執行**.

1. Before entering training, read the saved `PlayerData.Loadout` and record
   it byte for byte.
2. Enter training from the entrance pad, then choose Archer on the existing
   preset selector. Expected: the live main hand becomes the development
   training rifle, the off hand is empty, and Archer highlights only after
   that server Loadout. Saved `PlayerData.Loadout` is unchanged.
3. Fire at the training dummy with the existing Attack control. Expected:
   the existing server-result damage presentation shows the hit. Do not
   treat a missing label as a new damage system.
4. Keep firing until the development magazine is empty, then wait through
   the development reload and fire again. Expected: shots stop while
   reloading and resume after that reload, using the existing ammo path.
   The magazine size and reload time are development values, not approved
   balance.
5. Switch to another preset, then walk onto `TrainingExitPad`. Expected:
   the live hands match the saved loadout from step 1, and that saved
   record was not overwritten with the development rifle.

Status: **NOT YET RUN IN STUDIO.** No Studio session was run for this pass.

## Temporary training health potion

In-memory `health_potion` stock for an active training session. The quantity
is `Config.Combat.DevelopmentTrainingStock` (currently 2). That table is a
development configuration: the Product Owner has not approved a release
quantity, limit, price, or final balance. It is not `StarterConsumables`
(currently 3) and it is never written to `PlayerData.Consumables`.

The first successful training preset in a session grants a fresh stock.
Choosing another preset does not refill it. Touching the entrance again
without a successful exit stays in that same session and does not refill.
A successful exit ends the session. The next successful entry is a new
session and can grant a fresh stock.
`UseItem` for `health_potion` while training calls the existing
`CombatCore.useConsumable` and decrements the temporary count only after
that call succeeds. Cooldown (`Cooldown`) and full health (`FullHealth`)
reject without spending a potion and without calling
`PlayerDataService:Update`. Any other item rejects with
`TrainingItemUnsupported`. An empty or missing training stock rejects with
`NoTrainingStock`. Neither rejection falls through to permanent stock.

A manual exit clears the temporary stock only after the saved loadout
restore succeeds. A failed restore leaves the player in training and keeps
the remaining stock. Death, a new character, and disconnect clear it.
Clearing more than once is safe. Outside training, `UseItem` still spends
`PlayerData.Consumables` exactly as before.

Older sections below that say training potions are not implemented describe
those earlier increments.

### Studio steps (NOT YET RUN)

Record the commit SHA, Play mode, and Output for each step. Until that
record exists, every step below is **未執行**.

The temporary stock count is private in-memory state. This pass exposes no
UI, attribute, or debug accessor for it. Do not try to read that count.
A successful use is a visible health increase from the existing potion
control (`CombatPotion`: key `One` or DPadUp), which sends `UseItem`
`health_potion`. A rejection is the existing client Output line
`[Combat] {Reason}` printed for `CombatEvent` `Kind = "Rejected"`.
The existing health potion cooldown is 8 seconds. Wait for it between
successful uses. An early press prints `[Combat] Cooldown` and is not a
successful use. At full health the same control prints `[Combat] FullHealth`
and is not a successful use. Take damage again whenever health is full so
the uses below can heal. Do not use the potion outside training: that path
spends persistent `PlayerData.Consumables` and would spoil the byte-for-byte
check.

1. Before entering training, read `PlayerData.Consumables` (via
   `PlayerDataService:Get` or the `GetState` remote) and record the
   `health_potion` count byte for byte, including a missing key.
2. Enter training from the entrance pad. Take damage from the training
   dummy so health is below maximum. Successfully use two temporary health
   potions, waiting out the cooldown between them and taking damage again
   if the first use filled health. Expected: health increases on each of
   the two uses, and Output does not show `[Combat] NoTrainingStock` for
   those uses. Saved `Consumables` stay unchanged.
3. With health still below maximum, use the potion a third time. Expected:
   client Output shows `[Combat] NoTrainingStock`. Saved `Consumables` stay
   unchanged. A `UseItem` for any other item id still rejects with
   `[Combat] TrainingItemUnsupported`.
4. While still in that same training session, switch preset, then use the
   potion again with health below maximum. Expected: Output still shows
   `[Combat] NoTrainingStock`. Changing preset does not refill the stock.
   Saved `Consumables` stay unchanged. Do not leave the area for this step.
5. Exit through the training exit and confirm the saved loadout returns.
   Do not use a potion after the exit. Enter again; that exit ended the
   previous session, so this entry is a new session. Take damage and
   successfully use two temporary health potions, respecting cooldown. A
   third use, with health below maximum, rejects with
   `[Combat] NoTrainingStock`. `PlayerData.Consumables` is still the
   byte-for-byte value from step 1.
6. Enter a new session, then die and respawn. Do not use a potion on the
   new character until the next training entry. Expected: saved
   `Consumables` still match step 1. Enter training again and confirm two
   successful uses, then `[Combat] NoTrainingStock` on the third. Repeat
   once by disconnecting (or stopping Play) mid-session and rejoining:
   saved `Consumables` still match step 1, and a new training entry again
   allows two successful uses before `[Combat] NoTrainingStock`.

Status: **NOT YET RUN IN STUDIO.** No Studio session was run for this pass.

## Training preset selector (visible, server-truth)

Placeholder buttons for the three temporary presets. The selector stays
hidden until the owning client receives a valid `CombatEvent`
`Kind = "Loadout"` with `Temporary = true`. A valid `Temporary = false`
event hides it again. A malformed or unrelated event does not change
whether it is showing or which option is highlighted.

The options are exactly `TrainingLoadouts.PRESET_IDS` (Swordsman, Mage,
Archer). Each one is a `TextButton` at least 48 px tall. Mouse and touch
use `Activated` and call `CombatController.selectTrainingPreset`. That
sends the existing `TrainingPreset` request and does not send item ids.
The click does not highlight the option. The highlight changes only after
a later validated Loadout event's hands match that preset.
`CombatController` is the only `CombatEvent` listener for this state; a
UI script that starts later reads the cached snapshot.

The panel is placed on the left, just below the top coin/level HUD.
Clearance from that HUD, the centered bottom stamina/mana bars, and the
bottom-right ContextActionService combat buttons is expected; Studio not
yet run. The panel `Frame.Active` is true so its padding and the gaps
between buttons are expected to sink GUI input; Studio not yet run.
`Active = true` does not prove ContextActionService will suppress
`MouseButton1`. This is not final art.

Pure tests cover visibility, all three presets, a nil event passed
explicitly, malformed events, a request that leaves the highlight
unchanged, a subscriber that arrives after the event, and a listener
error that does not skip the next listener. They do not create Instances
and do not prove touch layout or mouse sinking in Studio.

### Studio steps (NOT YET RUN)

Record the commit SHA, Play mode, and Output for each step. Until that
record exists, every step below is **未執行**.

1. Sync this branch and start Play Solo. Before entering training, confirm
   the preset selector is not visible. The top HUD and the Attack, Skill,
   Off, Block, and Potion controls are unchanged.
2. Walk onto `TrainingEntrancePad`. The selector appears with exactly
   Swordsman, Mage, and Archer. Swordsman is highlighted only after the
   server Loadout for the training sword and wooden shield. Saved
   `PlayerData.Loadout` is unchanged.
3. Click or tap Mage. The highlight stays on Swordsman until the ember
   staff Loadout arrives, then Mage is the only highlight. The request
   does not contain item ids.
4. Click or tap Archer. The highlight waits for the development training
   rifle Loadout.
5. Click or tap Swordsman again. The hands return to the training sword
   and wooden shield, and Swordsman is highlighted only after that Loadout.
6. Walk onto `TrainingExitPad`. The selector hides. Live hands match the
   saved loadout. A later coin or XP update does not show the selector.
7. Desktop mouse, button bodies: click Swordsman, Mage, and Archer on the
   button itself. Expected; Studio not yet run: each click sends only that
   preset request. It does not also send Attack, swing, or spend stamina.
   `Frame.Active` is not evidence that this already happened.
8. Desktop mouse, gaps and padding: click the space between the buttons
   and the panel padding around them. Expected; Studio not yet run: those
   clicks do not send Attack and do not change the highlighted preset.
9. Phone or touch emulator: each option is at least about 48 px and usable
   without a keyboard. Expected; Studio not yet run: the selector stays
   inside the mobile safe area, and it does not cover the top HUD, the
   bottom stamina/mana bars, the Attack, Skill, Off, Block, and Potion
   touch buttons, the movement joystick start region, or the open chat
   window. Tapping a preset does not also fire Attack.
10. Enter again, then reset the character or die. After respawn the
    selector is hidden and the new character wears the saved loadout.

Status: **NOT YET RUN IN STUDIO.** No Studio session was run for this
selector. Do not treat these steps as a playable pass.

## Training preset pass (temporary Swordsman / Mage / Archer hands)

Server-owned, in-memory loadouts for an active training session. The first
successful enter applies Swordsman (`training_sword` + `wooden_shield`).
While that same session stays active, another enter does not put Swordsman
back. The on-screen selector described above asks for Mage (`ember_staff`)
or Archer (`development_training_rifle`) through the existing `CombatRequest` action
`TrainingPreset`. Manual exit reads the saved `PlayerData`
hands back onto the live combatant and does not call `PlayerDataService:Update`.
Death, respawn, and disconnect do not persist the training hands; a new
character still uses the existing saved-loadout spawn path.

The owning client receives `CombatEvent` `Kind = "Loadout"` with a required
boolean `Temporary`. A training preset sets it true and latches the local
attack map. While that latch is on, `StateChanged` and a late `GetState`
must not put the saved loadout back. A saved-hand restore, and the
saved-loadout equip on a fresh character, set `Temporary` false, replace
the map, and clear the latch. A missing or non-boolean flag, a bad hand,
or an unknown weapon id changes neither the map nor the latch.

Pure tests cover preset ids, hand compatibility, malformed requests,
in-memory rollback, lifecycle ordering, and those attack-map orderings.
They do **not** create Instances and do **not** prove remotes, touch
controls, or character respawn in Studio.

This preset pass originally shipped Archer as `hunting_bow` because the
approved rifle was absent. The later development-rifle section replaces
only that main-hand id. It is not approved release balance.

### Studio steps (NOT YET RUN)

Record the commit SHA, Play mode, and Output for each step. Until that
record exists, every step below is **未執行**.

1. Note the player's saved `Loadout` before entering training (command bar
   or `PlayerDataService:Get`).
2. Walk onto `TrainingEntrancePad`. The live hands become the training
   sword and wooden shield, even if the saved loadout was something else.
   Saved `PlayerData.Loadout` is unchanged.
3. While still inside the same session, touch the entrance again. The
   hands stay on whatever preset is currently equipped. They do not snap
   back to Swordsman if a later step already changed them.
4. Click or tap Mage on the training preset selector. That sends
   `CombatRequest` `{ Action = "TrainingPreset", PresetId = "Mage" }` and
   does not send item ids. The highlight stays on the previous preset until
   the server Loadout arrives. Hands then become the ember staff only.
5. Click or tap Archer. Hands become the development training rifle only,
   and Archer highlights only after that server Loadout.
6. Send `{ Action = "TrainingPreset", PresetId = "Rifle" }` and
   `{ Action = "Equip", Slot = "MainHand", ItemId = "iron_greatsword" }`.
   Both are rejected. Saved `Loadout` and `Consumables` stay unchanged.
7. Walk onto `TrainingExitPad`. The live hands match the saved loadout from
   step 1, and the saved record itself was not overwritten with the bow.
8. Enter again, switch to Mage, then die. After respawn, the new character
   is wearing the saved loadout, not the ember staff, and is not left in
   the Training ruleset.
9. Enter again and disconnect without using the exit pad. Rejoin. The new
   session is not wearing the training preset, and Output has no error from
   recreating that player.
10. Phone / touch layout: outside training the selector is hidden. During
    training the three options are touch buttons at least 48 px tall.
    Expected; Studio not yet run: they stay inside the mobile safe area,
    and they do not cover the top HUD, the bottom stamina/mana bars, the
    Attack, Skill, Off, Block, and Potion touch buttons, the movement
    joystick, or the chat window. Those five actions are unchanged, and a
    tap on a button body, a gap, or the panel padding does not also send
    Attack.
11. Rifle: the Archer preset selects only `development_training_rifle`.
    That is the development training weapon, not the approved Magadou
    rifle, and an ordinary Equip of it stays locked.
12. After step 4, while the ember staff is still the live training weapon,
    let the initial `GetState` return late or cause a `StateChanged` that
    only changes coins or XP. Attack and Skill must still use the staff.
    They must not send the saved weapon's attack id. Saved
    `PlayerData.Loadout` stays the pre-training loadout.
13. Walk onto `TrainingExitPad`. The normal `Loadout` event
    (`Temporary = false`) restores the saved hands. A later `StateChanged`
    may repeat that saved loadout. Attack then uses the saved weapon.
14. Enter again, switch to Archer, then reset the character. The new
    character wears the saved loadout, and Attack uses that saved weapon
    rather than the development training rifle.

Status: **NOT YET RUN IN STUDIO.** No Studio session was run for this pass.
Steps 12–14 are also **未執行**. The pure ordering tests do not prove
remote delivery or respawn.

## Damage float pass (server Hit presentation only)

Shows the damage number the server already broadcasts on `CombatEvent`
`Kind = "Hit"`. The client reads `Damage`, and when those fields are
present and finite, `Blocked` and `Absorbed`. It does not recompute the
hit, and it does not add a damage remote. A short `BillboardGui` is
parented to the target's `Head`, `HumanoidRootPart`, or `PrimaryPart`.

Pure tests in `tests/damage_float_spec.luau` cover label text, rejection of
malformed numbers, and the simultaneous-label cap. They do **not** create
Instances and do **not** prove `BillboardGui`, `TweenService` (unused),
Adornee lookup, or cleanup when a character respawns or a model is
destroyed. This pass does not use `TweenService`.

Older sections below that say damage numbers are not implemented describe
the passes that wrote them. This section is the current presentation slice.
It is not a playable-training claim.

### Studio steps (NOT YET RUN)

Record the commit SHA, Play mode, and Output for each step. Until that
record exists, every step below is **未執行**.

1. Sync this branch and start Play Solo. Walk to the Studio training dummy
   at `TrainingDummyMarker`.
2. Use the existing melee attack (left click / Attack). A short floating
   label above the dummy must show the server `Damage` from that `Hit`.
   The number is the server value, not a client-side estimate.
3. **Close range:** stand against the dummy and attack again. The label
   stays readable above the head or root and does not throw.
4. **Consecutive attacks:** land several hits quickly. Labels expire on
   their own, and they do not accumulate without a bound. After they
   expire, no `ServerDamageFloat` remains.
5. **Target death or destroy:** kill the dummy, or delete the target model
   in Explorer while a label is visible. Output stays quiet, and the label
   is gone with the target.
6. **Respawn:** reset the player character while a label is visible on the
   dummy. The new character has no leftover damage label or connection
   error. If a hit lands on the player, resetting also clears that label.
7. **Phone readability:** use a phone viewport or device emulator. The
   damage text is still large enough to read at melee range.

Status: **NOT YET RUN IN STUDIO.** No Studio session was run for this pass.

## Fourth pass (this assignment: fix-training-scene-reachability-ensure-dummy)

Bounded correctness pass on top of the third pass below, per Technical
Lead's reconciliation of Grok comment 5932757764. Scope is exactly the four
items in the assignment; lifecycle/combat core/other #23 features are
unchanged.

1. **Walkable fresh-place entry and world return (geometry rewrite).**
   `TrainingSceneConfig.luau` no longer places the scene on a platform
   floating at `Y=10` with no connection to ground level. Every walkable
   point (`Entrance`, `Exit`, `ReturnSpawn`, `DummyMarker`, the new
   `WalkwayCenter`, and `Origin` itself) now resolves at one shared
   `GroundLevelY = 0`, matching a fresh Baseplate/default-spawn standing
   surface. A new `Walkway` strip spans from near world origin (its near
   edge resolves to X=0) to several studs *inside* the platform footprint
   (`boxesOverlap` asserted true in tests), so there is a continuous walkable
   surface with no jump/gap. `TrainingReturnSpawnPad` now resolves onto that
   world-side walkway (X=12 in the default config), clear of both the
   platform footprint and a representative default-spawn footprint, instead
   of floating in training-local air. A new pure `restingCenterY(standY,
   fullHeightY)` helper centralizes the half-height math (part center =
   desired top-surface Y minus half the part's own height) so every part in
   `TrainingSceneBootstrap.luau` models its own thickness correctly instead
   of ad-hoc per-callsite arithmetic. Exact CollectionService tags
   (`TrainingEntrance`, `TrainingExit`, `TrainingReturnSpawn`) are unchanged;
   only the geometry moved.
2. **Owned ensure/repair, not name-only early return.**
   `TrainingSceneBootstrap.luau` no longer returns early on a bare
   `Workspace:FindFirstChild(ContainerName)` name check. It now finds-or-
   creates the container by Name AND a `TrainingScene = true` attribute; a
   same-named object without that attribute is treated as an unknown
   user-owned object, left completely untouched, and a `warn()` is printed
   instead of adopting/overwriting it. Each of the six required children
   (`TrainingWalkway`, `TrainingPlatform`, `TrainingEntrancePad`,
   `TrainingExitPad`, `TrainingReturnSpawnPad`, `TrainingDummyMarker`) is now
   ensured individually by deterministic Name: created if missing; repaired
   in place (anchored/collision/size/position/color/attributes/tag) if
   present and marked `TrainingSceneOwned = true` by this service; left
   untouched with a warning if present but not owned. `CollectionService:
   AddTag` is itself idempotent, so repeated `:Start()` calls never create
   duplicate tags, parts, or connections.
3. **Scene dummy reuse.** `TrainingDummyService.luau` now also spawns one
   additional dummy at `TrainingSceneConfig.resolve().DummyMarker` (+3 studs
   Y, matching the stand-height convention of the other `DUMMIES` entries),
   through the exact same existing `spawnDummy` / `CombatNPC` tag /
   death-respawn tracking used by every other dummy, still gated by
   `RunService:IsStudio()`. No second dummy/combat system was added, and
   live-server dummy spawning remains disabled. The `TrainingDummyMarker`
   part created by the bootstrap service remains a debug anchor only; it is
   not tagged as attackable and this document does not claim it is.
4. **Tests.** `tests/training_scene_config_spec.luau` was rewritten with
   assertions that fail against the prior floating-platform layout:
   shared-ground-level check (`Origin.Y`/every point's `Y` must equal
   `GroundLevelY`), walkway/platform overlap (`boxesOverlap`), walkway
   near-edge reachability (`<= 20` studs from world origin), return-spawn
   clear of both the platform and a default-spawn footprint, and the new
   `restingCenterY` half-height formula. `TrainingSceneConfig.luau` remains
   fully Roblox-API-free (no `script`, `Instance`, `Vector3`, or other
   datatype) so it still loads under the standalone Luau test runner.
   `TrainingSceneBootstrap.luau`'s ensure/repair logic itself uses `Instance`/
   `Vector3`/`Color3` (it creates real Workspace parts) and is therefore not
   separable into the pure runner; it is covered by the fresh-place and
   repeated-boot Studio steps below instead, same as the rest of this
   service's Roblox-only logic in prior passes.

### Tests actually run this pass

Command: `luau tests/run.luau` (see "Tests actually run" note below this
line for environment availability) — **not run**: no shell/Luau CLI/Rojo
tool was available in this session (consistent with every prior pass in
this file). The new and revised assertions above were checked by hand
against the module's own arithmetic (shown in the PR/commit description),
not by executing the runner. This is explicitly reported as unrun, not
claimed as passing.

### Fresh-place Studio steps (NOT YET RUN — see Status below, supersedes third-pass steps)

1. Create a brand-new Baseplate (or any place with a default `SpawnLocation`
   near world origin) in Studio. Do not hand-place any training parts.
2. Sync/publish this branch's `src/` into the place (Rojo) and start a Play
   Solo session on the recorded commit SHA.
3. In Output, confirm `[Server] booted N module(s)` with no errors, and
   confirm the line
   `[Combat] Training scene bootstrap ensured "TrainingGroundScene" placeholder geometry`
   appears exactly once, and (Studio only) `[Combat] Studio training dummies spawned`.
4. In Explorer, confirm `Workspace.TrainingGroundScene` contains
   `TrainingWalkway`, `TrainingPlatform`, `TrainingEntrancePad`,
   `TrainingExitPad`, `TrainingReturnSpawnPad`, `TrainingDummyMarker`, each
   with `TrainingSceneOwned = true`, and that the three pad parts carry
   their respective `TrainingEntrance` / `TrainingExit` /
   `TrainingReturnSpawn` CollectionService tags.
5. **Walkability check (this pass's core fix):** starting from the default
   `SpawnLocation`, walk in a straight line toward `TrainingWalkway` /
   `TrainingPlatform` with NO jump input. Confirm the character never falls
   through a gap, never needs to jump a ledge, and smoothly transitions from
   baseplate ground onto the walkway and onto the platform at the same
   height.
6. Confirm `TrainingReturnSpawnPad` sits on the world-side walkway, visibly
   separate from the default `SpawnLocation` (not overlapping it) and not on
   the training platform itself.
7. Stop and restart Play Solo (same place, same session) and repeat steps
   3-4: confirm the boot line still prints exactly once per boot and no
   duplicate `TrainingGroundScene` Folder, children, or tags are created
   (child count under the Folder stays exactly 6).
8. **Collision-safety check (new):** before starting Play Solo, manually
   create a plain unrelated `Part` named `TrainingGroundScene` directly in
   Workspace (simulating an unrelated user object). Start Play Solo and
   confirm Output shows the `warn()` from `findOrCreateOwnedContainer`
   (".. not an owned TrainingScene container .. leaving it untouched ..")
   and that the manually-created Part is NOT deleted, renamed, or
   re-parented, and no training children are created under it.
9. Walk onto `TrainingEntrancePad`: confirm `TrainingGroundService:Enter`
   behavior from prior passes (vitals reset, ruleset switched to
   `Training`) still fires against the real tagged part.
10. Walk onto `TrainingExitPad`: confirm `Exit` behavior (prior ruleset
    restored, vitals reset) and the character is moved to
    `TrainingReturnSpawnPad`'s position.
11. (Studio only) Confirm a `TrainingDummy_L1` model stands at the
    `TrainingDummyMarker` position (not just the marker part itself) and can
    be attacked with the existing combat core like any other training
    dummy.
12. Record Pass/Fail and Output for each step above with the commit SHA.

Status: **NOT YET RUN IN STUDIO.** No shell/Studio/Rojo tool was available
in this session. This section is the reproducible operation sheet required
by the task; it is not evidence of a passed test.

### Remaining #23 work not covered by this increment

Unchanged from the third pass below: visible server damage display/HUD
wiring beyond the existing `Hit` broadcast, the timed attack-practice
source for blocking/shield practice, temporary training potions, Sword/Mage/
Archer preset loadouts, the Magadou rifle weapon/ammo/reload behavior, and
the full Studio playable acceptance pass. This pass adds one working scene
   dummy at the marker point but does not add new damage-display UI.
   The later damage-float pass at the top of this file adds that
   presentation. Its Studio steps are still unrun.

## Third pass (training-scene-bootstrap, now superseded in part by the fourth pass above)

Adds the missing world-hookup layer that every prior pass explicitly listed
as a dependency: a server-authored placeholder scene so the training ground
is enterable in a FRESH Studio place with no manual level-authoring.

- New `src/ReplicatedStorage/Shared/Combat/TrainingSceneConfig.luau`: pure,
  Roblox-API-free, explicitly-marked DEV/PLACEHOLDER placement constants
  (origin, platform size, entrance/exit/return-spawn/dummy-marker offsets)
  plus a pure `resolve()` helper. Unit tested in
  `tests/training_scene_config_spec.luau` for non-overlap with a
  representative default-spawn footprint and for the three tagged points
  being distinct and within/outside the platform footprint as intended.
- New `src/ServerScriptService/Services/TrainingSceneBootstrap.luau`
  (`Priority = 15`, runs after `TrainingDummyService` (10) and before
  `TrainingGroundService` (20)): idempotently creates ONE Workspace Folder
  (`TrainingGroundScene`) containing a placeholder platform Part and three
  tagged marker Parts (`TrainingEntrance`, `TrainingExit`,
  `TrainingReturnSpawn` — the exact tags `TrainingGroundService.luau` already
  listens for; no change to that file's tag-handling logic). If the Folder
  already exists (any later server boot in the same Workspace), `:Start()`
  does nothing further: no duplicate parts, tags, or connections.
- Dummy reuse (assignment item 3, inspected before writing any code):
  `TrainingDummyService.luau`'s `:Start()` only spawns its Studio-only
  dummies from its own hardcoded `DUMMIES` position table, gated by
  `RunService:IsStudio()`, with **no public method** to add or relocate a
  dummy at an arbitrary world position. It cannot be safely pointed at this
  new scene without editing that table directly (content work, not
  bootstrap-layer work, and risky to do blindly in this increment). This
  increment therefore only reserves and tags an informational
  `TrainingDummyMarker` part (`Purpose = "ReservedForStationaryDummy"
  attribute, NOT one of the three CollectionService tags
  `TrainingGroundService` listens for) at the configured `DummyMarkerOffset`.
  **Superseded by the fourth pass — this is not a current API gap.** The
  third pass said `TrainingDummyService` needed a public `SpawnAt(position,
  spec)` entry point, or a scene-provided position in `DUMMIES`, before a
  stationary dummy could be bootstrapped onto the marker. The fourth pass
  already spawns that dummy through the existing `spawnDummy` path at
  `DummyMarker`. Do not treat this paragraph as an open Missing API.
- No art/materials/mesh pass: parts are plain anchored `Part`s with flat
  `Color3` values only, per the assignment's "no art polish or external
  assets" instruction.
- No economy, balance, runner, workflow, or permission changes.

### Fresh-place Studio steps (NOT YET RUN — see Status below)

1. Create a brand-new Baseplate (or any place with a default `SpawnLocation`
   near world origin) in Studio. Do not hand-place any training parts.
2. Sync/publish this branch's `src/` into the place (Rojo) and start a Play
   Solo session on the recorded commit SHA.
3. In Output, confirm `[Server] booted N module(s)` with no errors, and
   confirm the line
   `[Combat] Training scene bootstrap created "TrainingGroundScene" placeholder geometry`
   appears exactly once.
4. In the Explorer, confirm `Workspace.TrainingGroundScene` exists containing
   `TrainingPlatform`, `TrainingEntrancePad`, `TrainingExitPad`,
   `TrainingReturnSpawnPad`, `TrainingDummyMarker`, and that the three pad
   parts carry their respective `TrainingEntrance` / `TrainingExit` /
   `TrainingReturnSpawn` CollectionService tags (Explorer "Tags" view or
   `CollectionService:GetTagged(...)` from the command bar).
5. Confirm the scene does not overlap/intersect the default spawn (walk from
   the default spawn to the green `TrainingEntrancePad` — it should be a
   clear, unobstructed walk, not an immediate overlap).
6. Stop and restart Play Solo (same place, same session) and repeat step 3–4:
   confirm the boot line still prints exactly once per boot and no duplicate
   `TrainingGroundScene` Folder, pads, or tags are created.
7. Walk onto `TrainingEntrancePad`: confirm this triggers
   `TrainingGroundService:Enter` behavior from the prior passes (vitals
   reset, ruleset switched to `Training`) — this exercises the EXISTING
   lifecycle code against REAL tagged parts for the first time; prior passes
   could only be exercised with manually-placed parts or in isolation.
8. Walk onto `TrainingExitPad`: confirm `Exit` behavior (prior ruleset
   restored, vitals reset) and that the character is moved to
   `TrainingReturnSpawnPad`'s position (see `TrainingGroundService:Exit`'s
   existing `findTaggedSpawn` lookup).
9. Record Pass/Fail and Output for each step above with the commit SHA.

Status: **NOT YET RUN IN STUDIO.** No shell/Studio/Rojo tool was available in
this session. This section is the reproducible operation sheet required by
the task; it is not evidence of a passed test.

### Remaining #23 work not covered by this increment

Per the assignment's explicit scope list, the following remain open and are
NOT claimed as complete by this change:
- Visible server damage display against a dummy. The third-pass Missing API
  note above was superseded by the fourth pass, which spawns the scene dummy
  through the existing `spawnDummy` path. The damage-float pass at the top
  of this file reads the existing `CombatService` `Hit` broadcast. Studio
  confirmation of that label is still unrun.
- A timed attack-practice source for blocking/shield practice.
- Temporary training potions (non-persistent consumable stock).
- Sword / Mage / Archer preset loadouts.
- Magadou rifle weapon and ammo/reload behavior (no rifle `Weapons.luau`
  entry exists yet).
- UI/polish, and the full Studio playable acceptance pass across all of the
  above.

## Second correction pass (lifecycle-portability-identity-cleanup)

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

- As of the fourth pass (this assignment), placeholder
  `TrainingEntrance`/`TrainingExit`/`TrainingReturnSpawn` parts are created
  automatically, walkable by ordinary walking from a default spawn with no
  jump/gap, and ensure/repair instead of name-only skip on repeated boots —
  but no art/level-design pass has happened (plain gray/colored blocks
  only), and the geometry is still an explicitly-marked dev/placeholder
  configuration, not an approved layout.
- One Studio-only dummy now stands at the reserved `TrainingDummyMarker`
  point via `TrainingDummyService`'s existing spawn path; this is still only
  a Studio test aid (`RunService:IsStudio()` gated), not a live-server
  player-facing dummy.
- No client-facing UI/prompt indicates "you are now training"; this
  increment is server-state only, as scoped.
- Full #23 acceptance items (dummy damage DISPLAY/HUD beyond the existing
  `Hit` broadcast, timed attacker for block/shield practice, training
  potions, 3 class presets, rifle/shield practice) are not implemented and
  must not be reported as complete.
- This document was written without Studio/Luau-runner access; all steps
  (including the fresh-place and collision-safety steps above) are
  unexecuted and must be run and filled in before this task can be
  considered to have passing Studio evidence. The new/revised pure tests in
  `tests/training_scene_config_spec.luau` were checked by hand against the
  module's arithmetic but were not executed by any Luau CLI in this
  session.
