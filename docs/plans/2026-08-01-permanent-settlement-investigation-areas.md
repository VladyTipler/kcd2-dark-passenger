# Dark Passenger Permanent Settlement Investigation Areas Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Generate and live-prove one permanent irregular Pritoky investigation area without changing the proven confidence or quest progression flow.

**Architecture:** A PowerShell geometry module and build-time generator read one area-policy JSON plus the existing victim catalogue, emit a validated `SmartAreaShape`, waiting-link patch, manifest, and Lua catalogue, then the current build merges those outputs into the vanilla Kuttenberg level. The quest keeps `DP_PritokySearchArea`; runtime Lua only reads the generated entity name, while all shape data remains build-time and deterministic.

**Tech Stack:** PowerShell 7, JSON, KCD2 world XML, Lua, existing 7-Zip build pipeline, dev-build Online Debug API and `kcd.log`.

**Execution note:** Work in the current `feature/aftermath` branch. Vlad explicitly declined a worktree for this project.

---

### Task 1: Add tested polygon primitives

Use `@superpowers:test-driven-development`.

**Files:**
- Create: `H:\KCD2Mod\DarkPassenger\tests\Test-InvestigationAreaGeometry.ps1`
- Create: `H:\KCD2Mod\DarkPassenger\tools\InvestigationAreaGeometry.psm1`

**Step 1: Write the failing geometry test**

Create a script test with a local assertion helper. Import the not-yet-created
module and cover these public functions:

```powershell
$module = 'H:\KCD2Mod\DarkPassenger\tools\InvestigationAreaGeometry.psm1'
Import-Module $module -Force

$square = @(
    @{ x = 0.0; y = 0.0 },
    @{ x = 10.0; y = 0.0 },
    @{ x = 10.0; y = 10.0 },
    @{ x = 0.0; y = 10.0 }
)

Assert-True (Test-PointInPolygon -Point @{ x = 5; y = 5 } -Polygon $square) `
    'point inside polygon'
Assert-True (-not (Test-PointInPolygon -Point @{ x = 15; y = 5 } -Polygon $square)) `
    'point outside polygon'
Assert-True (-not (Test-PolygonSelfIntersection -Polygon $square)) `
    'simple polygon has no self-intersection'

$bowTie = @(
    @{ x = 0; y = 0 }, @{ x = 10; y = 10 },
    @{ x = 0; y = 10 }, @{ x = 10; y = 0 }
)
Assert-True (Test-PolygonSelfIntersection -Polygon $bowTie) `
    'bow-tie polygon is rejected'
```

Also assert stable winding and canonical decimal formatting.

**Step 2: Run the test to verify it fails**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'H:\KCD2Mod\DarkPassenger\tests\Test-InvestigationAreaGeometry.ps1'
```

Expected: FAIL because `InvestigationAreaGeometry.psm1` does not exist.

**Step 3: Implement the minimal geometry module**

Export only:

```powershell
Export-ModuleMember -Function @(
    'Get-PolygonSignedArea',
    'Test-PointInPolygon',
    'Test-PolygonSelfIntersection',
    'Get-ConvexHull',
    'Expand-Polygon',
    'Add-DeterministicIrregularity',
    'Assert-InvestigationPolygon'
)
```

Implementation requirements:

- use the ray-casting algorithm for point containment;
- treat points on an edge as contained;
- compare every non-adjacent edge pair for self-intersection;
- use monotonic-chain convex hull with stable `x,y` sorting;
- expand each hull vertex radially from the centroid by the requested metres;
- subdivide the longest edges until `MinVertices` is reached;
- offset inserted midpoints outward by a deterministic amount derived from the
  settlement seed, never runtime randomness;
- reject non-finite coordinates, fewer than three unique vertices, invalid
  winding, self-intersection, and more than `MaxVertices`.

Use invariant-culture numeric conversion everywhere.

**Step 4: Run the test to verify it passes**

Expected: `RESULT: PASS (investigation area geometry)`.

**Step 5: Commit**

```powershell
git -C 'H:\KCD2Mod\DarkPassenger' add -- 'H:\KCD2Mod\DarkPassenger\tests\Test-InvestigationAreaGeometry.ps1' 'H:\KCD2Mod\DarkPassenger\tools\InvestigationAreaGeometry.psm1'
git -C 'H:\KCD2Mod\DarkPassenger' commit -m 'test: add investigation area geometry contract'
```

### Task 2: Define the Pritoky area policy and failing generator contract

**Files:**
- Create: `H:\KCD2Mod\DarkPassenger\config\investigation-areas.json`
- Create: `H:\KCD2Mod\DarkPassenger\tools\Generate-InvestigationAreas.ps1`
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-InvestigationAreaGeometry.ps1`

**Step 1: Add the failing policy tests**

