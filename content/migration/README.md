# CaseKit migration fixtures

This directory preserves pre-CaseKit authoring inputs only for regression and
artifact-parity tests.

- `legacy-cases/` contains the two schema-v2 CaseSpecs that shipped before
  StoryPack compilation became the production source.
- `legacy-case-settlement-bindings.json` is their concrete world-binding
  manifest.
- `legacy-storypacks/` preserves superseded monolithic StoryPack input used by
  migration-contract tests.

`tools/Build-Mod.ps1` must never consume these files. Production authoring lives
under `content/stories`, `content/archetypes`, `content/evidence-modules`, and
`config/settlements`.
