# Automatic Settlement Investigation Area Selection Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Generate a stable multi-area investigation marker for every supported settlement in Kuttenberg and Trosky.

**Architecture:** Extract compiled vanilla TriggerArea identities and source polygons, select a deterministic primary-plus-supplemental union for each settlement, then generate quest states, world links and a Lua repair catalog. Pritoky remains the golden fixture. No custom runtime geometry is shipped.

**Tech Stack:** PowerShell 7, XML, JSON, Lua, Skald quest graphs, executable PowerShell tests, KCD2 dev bridge.

**Execution note:** Continue on `feature/aftermath` without a worktree, per the explicit project decision. Use @test-driven-development for every code task, @systematic-debugging for live failures and @verification-before-completion before commits/push.

---

### Task 1: Lock the polygon-transform contract

**Files:**
- Create: `tools/VanillaInvestigationAreaSelection.psm1`
- Create: `tests/Test-SettlementInvestigationAreas.ps1`
- Read: `tools/InvestigationAreaGeometry.psm1`

**Step 1: Write failing pure tests**

Cover:

- identity transform;
- non-uniform XY scale;
- KCD quaternion Z rotation;
- translation into world coordinates;
- point on boundary counts as contained;
- invalid or self-intersecting polygons return a rejection reason.

Use the real Pritoky inn transform as the golden fixture:

```powershell
$world = ConvertTo-VanillaAreaPolygon -Object $pritokyInn
Assert-True (Test-PointInPolygon -Point $innResident -Polygon $world)
```

**Step 2: Run and verify RED**

Run:

```powershell
& 'H:\KCD2Mod\DarkPassenger\tests\Test-SettlementInvestigationAreas.ps1'
```

Expected: FAIL because `VanillaInvestigationAreaSelection.psm1` or the transform functions do not exist.

**Step 3: Implement the minimal geometry API**

Export:

```powershell
ConvertTo-VanillaAreaPolygon
Get-PolygonBounds
Get-PolygonSurfaceArea
Test-VanillaAreaGeometry
```

Reuse `Test-PointInPolygon`, signed-area and self-intersection logic from
`InvestigationAreaGeometry.psm1`; do not duplicate geometry algorithms.

**Step 4: Run and verify GREEN**

Expected: all transform tests pass.

**Step 5: Commit**

```powershell
git -C 'H:\KCD2Mod\DarkPassenger' add -- 'H:\KCD2Mod\DarkPassenger\tools\VanillaInvestigationAreaSelection.psm1' 'H:\KCD2Mod\DarkPassenger\tests\Test-SettlementInvestigationAreas.ps1'
git -C 'H:\KCD2Mod\DarkPassenger' commit -m 'feat: parse vanilla area geometry'
```

---

### Task 2: Extract the vanilla TriggerArea inventory

**Files:**
- Create: `tools/Export-VanillaTriggerAreaCatalog.ps1`
- Create: `tests/fixtures/investigation-areas/objects_mission0.xml`
- Create: `tests/fixtures/investigation-areas/settlement-area.lyr`
- Modify: `tests/Test-SettlementInvestigationAreas.ps1`

**Step 1: Write failing contract tests**

The fixture must prove the extractor joins:

```text
objects_mission0 Entity name/GUID/EntityId/EditorLayer
  + matching .lyr Object full Id/Points/Pos/Rotate/Scale
  -> normalized compiled vanilla area record
```

Assert exact identity, world polygon, layer path, label and rejection reason for
a missing or malformed layer.

**Step 2: Run and verify RED**

Expected: FAIL because the exporter is missing.

**Step 3: Implement streaming extraction**

The exporter must:

1. parse the two Asset Linker mission-object files;
2. filter `EntityClass="TriggerArea"` before opening layers;
3. resolve `EditorLayer` to `Data/Levels/<region>/Layers/<path>.lyr`;
4. match the layer object by name plus short GUID prefix;
5. emit deterministic JSON sorted by region, GUID and EntityId;
6. retain rejected records and explicit reasons for diagnostics.

Do not scan all layer text with recursive regex. The mission-object index is
the routing table for the roughly 9000 TriggerAreas.

**Step 4: Run fixture tests and a real read-only export**

Run:

```powershell
& 'H:\KCD2Mod\DarkPassenger\tools\Export-VanillaTriggerAreaCatalog.ps1' -ReferenceDataRoot 'H:\KCD2Mod\_reference-mods\_extracted\AssetLinker\InternalData' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod' -OutputPath 'H:\KCD2Mod\DarkPassenger\build\generated\vanilla-trigger-areas.json'
```

Expected: both regions exported, Pritoky village/inn/camp identities present,
invalid records diagnosed without aborting the full scan.

**Step 5: Commit**

Commit extractor, fixtures and tests with `feat: extract vanilla trigger areas`.

---

### Task 3: Implement semantic filtering and weighted set cover

**Files:**
- Create: `config/investigation-area-overrides.json`
- Modify: `tools/VanillaInvestigationAreaSelection.psm1`
- Modify: `tests/Test-SettlementInvestigationAreas.ps1`

