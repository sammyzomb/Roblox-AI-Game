# GAME DESIGN

## Product Direction

Product Owner decision: **Hybrid PvE + PvP progression game**

The game combines:
- PvE progression and farming
- PvP arena / competitive combat
- Level-based weapon progression
- Multiple combat styles
- Defensive equipment, defensive items, and defensive magic

## Core Combat Archetypes

### 1. Close-Range Power
- Highest raw damage potential
- Shortest effective range
- High commitment / risk
- Slower recovery or stamina pressure may be used for balance
- Includes heavy melee weapons and strength-based attacks

### 2. Ranged Physical
- Bows, crossbows, throwing weapons, firearms if later approved
- Medium to long range
- Lower burst than heavy melee, balanced by reach and positioning
- Ammo / cooldown / reload systems may be used depending on weapon type

### 3. Magic Attack
- Ranged and area attacks
- Elemental / status / utility possibilities
- Mana or energy resource required
- Should not outclass melee in every situation
- Different spell classes can support damage, control, mobility, or defense

## Defense Systems

Defense must be more than armor value.

### Defensive Equipment
Examples:
- Armor
- Shields
- Helmets
- Cloaks
- Talismans

### Defensive Items
Examples:
- Potions
- Barrier consumables
- Temporary resistance items
- Escape / cleanse items

### Defensive Magic
Examples:
- Shields / barriers
- Damage reduction
- Reflect / absorb
- Resistance buffs
- Crowd-control protection
- Mobility / evasion spells

## Weapon Progression

Weapons are unlocked gradually by player level and/or progression milestones.

Principles:
- Many weapon choices
- Stronger does not always mean universally better
- Different weapons support different combat styles
- Progression should unlock new options, not only linear stat inflation
- Early weapons remain potentially useful through specialization, upgrades, rarity, or build synergy

Suggested weapon families:
- Light melee
- Heavy melee
- Polearms
- Dual wield
- Bows
- Crossbows
- Throwing weapons
- Magic staves / wands
- Hybrid weapons

## PvE + PvP Relationship

PvE:
- Main progression source
- XP, currency, materials, equipment
- Bosses and zones unlock stronger build options

PvP:
- Uses the same combat foundation
- Must avoid pay-to-win or unbounded PvE stat dominance
- PvP may use normalization, brackets, or capped scaling if needed
- Ronin Arena prototype is reference material only and must be optimized before reuse

## Ronin Prototype Decision

The Grok Ronin / odachi prototype is **approved as a reference**, not as the final combat implementation.

Before reuse:
- Remove known networking weaknesses
- Improve mobile controls
- Improve exploit resistance
- Separate generic combat logic from PvP round logic
- Make it compatible with the main service architecture
- Support PvE targets and multiple weapon archetypes
- Avoid hard-coding katana-specific assumptions into the shared combat core

## Progression Philosophy

Player progression should gradually unlock:
- New weapon families
- New skills / spells
- Defensive equipment tiers
- Defensive magic
- Build specialization
- Stronger zones / enemies / PvP brackets

The system should encourage build choice rather than one universally optimal loadout.
