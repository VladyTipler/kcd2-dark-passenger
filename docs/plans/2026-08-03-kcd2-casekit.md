# KCD2 CaseKit Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a reusable CaseBuilder/CaseCompiler toolchain that turns authored archetypes and story packs into validated, settlement-compatible Dark Passenger CaseVariants and existing native KCD2 artifacts.

**Architecture:** A self-contained `casekit/` module uses ports and adapters. Its pure PowerShell core owns typed authoring contracts, identity, binding and compatibility; KCD2 adapters import world data and materialize neutral CaseVariants through the existing proven native compiler backend. Dark Passenger remains a content/runtime consumer, not a dependency of CaseKit.

**Tech Stack:** PowerShell 7 modules and CLI scripts, JSON authoring data, generated Lua/XML/localization, existing KCD2 catalogs and current script-based test harness.

---

## Guardrails

- Keep one universal regional quest container; do not generate a quest graph per story.
- Treat `CaseDefinition` and `SceneDefinition` as build-time content, and
  `CaseInstance` and `SceneInstance` as persisted runtime state.
- Runtime may resolve live actors, place predefined evidence and activate
  compiled assets; it must not generate dialogue, roles, cameras or quest XML.
- Let one StoryPack compose several `InvestigationArchetype` mini-chains.
- Keep existing numeric codes, enum values and aliases as save schema.
- Preserve `tools/CaseSpecCompiler.psm1` as native backend until parity passes.
- Generated files are disposable; authored files are the source of truth.
- Run test scripts sequentially because several generators share `build/mod`.
- Do not require a running game until the final focused live acceptance.
- Treat one StoryPack as one coherent authored truth with controlled world,
  actor, clue-order and delivery variation; do not combine random narrative
  fragments into a case.
- Model a StoryPack as several connected `InvestigationThread` chains:
  lead -> search or communication -> result. Threads may branch, converge and
  tolerate out-of-order clue discovery.
- Keep the long-term content target (roughly ten stories per roughly ten
  archetypes) outside the first contract slice; prove the authoring model with
  one archetype and one story first. Target roughly twenty polished stories
  for the initial playable content milestone before expanding toward one
  hundred base stories.

## Immediate implementation slice

The plan below is the full roadmap, not one refactoring batch. The next
implementation slice is additive and stops after proving the seam:

1. create the isolated CaseKit module and neutral CaseVariant model;
2. add a legacy KCD2 input adapter over the current CaseSpecs, catalogs and
   settlement bindings;
3. resolve the two already proven Pritoky/Zhelejov bindings through that API;
4. feed the neutral variant back into the unchanged native compiler and prove
   semantic output parity.

During this slice:

- do not move native emitters out of `tools/CaseSpecCompiler.psm1`;
- do not delete or rename current CaseSpecs or
  `config/case-settlement-bindings.json`;
- do not change Lua runtime selection or save schema;
- do not add a third story merely to exercise the abstraction;
- stop for review as soon as the adapter produces byte/semantic-equivalent
  Pritoky and Zhelejov artifacts.

World-wide semantic indexing, content migration and multi-variant runtime
selection are later milestones. They begin only after this low-risk seam is
green.

### Task 1: Scaffold the reusable CaseKit boundary - completed

**Files:**
- Create: `casekit/CaseKit.psd1`
- Create: `casekit/CaseKit.psm1`
- Create: `casekit/core/CaseKit.Model.psm1`
- Create: `casekit/tests/Test-CaseKitModule.ps1`
- Create: `casekit/README.md`

**Step 1: Write the failing module contract test**

Create `casekit/tests/Test-CaseKitModule.ps1` and assert that importing the
manifest exports only the intended facade:

```powershell
$module = Join-Path $PSScriptRoot '..\CaseKit.psd1'
Import-Module $module -Force

$expected = @(
    'Read-CaseKitAuthoringDeck',
    'New-CaseKitWorldIndex',
    'Resolve-CaseKitVariants',
    'Write-CaseKitBuild'
)
$actual = @(Get-Command -Module CaseKit | Select-Object -ExpandProperty Name)
if (@(Compare-Object $expected $actual).Count -ne 0) {
    throw "Unexpected CaseKit facade: $($actual -join ', ')"
}
```

