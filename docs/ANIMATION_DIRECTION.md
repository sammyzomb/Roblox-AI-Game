# Animation Direction

Role: Animation Designer / 動畫設計
Issue: #17
Status: draft for Technical Lead review
Depends on: `docs/ART_DIRECTION.md` (Issue #8, still open)

This document owns animation language and production priority. It does not change gameplay rules, combat numbers, or production code. Visual style that is not yet in Art Direction is marked **provisional** and must be reconciled when Issue #8 lands.

Sources read: `README.md`, `docs/GAME_DESIGN.md`, `docs/TEAM_ROLES.md`, `docs/CREATIVE_TEAM.md`, Issue #17. `docs/ART_DIRECTION.md` does not exist yet.

## 1. Animation identity

The combat foundation is one system for PvE and PvP. Animation has to stay readable on a phone and fair in PvP: a player must see commitment, range, and recovery before the hit lands.

**Style adjectives (provisional, pending #8):** grounded, readable, weight-forward, committed, mobile-clear.

**Motion principles**

- Weight matches the archetype in `docs/GAME_DESIGN.md`. Close-range power is heavy and committed. Ranged physical is planted, then released. Magic is a clear cast shape, not a generic arm wave.
- Silhouette first. The important pose must read with the body and weapon, not with fingers or facial detail.
- One idea per action. A swing does not also dash. A cast does not also strafe.
- Recovery is part of the attack. High-damage melee shows a longer settle. Light weapons and mobility tools settle faster. These are readability differences, not balance numbers.
- The Ronin / odachi prototype is a motion reference for a heavy two-hand slash only. Do not hard-code katana poses into the shared combat set.

**Not the target:** floaty anime loops with no recovery, dense mocap, or subtle acting that disappears on a phone.

## 2. Locomotion matrix

Locomotion is in-place. The character controller owns translation. See root-motion policy in section 11.

| State | Intent | Pose notes | Transition |
| --- | --- | --- | --- |
| Idle | Ready, weapon visible | Weight on both feet, weapon in its carry pose, small breathing only | To walk on move input; to attack without a long blend |
| Walk | Exploration, low threat | Short stride, weapon stable | To run on speed threshold; to idle with a short settle |
| Run | Travel | Longer stride, weapon still readable, no wild arm swing | To sprint if sprint exists as a speed state; to stop with a short skid pose |
| Sprint | Fast travel, higher commitment | Body leans forward, weapon pinned so it does not cover the torso | Leaving sprint is slower than leaving walk, so it reads as commitment |
| Turn | Direction change in place or while moving | Hips and shoulders lead; no full-body spin that hides the weapon | Short blend, under a quarter second |
| Strafe | Aim or guard while moving | Torso stays aimed; legs cross cleanly; weapon stays in aim or guard | Used by ranged aim and guarded advance |
| Jump | Leave the ground | Clear crouch then push. Arms do not cover the weapon | Only from grounded states |
| Fall | Airborne, no attack | Relaxed but readable, weapon still in carry or aim | From jump or from walking off a ledge |
| Land | Return to control | Soft land from short fall; heavier absorb from long fall. No long stun pose in the animation itself | Back to idle, walk, or run. Any landing lock belongs to combat code, not this clip |

Walk, run, and sprint are loopable. Jump is anticipation plus push. Fall loops. Land is a one-shot.

## 3. Combat animation matrix

Every attack clip is three phases: anticipation (wind-up), active (the readable strike or release), recovery (settle). Phase boundaries are animation markers for engineering. They are not hitbox durations and they are not damage numbers.

### Close-range power

Families: light melee, heavy melee, polearms, dual wield.

| Action | Light / dual | Heavy / polearm |
| --- | --- | --- |
| Attack 1 | Short wind-up, wide silhouette, fast settle | Obvious wind-up, full body, long settle |
| Attack 2 | Continues the line of attack 1, opposite side or step | Second commitment, still readable as its own swing |
| Attack 3 | Finisher pose, slightly longer recovery | Big finisher, longest recovery in the melee set |
| Combo link | End pose of N matches start pose of N+1 so the blend is under a few frames | Same rule, but do not hide the wind-up of the next heavy hit |

Combo rule: a combo is a chain of whole attacks, not a smear from one swing into the next. The player must still see each hit's wind-up, especially in PvP.

### Ranged physical

Families: bow, crossbow, throwing. Firearms stay out until Product Owner approves them.

| Phase | Bow | Crossbow | Throw |
| --- | --- | --- | --- |
| Draw / ready | Both hands, string or stock visible | Weapon up, visible load if a reload state exists | Arm cocks back, projectile readable |
| Aim | Strafe-compatible upper body | Same | Short aim, not a long hold unless design asks for it |
| Fire | Release is one clear frame | Shot is a kick plus a still weapon | Arm extends along the throw line |
| Recovery | Return to aim or carry | Optional reload pose, separate clip | Hand returns to carry |

Reload, ammo, and cooldown stay in combat design. Animation only supplies the pose and a marker named `release`.

### Magic

Families: staff, wand, and later hybrid weapons. One cast language, retargeted by prop.

| Phase | What it must show |
| --- | --- |
| Cast start | Hands leave carry and form a readable shape. Staff tip or wand tip leads |
| Channel | Loop. Body stays planted. Do not cover the face or the tip |
| Release | One accent pose. This is the VFX and SFX handoff |
| Interrupt | Break the channel into a flinch. Do not play the release pose |
| Recovery | Hands back to carry |

Utility, barrier, and mobility spells reuse this four-phase pattern. They do not get unique body language until Art Direction and combat design name them.

## 4. Defensive and reaction matrix

Defense is more than an armor stat. These clips show *that* a defense happened. They do not decide *whether* it succeeded.

| Action | Read | Notes |
| --- | --- | --- |
| Block / guard | Shield or weapon across the body, stable stance | Loop while held. Enter and exit are short |
| Parry | Small, early, opposite to the incoming swing | A parry is not a block. It is a short counter-pose. Success timing belongs to combat code |
| Dodge / evade | Whole body leaves the line, then returns | Must read on a phone. No tiny sidestep |
| Hit react | Head and chest snap, weapon stays in hand | Light, medium, heavy. Direction: front, back, left, right |
| Stagger | Larger than hit react, feet move in pose only | Displacement is scripted, not in the clip |
| Knockback | Body thrown, then recover to idle | Same rule: pose only |
| Death | Clear collapse, ends in a still pose | One-shot. No loop. PvP and PvE can share it |
| Equip | Weapon moves from stowed to carry | Hands and prop markers |
| Unequip | Reverse of equip | |
| Swap | Old weapon leaves, new weapon arrives | Do not overlap two large weapons in front of the torso |
| Carry / stance | Idle and locomotion variants per family | See section 8 |

Potions, barriers, and escape items use a short upper-body use clip. They must not look like a weapon attack.

## 5. Boss and enemy readability

Players and enemies share the same phase language so PvP and PvE teach the same thing.

- A boss wind-up is longer and larger than the player's version of the same idea. The pose at the end of anticipation is held long enough to see on a phone.
- Color and VFX may help, but the body pose has to work with VFX turned down.
- A boss must not turn its weapon or casting hand away from camera during anticipation.
- Adds use the player families, scaled in timing, not a second style.
- Elite enemies may add one extra anticipation pose. They do not get a unique locomotion set in the MVP.
- Nothing in an enemy attack should read as a dodge or a death until it is one.

## 6. Timing conventions

Targets below are animation readability, at 60 fps. They are not hitbox windows, stun times, or damage. If a combat designer needs different hit timing, that change goes to the Technical Lead. Do not silently retune these into balance.

| Clip kind | Anticipation | Active | Recovery |
| --- | --- | --- | --- |
| Light melee | 6–10 f | 4–8 f | 8–14 f |
| Heavy melee / polearm | 14–22 f | 6–10 f | 16–26 f |
| Bow release | aim is a hold | 2–4 f | 8–12 f |
| Throw | 8–12 f | 4–6 f | 10–14 f |
| Magic cast to release | 10–16 f | 4–6 f | 10–16 f |
| Magic channel loop | — | loop | — |
| Parry | 4–6 f | 4–6 f | 8–12 f |
| Dodge | 4–6 f | 8–12 f | 8–12 f |
| Hit react | 0–2 f | 6–10 f | 6–10 f |
| Boss anticipation | at least 1.5× the player version of that idea | same language | longer than the player's |

Blends:

- Locomotion blends: about 0.12–0.20 s.
- Idle to first attack: about 0.06–0.10 s, so the wind-up is not eaten by the blend.
- Combo link blend: about 0.04–0.08 s.
- Hit react: snap, about 0.03–0.05 s.

**Cancel policy proposal (Technical Lead decides):**

- Movement cancels recovery only, never anticipation or active, except dodge if combat design explicitly allows it.
- A combo input during recovery may start the next swing. It may not skip the next wind-up.
- Hit react cancels attack recovery. It does not cancel an already-started dodge.
- Death cancels everything.
- Parry is not an attack cancel. It is its own state.

## 7. Mobile and performance constraints

- Poses must read at roughly a thumb's width on a phone. If a tell depends on a finger or a face, it is not a tell.
- Prefer R15. If the avatar rig is still undecided, author on R15 and do not depend on extra bones. This is provisional.
- Keep clips short. Loops for idle, channel, guard, and fall. One-shots for attacks, hit reacts, and death.
- One weapon family shares one animation set. Do not author a unique swing per sword mesh.
- Avoid stacked upper-body and full-body tracks on the same limbs during attacks. Aim offset for bows is the main upper-body exception.
- No root motion in exported clips. No camera animation inside the character clip.
- Target a modest keyframe budget: pose-to-pose keys, not baked mocap curves.
- Death, hit react, and dodge stay on the shared humanoid so enemies can reuse them.
- Particle and trail work is VFX, not extra bones.

## 8. Asset naming

Pattern:

`anim_<family>_<state>_<variant>`

Family tokens: `unarmed`, `light`, `heavy`, `polearm`, `dual`, `bow`, `crossbow`, `throw`, `staff`, `wand`, `shield`.

State tokens: `idle`, `walk`, `run`, `sprint`, `turn_l`, `turn_r`, `strafe_l`, `strafe_r`, `jump`, `fall`, `land`, `land_heavy`, `atk1`, `atk2`, `atk3`, `draw`, `aim`, `release`, `reload`, `cast`, `channel`, `interrupt`, `block`, `parry`, `dodge`, `hit_f`, `hit_b`, `hit_l`, `hit_r`, `stagger`, `knockback`, `death`, `equip`, `unequip`, `swap`.

Examples: `anim_heavy_atk1`, `anim_bow_aim`, `anim_staff_channel`, `anim_shield_block`, `anim_shared_death`.

Markers inside a clip, when needed: `anticipation_end`, `active_start`, `active_end`, `release`, `recover_start`.

Shared clips that are not weapon-specific use the family `shared`.

## 9. MVP animation priority

Vertical slice, in this order. Later rows do not start until the row above is readable on a phone.

1. Shared locomotion: idle, walk, run, jump, fall, land.
2. Heavy melee: carry idle, atk1–atk3, hit reacts, death. This is the Ronin reference, generalized off the katana.
3. Light melee: carry idle and atk1–atk3, reusing shared hit and death.
4. Bow: draw, aim, release, recover.
5. Staff cast: cast, channel, release, interrupt.
6. Defense: block, dodge, parry.
7. Equip, unequip, swap for heavy, light, bow, staff.
8. Boss telegraph template: one heavy slam and one cast, using the longer anticipation rule.
9. Polearm, dual wield, crossbow, throw, wand, sprint, strafe, knockback. After the slice.

Out of slice until design names them: firearms, per-spell unique casts, per-boss unique locomotion.

## 10. Engineering, VFX, and SFX handoff

**Engineering (Claude owns production code; this is a request, not a change)**

- Drive locomotion and knockback in the controller. Do not read translation out of the clip.
- Read markers `active_start`, `active_end`, and `release` if combat needs a phase. Combat still owns the hitbox.
- Cancel rules in section 6 are a proposal. Technical Lead accepts or rewrites them before implementation.
- Weapon attach points: hand, and a stow point on the back or hip. Swap plays `unequip` then `equip`, or a single `swap` if both props can be shown without covering the body.
- Do not fork a katana-only animator from the Ronin prototype into the shared core.

**VFX**

- Melee trail: `active_start` to `active_end`.
- Bow and throw: `release`.
- Magic: channel loop during `anim_*_channel`, burst on `release`, nothing on `interrupt` except a dissipate.
- Block and parry: impact on contact, not on the start of the pose.
- Boss anticipation may add a tell VFX at `anticipation_end`, never instead of the pose.

**SFX**

Event names should line up with the animation markers so SFX Planner can map them without a second vocabulary: `atk_swing`, `atk_release`, `cast_release`, `block_contact`, `parry_contact`, `dodge`, `hit`, `death`, `equip`. Whoosh on anticipation or active start. Impact on contact, which may be later than `active_start`. This list is a handoff, not a replacement for `docs/SFX_PLAN.md`.

## 11. Open decisions and dependencies

| Item | Owner | Notes |
| --- | --- | --- |
| Art direction not landed | Art Planner, Issue #8 | Adjectives in section 1 are provisional. Re-read `docs/ART_DIRECTION.md` before final keys |
| Root motion | Technical Lead | Recommendation: no root motion. In-place clips plus scripted movement. Reject if the controller needs authored displacement |
| Cancel rules | Technical Lead | Section 6 is a proposal. It must not ship as balance |
| Sprint as its own state | Technical Lead / combat design | Included as a locomotion slot. Drop the clip if sprint is only a speed scalar |
| Rig: R15 vs R6 | Technical Lead | Provisional R15 |
| Firearm animations | Product Owner | Not in the matrix until approved |
| Per-spell body language | Art Planner + combat design | MVP uses one cast family |
| Ronin prototype reuse | Technical Lead | Motion reference only. Known networking and mobile issues stay out of this document |

## Boundaries

- Does not change gameplay rules or combat numbers.
- Does not replace Art Planner.
- Does not claim production Luau or animator implementation.
- Timing that would change fairness goes to the Technical Lead before anyone treats it as design.
