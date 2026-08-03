# KCD2 CaseKit Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a reusable CaseBuilder/CaseCompiler toolchain that turns authored archetypes and story packs into validated, settlement-compatible Dark Passenger CaseVariants and existing native KCD2 artifacts.

**Architecture:** A self-contained `casekit/` module uses ports and adapters. Its pure PowerShell core owns typed authoring contracts, identity, binding and compatibility; KCD2 adapters import world data and materialize neutral CaseVariants through the existing proven native compiler backend. Dark Passenger remains a content/runtime consumer, not a dependency of CaseKit.

**Tech Stack:** PowerShell 7 modules and CLI scripts, JSON authoring data, generated Lua/XML/localization, existing KCD2 catalogs and current script-based test harness.

---

## Guardrails

- Keep one universal regional quest container; do not generate a quest graph per story.
- Keep existing numeric codes, enum values and aliases as save schema.
- Preserve `tools/CaseSpecCompiler.psm1` as native backend until parity passes.
- Generated files are disposable; authored files are the source of truth.
- Run test scripts sequentially because several generators share `build/mod`.
- Do not require a running game until the final focused live acceptance.

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

### Task 1: Scaffold the reusable CaseKit boundary

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

### Task 2: Generate the KCD2 semantic world index

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

### Task 3: Resolve identity and central settlement profiles

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

### Task 4: Add CaseBuilder authoring contracts and typed templates

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

- archetype required/optional slots and evidence topology;
- story facts plus identical Russian/English key sets;
- evidence module capability requirements and one-shot confidence;
- placeholders matching `{{slot.property}}`;
- a reachable confidence path to 70.

Required error cases:

```text
unknown slot in template
anonymous actor referenced through .name
missing English key
unknown evidence module
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

Do not migrate current CaseSpecs yet; this task proves the new authoring layer
in isolation.

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

### Task 5: Implement deterministic compatibility solving

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
5. sort by authored preference, identity quality and stable GUID;
6. emit at most `MaxVariantsPerCombination`.

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

### Task 6: Materialize neutral variants through the proven native backend

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

### Task 7: Migrate both authored cases and remove per-case world bindings

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

### Task 8: Select and persist multiple compiled variants at runtime

**Files:**
- Modify: `src/Data/Scripts/mods/dpcasecontent.lua`
- Modify: `src/Data/Scripts/mods/dpcasesnapshot.lua`
- Modify: `src/Data/Scripts/mods/dpinvestigation.lua`
- Modify: `tests/Test-CaseContent.ps1`
- Modify: `tests/Test-TargetRestoreIdempotency.ps1`
- Create: `tests/Test-CaseVariantSelection.ps1`

**Step 1: Write failing runtime contract tests**

Assert selection:

- considers only variants compatible with current region/settlement;
- excludes invalid, dead and story-critical targets at selection time;
- honors anti-repeat metadata;
- persists `variantId`, target and every concrete binding before presentation;
- never rerolls after save/load, movement, Lua reload or streaming retry;
- migrates existing case 1001/2001 snapshots without replacing the target.

**Step 2: Run and verify failure**

```powershell
pwsh -NoProfile -File '.\tests\Test-CaseVariantSelection.ps1'
```

Expected: FAIL because runtime catalogs assume one authored case per region.

**Step 3: Implement minimal variant selection**

Keep the runtime policy small: filter, weighted choose, persist snapshot, then
invoke existing evidence and presentation systems. Do not add runtime template
rendering or native graph mutation.

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

### Task 9: Finish build integration, docs and extraction readiness

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