Also assert that `New-CaseKitVariant` returns a neutral object with no
`DarkPassenger*` property or runtime global.

**Step 2: Run the test and verify failure**

Run:

```powershell
pwsh -NoProfile -File '.\casekit\tests\Test-CaseKitModule.ps1'
```

Expected: FAIL because `casekit/CaseKit.psd1` does not exist.

**Step 3: Add the minimal module facade and model**

Implement the manifest, root module and a strict constructor:

```powershell
function New-CaseKitVariant {
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [Parameter(Mandatory)][string]$VariantId,
        [Parameter(Mandatory)][string]$ArchetypeId,
        [Parameter(Mandatory)][string]$StoryId,
        [Parameter(Mandatory)]$Binding,
        [Parameter(Mandatory)][object[]]$Evidence
    )

    [ordered]@{
        schemaVersion = 1
        caseId = $CaseId
        variantId = $VariantId
        archetypeId = $ArchetypeId
        storyId = $StoryId
        binding = $Binding
        evidence = @($Evidence)
    }
}
```

Keep non-facade commands private through `FunctionsToExport`.

**Step 4: Run the test and verify success**

Run the command from Step 2.

Expected: `RESULT: PASS` and exactly four public facade commands.

**Step 5: Commit**

```powershell
git add -- casekit
git commit -m "feat: scaffold reusable casekit module"
```

### Task 2: Generate the KCD2 semantic world index - completed

Implementation note: the raw exporter keeps legacy `candidates` byte-stable
for victim-slot generation and adds complete `actors` plus settlement
`containers` for CaseKit. The semantic index is built from `actors`, then
annotated by the unchanged victim catalog; it does not mistake the filtered
951-target pool for the whole world.

**Files:**
- Create: `casekit/adapters/kcd2/CaseKit.Kcd2World.psm1`
- Create: `casekit/cli/Build-WorldSemanticIndex.ps1`
- Create: `casekit/tests/fixtures/world/actors.json`
- Create: `casekit/tests/Test-WorldSemanticIndex.ps1`
- Modify: `tools/Export-WorldVictimCandidates.ps1`
- Create: `config/world-semantic-index.json`

**Step 1: Write failing world-index tests**

Use a small fixture containing a named innkeeper, an anonymous tavern worker,
a story-critical actor and a container. Assert normalized records contain:

```text
entityName, entityGuid, soulGuid, characterName, factionName
region, settlement, position, homeLinks, workLinks
identityMode, capabilities[], policyFlags[]
```

Assert output ordering is deterministic by
`region, settlement, entityName, entityGuid` and rejects duplicate GUIDs.

**Step 2: Run and verify failure**

```powershell
pwsh -NoProfile -File '.\casekit\tests\Test-WorldSemanticIndex.ps1'
```

Expected: FAIL because the KCD2 world adapter is missing.

**Step 3: Implement normalization and exporter integration**

Add pure conversion in `CaseKit.Kcd2World.psm1`:

```powershell
function ConvertTo-CaseKitWorldActor {
    param([Parameter(Mandatory)]$Actor)

    [ordered]@{
        entityName = [string]$Actor.entityName
        entityGuid = [string]$Actor.entityGuid
        soulGuid = [string]$Actor.soulGuid
        characterName = [string]$Actor.characterName
        factionName = [string]$Actor.factionName
        region = [string]$Actor.region
        settlement = [string]$Actor.settlement
        position = $Actor.position
        homeLinks = @($Actor.homeLinks)
        workLinks = @($Actor.workLinks)
        identityMode = if ($Actor.characterName) { 'named' } else { 'anonymous' }
        capabilities = @(Get-CaseKitDerivedCapabilities -Actor $Actor)
        policyFlags = @($Actor.policyFlags)
    }
}
```

Extend the existing exporter only where source fields are missing; do not
duplicate its game-data parsing inside CaseKit.

**Step 4: Run focused and real-data checks**

```powershell
pwsh -NoProfile -File '.\casekit\tests\Test-WorldSemanticIndex.ps1'
pwsh -NoProfile -File '.\casekit\cli\Build-WorldSemanticIndex.ps1' `
  -VictimCatalogPath '.\config\victim-candidates.json' `
  -OutputPath '.\config\world-semantic-index.json'
```

