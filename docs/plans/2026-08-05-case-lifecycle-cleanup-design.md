# Case Lifecycle Cleanup Design

## Goal

Make every generated case generation self-contained and replayable: closing or replacing a case removes only its temporary artifacts, while permanent trophies, ordinary loot, and replay history survive.

## Decision

Use a hybrid contract:

- CaseKit generates an exact `cleanup_manifest` for every compiled variant.
- One runtime module, `DarkPassengerCaseLifecycle`, executes manifests.
- Generated variants expose data, not bespoke cleanup logic.
- Cleanup and activation are separate phases. Activation is delayed after cleanup so CryEngine cannot observe remove/add of the same buff in one frame.

Pure runtime discovery was rejected because it cannot safely infer ownership. Per-variant generated Lua functions were rejected because they duplicate lifecycle logic and make schema upgrades unsafe.

## Generated manifest

Each native-ready variant contains:

- `case_code`, `variant_code`, and generated schema version;
- evidence codes owned by the generation;
- temporary signal buffs: journal states, dialogue variants, and overheard availability;
- lead availability roles (`innkeeper`, `witness`, `overheard`);
- entity contexts owned by native dialogue/overheard bridges;
- physical items with GUID, classification, retention, and placement backend;
- generated scene identifiers;
- permanent items such as trophies, explicitly marked and therefore preserved.

The compiler rejects a generated artifact without lifecycle ownership or retention.

## Runtime API

`DarkPassengerCaseLifecycle.ClearCaseArtifacts(generation, reason)`:

1. resolves the selected variant and manifest;
2. ignores an already-cleared generation;
3. disables lead availability through the owning runtime adapters;
4. removes generated temporary signal buffs and contexts;
5. removes only `retention = "case"` items from the player and stale world/container placement requests;
6. clears materialized scene runtime state;
7. preserves trophies, loot, and StoryPack replay history;
8. records cleanup generation only after all mandatory cleanup steps complete.

`DarkPassengerCaseLifecycle.PrepareCaseGeneration(generation)` performs a cleanup barrier and schedules lead-plan publication on the next engine tick. Repeating calls are idempotent.

## Integration

- Before selecting a replacement target: clear the prior generation.
- After a new evidence registry is initialized: prepare the new generation and publish availability after the barrier.
- On resolved hunt: clear case-retained artifacts.
- On save/load: reconcile the active generation; never clear it merely because Lua reloaded.

## Failure behavior

- Missing manifest: refuse to present the generated case and log the variant ID.
- Optional world entity unavailable: record deferred cleanup and retry.
- Player inventory unavailable: do not commit cleanup generation.
- Permanent artifact in a removal request: reject and log.

## Verification

- Compiler test proves complete manifests and retention classification.
- Lua lifecycle self-test proves idempotency, preservation, and two-phase activation.
- Integration test crosses compiler output into the runtime contract.
- Live test repeats `missing_traveler`: Lavrentiy's rumor is available again, evidence starts pending, and the journal/area are present.

## Unresolved questions

None.