The test must require schema version `1`, exactly one Pritoky pilot area, and
these values:

```json
{
  "schemaVersion": 1,
  "defaults": {
    "paddingMeters": 100,
    "minVertices": 10,
    "maxVertices": 20
  },
  "areas": [
    {
      "id": "pritoky",
      "gameRegion": "kutnohorsko",
      "settlement": "pritoky",
      "alias": "DP_PritokySearchArea",
      "entityName": "dp_pritoky_investigation_area",
      "identitySeed": "darkpassenger:kutnohorsko:pritoky:investigation-area:v1",
      "smartAreaTemplateGuid": "d9064870-2806-4032-8698-c09886772cf6",
      "poiAnchors": [
        { "id": "village-core", "x": 2268.442, "y": 1803.583 },
        { "id": "pritoky-inn", "x": 2168.600, "y": 1533.400 },
        { "id": "deserter-camp", "x": 2293.569, "y": 2086.651 }
      ]
    }
  ]
}
```

Do not copy resident coordinates into this file. Load all enabled Pritoky
residents from `config/victim-candidates.json` and assert all 37 become anchors.

**Step 2: Run the test to verify it fails**

Expected: FAIL because the config and generator do not exist.

**Step 3: Create the policy file and generator shell**

The generator parameters must be explicit and testable:

```powershell
param(
    [string]$PolicyPath,
    [string]$VictimCatalogPath,
    [string]$GeneratedRoot,
    [string]$StageRoot
)
```

It imports `InvestigationAreaGeometry.psm1`, validates both JSON inputs, joins
enabled candidates by `gameRegion + settlement`, and builds one anchor list per
area. Stop before XML emission in this task.

**Step 4: Run the geometry/policy test**

Expected: PASS for schema, anchor join, and duplicate-coordinate handling.

**Step 5: Commit**

```powershell
git -C 'H:\KCD2Mod\DarkPassenger' add -- 'H:\KCD2Mod\DarkPassenger\config\investigation-areas.json' 'H:\KCD2Mod\DarkPassenger\tools\Generate-InvestigationAreas.ps1' 'H:\KCD2Mod\DarkPassenger\tests\Test-InvestigationAreaGeometry.ps1'
git -C 'H:\KCD2Mod\DarkPassenger' commit -m 'feat: define Pritoky investigation area policy'
```

### Task 3: Generate the world asset and bridge manifests

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\tools\Generate-InvestigationAreas.ps1`
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-InvestigationAreaGeometry.ps1`
- Generated: `H:\KCD2Mod\DarkPassenger\build\generated\investigation-areas\kutnohorsko.entities.xml`
- Generated: `H:\KCD2Mod\DarkPassenger\build\generated\investigation-areas\manifest.json`
- Generated: `H:\KCD2Mod\DarkPassenger\build\mod\Data\Levels\kutnohorsko\waitinglinks.xml`
- Generated: `H:\KCD2Mod\DarkPassenger\build\mod\Data\Scripts\mods\generated\dp_investigation_area_catalog.lua`

**Step 1: Add failing output assertions**

Run the generator twice into separate fixture folders. Require identical
SHA-256 hashes. Parse the emitted XML and assert:

- one `SmartAreaShape` named `dp_pritoky_investigation_area`;
- 10-20 relative `<Point Pos="x,y,z">` vertices;
- `guidSmartAreaTemplate="d9064870-2806-4032-8698-c09886772cf6"`;
- all 37 enabled residents and all three POIs are inside the world polygon;
- the waiting link targets the generated entity GUID using
  `asset['DP_PritokySearchArea']`;
- the Lua catalogue contains the same alias, entity name, GUID, and region.

**Step 2: Run the test to verify it fails**

Expected: FAIL because the generator emits no files.

**Step 3: Implement deterministic output**

Derive stable identifiers from SHA-256 of `identitySeed`:

```powershell
$hex = [Convert]::ToHexString(
    [Security.Cryptography.SHA256]::HashData(
        [Text.Encoding]::UTF8.GetBytes($area.identitySeed)
    )
).ToLowerInvariant()
$entityGuid = '{0}-{1}-{2}' -f $hex.Substring(0,8), $hex.Substring(8,4), $hex.Substring(12,4)
$entityId = 1800000 + ([Convert]::ToInt32($hex.Substring(16,6), 16) % 100000)
```

Emit a vanilla-shaped entity:

```xml
<Entity Name="dp_pritoky_investigation_area"
        Pos="CENTROID_X,CENTROID_Y,CENTROID_Z"
        EntityClass="SmartAreaShape"
        EntityId="DERIVED_ID"
        EntityGuid="DERIVED_GUID"
        CastShadowMinSpec="1"
        EditorLayer="Main/_quest/activity/darkpassengertest/static">
  <Properties guidSmartAreaTemplate="d9064870-2806-4032-8698-c09886772cf6"
              bSaved_by_game="0" />
  <Area Id="0" Group="0" Proximity="0" Priority="0" Height="500">
    <Points>...</Points>
    <Roof ObstructSound="0" />
    <Floor ObstructSound="0" />
  </Area>
</Entity>
```