Expected: PASS; repeated generation is byte-identical and both regions exist.

**Step 5: Commit**

```powershell
git add -- casekit tools/Export-WorldVictimCandidates.ps1 config/world-semantic-index.json
git commit -m "feat: generate semantic world index"
```

### Task 3: Resolve identity and central settlement profiles - completed

Implementation note: non-generic localization keys enter the raw index as
`unresolved`, not automatically `named`. Pritoky and Zhelejov profiles are the
reviewed authority that promotes concrete actors to `named` or `titled` and
confirms evidence containers.

**Files:**
- Create: `casekit/core/CaseKit.Identity.psm1`
- Create: `casekit/core/CaseKit.Profiles.psm1`
- Create: `casekit/tests/Test-IdentityResolver.ps1`
- Create: `config/settlements/pritoky.profile.json`
- Create: `config/settlements/zelejov.profile.json`

**Step 1: Write failing identity tests**

Cover all three modes:

- named actor uses the game localization key and reviewed localized name;
- titled actor uses a unique verified title;
- anonymous actor never receives an invented name and gets a precise
  direction label from role plus workplace.

Add a regression for Zhelejov: `tzel_bretislav` resolves to the reviewed
Russian player-facing identity `Богуслав`, `батрак`, while the engine identity
and GUID stay unchanged.

**Step 2: Run and verify failure**

```powershell
pwsh -NoProfile -File '.\casekit\tests\Test-IdentityResolver.ps1'
```

Expected: FAIL because identity/profile modules do not exist.

**Step 3: Implement profiles as overrides, not duplicate catalogs**

Profile records reference stable entity IDs and add only reviewed semantics:

```json
{
  "entityName": "tzel_bretislav",
  "addCapabilities": ["role.farmhand", "workplace.inn_stable"],
  "identity": {
    "mode": "named",
    "ru": { "name": "Богуслав", "occupation": "батрак" },
    "en": { "name": "Bretislav", "occupation": "farmhand" }
  }
}
```

Reject profile references absent from the world index and reject ambiguous
`titled` labels inside one settlement.

**Step 4: Run tests**

```powershell
pwsh -NoProfile -File '.\casekit\tests\Test-IdentityResolver.ps1'
pwsh -NoProfile -File '.\tests\Test-ZhelejovBindings.ps1'
```

Expected: both PASS; existing live-proven entity bindings remain unchanged.

**Step 5: Commit**

```powershell
git add -- casekit/core casekit/tests config/settlements
git commit -m "feat: resolve semantic actor identities"
```

### Task 4: Add CaseBuilder authoring contracts and typed templates - completed

Implementation note: CaseKit schema version 1 now models each coherent
StoryPack as connected `InvestigationThread` records with typed leads, evidence
actions and results. The first production authoring deck contains
`paper-trail-witness`, `missing-traveler` and four core EvidenceModules, but is
not yet connected to the shipping compiler. The 24-check contract suite covers
RU/EN parity, typed templates, anonymous identity, module ports and kinds,
fact/thread/step references, structural reachability, out-of-order
presentation and reachable confidence.

**Files:**
- Create: `casekit/core/CaseKit.Authoring.psm1`
- Create: `casekit/core/CaseKit.Templates.psm1`
- Create: `casekit/tests/Test-CaseBuilderContracts.ps1`
- Create: `casekit/tests/fixtures/authoring/valid/`
- Create: `casekit/tests/fixtures/authoring/invalid/`
- Create: `content/archetypes/paper-trail-witness.archetype.json`
- Create: `content/stories/missing-traveler.story.json`
- Create: `content/evidence-modules/core.evidence.json`

**Step 1: Write failing authoring and template tests**

Assert the loader validates:

- archetype required/optional slots, allowed investigation-thread grammar and
  evidence topology;
- one coherent StoryPack truth, declared facts and several connected
  `InvestigationThread` chains;
- every thread has a lead, one or more search/communication evidence steps and
  at least one declared result;
- multiple leads may converge on one evidence node and out-of-order discovery
  has an authored conditional presentation path;
