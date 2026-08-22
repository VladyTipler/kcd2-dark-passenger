# CaseKit Story Identity Overlay

**Date:** 2026-08-22  
**Status:** Approved

## Goal

Let one authored investigation character be played by any compatible NPC without generating dialogue variants for every vanilla name.

## Decision

Separate the physical game actor from the character portrayed in the case:

- `worldActor` identifies the selected NPC and keeps its entity, Soul, voice profile, schedules and gameplay state;
- `storyIdentity` contains the fixed authored name and localized presentation used by the StoryPack;
- the story identity overrides the visible UI name of both anonymous and already named actors for the lifetime of the case.

The override activates when the case starts, persists across save/load and is removed by case cleanup. The engine-native implementation is a generated `SoulUiNameOverride` node. Lua selects the precompiled variant and activates its existing bridge state; Lua does not mutate Soul data.

## Presentation contract

The identity resolver derives an effective label from the authored name and the selected actor's semantic role:

- generic actor: `Батрак` + `Ян` -> `Батрак Ян`;
- merchant: `Купец` + `Ян` -> `Купец Ян`;
- already named actor: its vanilla personal name is replaced, while a useful profession/title may remain;
- actor without a meaningful role: use the authored name alone.

Each language owns its complete rendered label; word order is not assembled at runtime. Engine entity and Soul identifiers never change.

## Narrative reveal contract

The visible world label may exist from case start, but authored content cannot use the name until an investigation chain reveals its hard identity fact.

Before reveal, dialogue, objectives and journal entries use relationship or direction labels such as `бывший друг жениха` or `мужчина, которого видели у поляны`. After reveal, `storyIdentity.name` becomes available to authored templates, journal updates, dialogue and target guidance.

The authoring validator must fail if a reachable pre-reveal asset references the protected name. Every name reveal is tied to an explicit hard identity fact.

## Generation and persistence

- StoryPack defines one fixed localized identity per semantic character.
- Compatibility selects a compatible physical actor, including gender/role constraints.
- Materialization renders one identity overlay for every finite native-ready actor variant.
- Runtime persists the chosen variant before presentation, so reload cannot change actor or identity.
- Repeated cases receive a new `caseGeneration`; only its selected overlay is active.
- Cleanup and recovery deactivate stale overlays before another case is presented.

Dialogue audio remains actor-specific by voice profile but text-specific by one authored story identity. This avoids multiplying authored dialogue by every possible vanilla NPC name.

## Failure policy

- unresolved actor role: fall back to the authored personal name, not an invented profession;
- missing localization or hard-identity gate: fail the build;
- multiple active identity overlays for one case generation: fail validation and suppress presentation;
- stale save state: cleanup old overlay, then restore only the persisted current variant.

## Acceptance

1. An anonymous `Странник` selected for a case receives the configured story label at case start.
2. An already named NPC receives the same story identity without changing its entity/Soul IDs, voice or AI.
3. Pre-reveal generated content contains no protected personal name.
4. A hard identity fact unlocks name-bearing journal and dialogue content.
5. Save/load restores the same actor and label.
6. Case cleanup restores the vanilla UI name.