**Step 1: Write failing selector tests**

Test three alternatives:

- all-hit selection is rejected because it includes technical triggers;
- primary-only leaves supplemental residents uncovered;
- hybrid selection chooses primary plus the smallest safe supplement set.

Required assertions:

```powershell
Assert-Equal @(
  'd0fa0ece-6af5-19f6',
  'd2fc29a3-6787-141c',
  '1b6b6d4e-905c-4f9e'
) $pritoky.areaGuids
```

Also cover manual force-primary, force-include, deny precedence, stable GUID
tie-breaking and a hard failure for an uncovered enabled candidate.

**Step 2: Run and verify RED**

Expected: FAIL on missing selector and override schema.

**Step 3: Implement minimal policy**

Export:

```powershell
Get-AreaSemanticClassification
Get-InvestigationAreaScore
Select-SettlementInvestigationAreas
```

Hard reject invalid geometry and known technical classes/patterns. Prefer
same-settlement `publicEnemiesRepulsionZone` as primary. Permit cross-layer
camp/quest areas only when they cover a required anchor or are forced. Rank by
new coverage, semantic stability, excess surface, distance/risk, then GUID.

**Step 4: Run and verify GREEN**

Expected: synthetic cases and the exact Pritoky golden union pass.

**Step 5: Commit**

Commit with `feat: select settlement area unions`.

---

### Task 4: Generate and review both-region settlement coverage

**Files:**
- Create: `tools/Generate-SettlementInvestigationAreas.ps1`
- Create: `config/settlement-investigation-areas.json`
- Modify: `config/investigation-area-overrides.json`
- Modify: `tests/Test-SettlementInvestigationAreas.ps1`

**Step 1: Write the failing feature test**

The generated manifest must assert:

- every settlement with enabled candidates has one primary area;
- every enabled candidate is contained by at least one selected polygon;
- aliases are unique per region/settlement;
- selected identities exist in the vanilla inventory;
- output is byte-for-byte deterministic.

**Step 2: Run and verify RED**

Expected: FAIL because the two-region manifest generator is missing.

**Step 3: Generate the first diagnostic report**

Run the generator against all 959 current candidates. Review uncovered anchors,
oversized areas and rejected technical triggers. Add only evidence-backed
manual overrides; do not relax global filters to fix one settlement.

**Step 4: Regenerate until GREEN**

Expected: all enabled candidates in both regions are covered or explicitly
excluded by existing victim policy with a documented reason. Pritoky remains
the exact three-area fixture.

**Step 5: Commit**

Commit generator, override policy and generated manifest with
`feat: generate settlement investigation coverage`.

---

### Task 5: Generate dynamic settlement search states

**Files:**
- Modify: `tools/Generate-VictimArtifacts.ps1`
- Modify: `src/Data/Quests/darkpassengertest/kutnohorsko/dark_within_k.xml.template`
- Modify: `tests/Test-DarkPassengerSatisfaction.ps1`
- Modify: `localization/English/text__darkpassengertest.xml`
- Modify: `localization/Russian/text__darkpassengertest.xml`

**Step 1: Write failing generated-graph tests**

Assert both regional quests contain:

- `DP_SearchProgress` states for every supported settlement;
- one `TriggerAreaAsset` and search `EnumLog` per settlement;
- marker aliases from the generated area manifest;
- every candidate slot mapped to its settlement search state;
- target reveal completes the active search objective once;
- no fixed Pritoky marker remains as the regional default.

**Step 2: Run and verify RED**

Run the main test with explicit roots. Expected: FAIL on missing generated
settlement states.

**Step 3: Implement graph generation**

Add template tokens for search enums, assets, logs and candidate-to-settlement
edges. Keep one visible search objective. Reuse the existing candidate tag-24
check; do not add a new Lua-to-quest signal.

Generate stable localization keys per settlement. Store bilingual display
names in the override/config source and validate that every emitted key exists.

**Step 4: Run and verify GREEN**

Expected: generated Kuttenberg and Trosky graphs map all candidate slots to the
correct area state and retain existing reveal/death/cleanup behavior.

**Step 5: Commit**

Commit with `feat: generate settlement search objectives`.

---

### Task 6: Generate regional world bindings

**Files:**
- Create: `tools/Generate-SettlementAreaBindings.ps1`
- Create: `src/Data/Levels/trosecko/objects_mission0.patch.xml`
- Create: `src/Data/Levels/trosecko/waitinglinks.xml`
- Modify: `src/Data/Levels/kutnohorsko/objects_mission0.patch.xml`
- Modify: `src/Data/Levels/kutnohorsko/waitinglinks.xml`
- Modify: `tools/Build-Mod.ps1`
- Modify: `tests/Test-DarkPassengerSatisfaction.ps1`

**Step 1: Write failing binding tests**

For each region assert:

