# CaseKit Area Listening Design

**Date:** 2026-08-13
**Status:** Approved

## Goal

Replace fragile NPC-pair overhearing with a reusable investigation action available anywhere inside a compiled quest area, without aiming at an entity.

## Player flow

1. The active clue displays its authored journal objective and local quest area.
2. Entering that area exposes `F - Listen to conversations`.
3. The action is accepted only from 10:00 through 22:00 and while normal quest interaction is safe.
4. Activation fades the screen, displays `You listen to what people are saying...`, advances game time by two hours and resolves the authored rumor.
5. Resolution awards the clue/confidence, updates the journal and removes the local area prompt.
6. Outside working hours, activation explains that the place is too quiet and does not advance time or the Case.

## Architecture

- Case content declares one reusable `timed-area-action` presentation: area guidance, bilingual prompt/message, availability window, duration and completion signal.
- The native quest graph owns area activation and the existing objective/marker lifecycle.
- One global Lua action layer listens for the F-bound action but handles it only while an active Case exposes an eligible area action.
- The handler validates case generation, active clue, region/area membership, time window and unsafe player states before starting the effect.
- Completion uses the existing save-safe evidence/progress path; no story-specific Lua branch is generated.

## Input isolation

The feature must not change global interaction range or mutate actions attached to NPCs, corpses or containers. F remains a normal game key everywhere else. The area handler runs only with a positive active-area token and yields when a higher-priority vanilla F interaction is available.

## Removal contract

Remove the superseded NPC-pair path completely:

- NPC `Listen` action injection;
- pair proximity/readiness polling;
- staging, teleport and behavior watchdog probes;
- pair-specific runtime state and console commands;
- compiler/runtime fields used only by the old path;
- obsolete focused tests and generated artifacts.

Reusable dialogue compilation and general NPC debug helpers stay only if another live feature owns them.

## Verification

- Unit tests: schema/defaults, working-hours boundary, two-hour duration, one-shot/debounce and fail-closed area token.
- Feature test: StoryPack -> CaseKit -> regional graph/runtime catalog contains the area action and no NPC action/pair dependency.
- Static cleanup test: no obsolete player-facing NPC overhearing action or staging hooks remain.
- Retail acceptance: area visible; prompt appears only inside; F works without aim; ordinary F actions retain normal range; outside-hours denial works; time and clue update exactly once.

