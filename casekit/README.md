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

The typed authoring boundary now normalizes both migration schema v1 and the
compositional StoryPack schema v2 into one CaseKit schema version 2 deck:

```text
content/archetypes/*.archetype.json
  + content/stories/*.story.json                 migration input
  + content/stories/<story>/case.json            v2 canonical truth
  + content/stories/<story>/threads.json         v2 connected routes
  + content/stories/<story>/dialogues/*.json     semantic scenes
  + content/stories/<story>/documents/*.json
  + content/stories/<story>/localization/{ru,en}.json
  + content/evidence-modules/*.evidence.json
  -> Read-CaseKitAuthoringDeck
  -> normalized schema v2 deck
```

A CaseArchetype owns reusable investigation grammar, semantic slots, evidence
balance and reveal threshold. A StoryPack owns one coherent canonical truth
and several connected `InvestigationThread` chains. Each thread combines a
lead with one or more evidence actions and explicit results: revealed facts,
next steps, unlocked threads and journal feedback. EvidenceModules implement
reusable in-game actions such as source dialogue, document search, witness
testimony and timed actions inside quest areas.

The first deck contains `paper-trail-witness`, `missing-traveler` and four core
EvidenceModules. The loader validates module ports, semantic slot bindings,
fact and thread references, one-shot confidence, a reachable reveal threshold,
out-of-order presentation variants, typed `{{slot.field}}` templates and exact
Russian/English asset-key parity. Anonymous-capable slots cannot use `.name`.

`timed-area-listening` steps require an explicit activation contract:

```json
"activation": {
  "mode": "timed-area-action",
  "availableFromHour": 10,
  "availableUntilHour": 22,
  "durationHours": 2
}
```

The step owns one area guidance target and no speaker bindings. Entering the
compiled quest area exposes an aimless **F** action. The runtime yields to any
vanilla usable object, rejects combat/dialogue and out-of-hours attempts, then
opens the native time-skip flow and grants the configured one-shot evidence.

Schema v2 lets one StoryPack compose several InvestigationArchetypes while
preserving one canonical truth. Its connected fact graph must reach the
configured confidence threshold and satisfy an explicit `identityRequirement`:
`allOf` requires every listed hard fact, while `anyOf` accepts any one listed
hard fact. Legacy `requiredFacts` compile to `allOf`. Dialogue
definitions use semantic scene presets (`standing-conversation`,
`seated-tavern`, `lying-interrogation`); raw camera GUIDs, animation names and
world coordinates are rejected. RU/EN localization must have exact key parity.

The isolated compatibility solver is also implemented:

```text
normalized v2 StoryPack + semantic world index
  -> Resolve-CaseKitCompatibility
  -> accepted finite bindings + exact settlement rejections
```

It filters capabilities and victim policy, prevents one entity from filling
conflicting slots, renders both languages against concrete identities, ranks
bindings by authored preference, identity quality and stable GUID, applies a
deterministic per-combination cap and derives stable IDs from the complete
binding seed. An incompatible settlement is diagnostic only. An active
StoryPack with no playable variant or unmet explicit regional coverage fails;
draft packs may remain incomplete and are never packaged.

The authored KCD2 materialization boundary is active in the build:

```text
StoryPacks + archetypes + EvidenceModules
  + semantic world index + settlement profiles
  + stable-ID registry + KCD2 adapter metadata
  -> casekit/cli/Compile-CaseKit.ps1
  -> shared CompiledCaseDefinition + finite concrete variants
  -> generated CaseVariant root
  -> tools/Compile-CaseSpecs.ps1 -CaseVariantRoot
  -> unchanged native emitters
```

Shared story, dialogue, document and localization definitions are emitted once;
variants carry only stable identity, settlement and concrete bindings. Stable
case/evidence codes live outside StoryPack prose. The current 1001/2001 route is
byte-identical to direct legacy compilation, excluding the dedicated runtime
variant catalog that only authored definitions can populate. The build keeps
several finite bindings per story/settlement and marks only variants backed by
the current native quest presentation as `native_ready`.

Dark Passenger selects one compatible live target from that catalog, persists
`variantCode`, the previous anti-repeat identity and all concrete bindings, then
creates one `CaseInstance` with bound `SceneInstances`. `SceneDirector` reuses
the existing evidence and lead adapters idempotently. Save/load and Lua reload
restore the same selection; streamed-out actors defer and retry resolution
without rerolling. The two old CaseSpecs and their binding manifest now live
under `content/migration` only as a parity baseline; production compilation
cannot fall back to them implicitly.

