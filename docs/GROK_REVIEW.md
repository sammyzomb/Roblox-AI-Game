# GROK_REVIEW — Gameplay & Architecture Review (Sprint 0)

- **Author:** Grok — Secondary Developer / Reviewer
- **Task:** Issue #2 — Review architecture and propose MVP gameplay loop
- **Branch:** `grok-dev` (target PR: `docs: gameplay and architecture review`)
- **Reviewed against:** `main` @ `fa0c84c` (README, AI_RULES, ARCHITECTURE, TASKS, AI_COORDINATION_PROTOCOL, PROJECT_STATUS)
- **Status:** Review/recommendations only. Nothing here overrides ChatGPT (Technical Lead) or the Product Owner. Anything marked **DECISION** needs owner/TL sign-off.

> 繁中摘要：架構方向正確（伺服器權威、遠端驗證、資料服務層、手機優先）。建議先補齊「Rojo 專案設定、Remotes 規範、DataStore 服務層規格」三件事。附一個已可運作的 PvP 刀戰原型「Ronin Arena v1」作為**可選參考**，是否採用由 Product Owner / ChatGPT 決定。

---

## 1. Summary (TL;DR)

1. `ARCHITECTURE.md` principles are sound. The gaps are **tooling and conventions**, not direction: no Rojo/toolchain decision, no Remote naming/validation contract, no DataStore spec, no module/service lifecycle pattern.
2. **Proposed MVP loop:** *Fight → Earn → Upgrade → Fight harder*, playable **solo** (PvE first), with PvP as an optional mode. Must work with 1 player so every AI/tester can validate it in Studio alone.
3. **Biggest technical risks:** (a) character physics are client-owned, so attacker position/speed can be spoofed; (b) DataStore without session locking = item/currency duplication and data loss; (c) mobile tap-to-attack conflicts with camera drag.
4. Grok has a working local prototype (**Ronin Arena v1**, PvP katana arena, Rojo, ~2.2k lines Luau). Offered as an **optional reference** for combat/round/remote-validation patterns — not a proposal to replace Claude's foundation (Issue #1).
5. Five open questions for owner/TL are in §9.

---

## 2. Repository & Architecture Review

### 2.1 What is good
- Branch-per-agent + PR-only to `main` + GitHub-as-source-of-truth is the right model for multi-AI work.
- Engineering principles (server authority, validate all remotes, isolated persistence layer, shared config in `ReplicatedStorage/Shared`, no circular deps, mobile from day one) match Roblox best practice.
- MVP list (join → spawn → repeatable action → reward → progression → save/load → minimal UI → extension points) is a good checklist.

### 2.2 Gaps / recommendations

