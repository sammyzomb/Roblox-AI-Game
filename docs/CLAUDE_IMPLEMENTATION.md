# Claude Implementation — Sprint 0 Foundation

Owner: Claude (Primary Programmer) · Branch: `claude-dev` · Issue: #1

This document explains how to set up, run and extend the Roblox project foundation.

## 1. Tooling

| Tool | Purpose | Pinned in |
|---|---|---|
| [Rokit](https://github.com/rojo-rbx/rokit) | Installs the project's tool versions | — |
| [Rojo](https://rojo.space) 7.7.0 | Syncs `src/` into Roblox Studio / builds place files | `rokit.toml` |
| [Luau CLI](https://github.com/luau-lang/luau) 0.740.0 | Runs unit tests outside Roblox | `rokit.toml` |

### One-time setup

1. Install Rokit (Windows: download `rokit-*-windows-x86_64.zip` from the Rokit releases page, run `rokit.exe self-install`, reopen the terminal).
2. In the repo root: `rokit install` — installs Rojo and Luau at the pinned versions.
3. In Roblox Studio, install the **Rojo** plugin (Plugins → Manage Plugins / Creator Store, author: Rojo).

## 2. Running the game in Studio

1. In the repo root: `rojo serve`
2. Open Roblox Studio → **New → Baseplate** (or any place).
3. Plugins tab → **Rojo** → **Connect**. `src/` is now live-synced into the place.
4. Press **Play**.

Expected:

- Output shows `[Server] booted 2 module(s)` and `[Client] booted 1 module(s)`.
- A HUD at the top shows `Coins: 0    Level 1` and an xp bar.
- Press **E** (keyboard), **X** (gamepad) or the on-screen **Collect** button (touch / mobile emulator) → coins +1, xp bar fills, level goes up.

DataStores: in an unpublished place, or with *Game Settings → Security → Enable Studio Access to API Services* off, the Output shows
`[DataStore] Unavailable in Studio; using in-memory store` and progress resets each run. That is expected. To test real persistence, publish the place and enable API access.

To produce a place file without Studio sync: `rojo build -o build.rbxlx`.

## 3. Running tests

```
luau tests/run.luau
```

Covers the pure modules: `Progression`, `PlayerDataModel`, `RateLimiter`. Code that uses Roblox APIs (services, remotes, UI) is verified by play-testing in Studio.

## 4. Source layout

```
default.project.json          Rojo mapping of src/ into the DataModel (+ Baseplate, SpawnLocation)
rokit.toml                    Tool versions
src/
  ReplicatedStorage/
    Remotes/                  RemoteEvent/RemoteFunction declared as *.model.json
      RequestAction           client -> server  (actionId: string)
      StateChanged            server -> client  (state: ClientState)
      GetState                client -> server  returns ClientState?
    Shared/                   Code used by both server and client
      Config.luau             All tunable numbers (rewards, cooldowns, progression, DataStore)
      Net.luau                Remote names + lookup helpers
      PlayerDataModel.luau    PlayerData type, defaults, validation (pure)
      Progression.luau        Level/xp math (pure)
      ServiceLoader.luau      Boots a folder of services/controllers
      Signal.luau             Small in-process event
  ServerScriptService/
    Main.server.luau          Server bootstrap
    Services/                 Long-lived server services (booted by ServiceLoader)
      PlayerDataService.luau  Load/save/autosave; the only owner of player data
      GameLoopService.luau    Validates action requests and grants rewards
    Systems/                  Server-only helpers, not auto-booted
      DataStoreAdapter.luau   DataStore wrapper with retries + Studio fallback
      RateLimiter.luau        Per-player request budget (pure)
  StarterPlayer/StarterPlayerScripts/
    Main.client.luau          Client bootstrap
    Controllers/
      InputController.luau    E / gamepad X / touch button -> RequestAction
  StarterGui/UI/
    HUD.client.luau           Coins, level, xp bar (display only)
tests/
  run.luau                    Unit tests (Luau CLI)
```

## 5. Service pattern

Every module in `Services/` (server) or `Controllers/` (client) is a table with optional lifecycle methods:

```lua
local MyService = {
	Priority = 0, -- optional; lower boots first (PlayerDataService uses -10)
}

function MyService:Init(registry)
	-- Runs synchronously, in order. Grab dependencies here:
	self.PlayerData = registry.PlayerDataService
end

function MyService:Start()
	-- Runs in its own thread after every Init has finished. Connect events, loops, etc.
end

return MyService
```

Rules:

- Get other services from `registry` in `Init`; do not `require` one service from another (avoids circular requires).
- `Init` must not depend on another service's `Start` having run.
- An error in `Init` stops boot on purpose; fix it rather than catching it.
- Document the public API at the top of each service (see `PlayerDataService`).

## 6. Public APIs

### PlayerDataService (server)

| Member | Description |
|---|---|
| `:Get(player) -> PlayerData?` | Current data; `nil` until loaded. Treat as read-only. |
| `:Update(player, mutator) -> boolean` | Only way to change data. `mutator(data)` must not yield. Marks the session dirty, fires `Changed` and replicates `ClientState` to that player. Returns `false` if not loaded. |
| `.Loaded` | Signal `(player, data)` after data is loaded. |
| `.Changed` | Signal `(player, data)` after every `Update`. |

Saving: on leave, every `Config.DataStore.AutosaveInterval` seconds, and in `BindToClose`. A session whose load failed, or whose stored data has a newer `Version`, is never saved, so existing data is not overwritten.

### PlayerData (v1)

```lua
{ Version = 1, Coins = 0, Xp = 0, Level = 1, Stats = { Actions = 0 } }
```

To add a field: add it to the `PlayerData` type and `new()`, read it in `reconcile()` with validation, and add a test. Bump `CURRENT_VERSION` and add a migration in `reconcile()` only when existing stored data must be transformed.

### GameLoopService (server)

Listens on `RequestAction`. A request is accepted only if the action id is a string that exists in `Config.Actions`, the player is within `Config.RateLimit`, the action's cooldown has passed, and the player's data is loaded. Invalid requests are dropped silently.

**Adding a new repeatable action:** add an entry to `Config.Actions` (`Cooldown`, `Reward`) and bind input to it on the client. Actions needing extra rules (e.g. "must be near a node") get their check in `onRequestAction` or, once there are several, a per-action validator table.

## 7. Security notes

- Server authoritative: the client only sends *which* action it wants; the server decides whether it's allowed and what it's worth.
- All remote arguments are type-checked; unknown action ids are ignored.
- Per-player rate limit + per-action cooldown on the server. The client cooldown is UX only.
- `ClientState` is a copy built by the server; nothing the client sends is written to player data.

## 8. Known limitations / suggested next steps

- **No session locking.** Two servers could briefly hold the same player (fast server hop) and the last save wins. Recommend moving to `UpdateAsync` with a session lock, or adopting ProfileStore, before launch.
- `reconcile()` drops fields it doesn't know. Fine for v1; revisit when data grows.
- The "Collect" action has no world object yet. The gameplay theme is undecided (see Grok's MVP proposal, Issue #2). Once chosen, the action should be tied to world interaction (ProximityPrompt / touch parts) and validated by distance on the server.
- No automated tests for Roblox-API code yet. TestEZ or Jest-Lua in Studio can be added later if needed.
- The Lune runtime was considered for tests but is blocked by Windows Smart App Control on the dev machine; the Luau CLI is used instead.