- story dialogue, document, clue and journal assets have identical
  Russian/English key sets;
- evidence module capability requirements and one-shot confidence;
- placeholders matching `{{slot.property}}`;
- a reachable confidence path to 70.

Required error cases:

```text
unknown slot in template
anonymous actor referenced through .name
missing English key
unknown evidence module
thread result references unknown fact
dangling next-thread reference
maximum reachable confidence below 70
```

**Step 2: Run and verify failure**

```powershell
pwsh -NoProfile -File '.\casekit\tests\Test-CaseBuilderContracts.ps1'
```

Expected: FAIL because the authoring loader is missing.

**Step 3: Implement strict parsing and rendering**

Keep rendering pure and fail closed:

```powershell
function Expand-CaseKitTemplate {
    param([string]$Text, [hashtable]$Bindings)

    return [regex]::Replace($Text, '\{\{(?<slot>\w+)\.(?<field>\w+)\}\}', {
        param($match)
        $slot = $match.Groups['slot'].Value
        $field = $match.Groups['field'].Value
        if (-not $Bindings.ContainsKey($slot)) {
            throw "Unknown template slot '$slot'."
        }
        $value = $Bindings[$slot].$field
        if ([string]::IsNullOrWhiteSpace([string]$value)) {
            throw "Template value '$slot.$field' is unavailable."
        }
        [string]$value
    })
}
```

Use `missing-traveler` as the first coherent dossier: its innkeeper lead,
pre-seeded ledger, stablehand testimony and optional overheard clue become
connected threads over one shared fact graph. Do not migrate current CaseSpecs
yet; this task proves the new authoring layer in isolation.

**Step 4: Run tests**

```powershell
pwsh -NoProfile -File '.\casekit\tests\Test-CaseBuilderContracts.ps1'
```

Expected: PASS with deterministic diagnostics naming the exact source path.

**Step 5: Commit**

```powershell
git add -- casekit content/archetypes content/stories content/evidence-modules
git commit -m "feat: add typed casebuilder contracts"
```

### Task 5: Extend authoring to compositional StoryPack schema v2

**Status:** Done. Schema v1 remains readable and normalizes to v2; the focused
contract suite passes 41 checks.

**Files:**
- Modify: `casekit/core/CaseKit.Authoring.psm1`
- Modify: `casekit/core/CaseKit.Model.psm1`
- Modify: `casekit/tests/Test-CaseBuilderContracts.ps1`
- Create: `casekit/tests/fixtures/authoring/v2/`

**TDD contract:**

1. Write failing tests for a package split across `case.json`, `threads.json`,
   dialogues, documents and exact RU/EN localization parity.
2. Require composition of several `InvestigationArchetype` ids, a connected
   fact graph, reachable confidence and at least one reachable hard identity
   fact.
3. Validate semantic scene presets without exposing native GUIDs or animation
   names to StoryPack content.
4. Keep schema v1 readable as a migration input; emit normalized schema v2.

**Verification:**

```powershell
pwsh -NoProfile -File '.\casekit\tests\Test-CaseBuilderContracts.ps1'
```

Expected: v1 still passes; valid v2 normalizes deterministically; invalid
graph, localization or scene preset fails with an exact source path.

### Task 6: Implement deterministic compatibility solving

**Status:** Done. The isolated solver passes 16 focused checks; all 11 CaseKit
suites pass 102 checks without changing shipping artifacts or save state.

**Files:**
- Create: `casekit/core/CaseKit.Compatibility.psm1`
- Create: `casekit/tests/Test-CompatibilitySolver.ps1`
- Create: `casekit/tests/fixtures/compatibility/`

**Step 1: Write failing solver tests**

Test a matrix with:

- one fully compatible settlement;
- one settlement missing a required innkeeper;
- one with two eligible anonymous farmhands;
- one actor incorrectly proposed for conflicting source and target slots;
- one story-critical or dead target;
- deterministic variant ranking and a configurable cap.
- one StoryPack composing several archetypes with intersecting threads;
- one settlement rejection that does not fail the complete build;
- one active StoryPack with zero variants that does fail the build;
- one draft pack and explicit regional coverage contracts.