| # | Finding | Recommendation | Owner |
|---|---|---|---|
| A1 | No toolchain decision. "Design through GitHub, Studio for testing" only works if files on disk map to the DataModel. | Adopt **Rojo** (+ `rokit` for pinned tool versions). Commit `default.project.json`, `rokit.toml`, `selene.toml`, `.luaurc`. Studio work = `rojo serve` or `rojo build -o build/Game.rbxlx`. | ChatGPT decides, Claude sets up in #1 |
| A2 | Layout in ARCHITECTURE.md mirrors service names (`src/ReplicatedStorage/...`). Fine, but must be matched 1:1 in the Rojo project file or the tree silently diverges. | Keep the proposed layout, and document the exact Rojo mapping in `docs/CLAUDE_IMPLEMENTATION.md`. | Claude |
| A3 | `StarterGui/UI` implies Studio-authored GUIs, which are hard to diff/review in PRs. | Prefer UI built in code (or `.model.json`) so AIs can review it. Studio-authored assets go in a separate `assets/` path with a note. | ChatGPT |
| A4 | No service lifecycle convention (init order, start, dependencies). | Simple pattern: each Service module exposes `init()` (no yields, wire refs) and `start()` (connect events, spawn loops); one server bootstrap requires services in an explicit order. Same for client Controllers. No framework needed for MVP. | Claude |
| A5 | "Remotes" folder exists but no contract. | Add `docs/REMOTES.md`: one table listing each Remote, direction, payload schema, rate limit, validation, owner service. Create Remotes **server-side or in project file**, never from the client. | ChatGPT/Claude |
| A6 | "Persistent data isolated behind a service layer" — no spec. | See §5. Define `DataService` public API before any feature stores data. | Claude (spec reviewed by Grok) |
| A7 | No testing story. Linux/AI agents cannot run Studio. | Mandatory: `selene` + `luau-lsp analyze` (or `luau-analyze`) in CI via GitHub Actions; `--!strict` on all modules. Optional later: TestEZ/Jest-Lua for pure modules. Every PR states "Studio-tested: yes/no". | ChatGPT |
| A8 | Branches `chatgpt-dev` / `claude-dev` / `grok-dev` all point at `eff9578` (initial commit) and are **behind `main`** (docs added after). | Rebase/merge `main` into each dev branch before feature work, or PRs will show unrelated diffs/conflicts in `docs/`. | Owner |
| A9 | `StreamingEnabled` not mentioned. | Decide early (DECISION). Enabling it later breaks code that assumes parts exist on the client. Small maps: off is fine; large open world: on, with `WaitForChild`/`ModelStreamingMode` discipline from day one. | ChatGPT |

---

## 3. Proposed Lightweight MVP Gameplay Loop

Goal: smallest loop that exercises **every** MVP bullet in ARCHITECTURE.md and is testable by one person in Studio.

```
Spawn in hub ─► Enter zone ─► Repeatable action (defeat enemy / dummy)
     ▲                                   │
     │                                   ▼
Upgrade (spend currency)  ◄──  Reward feedback (+coins, +XP, popup/sound)
     │
     └─► Progression state (level/weapon tier) ─► saved via DataService
```

**Concrete MVP spec (theme-agnostic; can be skinned as ronin/samurai if owner chooses):**
1. **Join/spawn:** hub area with spawn + 1 combat zone.
2. **Repeatable action:** melee attack on server-spawned NPC enemies (start with stationary dummies, then simple chase AI). 1 input (attack) + optional 1 defensive input.
3. **Reward:** enemy defeat → coins + XP, floating number + sound, server-authoritative.
4. **Progression:** level from XP; one upgrade track (e.g. weapon damage tier) bought with coins at a single shop pad/prompt (`ProximityPrompt` works on all platforms).
5. **Save/load:** coins, XP, weapon tier via `DataService` (schema-versioned).
6. **Minimal UI:** health, coins, level/XP bar, shop prompt.
7. **Extension points:** `EnemyService` (spawn definitions table), `ZoneService` (zone configs), `ShopService` (item table) — quests plug into enemy-defeat/shop events via a small signal module.

**Why PvE-first:** PvP-only needs ≥2 players to test and to be fun on a low-population new game; PvE works with 1 player, in Studio, for every AI tester. PvP can be a later mode reusing the same combat service.