Use the average anchor Z for entity origin and `-0.1` for local point Z. Write
all generated text without BOM and with invariant decimal points.

**Step 4: Run the test twice**

Expected: PASS and identical hashes.

**Step 5: Commit**

```powershell
git -C 'H:\KCD2Mod\DarkPassenger' add -- 'H:\KCD2Mod\DarkPassenger\tools\Generate-InvestigationAreas.ps1' 'H:\KCD2Mod\DarkPassenger\tests\Test-InvestigationAreaGeometry.ps1'
git -C 'H:\KCD2Mod\DarkPassenger' commit -m 'feat: generate irregular investigation areas'
```

### Task 4: Cross the real build and level-merge boundary

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\tools\Build-Mod.ps1:68-430`
- Delete: `H:\KCD2Mod\DarkPassenger\src\Data\Levels\kutnohorsko\waitinglinks.xml`
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1:43-69,584-689,2700-2860`
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-DevLevelOverlay.ps1:24-140`
- Modify: `H:\KCD2Mod\DarkPassenger\tools\Deploy-DevLevelOverlay.ps1:70-92`

**Step 1: Add failing integration assertions first**

The main suite must require that a real `Build-Mod.ps1` run:

- invokes `Generate-InvestigationAreas.ps1` after candidate generation;
- merges the generated `SmartAreaShape` beside the quest holder into the full
  vanilla `objects_mission0.xml`;
- rejects derived EntityId or EntityGuid collisions against the extracted base;
- packages generated waiting links instead of a hand-authored duplicate;
- preserves exactly one LevelHolder -> quest-holder link and one quest-holder
  -> generated-area link;
- contains no reference to vanilla area GUID `d0fa0ece-6af5-19f6`;
- keeps the main pak free of level registries;
- packages only `objects_mission0.xml` and `waitinglinks.xml` in the Kuttenberg
  level pak.

Update the dev-overlay fixture to contain the generated area and new target
GUID. Its backup/hash checks remain unchanged.

**Step 2: Run the suites to verify they fail**

```powershell
& 'H:\KCD2Mod\DarkPassenger\tools\Build-Mod.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
& 'H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod' -ReferenceDataRoot 'H:\KCD2Mod\_reference-mods\_extracted\AssetLinker\InternalData'
& 'H:\KCD2Mod\DarkPassenger\tests\Test-DevLevelOverlay.ps1'
```

Expected: FAIL on missing generated area merge and stale vanilla GUID.

**Step 3: Integrate the generator minimally**

In `Build-Mod.ps1`:

1. call the area generator after `Generate-VictimArtifacts.ps1`;
2. load its entity fragment and manifest;
3. extract the current base level objects;
4. fail on ID/GUID/name collision;
5. insert the quest holder plus generated area before `</Objects>`;
6. merge the generated two-link waiting-link patch into the full vanilla file;
7. remove all intermediate fragments from staging before packaging.

Update deploy validation to read the expected entity name/GUID from generated
Lua or manifest instead of hard-coding the old vanilla target.

**Step 4: Run all three suites**

Expected: geometry PASS, main suite PASS with a count greater than 853, overlay
PASS.

**Step 5: Commit**

```powershell
git -C 'H:\KCD2Mod\DarkPassenger' add -A -- 'H:\KCD2Mod\DarkPassenger\src\Data\Levels\kutnohorsko' 'H:\KCD2Mod\DarkPassenger\tools\Build-Mod.ps1' 'H:\KCD2Mod\DarkPassenger\tools\Deploy-DevLevelOverlay.ps1' 'H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1' 'H:\KCD2Mod\DarkPassenger\tests\Test-DevLevelOverlay.ps1'
git -C 'H:\KCD2Mod\DarkPassenger' commit -m 'feat: merge generated Pritoky area into level data'
```

### Task 5: Point the runtime bridge at generated metadata

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\darkpassengertest.lua:16-24,728-903`
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1:2760-2810`

**Step 1: Add the failing runtime contract test**

Require the init script to load
`Scripts/mods/generated/dp_investigation_area_catalog.lua` before the area
bridge. Reject the literal vanilla target name
`kpri_publicEnemiesRepulsionZoneVillageArea_1`.

Require `EnsureLinked()` to fail closed and log a diagnostic when the generated
catalogue, regional entry, or entity name is unavailable.

**Step 2: Run the main suite to verify it fails**

Expected: FAIL on the hard-coded vanilla target name.

**Step 3: Implement the generated lookup**

Load the generated file near the candidate catalogue:

```lua
Script.ReloadScript(
    "Scripts/mods/generated/dp_investigation_area_catalog.lua"
)
```

Resolve once before polling:

```lua
local areaRegion = DarkPassengerInvestigationAreaCatalog and
    DarkPassengerInvestigationAreaCatalog.kutnohorsko
