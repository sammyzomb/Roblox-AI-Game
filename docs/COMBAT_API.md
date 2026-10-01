# Combat & Progression Core — Public API

Owner: Claude (Primary Programmer) · Branch: `claude-dev` · Issue: #6
PR: `feat: hybrid combat and progression core`

One combat foundation for PvE and PvP. Weapon-agnostic, data-driven, server-authoritative.

## 1. Layers

```
ReplicatedStorage/Shared/
  ProgressionGates.luau        Level / milestone unlock checks (pure)
  PlayerDataModel.luau         v2: Loadout, Milestones, Consumables (+ v1 migration)
  Combat/
    Types.luau                 Every data shape (WeaponDef, AttackDef, StatusEffectDef, ...)
    DamageTypes.luau           Damage type registry + category (Physical / Magical / True)
    Definitions.luau           Loads + validates + freezes all combat data
    Data/Weapons.luau          Weapons and shields            <- balance lives here
    Data/Armor.luau            Defensive equipment
    Data/Consumables.luau      Defensive items / potions
    Data/StatusEffects.luau    Buffs, debuffs, CC, DoT, defensive magic effects
    CombatCore.luau            Rules engine (pure: no Roblox APIs, no clock)
    DamageCalculator.luau      Damage math (pure)
    StatusEffects.luau         Apply / stack / tick / cleanse / aggregate (pure)
    Resources.luau             Stamina / mana / energy pools (pure)
    Rulesets.luau              PvE / PvP targeting + normalization
    Projectile.luau            Projectile simulation + sweep tests (pure, `vector`)
ServerScriptService/Services/
  CombatService.luau           Roblox glue: remotes, geometry, Humanoids, projectiles, NPCs
  TrainingDummyService.luau    Studio-only PvE training dummies
StarterPlayer/.../Controllers/CombatController.luau   Input -> CombatRequest
StarterGui/UI/CombatHUD.client.luau                   Stamina / mana / barrier bars
```

Rule: **everything under `Shared/Combat` is pure** and covered by `luau tests/run.luau`.
Roblox-specific code only lives in `CombatService`, the controller and the HUD.

Pure modules require each other with Luau string requires (`require("./Types")`),
which work identically in Roblox and in the Luau CLI.

## 2. Data model (extension points)

All shapes are in `Combat/Types.luau`. Summary:

| Data | Key fields |
|---|---|
| `WeaponDef` | `Family` (free text), `Archetype` (Melee / RangedPhysical / Magic / Defense / Hybrid), `Slot` (MainHand / OffHand), `TwoHanded`, `Tier`, `Unlock`, `Attacks`, `Block?`, `Defense?` |
| `AttackDef` | `Delivery` (Melee / Projectile / Area / Self), `Damage` (list of `{Type, Amount}`), `Range`, `Arc`, `Radius`, `Projectile`, `Windup`, `Recovery`, `Cooldown`, `Cost` (`{Pool, Amount}`), `Ammo`, `ArmorPenetration`, `Interruptible`, `RecoveryVulnerability`, `Blockable`, `OnHit`, `OnSelf`, `Heal` |
| `ArmorDef` | `Slot` (Head / Body / Cloak / Talisman), `Defense` (`Armor`, `Resist` per damage type) |
| `ConsumableDef` | `Cooldown`, `CooldownGroup`, `Heal`, `Restore`, `Apply` (statuses), `Cleanse` (tags) |
| `StatusEffectDef` | `Duration`, `Stacking` (Refresh / Stack / Ignore), `Tags`, modifiers: `DamageTakenMultiplier`, `DamageDealtMultiplier`, `MoveSpeedMultiplier`, `Defense`, `Absorb`, `Reflect`, `Evasion`, `ImmuneToTags`, `Interrupts`, `PreventsActions`, `DamagePerSecond`, `HealPerSecond` |
| `UnlockGate` | `Level?`, `Milestones?` (all present fields must pass) |
| `Ruleset` | `Targeting`, `DamageMultiplier`, `ArchetypeMultipliers`, `LevelCap`, `ArmorCap`, `ResistCap`, `HealingMultiplier` |