**Iteration plan (suggested, TL to assign):**
- Sprint 1: foundation (#1) + DataService + combat vs dummy + coins.
- Sprint 2: enemy AI, shop/upgrade, level, mobile UI pass.
- Sprint 3: second zone or PvP arena mode, polish, publish test build.

---

## 4. Networking & RemoteEvents

**Rules (proposed for `docs/REMOTES.md`):**
1. Client sends **intent only** (`"Attack"`, `"Buy", itemId`), never results (damage, hit target, price, position).
2. Every `OnServerEvent`/`OnServerInvoke` handler: type-check every argument (`typeof`), whitelist enums/ids against server tables, clamp numbers, reject NaN/inf (`x ~= x`), check string length.
3. **Per-player rate limit** in one shared helper (token bucket), not ad hoc per remote.
4. Cooldowns enforced on server with a small latency tolerance (~50–100 ms); client-side cooldowns are UX only.
5. **Avoid `RemoteFunction` client→server→client invokes from server** (`InvokeClient`) — a client can hang the server thread forever. Server→client = RemoteEvent only.
6. Prefer `UnreliableRemoteEvent` for cosmetic, high-frequency, loss-tolerant messages (VFX, swing animations); keep damage/reward on reliable events.
7. Replicate state via **Attributes / ValueObjects** where possible (e.g. round phase, coins) instead of chatty events.
8. Few multiplexed remotes (e.g. `CombatAction(action: string)`) with a dispatch table are easier to validate and audit than dozens of single-purpose remotes.
9. Clean up per-player state on `PlayerRemoving` (memory leaks are the #1 long-server bug).

**Latency:** server-side melee hit detection at 150–250 ms ping feels "I hit him on my screen but it didn't count". For MVP accept it (generous hitboxes); document it as a known limitation. Real lag compensation (position history rewind) is post-MVP.

---

## 5. DataStore Risks & Recommendations

| Risk | Consequence | Recommendation |
|---|---|---|
| No session locking | Player joins server B before server A saved → overwrite/duplication exploits | Use **ProfileStore** (successor to ProfileService, session-locked) or implement a lock field with `UpdateAsync`. DECISION: use library vs hand-rolled. Recommendation: ProfileStore. |
| `SetAsync` overwrites | Race conditions, data loss | Always `UpdateAsync` with a transform function. |
| No retry / budget awareness | Throttling drops saves | Retry with backoff; check `DataStoreService:GetRequestBudgetForRequestType`; autosave every 60–120 s, not on every change. |
| Server shutdown | Last minutes lost | `game:BindToClose` saving all profiles (30 s limit), plus save on `PlayerRemoving`. |
| Schema changes | Old saves break new code | `schemaVersion` field + migration functions; defaults reconcile missing keys. |
| Studio testing hits production data | Corrupts live data | Separate store name per environment (e.g. `PlayerData_dev` in Studio via `RunService:IsStudio()`), and enable "Studio Access to API Services" only in a dev place. |
| Data accessed by features directly | Unauditable writes | Only `DataService` touches DataStore. Features call `DataService:Get(player)`, `:Increment(player, key, n)`, `:OnChanged(...)`. |
| Monetization (DevProducts) | Double-grant / lost purchases | `ProcessReceipt` must record the purchase id in the profile and only return `PurchaseGranted` after save succeeds. (Post-MVP, but design DataService for it.) |

**Proposed `DataService` public API (for Claude's scaffold):**
```lua
DataService.init()
DataService.start()
DataService.get(player): PlayerData?          -- nil until loaded
DataService.waitForData(player, timeout): PlayerData?
DataService.update(player, key, fn)           -- server-only mutation
DataService.changed: Signal<(player, key, newValue)>
-- leaderstats / Attributes mirror is a *view*, never the source of truth
```

---

## 6. Exploit Prevention

Roblox reality: **the client owns its character's physics.** Position, rotation, velocity, WalkSpeed, jumping, and local animations of a player's own character can be spoofed. Anything *derived* from them on the server is only as trustworthy as the checks added.

| Area | Risk | Recommendation |
|---|---|---|
| Melee hit detection | Server uses attacker's (client-owned) root CFrame → teleport-behind / spin exploits, reach extension via position spoof | Server hitbox (done in prototype) **plus** sanity check: `(victimPos - attackerPos).Magnitude <= range + tolerance`; optionally reject if attacker moved > maxSpeed·dt since last check. |
| Speed/teleport/fly | Client edits WalkSpeed or CFrame | Lightweight server movement monitor (distance per heartbeat vs WalkSpeed + dash allowance); on violation: rubber-band (`PivotTo` last valid pos) and log, don't auto-ban in MVP. |
| Remote spam | Server CPU / event flooding | Shared token-bucket rate limiter per player per remote; drop silently, count violations, kick above a high threshold. |
| Economy | Client sends price / reward amounts | Prices and rewards live only in server tables; client sends item id only; server validates ownership, currency, proximity to shop. |
| Kill/reward farming | Alt accounts feeding kills | Diminishing rewards for repeated kills of same victim; no reward for dummies beyond small amount. |
| Instances created by client | Client-created instances don't replicate — but server code that trusts `FindFirstChild` on client-controlled paths (character children) can be fooled | Validate tools/instances by server-side registry or attributes set by server, not by name alone where it matters (e.g. "is weapon equipped" before granting rewards). |
| Knockback | Applied by victim client (because it owns physics) — exploiter can ignore it | Accept for MVP; note it. |

---

## 7. Mobile Control Risks

| Risk | Recommendation |
|---|---|
| `Tool.Activated` fires on **any screen tap** on mobile → attacking while trying to rotate camera / move | Dedicated on-screen **Attack button**; consider `Tool.ManualActivationOnly = true` and fire attack from the button/mouse/gamepad input only. |
| `ContextActionService` auto-buttons are small, stack near the jump button, hard to style/position | Custom `ImageButton` layout sized ≥ 44–48 px equivalent (scale-based), positioned for right thumb; respect `GuiService:GetGuiInset()` / safe area on notch devices. |
| Hold-to-block on touch: if finger slides off button, `End` may not fire → stuck blocking | Handle `InputEnded` globally for that touch id, and add a server-side max hold / auto-release. |
| Too many actions for touch | MVP: ≤3 touch actions (Attack, Defend, Dash/Skill). |
| Performance (low-end Android) | Budget parts/particles; pool VFX; avoid per-frame `Instance.new`; test on a real low-end device before publish. Keep draw calls low in UI. |
| Text/UI scaling | Use Scale + `UIAspectRatioConstraint` + `UITextSizeConstraint`; test at 16:9, 19.5:9 (phones), 4:3 (tablets). |
| Input type detection | Use `UserInputService.PreferredInput` (or `LastInputTypeChanged`) to switch prompts/icons between KB/M, gamepad, touch. |

---

## 8. Optional Prototype Reference — "Ronin Arena v1"

Grok built a self-contained prototype locally (not pushed; see blocker in Issue #3). **Offered as reference only.** Adoption, partial reuse, or discard is the Owner's / ChatGPT's call.

**What it is:** Multiplayer PvP katana arena using the owner's *Black Ronin Odachi* design (from `sammyzomb/Roblox-UGC`). Rojo project, `--!strict` Luau, selene + luau-lsp clean. **Not yet tested in Studio** (written on Linux; statically checked only).

**Features:** round arena built by server code; server-authoritative combat (3-hit combo, block = −80% frontal damage, dash with 0.35 s i-frames, hit-stun, knockback); round loop (min 2 players, 10 s countdown, 180 s limit, last-standing wins, 8 s intermission, ring-out = elimination with kill credit); lobby training dummies; code-built HUD; leaderstats Kills/Wins; PC / gamepad / mobile inputs; all tunables in one `Config` module.
**Missing:** sound, DataStore persistence, arm/character animations (sword-only animation), parry, stamina.

**Patterns worth reusing (regardless of theme):**
- Single multiplexed `CombatAction` remote with `typeof` check, per-player rate limit (25/s), server cooldowns with 80 ms network tolerance, intent-only payloads.
- Server-side `GetPartBoundsInBox` hitbox; weak-keyed "last hit by" table for kill credit.
- Round state replicated via Attributes on a `GameState` folder (no polling remotes).
- `pvpFilter` injection (RoundService decides who may damage whom; CombatService stays generic).

**Known weaknesses found while reviewing my own prototype (would fix before any adoption):**
1. No attacker↔victim distance / movement sanity check (see §6) — relies on client-owned root CFrame.
2. Block has no cost/limit (no stamina/guard-break) → time-limit tie-break "highest HP wins" rewards turtling.
3. Mobile attack uses `Tool.Activated` (tap-anywhere) and default CAS buttons — see §7.
4. Rate limit is one shared bucket for all combat actions; drops silently without violation logging.
5. `PlayerData` is leaderstats only (no persistence); not yet behind a DataService API.
6. Cosmetic events (`Swing`, `Hit`) use reliable `RemoteEvent`; could be `UnreliableRemoteEvent`.

**Compatibility with ARCHITECTURE.md:**

| Principle | Prototype | Status |
|---|---|---|
| Server authoritative gameplay | Damage, cooldowns, HP, rounds all server-side | ✅ Compatible |
| Client presentation/input only | Client sends intent; VFX/HUD client-side | ✅ |
| Validate all remote input | typeof + rate limit + cooldown; missing distance check | ⚠️ Partial |
| Persistence behind service layer | No persistence yet | ⚠️ Not implemented |
| Shared config in `ReplicatedStorage/Shared` | `Config.luau` there | ✅ |
| No circular deps / small modules | Services acyclic (Round→Combat, no reverse require; filter injected) | ✅ |
| Public API documented | Comments only; no API doc | ⚠️ |
| Mobile from start | Inputs exist, but UX issues (§7) | ⚠️ |

**Conflicts with ARCHITECTURE.md / current plan:**
- **C1 — Source layout:** prototype uses `src/server`, `src/client`, `src/shared` (mapped by Rojo to `ServerScriptService/Server`, `StarterPlayerScripts/Client`, `ReplicatedStorage/Shared`), not `src/ServerScriptService/Services|Systems`, `src/StarterGui/UI`. Easy to re-map; no code change beyond `require` paths.
- **C2 — UI location:** HUD is built in code in a client script, not in `StarterGui/UI`.
- **C3 — Map:** arena/lobby generated at runtime by `ArenaBuilder` (nothing visible in edit mode) vs. Studio-authored world assets.
- **C4 — MVP direction:** ARCHITECTURE MVP implies solo repeatable action + progression + save/load + shops/quests/zones. Prototype is PvP-only rounds (≥2 players) with no economy/progression. Its combat core fits the MVP; its round/PvP layer does not, unless the owner chooses a PvP theme.
- **C5 — Ownership:** Combat/round systems overlap with what Claude may build in Sprint 1. Per AI_RULES, Grok will **not** push these modules into shared paths without TL assignment.

---

## 9. Open Questions (Owner / ChatGPT)

1. **DECISION (Owner): Game theme/genre.** PvE progression (matches ARCHITECTURE MVP) vs PvP arena (matches prototype) vs hybrid (PvE loop + PvP arena mode)? Is the Ronin/odachi theme from `Roblox-UGC` wanted here?
2. **DECISION (ChatGPT): Toolchain.** Rojo + rokit + selene + luau-lsp + GitHub Actions lint — approve?
3. **DECISION (ChatGPT): Persistence library.** ProfileStore vs hand-rolled `UpdateAsync` + session lock?
4. **DECISION (Owner/ChatGPT): Prototype.** (a) ignore, (b) keep as reference under `prototypes/ronin-arena/` on `grok-dev` only, or (c) assign Grok to port its combat core into Claude's foundation after #1 merges?
5. **Access (Owner):** Grok currently can comment on Issues but cannot push branches/files. Either grant push to `grok-dev` or the owner pushes this file. Also please sync `grok-dev` with `main` (it is still at `eff9578`).

---

## 10. Suggested Acceptance Checklist for Sprint 0/1 PRs
- [ ] `--!strict`, selene and luau-lsp pass (CI).
- [ ] Every new Remote listed in `docs/REMOTES.md` with validation + rate limit.
- [ ] No feature code calls DataStoreService directly.
- [ ] Per-player tables cleaned on `PlayerRemoving`.
- [ ] Works with 1 player in Studio; tested on emulated phone (Device Emulator) at least once.
- [ ] PR states Studio-tested yes/no, risks, dependencies (per AI_RULES).