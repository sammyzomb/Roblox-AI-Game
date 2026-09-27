# ARCHITECTURE

## Goal

Build a Roblox game that can be designed and iterated primarily through GitHub-based AI collaboration, with Roblox Studio used mainly for testing, assets, and final validation.

## Repository Roles

- `main`: stable integration branch
- `chatgpt-dev`: architecture, integration, orchestration
- `claude-dev`: primary implementation
- `grok-dev`: secondary implementation, prototypes, review

## Initial Source Layout

```
src/
  ReplicatedStorage/
    Shared/
    Remotes/
  ServerScriptService/
    Services/
    Systems/
  StarterPlayer/
    StarterPlayerScripts/
  StarterGui/
    UI/
docs/
```

## Engineering Principles

- Server authoritative gameplay.
- Client handles presentation and input only where possible.
- All remote input must be validated server-side.
- Persistent data logic must be isolated behind a service layer.
- Shared configuration belongs in `ReplicatedStorage/Shared`.
- Avoid circular module dependencies.
- Prefer small modules with explicit responsibilities.
- New systems must document their public API.
- Mobile compatibility must be considered from the start.

## MVP Direction

The first playable build should support:
- Player joins
- Basic world/spawn
- One repeatable gameplay action
- Reward feedback
- Simple progression state
- Save/load scaffold
- Minimal UI
- Clean extension points for quests, enemies, shops, and zones

The exact game theme will be decided by the Product Owner.