- vanilla LevelHolder -> regional quest holder `module` link;
- every selected TriggerArea has one same-alias waiting link;
- mission-object holder links match waiting links exactly;
- no generated custom TriggerArea, layer, `whdata`, `leveldata.xml` or BAI;
- Trosky uses its real LevelHolder GUID `30277b74-1c65-41e9`.

**Step 2: Run and verify RED**

Expected: FAIL because bindings remain fixed to the Pritoky pilot and Trosky
has no vanilla-namespace holder.

**Step 3: Implement deterministic binding generation**

Generate stable quest-holder identities per region, merge both current Barbora
regional parents from installed `Scripts.pak`, and emit regional minimal level
paks containing only `objects_mission0.xml` and `waitinglinks.xml`.

**Step 4: Build and verify GREEN**

Run `tools/Build-Mod.ps1`, `7z t` on both level paks and the full core test.

**Step 5: Commit**

Commit with `feat: bind settlement areas in both regions`.

---

### Task 7: Replace the hard-coded Lua area bridge

**Files:**
- Generate: `src/Data/Scripts/mods/generated/dp_investigation_area_catalog.lua`
- Modify: `src/Data/Scripts/mods/darkpassengertest.lua`
- Modify: `tests/Test-DarkPassengerSatisfaction.ps1`

**Step 1: Write failing Lua contract tests**

Assert the generated catalog groups target names by region and settlement and
the bridge:

- restores only the active case settlement;
- ensures the regional module link;
- ensures every same-alias area link idempotently;
- retries missing streamed entities without changing target or settlement;
- handles save restoration before selecting a new case.

**Step 2: Run and verify RED**

Expected: FAIL because `TARGET_NAMES` is still the hard-coded Pritoky table.

**Step 3: Implement catalog-driven repair**

Load the generated catalog, expose `EnsureSettlementLinked(region,
settlement)`, and call it after case selection, restoration, player init and
reload. Preserve bounded generation-safe polling.

**Step 4: Run and verify GREEN**

Expected: LuaCompiler and all bridge assertions pass.

**Step 5: Commit**

Commit with `feat: repair active settlement area links`.

---

### Task 8: Extend safe dev deployment and full verification

**Files:**
- Modify: `tools/Deploy-DevLevelOverlay.ps1`
- Modify: `tests/Test-DevLevelOverlay.ps1`
- Modify: `README.md`

**Step 1: Write failing overlay integration tests**

Use isolated Kuttenberg and Trosky fixtures. Assert atomic backups, exact two
loose files per region, preservation of all vanilla registries and removal only
of the two known obsolete custom Pritoky layer artifacts.

**Step 2: Run and verify RED**

Expected: FAIL because deployment handles only Kuttenberg.

**Step 3: Implement both-region deployment**

Generalize the existing validated copy/backup/hash loop without broad recursive
deletion. Update README build/test commands and area-generation source contract.

**Step 4: Run the complete static matrix**

Run:

```powershell
& 'H:\KCD2Mod\DarkPassenger\tools\Build-Mod.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
& 'H:\KCD2Mod\DarkPassenger\tests\Test-SettlementInvestigationAreas.ps1'
& 'H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1' -ReferenceDataRoot 'H:\KCD2Mod\_reference-mods\_extracted\AssetLinker\InternalData' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
& 'H:\KCD2Mod\DarkPassenger\tests\Test-DevLevelOverlay.ps1'
& 'H:\KCD2Mod\DarkPassenger\tests\Test-InvestigationAreaGeometry.ps1'
git -C 'H:\KCD2Mod\DarkPassenger' diff --check
```

Expected: all relevant tests and both PAK integrity checks pass.

**Step 5: Commit**

Commit with `test: verify settlement area pipeline`.

---

### Task 9: Deploy and prove live

**Files:**
- Update after proof: `docs/plans/2026-08-01-automatic-settlement-investigation-area-selection-design.md`
- Update after proof: LLM Wiki `KCD2 Modding - Technical Reference`

**Step 1: Build and deploy with the game closed**

Back up the current dev mod and both loose level overlays, deploy atomically and
verify source/deployed SHA-256 trees.

**Step 2: Cold-start dev and check the bridge**

Require `LEVEL_LOAD_COMPLETE`, no marker-resolution/custom-layer errors and a
catalog-driven bridge proof for the active settlement.

**Step 3: Run live acceptance cases**

Verify Pritoky, dense Kuttenberg, one sparse supplemental settlement, one
Trosky settlement and save/load stability. For every case confirm correct
journal text, irregular multi-area union, threshold transition and target
marker.

**Step 4: Crystallize the result**

Only after live proof, update the existing Wiki page with the extractor,
selection, quest-state and runtime contracts. Do not replace the Pritoky proof;
mark it as the golden fixture for the generalized pipeline.

**Step 5: Final verification, simplify, commit and push**

Run the full static matrix again, review `git diff`, simplify feature changes,
commit the live-proof/docs delta and push `feature/aftermath`.

---

## Unresolved questions

None blocking implementation. Concrete safety thresholds and manual overrides
must be justified by the Task 4 diagnostics rather than guessed in advance.
