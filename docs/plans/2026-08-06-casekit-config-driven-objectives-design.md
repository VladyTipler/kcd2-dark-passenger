# CaseKit config-driven objectives

## Decision

StoryPack owns every investigation-specific journal objective presentation.
Native KCD2 wiring remains compiler-owned.

One reusable contract is used for lifecycle and guidance objectives:

```json
{
  "nameAsset": "objective.overheard.name",
  "states": {
    "active": "objective.overheard.active"
  }
}
```

Lifecycle objectives live in `case.json` under `journal.objectives`:

- `search`
- `investigation`
- `target`
- `cleanup`

Marker-specific objectives live beside their semantic `guidance` target under
`objective`. Story authors never provide native keys, GUIDs, enum names or XML.

## Materialization

```text
StoryPack objective assets
  -> authoring validation and RU/EN parity
  -> CompiledCaseDefinition
  -> deterministic native localization keys
  -> proven State / ObjectiveVisual / Objective / Log / Marker wiring
```

The compiler maps semantic state names onto the fixed universal quest shell.
Missing presentation uses the current generic Dark Passenger copy as a
compatibility fallback. Authored assets always win.

## Duplicate prevention

The investigation objective remains the broad case stage. A guidance objective
must describe its concrete action. They may be active together, but cannot
accidentally share the generic investigation title and log when StoryPack
presentation is available.

## Scope

- No runtime graph mutation.
- No raw Skald in StoryPack files.
- No new Lua state machine.
- Existing finite guidance signals remain the activation mechanism.
- Existing one-universal-quest-container architecture remains unchanged.