local area = areaRegion and areaRegion.pritoky

DarkPassengerAreaBridge.TARGET_NAME = area and area.entityName or nil
DarkPassengerAreaBridge.LINK_NAME = area and
    "asset['" .. tostring(area.alias) .. "']" or nil
```

Do not fall back to the old vanilla entity.

**Step 4: Run the main suite**

Expected: PASS.

**Step 5: Commit**

```powershell
git -C 'H:\KCD2Mod\DarkPassenger' add -- 'H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\darkpassengertest.lua' 'H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1'
git -C 'H:\KCD2Mod\DarkPassenger' commit -m 'feat: bind area bridge from generated catalogue'
```

### Task 6: Run the complete static gate

Use `@verification-before-completion` and run the repository simplification
review before any deployment.

**Files:**
- Modify only if verification exposes a defect.

**Step 1: Run the complete build and tests fresh**

```powershell
& 'H:\KCD2Mod\DarkPassenger\tools\Build-Mod.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
& 'H:\KCD2Mod\DarkPassenger\tests\Test-InvestigationAreaGeometry.ps1'
& 'H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod' -ReferenceDataRoot 'H:\KCD2Mod\_reference-mods\_extracted\AssetLinker\InternalData'
& 'H:\KCD2Mod\DarkPassenger\tests\Test-DevLevelOverlay.ps1'
git -C 'H:\KCD2Mod\DarkPassenger' diff --check
```

Expected: every command exits `0`; all PASS summaries are present.

**Step 2: Inspect the generated polygon evidence**

Record vertex count, bounding box, area, anchor count, manifest SHA-256, world
entity name/GUID, and both archive hashes. Confirm all 37 Pritoky candidates are
inside.

**Step 3: Run the simplification pass**

Review `git diff c426343..HEAD` for duplicated XML formatting, geometry helpers,
or repeated config parsing. Apply only behaviour-preserving simplifications and
rerun Step 1 after any change.

**Step 4: Commit verification-only fixes if needed**

```powershell
git -C 'H:\KCD2Mod\DarkPassenger' commit -am 'refactor: simplify investigation area generation'
```

Skip this commit when no change is justified.

### Task 7: Deploy and perform the live Pritoky acceptance test

**Files:**
- Modify after proof: `H:\KCD2Mod\DarkPassenger\evidence\pritoky-investigation-validation.md`
- Modify after proof: `H:\KCD2Mod\DarkPassenger\README.md`
- Update after proof: `C:\Users\Vladislav\Obsidian Vaults\LLM Wiki\kcd2-modding-technical-reference.md`

**Step 1: Stop before deployment if the game is running**

Resolve the exact dev target and verify that `KingdomCome.exe` is closed. Do not
deploy or replace loose level files while the process is active.

**Step 2: Deploy transactionally**

Deploy the freshly built mod and loose level overlay using the existing backup
scripts. Verify source/target SHA-256 equality before launching the game.

**Step 3: Run the cold live scenario**

1. start the dev build and load a save before the active Case;
2. start a Pritoky Case;
3. visually inspect the irregular area on map and compass;
4. confirm village, inn, deserter camp, outlying homes, and selected victim lie
   inside;
5. save/load below confidence 70;
6. verify the same area, target, and confidence;
7. cross 70 through the tested bridge;
8. verify one objective update, native sound, area removal, and exact NPC point;
9. inspect fresh `kcd.log` for marker/world-link errors.

**Step 4: Apply tuning only through policy**

If the marker works but looks poor, adjust padding, POIs, or a manual polygon in
`config/investigation-areas.json`. Do not change quest XML or Lua flow. Repeat
the complete static gate before redeployment.

If `SmartAreaShape` does not resolve, stop and capture the exact log. The next
design adjustment may change only the emitted world entity type/schema; do not
replace the area with a circle or expose the victim early.

**Step 5: Record proof and commit**

Use `@wiki-crystallize` and `@wiki-integrate` after live proof. Update the
evidence page with the exact build hashes, log slice, screenshot outcome, and
whether `SmartAreaShape` is marker-compatible.

```powershell
git -C 'H:\KCD2Mod\DarkPassenger' add -- 'H:\KCD2Mod\DarkPassenger\evidence\pritoky-investigation-validation.md' 'H:\KCD2Mod\DarkPassenger\README.md'
git -C 'H:\KCD2Mod\DarkPassenger' commit -m 'docs: record irregular Pritoky area proof'
git -C 'H:\KCD2Mod\DarkPassenger' push origin feature/aftermath
```
