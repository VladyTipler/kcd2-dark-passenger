# CaseKit

CaseKit is the reusable build-time case authoring and compilation boundary
growing inside Dark Passenger.

## Current checkpoint

The first additive seam is implemented:

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

This checkpoint does not change the generated mod, runtime selection or save
schema. Current CaseSpecs and `config/case-settlement-bindings.json` remain the
source of truth while the semantic world index and new authoring contracts are
built later.

## Tests

Run sequentially from the repository root:

```powershell
pwsh -NoProfile -File '.\casekit\tests\Test-CaseKitModule.ps1'
pwsh -NoProfile -File '.\casekit\tests\Test-LegacyAuthoringDeck.ps1'
pwsh -NoProfile -File '.\casekit\tests\Test-LegacyVariants.ps1'
pwsh -NoProfile -File '.\casekit\tests\Test-LegacyBackendParity.ps1'
pwsh -NoProfile -File '.\casekit\tests\Test-LegacyCompilerBoundary.ps1'
```

The compiler-boundary test invokes the real existing
`tools/CaseSpecCompiler.psm1` and requires byte-identical Lua plus equivalent
compatibility and native-wiring output.

## Next boundary

The next milestone replaces the legacy input adapter with a generated semantic
world index, central settlement profiles and typed archetype/story contracts.
Native emitters stay behind the same output port until multiple settlements
and archetypes prove the abstraction.