Expected report shape:

```json
{
  "accepted": [{ "variantId": "...", "bindings": {} }],
  "rejected": [{
    "combination": "paper_trail/missing_traveler/example",
    "reasons": ["required capability role.innkeeper not found"]
  }]
}
```

**Step 2: Run and verify failure**

```powershell
pwsh -NoProfile -File '.\casekit\tests\Test-CompatibilitySolver.ps1'
```

Expected: FAIL because the solver is missing.

**Step 3: Implement search, constraints and stable ranking**

The solver must:

1. filter candidates by all required capabilities and policy flags;
2. allocate slots without conflicts;
3. render and validate both languages against the candidate binding;
4. prove playable evidence and confidence reachability;
5. prove at least one reachable hard identity fact;
6. enforce StoryPack and deck-level coverage contracts;
7. sort by authored preference, identity quality and stable GUID;
8. emit at most `MaxVariantsPerCombination`.

Use deterministic variant IDs derived from the full binding seed through the
existing stable GUID/hash convention.

**Step 4: Run tests twice and compare hashes**

```powershell
pwsh -NoProfile -File '.\casekit\tests\Test-CompatibilitySolver.ps1'
```

Expected: PASS; identical accepted order and report bytes on repeat.

**Step 5: Commit**

```powershell
git add -- casekit/core/CaseKit.Compatibility.psm1 casekit/tests
git commit -m "feat: solve compatible case bindings"
```

### Task 7: Materialize neutral variants through the proven native backend

**Status:** Done. The neutral materializer passes 13 checks; the disk/compiler
parity suite proves byte-identical native artifacts for cases 1001 and 2001.
All 12 CaseKit suites pass. `Build-Mod.ps1` now routes through a generated
CaseVariant root while legacy CaseSpecs remain the migration source.

**Files:**
- Create: `casekit/adapters/kcd2/CaseKit.Kcd2Materializer.psm1`
- Create: `casekit/cli/Compile-CaseKit.ps1`
- Create: `casekit/tests/Test-Kcd2Materializer.ps1`
- Create: `tests/Test-CaseKitParity.ps1`
- Modify: `tools/Compile-CaseSpecs.ps1`
- Modify: `tools/Build-Mod.ps1`

**Step 1: Write failing adapter and parity tests**

Compile the Pritoky and Zhelejov fixtures into neutral CaseVariants, adapt them
to the current `CaseSpecCompiler.psm1`, and compare semantic output with the
current generated artifacts:

- case/evidence codes;
- Lua runtime fields;
- native aliases, roles and contexts;
- dialogue and item GUIDs;
- Russian/English localization keys and values;
- regional enum names and legacy aliases.

Ignore only generator comments and stable ordering changes explicitly approved
in the fixture.

**Step 2: Run and verify failure**

```powershell
pwsh -NoProfile -File '.\casekit\tests\Test-Kcd2Materializer.ps1'
pwsh -NoProfile -File '.\tests\Test-CaseKitParity.ps1'
```

Expected: FAIL because no KCD2 materializer exists.

**Step 3: Implement the adapter without moving emitters**

Map neutral variants into the legacy normalized CaseSpec object expected by
`tools/CaseSpecCompiler.psm1`. Update `Compile-CaseSpecs.ps1` to accept either:

```text
-CaseVariantRoot <generated variants>  preferred
-CaseRoot <legacy CaseSpecs>            migration fallback
```

Update `Build-Mod.ps1` to call `casekit/cli/Compile-CaseKit.ps1`, then pass its
variant output into the existing native compiler.

Emit shared dialogue, localization, document and semantic scene definitions
once where possible. Per-settlement variants contain concrete bindings and
stable aliases rather than duplicate an entire native registry without need.
The first semantic scene adapter is `lying-interrogation`, built from the
live-proven lying-character camera rig.

**Step 4: Run focused integration sequentially**

```powershell
pwsh -NoProfile -File '.\casekit\tests\Test-Kcd2Materializer.ps1'
pwsh -NoProfile -File '.\tests\Test-CaseKitParity.ps1'
pwsh -NoProfile -File '.\tests\Test-CaseSpecCompiler.ps1'
pwsh -NoProfile -File '.\tests\Test-CaseSpecGeneration.ps1' `
  -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
