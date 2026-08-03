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

The typed authoring boundary is implemented as CaseKit schema version 1:

```text
content/archetypes/*.archetype.json
  + content/stories/*.story.json
  + content/evidence-modules/*.evidence.json
  -> Read-CaseKitAuthoringDeck
  -> validated InvestigationThreads + bilingual assets
```

A CaseArchetype owns reusable investigation grammar, semantic slots, evidence
balance and reveal threshold. A StoryPack owns one coherent canonical truth
and several connected `InvestigationThread` chains. Each thread combines a
lead with one or more evidence actions and explicit results: revealed facts,
next steps, unlocked threads and journal feedback. EvidenceModules implement
reusable in-game actions such as source dialogue, document search, witness
testimony and overheard dialogue.

The first deck contains `paper-trail-witness`, `missing-traveler` and four core
EvidenceModules. The loader validates module ports, semantic slot bindings,
fact and thread references, one-shot confidence, a reachable reveal threshold,
out-of-order presentation variants, typed `{{slot.field}}` templates and exact
Russian/English asset-key parity. Anonymous-capable slots cannot use `.name`.

StoryPack content is authored rather than assembled from unrelated narrative
fragments. Settlement, concrete actors and clue order may vary while the
canonical crime, motive and causal history remain intact.

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
pwsh -NoProfile -File '.\casekit\tests\Test-CaseBuilderContracts.ps1'
```

The compiler-boundary test invokes the real existing
`tools/CaseSpecCompiler.psm1` and requires byte-identical Lua plus equivalent
compatibility and native-wiring output.

## Current migration boundary

The new deck is not yet an active mod input. Current CaseSpecs and
`config/case-settlement-bindings.json` remain the source of the shipping
artifacts. The next milestone resolves authored threads against semantic world
profiles and materializes finite neutral CaseVariants. Native emitters stay
behind the unchanged output port until parity is proven.
