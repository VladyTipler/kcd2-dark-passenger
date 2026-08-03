# CaseKit

CaseKit is the reusable build-time case authoring and compilation boundary
growing inside Dark Passenger.

## Current checkpoints

The additive compatibility seam remains intact:

```text
legacy CaseSpec + settlement bindings
  -> Read-CaseKitAuthoringDeck
  -> Resolve-CaseKitVariants
  -> neutral CaseVariant
  -> ConvertTo-CaseKitBackendInput
  -> unchanged CaseSpecCompiler backend
```

The neutral variant separates:

- case identity, selection weight and reveal threshold;
- target policy;
- concrete region, settlement and role bindings;
- authored crime, text and localization;
- evidence definitions;
- KCD2-native presentation hints owned by the output adapter.

The semantic world input boundary is also implemented:

```text
KCD2 objects XML + soul table
  -> raw actors + stashes
  -> New-CaseKitWorldIndex
  -> config/world-semantic-index.json
  + config/settlements/*.profile.json
```

The tracked index currently contains all 1,640 joined settlement actors and
2,872 settlement stashes across both regions. Candidate policy remains a
separate projection: only the existing 951 reviewed actors receive
`victim.eligible`. A stash receives `container.stash`; only a reviewed
settlement profile may add `container.evidence`.

The raw export preserves its old `candidates` field for the shipping victim
generator and adds the complete `actors` field for CaseKit. Rebuilding
`victim-candidates.json` therefore remains byte-identical and does not renumber
save-sensitive slots or aliases.

Pritoky and Zhelejov profiles contain only reviewed overrides. They confirm
case roles, evidence containers and typed localized identity without copying
world coordinates or engine IDs into story packs.

These checkpoints do not change the generated mod, runtime selection or save
schema. Current CaseSpecs and `config/case-settlement-bindings.json` remain the
active source of truth until authoring-contract parity passes.

## Build the world index

First export raw game data with explicit source paths or the existing
`KCD2_REFERENCE_DATA_ROOT` / `KCD2_DEV_ROOT` environment variables. Then run:

```powershell
pwsh -NoProfile -File '.\casekit\cli\Build-WorldSemanticIndex.ps1' `
  -RawWorldPath '.\evidence\world-candidates.raw.json' `
  -VictimCatalogPath '.\config\victim-candidates.json' `
  -OutputPath '.\config\world-semantic-index.json'
```

## Tests

Run sequentially from the repository root:

```powershell
pwsh -NoProfile -File '.\casekit\tests\Test-CaseKitModule.ps1'
pwsh -NoProfile -File '.\casekit\tests\Test-LegacyAuthoringDeck.ps1'
pwsh -NoProfile -File '.\casekit\tests\Test-LegacyVariants.ps1'
pwsh -NoProfile -File '.\casekit\tests\Test-LegacyBackendParity.ps1'
pwsh -NoProfile -File '.\casekit\tests\Test-LegacyCompilerBoundary.ps1'
pwsh -NoProfile -File '.\casekit\tests\Test-Kcd2WorldExporter.ps1'
pwsh -NoProfile -File '.\casekit\tests\Test-WorldSemanticIndex.ps1'
pwsh -NoProfile -File '.\casekit\tests\Test-WorldSemanticIndexCli.ps1'
pwsh -NoProfile -File '.\casekit\tests\Test-IdentityResolver.ps1'
```

The compiler-boundary test invokes the real existing
`tools/CaseSpecCompiler.psm1` and requires byte-identical Lua plus equivalent
compatibility and native-wiring output.

## Next boundary

The next milestone adds typed archetype, story and evidence-module contracts
over this index. Native emitters stay behind the unchanged output port until
multiple settlements and archetypes prove the abstraction.