```

Expected: all PASS and no generated save-schema drift.

**Step 5: Commit**

```powershell
git add -- casekit tools/Compile-CaseSpecs.ps1 tools/Build-Mod.ps1 tests/Test-CaseKitParity.ps1
git commit -m "feat: materialize casekit variants"
```

### Task 8: Migrate both authored cases and remove per-case world bindings - completed

Completed with exact native artifact parity. Production builds now start from
schema-v2 StoryPacks, settlement profiles, stable IDs and the KCD2 adapter. The
old CaseSpecs and binding manifest remain only under `content/migration` as
explicit regression fixtures.

**Files:**
- Create: `content/stories/convenient-accident.story.json`
- Modify: `content/stories/missing-traveler.story.json`
- Modify: `content/archetypes/paper-trail-witness.archetype.json`
- Modify: `config/settlements/pritoky.profile.json`
- Modify: `config/settlements/zelejov.profile.json`
- Modify: `tests/Test-CaseContentMigration.ps1`
- Delete after parity: `config/case-settlement-bindings.json`
- Archive after parity: `content/cases/convenient-accident.case.json`
- Archive after parity: `content/cases/missing-traveler.case.json`

**Step 1: Extend migration tests before moving content**

Assert both legacy case IDs materialize from the new layers with unchanged
stable codes and native identifiers. Assert concrete GUIDs appear only in the
world index or settlement profiles, never in story packs.

**Step 2: Run and verify failure**

```powershell
pwsh -NoProfile -File '.\tests\Test-CaseContentMigration.ps1'
```

Expected: FAIL because the new authored sources do not yet cover both cases.

**Step 3: Split current CaseSpecs into reusable layers**

Move gameplay topology to the archetype, narrative facts/copy to story packs,
and exceptional concrete bindings to settlement profiles. Keep legacy files
until the parity test passes, then move them to a documented migration fixture
or remove them from active compiler inputs.

**Step 4: Run the complete case/compiler regression set**

```powershell
pwsh -NoProfile -File '.\tests\Test-CaseContentMigration.ps1'
pwsh -NoProfile -File '.\tests\Test-MissingTravelerCase.ps1'
pwsh -NoProfile -File '.\tests\Test-MissingTravelerGeneration.ps1' `
  -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
pwsh -NoProfile -File '.\tests\Test-CaseNativeWiring.ps1'
pwsh -NoProfile -File '.\tests\Test-QuestSaveCompatibility.ps1'
```

Expected: all PASS; case 1001 and 2001 remain save-compatible.

**Step 5: Commit**

```powershell
git add -A -- content config tests/Test-CaseContentMigration.ps1
git commit -m "refactor: author cases through casekit"
```

### Task 9: Select variants and materialize scenes at runtime

**Status:** Done. The production build emits 32 finite variants from the two
current StoryPacks; 16 are `native_ready` for their reviewed native region.
Runtime selection filters policy-valid living candidates, applies target
anti-repeat, persists schema-v3 variant identity before presentation, and
restores without reroll. `SceneDirector` builds bound scene instances, delegates
to the proven idempotent evidence/lead adapters, and retries streamed-out actors.
The packaged master contract passes 912 checks.

**Files:**
- Modify: `src/Data/Scripts/mods/dpcasecontent.lua`
- Modify: `src/Data/Scripts/mods/dpcasesnapshot.lua`
- Modify: `src/Data/Scripts/mods/dpinvestigation.lua`
- Modify: `tests/Test-CaseContent.ps1`
- Modify: `tests/Test-TargetRestoreIdempotency.ps1`
- Create: `tests/Test-CaseVariantSelection.ps1`
- Create: `tests/Test-CaseSceneMaterialization.ps1`

**Step 1: Write failing runtime contract tests**

Assert selection:

- considers only variants compatible with current region/settlement;
- excludes invalid, dead and story-critical targets at selection time;
- honors anti-repeat metadata;
- persists `variantId`, target and every concrete binding before presentation;
- never rerolls after save/load, movement, Lua reload or streaming retry;
- migrates existing case 1001/2001 snapshots without replacing the target.