An optional StoryPack `trophyDefinition` is compiled per concrete variant. The
central `bird-feather` KCD2 preset owns one shared, permanent, weightless loot
class; variants reuse that class and keep only their contextual story
description. After selected-target death, `dptrophy.lua` requests native quest
graph creation, moves exactly one newly created instance to the corpse and
persists `pending -> placed -> collected`. A saved player-inventory baseline
distinguishes the new trophy from feathers collected in earlier cases. Corpse
and Henry inventory reconciliation, snapshot-based corpse recovery and polling
make save/load, Lua reload, repeated death signals and entity streaming
idempotent. The trophy intentionally bypasses the native quest-item placement
bridge so repeated Cases can accumulate feathers without consuming request
signals.

Every physical evidence action declares `item.classification` (`quest` or
`loot`) and `item.retention` (`case` or `permanent`). Missing or unknown values
fail authoring validation. Native quest items use one reusable transient signal
per unique item class, not per variant or runtime instance. The current build
therefore emits signals only for its two quest documents; ordinary loot and the
shared Bloodied Feather are excluded.

The KCD2 backend emits a versioned `cleanup_manifest` for every concrete
variant. It contains the exact evidence codes, availability roles, signal buff
GUIDs, scene IDs and physical-item destinations owned by one generated Case.
`dpcaselifecycle.lua` is the only executor: it deletes `retention=case`
artifacts, disables presentation adapters and cancels placement requests while
preserving `retention=permanent` trophies and replay history. Presentation is
reissued only after the native quest activation timer, which makes fresh start
and save restoration converge on the same journal state.

Guidance follows the same ownership model:

```text
step GuidanceTarget -> concrete actor/entity/place/area binding
  -> hidden signal buff -> regional Skald objective + Marker
  -> Lua visibility policy
```

Actor markers compile to `SoulAsset` aliases backed by a concrete `soulGuid`.
Entity and point-place markers compile to linked `InteractionTriggerAsset`
aliases. Area guidance reuses an existing `DP_SearchArea_*` alias without
redeclaring its `TriggerAreaAsset`. Unsupported optional targets use the
explicit journal fallback; mandatory targets reject the variant. Lua toggles
only finite, precompiled signal buffs using `step-active`, `facts-known` or
`target-revealed` visibility, and the cleanup manifest owns every signal GUID.

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
pwsh -NoProfile -File '.\casekit\tests\Test-CompatibilitySolver.ps1'
pwsh -NoProfile -File '.\casekit\tests\Test-Kcd2Materializer.ps1'
pwsh -NoProfile -File '.\casekit\tests\Test-AuthoredCompilerCli.ps1'
pwsh -NoProfile -File '.\casekit\tests\Test-Kcd2BackendAdapter.ps1'
pwsh -NoProfile -File '.\tests\Test-CaseKitParity.ps1'
pwsh -NoProfile -File '.\tests\Test-CaseVariantSelection.ps1'
pwsh -NoProfile -File '.\tests\Test-CaseSceneMaterialization.ps1'
pwsh -NoProfile -File '.\tests\Test-CaseTrophyCompiler.ps1'
pwsh -NoProfile -File '.\tests\Test-CaseGuidanceCompiler.ps1'
pwsh -NoProfile -File '.\tests\Test-NonlinearEvidenceRuntime.ps1'
pwsh -NoProfile -File '.\tests\Test-QuestItemPlacementBackend.ps1'
pwsh -NoProfile -File '.\tests\Test-TargetTrophyRuntime.ps1'
```

The compiler-boundary test invokes the real existing
`tools/CaseSpecCompiler.psm1` and requires byte-identical Lua plus equivalent
compatibility and native-wiring output.

## Current migration boundary

The finite CaseVariant root is the production native-compiler input. Direct
`-CaseRoot` compilation remains available only when both migration paths are
passed explicitly. `Build-Mod.ps1` always starts from authored StoryPacks,
profiles, stable IDs and the KCD2 adapter. Exact legacy artifact parity is a
test gate for native assets, not a runtime dependency. The authored-only
`dp_case_variant_catalog.lua` is verified separately because legacy CaseSpecs
do not contain the compiled semantic definitions needed to build it.
