# Creative Team Roles

The creative team collaborates with the engineering AI team through GitHub.

## Creative Roles

### Art Planner
Primary responsibility:
- Visual direction
- World theme
- Environment style
- Character / enemy visual language
- Weapon visual families
- UI visual direction
- Asset priority planning

Deliverables:
- docs/ART_DIRECTION.md
- asset priority list
- reference moodboards or prompt briefs
- environment / character / weapon art briefs

### Art Supervisor
Primary responsibility:
- Quality control
- Visual consistency
- Review of generated or imported assets
- Style compliance
- Readability in gameplay
- Mobile performance / visual complexity review

Deliverables:
- docs/ART_REVIEW_GUIDE.md
- review comments on art-related PRs
- approval / revision notes

### Animation Designer
Primary responsibility:
- Character locomotion animation language
- Idle / walk / run / jump / fall / landing
- Melee / ranged / magic / defense animation direction
- Dodge / block / parry / hit reaction / knockback / death
- Combo transition and weapon handling rules
- Boss attack telegraph readability
- Mobile readability and animation performance constraints

Deliverables:
- docs/ANIMATION_DIRECTION.md
- animation state/action matrix
- combat timing/readability rules
- animation asset priority list
- implementation handoff notes for engineering

Boundaries:
- Does not redefine gameplay rules or combat balance.
- Does not replace Art Planner's overall visual direction.
- Does not own production gameplay code.
- Raises cross-discipline conflicts to ChatGPT Technical Lead.

### Sound Effects Planner
Primary responsibility:
- Combat SFX plan
- Magic SFX plan
- UI feedback sounds
- Environment / ambience effects
- Reward / progression sounds
- Defensive / impact sound language

Deliverables:
- docs/SFX_PLAN.md
- SFX event list
- naming conventions
- implementation priority

### Music Planner
Primary responsibility:
- Musical identity
- Hub / exploration / combat / boss / PvP music structure
- Dynamic music transition plan
- Loop lengths and intensity layers
- Audio mood consistency

Deliverables:
- docs/MUSIC_PLAN.md
- music cue map
- scene / state music table
- implementation priority

## Collaboration Rules

- These roles may all be operated by separate Grok bots.
- Each bot must identify its role in Issue #3 when checking in.
- Each role works through its own GitHub Issue.
- Do not overwrite engineering architecture or gameplay rules.
- Any art/audio decision affecting gameplay clarity or performance must be raised to ChatGPT.
- ChatGPT remains Technical Lead and project-wide coordinator.
- Product Owner remains sammyzomb.