How to extend without touching core logic:

- **New weapon** — add an entry to `Data/Weapons.luau`.
- **New weapon class** (whips, scythes, approved firearms…) — new entries with a new `Family` and any combination of `Delivery`, `Damage`, `Ammo`, `Cost`. Proven by the test *"a brand-new weapon class works from data alone"*.
- **New damage type** — one line in `DamageTypes.luau`.
- **New resource** (Rage, Focus…) — add it to `Config.Combat.Pools`; reference it in `Cost`.
- **New status / defensive spell** — entry in `Data/StatusEffects.luau`, then use it from `OnHit`, `OnSelf` or a consumable's `Apply`.
- **New defensive item** — entry in `Data/Consumables.luau`.
- **New mode / bracket** — add a ruleset in `Rulesets.luau`. Round logic (score, timer, respawn) belongs in a separate mode service that listens to `CombatService.Killed` / `Damaged`.

`Definitions.get()` validates everything at boot and errors with a full list of problems.
`Definitions.build(raw)` validates arbitrary data (tests, tools, future editor).

## 3. Combat rules

### Attack lifecycle (server)
1. `beginAttack` — alive, not stunned/busy/blocking, cooldown, ammo, resources; pays costs; returns a plan with `ImpactAt`.
2. Server waits `Windup`. `Interrupts` statuses (e.g. Stagger) cancel `Interruptible` windups.
3. At impact the server measures geometry again (never trusts the client) and calls `checkReach` per target.
4. `applyHit` per target (or `applySelf` for `Delivery = "Self"`).

### Damage order
`raw → level scale (capped by ruleset) → ruleset/archetype multiplier → armor (physical only, with penetration) → resist → damage-taken multipliers (statuses, heavy-attack recovery) → block → barrier → health → reflect (melee only) → on-hit statuses`

- Armor: `reduction = armor / (armor + ArmorConstant)` — diminishing, never 100 %.
- Resist is clamped to `[-0.5, ruleset.ResistCap]`.
- DoT ignores armor, respects resist, can be absorbed by barriers.

### Defense systems
| System | Where |
|---|---|
| Armor / resist gear | `Data/Armor.luau`, weapon `Defense` |
| Shields / blocking | weapon `Block` (frontal arc, % reduction, stamina per damage, guard break → Stagger) |
| Defensive items | `Data/Consumables.luau` (heal, restore, barrier, resist, cleanse, escape) |
| Defensive magic | `Delivery = "Self"` attacks with `OnSelf` (Barrier, FrostWard, Steadfast, Thornmail) |
| Evasion | `Evasion` status modifier |
| CC protection | `ImmuneToTags = { "CrowdControl" }` |

### Balance levers
- **Close-range power**: heavy melee has the highest per-hit damage (test-enforced) and pays with long `Windup` (interruptible), long `Recovery`, high stamina `Cost`, and `RecoveryVulnerability` (takes extra damage while recovering).
- **Ranged physical**: lower burst, reach; `Ammo` + reload for crossbows/throwing.
- **Magic**: `Mana` cost, cooldowns on the strongest spells, interruptible area casts.
- **PvP normalization** (`Rulesets.PvP`): level scaling capped at 30, armor cap 40, resist cap 50 %, damage ×0.6, healing ×0.5. PvE progress helps, but cannot dominate.

## 4. Progression gates

```lua
ProgressionGates.check(gate, profile) -> (boolean, reason?)
ProgressionGates.unlocked(defs, profile) -> { id }       -- everything usable now
ProgressionGates.newAtLevel(defs, level) -> { id }       -- "new unlocks" on level-up
```
`profile = { Level, Milestones = { [id] = true } }`. Gates are enforced by `CombatCore.equipWeapon`, `equipArmor` and `useConsumable` for players (NPCs skip them).
Milestones are granted with `PlayerDataService:GrantMilestone(player, id)` (bosses, arena ranks…).