Assert scene materialization:

- resolves the nearest supported settlement before reading its variant pool;
- creates one persisted `CaseInstance` from one compiled `CaseDefinition`;
- binds live actors, places and containers to each `SceneInstance`;
- places predefined evidence idempotently;
- activates only compiled dialogue, role, quest, marker, area and camera assets;
- restores scene and evidence state without reroll or duplicate confidence;
- offers `pre-execution-interrogation` once under its approved target,
  consciousness and Cockeral conditions.

**Step 2: Run and verify failure**

```powershell
pwsh -NoProfile -File '.\tests\Test-CaseVariantSelection.ps1'
pwsh -NoProfile -File '.\tests\Test-CaseSceneMaterialization.ps1'
```

Expected: FAIL because runtime catalogs assume one authored case per region.

**Step 3: Implement minimal variant selection**

Keep the runtime policy small: filter, weighted choose, persist snapshot, then
invoke a small `SceneDirector` over the existing evidence and presentation
systems. Do not add runtime template rendering or native graph mutation.

**Step 4: Run runtime regression tests**

```powershell
pwsh -NoProfile -File '.\tests\Test-CaseVariantSelection.ps1'
pwsh -NoProfile -File '.\tests\Test-CaseContent.ps1' `
  -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
pwsh -NoProfile -File '.\tests\Test-TargetRestoreIdempotency.ps1'
pwsh -NoProfile -File '.\tests\Test-NonlinearEvidenceRuntime.ps1' `
  -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
```

Expected: all PASS; saved variant identity is immutable.

**Step 5: Commit**

```powershell
git add -- src/Data/Scripts/mods tests
git commit -m "feat: persist compiled case variants"
```

The known standing-to-unconscious fall after the interrogation is a deferred
presentation bug. It does not block the mechanical contract; later work should
replace the exit pose/state transition without changing scene domain logic.

### Task 10: Compile and place one victim trophy after target death

**Status:** Done. Both active StoryPacks compile a semantic `bird-feather`
trophy into every concrete variant. The native backend emits 32 stable,
non-divisible item definitions plus Russian and English copy. On target death,
`dptrophy.lua` persists `pending -> placed -> collected`, places the item before
the target binding is cleared, restores the corpse through the immutable case
snapshot after streaming, and never changes investigation or aftermath
semantics. Focused contracts pass 13/13 compiler and 28/28 runtime checks;
native parity passes 11/11 and the packaged master suite passes 916 checks.
Actual corpse presentation, pickup and save/load remain the live acceptance
test; static/build integration is complete.

**Files:**
- Modify: `casekit/core/CaseKit.Authoring.psm1`
- Modify: `casekit/adapters/kcd2/CaseKit.Kcd2Materializer.psm1`
- Modify: `tools/CaseSpecCompiler.psm1`
- Create: `src/Data/Scripts/mods/dptrophy.lua`
- Create: `tests/Test-CaseTrophyCompiler.ps1`
- Create: `tests/Test-TargetTrophyRuntime.ps1`

**TDD contract:**

1. Add an optional semantic `TrophyDefinition` to a compiled CaseVariant.
2. Generate one unique, non-stackable item row and RU/EN description per
   concrete variant through a central `bird-feather` asset preset.
   Canonical labels: **"Трофей - Окровавленное перо"** and
   **"Trophy - Bloodied Feather"**.
3. On selected-target death, create the item in that corpse inventory before
   clearing the target binding.
4. Persist `pending -> placed -> collected`; detect the item in the corpse or
   Henry inventory and repair stale state without duplication.
5. Prove repeated death signals, save/load, Lua reload and streaming retry do
   not create a second trophy.
6. Keep confidence, satisfaction, aftermath and Case completion unchanged.

The initial icon/model may be an ordinary vanilla bird feather. The later
bloodied-feather icon replaces only the central asset preset, not StoryPacks or
runtime logic. A deferred Lua follow-up blocks burial while the selected target
corpse still holds its trophy and shows **"Я ещё не взял то, за чем пришёл."**
Do not mix that polish into this core slice.

**Verification:**