## 5. CombatCore API (pure)

```lua
local engine = CombatCore.new(Definitions.get(), Config.Combat)
engine:newCombatant(spec) -> Combatant
engine:equipWeapon(c, id, profile?) / engine:equipArmor(c, id, profile?) / engine:unequip(c, slot)
engine:defenseProfile(c) -> { Armor, Resist }
engine:canAct(c, now)
engine:beginAttack(c, slot, attackId, now) -> (Plan?, reason?)
engine:isPlanValid(c, plan) / engine:finishAttack(c, plan) / engine:interrupt(c, now)
engine:checkReach(attacker, target, attack, ruleset, { Distance, Angle? })
engine:applyHit(attacker, target, weapon, attack, ruleset, now, { Random?, AngleFromTargetFacing? }) -> HitResult
engine:applySelf(c, plan, ruleset?, now)
engine:setBlocking(c, active, now)
engine:useConsumable(c, id, now, profile?, ruleset?)
engine:heal(c, amount, ruleset?)
engine:tick(c, now, dt, ruleset) -> { Damage, Healed, Expired, Killed, KillerId }
engine:revive(c, maxHealth?)
```

## 6. CombatService API (server)

```lua
CombatService:RegisterNPC(model, { Level, MaxHealth?, Team?, Weapons?, Armor?, BaseDefense?, RulesetId? })
CombatService:Unregister(model)
CombatService:GetCombatant(model) / CombatService:GetModel(combatantId)
CombatService:RequestAttack(model, slot, attackId, aimPoint?)   -- same path for players and NPC AI
CombatService:SetBlocking(model, active)
CombatService:SetRuleset(player, "PvE" | "PvP" | ...)
CombatService:SetTeam(model, team?)
CombatService:Revive(model)                                      -- living combatants / round resets
CombatService.AttackStarted / .Damaged / .Killed                 -- Signals for modes, rewards, quests, SFX
```
Tagging a Model (Humanoid + HumanoidRootPart) with `CombatNPC` registers it automatically; attributes `Level`, `MaxHealth`, `Weapon`, `Team`.

### Network protocol
`CombatRequest` (client → server), rate-limited and fully validated:

| Action | Fields |
|---|---|
| `Attack` | `Slot` (MainHand/OffHand), `AttackId`, `Aim` (world point, optional) |
| `Block` | `Active` (boolean) |
| `UseItem` | `ItemId` (must be owned; count decremented) |
| `Equip` | `Slot`, `ItemId` or `false` to unequip (gates checked, saved) |

`CombatEvent` (server → clients), presentation only: `AttackStarted`, `Projectile`, `Area`, `Hit`, `Evaded`, `Killed`, `ItemUsed`, `Rejected` (to one player, with reason). Animation / VFX / SFX hook in `CombatController` here — see the SFX map from the creative team.

Character attributes (replicated, 10 Hz): `Stamina`, `StaminaMax`, `Mana`, `ManaMax`, `Blocking`, `Barrier`.

## 7. Security notes
- The client sends intent only. Targets, damage, range, arcs, cooldowns, costs, ammo and unlocks are decided on the server.
- Reach is re-measured at impact time with latency tolerances (`MeleeRangeTolerance`, `MeleeArcTolerance`).
- Projectiles are simulated on the server from the attacker's real position and stopped by world geometry.
- Aim points are validated (type, finite, max distance) and clamped to attack range.
- Known limitation: character position and facing are client-owned physics in Roblox; this system bounds but cannot fully prevent movement exploits. A movement sanity check belongs in a future anti-cheat service.

## 8. Ronin prototype
The Ronin / odachi prototype maps onto this core as data: an `odachi` weapon entry (HeavyMelee family) plus a PvP arena mode service using `Rulesets.PvP` and the `Killed` signal. No katana-specific logic belongs in `Shared/Combat`.