```powershell
pwsh -NoProfile -File '.\tests\Test-CaseTrophyCompiler.ps1'
pwsh -NoProfile -File '.\tests\Test-TargetTrophyRuntime.ps1'
```

Expected: exactly one collectible appears on the selected target corpse and
survives state restoration without duplication.

### Task 11: Prove the rich StoryPack model with the love-triangle case

**Files:**
- Create: `content/stories/love-triangle/case.json`
- Create: `content/stories/love-triangle/threads.json`
- Create: `content/stories/love-triangle/dialogues/`
- Create: `content/stories/love-triangle/documents/`
- Create: `content/stories/love-triangle/localization/ru.json`
- Create: `content/stories/love-triangle/localization/en.json`
- Create: `casekit/tests/Test-LoveTriangleStoryPack.ps1`

**TDD contract:**

1. Encode the approved canonical truth and several intersecting investigation
   routes without concrete world GUIDs.
2. Require `confidence >= 70` and at least one hard identity fact before target
   reveal.
3. Compile wherever settlement capabilities fit; do not require both regions
   unless the StoryPack explicitly declares that coverage.
4. Include the optional authored pre-execution confession scene.
5. Prove one complete route and selected alternate clue orders automatically;
   live-test only new scene or evidence boundaries.

Content prose, dialogue branches and clue wording remain subject to explicit
review before implementation.

### Task 12: Finish build integration, docs and extraction readiness

**Files:**
- Modify: `casekit/README.md`
- Modify: `README.md`
- Modify: `tests/Test-CaseSpecBuildIntegration.ps1`
- Create: `casekit/tests/Test-StandaloneBoundary.ps1`
- Modify: `docs/plans/2026-08-03-kcd2-casekit-design.md`

**Step 1: Write the boundary and build tests**

Assert CaseKit core files contain no Dark Passenger runtime/module imports and
the real `Build-Mod.ps1` crosses the full contract:

```text
authored deck -> world/profile binding -> CaseVariant
-> legacy native backend -> packaged Lua/XML/localization
```

**Step 2: Run and verify failure**

```powershell
pwsh -NoProfile -File '.\casekit\tests\Test-StandaloneBoundary.ps1'
pwsh -NoProfile -File '.\tests\Test-CaseSpecBuildIntegration.ps1' `
  -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
```

Expected: boundary test initially identifies undocumented or direct coupling.

**Step 3: Remove coupling and document author workflow**

Document:

1. adding an evidence module;
2. authoring bilingual story content;
3. declaring semantic slot requirements;
4. reading compatibility rejection reports;
5. compiling and inspecting generated artifacts;
6. criteria for extracting/publishing standalone KCD2 CaseKit.

Do not publish or split repositories in this task.

**Step 4: Run complete verification sequentially**

Run all `casekit/tests/Test-*.ps1`, then all repository `tests/Test-*.ps1`
sequentially with the dev root where accepted, followed by:

```powershell
pwsh -NoProfile -File '.\tools\Build-Mod.ps1' `
  -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
git diff --check
git status --short
```

Expected: every relevant test PASS; deterministic package build; only intended
source, documentation and generated tracked catalogs are changed.

**Step 5: Live acceptance**

Install the built mod into dev. Verify only the new boundary:

1. start a fresh Pritoky case and confirm existing flow is unchanged;
2. start a Zhelejov case and confirm the same persisted variant survives
   save/load;
3. confirm journal, area, evidence and target marker still use native output;
4. inspect logs for one selected `caseId`, `variantId` and binding snapshot.

Do not repeat unrelated burial, hunger or aftermath acceptance tests.

**Step 6: Update Wiki and commit**

Crystallize the proven CaseKit boundary into the existing
`[[KCD2 Modding - Technical Reference]]` and `[[KCD2 Quest SDK - Design]]`,
then integrate the updated pages.

```powershell
git add -- casekit README.md tests/Test-CaseSpecBuildIntegration.ps1 docs
git commit -m "docs: document casekit authoring workflow"
```

## Unresolved questions

- Public name: `KCD2 CaseKit` vs `CaseBuilder`.
- Variant cap and ranking weights after real content volume exists.
- Profession capability sources beyond faction/work links need one focused
  world-data audit.
- Standalone publication timing: after three archetypes, not before.
