# Worldwide Nearest-Settlement Victim Selection Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Select and mark one eligible permanent resident from the settlement nearest to Henry in either KCD2 region.

**Architecture:** Build-time extraction produces one policy-reviewed resident catalogue with full SharedSoul GUIDs. The generator emits region-specific quest marker slots and one Lua catalogue; Lua chooses the nearest eligible settlement and living resident while quest XML owns journal and native marker state. Main-story actors are always excluded; side-quest participation is an explicit risk flag and may be allowed.

**Tech Stack:** KCD2 Lua, Skald quest XML, PowerShell 7, JSON, local Modding Tools/game data, 7-Zip, retail runtime testing.

---

## Preconditions

- Work in `<repo-root>`.
- The directory is not a Git repository; commit steps are omitted.
- Preserve `config/victim-candidates.json` as the single source of truth.
- Never deploy while either game build is running.
- Keep `a_PlayerEventDispatcher` installed as an explicit runtime dependency.
- Do not generate `EntityGuid` waiting links for quest targets. Retail testing
  proved that Asset Linker binds them to the regional `LevelHolder`, not to a
  custom quest `SoulAsset`.

### Task 0: Remove the failed EntityGuid marker experiment

**Files:**
- Modify: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`
- Modify: `<repo-root>\config\victim-candidates.json`
- Modify: `<repo-root>\tools\Generate-VictimArtifacts.ps1`

**Step 1: Write failing regression tests**

Require every enabled candidate to have a full SharedSoul GUID, generated
`SoulAsset SharedSoulGuids`, and no `bindingMode=entityLink` or generated
`waitinglinks.xml` dependency.

**Step 2: Run RED**

Expected: the current `kpri_man_34` EntityGuid probe fails.

**Step 3: Restore SharedSoul generation**

Restore `kpri_man_34` to GUID `58d0827f-4254-4de2-93d5-aecfde1d7065`,
normal weight, and the previously working static alias mechanism. Remove only
the EntityGuid/waitinglink branch; preserve the level data sources as extractor
inputs.

**Step 4: Run GREEN**

Expected: all three Pritoky aliases have explicit SharedSoul GUIDs and all
structural tests pass.

### Task 1: Find authoritative world-data sources

**Files:**
- Create: `<repo-root>\evidence\world-data-sources.md`
- Inspect: `<kcd2-dev-root>`
- Inspect: `<reference-mods-root>\_extracted`

**Step 1: Inventory candidate sources**

Search Modding Tools, unpacked tables, level data, quest data, and available
database exports for:

- persistent Soul GUID and entity name;
- position, home, schedule, or spawn location;
- role, archetype, faction, shop, and social metadata;
- immortality and quest/story references.

**Step 2: Prove extraction on Pritoky**

Recover the three known PoC records from the discovered source without using the
existing catalogue as input.

Expected: extracted GUID/entity pairs match all three known records.

**Step 3: Record reliability**

For each source, document fields, coverage, confidence, and missing safety data.

**Step 4: Stop on feasibility failure**

Do not generate a world catalogue if stable Soul GUIDs or region positions
cannot be extracted. Report the precise missing link and switch to a dev-runtime
export design only after approval.

### Task 2: Add schema-v2 catalogue tests

**Files:**
- Modify: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`
- Modify: `<repo-root>\config\victim-candidates.json`

**Step 1: Write failing tests**

Require:

- schema version 2;
- both region ids;
- unique settlement ids and candidate slots;
- center coordinates on every settlement;
- every candidate references a valid settlement in the same region;
- explicit persistent-resident, temporary, main-story, side-quest-risk,
  killability, immortality, and evidence fields.

**Step 2: Run RED**

```powershell
pwsh -NoProfile -File "<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1"
```

Expected: schema-v1 catalogue fails.

**Step 3: Migrate the three PoC candidates**

Create minimal region and Pritoky settlement records, preserving the verified
candidate identity and safety data.

**Step 4: Run GREEN**

Expected: schema checks pass; existing generated behavior remains unchanged.

### Task 3: Build deterministic raw extraction

**Files:**
- Create: `<repo-root>\tools\Export-WorldVictimCandidates.ps1`
- Create: `<repo-root>\evidence\world-candidates.raw.json`
- Modify: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`

**Step 1: Write failing extraction tests**

Require deterministic output, valid GUIDs, stable source references, region
membership, coordinates, and recovery of the known Pritoky records.

**Step 2: Run RED**

Expected: exporter/output checks fail.

**Step 3: Implement minimal extractor**

Read only the authoritative sources confirmed in Task 1. Do not infer unknown
safety fields as safe.

**Step 4: Run exporter twice**

Expected: byte-identical raw JSON.

**Step 5: Run GREEN**

Expected: extraction tests pass.

### Task 4: Classify settlements, residency, and story safety

**Files:**
- Create: `<repo-root>\config\victim-exclusions.json`
- Modify: `<repo-root>\tools\Export-WorldVictimCandidates.ps1`
- Modify: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`

**Step 1: Write failing classification tests**

Require:

- every shipping candidate belongs to one settlement;
- non-residents and main-story references cause exclusion;
- side-quest references set a risk flag but do not automatically exclude;
- temporary, immortal, dead, or unknown-killability records cause exclusion;
- manual exclusions override extracted metadata;
- manual policy may explicitly enable a side-quest resident;
- empty settlements remain valid but are not selection-eligible.

**Step 2: Run RED**

Expected: raw records are not yet safe for shipping.

**Step 3: Add conservative classification**

Assign settlements and permanent residency by authoritative home/schedule data
when available, otherwise require an explicit policy override. Keep unknown
main-story relevance and unknown killability out of the shipping catalogue.

**Step 4: Run GREEN**

Expected: only permanent, killable, non-main-story residents are enabled;
side-quest risk remains visible in generated metadata.

### Task 5: Generalize generation for two regional graphs

**Files:**
- Modify: `<repo-root>\tools\Generate-VictimArtifacts.ps1`
- Create: `<repo-root>\build\mod\Data\Quests\darkpassengertest\trosecko\dark_within_t.xml.template`
- Generate: `<repo-root>\build\mod\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml`
- Generate: `<repo-root>\build\mod\Data\Quests\darkpassengertest\trosecko\dark_within_t.xml`
- Generate: `<repo-root>\build\mod\Data\Scripts\mods\generated\dp_candidate_catalog.lua`
- Modify: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`

**Step 1: Write failing regional generation tests**

Require every enabled candidate to appear exactly once in Lua and only in the
matching regional quest graph. Require every generated marker to resolve an
existing regional `SoulAsset SharedSoulGuids` alias. Reject entity-link-only
aliases.

**Step 2: Run RED**

Expected: current Kuttenberg-only generator fails.

**Step 3: Implement region-partitioned generation**

Generate both quest files from one catalogue and region-specific templates.

**Step 4: Add scale guard**

Report candidate count and generated XML size per region. Fail on configurable
limits rather than silently producing an untestable graph.

**Step 5: Run GREEN**

Expected: structural XML and catalogue tests pass for both regions.

### Task 6: Implement nearest-settlement selection

**Files:**
- Modify: `<repo-root>\build\mod\Data\Scripts\mods\darkpassengertest.lua`
- Modify: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`

**Step 1: Write failing selector tests**

Require:

- planar squared-distance settlement ordering;
- selection only inside the requesting region;
- nearest eligible settlement wins;
- empty unsafe settlement falls through to the next;
- selected settlement remains fixed after Henry moves;
- one global active case despite `cases[region]` storage;
- weighted random selection among eligible local candidates.

**Step 2: Run RED**

Expected: hard-coded `pritoky` selection fails.

**Step 3: Implement minimal regional case store**

Add `cases[region]` and a one-active-case policy. Resolve Henry's position only
when opening a new case.

**Step 4: Implement local candidate resolution**

Apply static safety filters first and runtime entity/Soul/alive filters second.
Preserve bounded delayed retries for temporarily unloaded candidates.

**Step 5: Run GREEN**

Expected: selector and all existing lifecycle tests pass.

### Task 7: Wire region-specific selection requests

**Files:**
- Modify: `<repo-root>\build\mod\Data\Libs\Tables\ai\ScriptContext__darkpassengertest.xml`
- Modify: both regional quest templates
- Regenerate: both regional quest XML files
- Modify: `<repo-root>\build\mod\Data\Scripts\mods\darkpassengertest.lua`
- Modify: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`

**Step 1: Write failing request-routing tests**

Require unambiguous Kuttenberg and Trosky request contexts and no hard-coded
Pritoky call.

**Step 2: Run RED**

Expected: the shared Pritoky request fails.

**Step 3: Add regional contexts**

Route each quest graph to the matching selector region while keeping the
existing PlayerEventDispatcher-driven polling lifecycle.

**Step 4: Run GREEN**

Expected: request routing, marker generation, lifecycle, and dependency checks
all pass.

### Task 8: Incremental runtime validation

**Files:**
- Update: `<repo-root>\evidence\world-data-sources.md`

**Step 1: Validate generated Pritoky resident pool**

Retail-test repeated cases, dead filtering, marker identity, selected-target
death by multiple causes, satisfaction expiry, and fresh selection on the next
cycle. Include at least one policy-approved side-quest resident if the
extracted evidence is clear enough.

**Step 2: Validate multiple Kuttenberg settlements**

Test inside settlements, between two settlements, and in distant wilderness.
Confirm logs show the mathematically nearest eligible settlement.

**Step 3: Validate Trosky**

Repeat the same cases in the second region.

**Step 4: Validate persistence**

Save/reload after target selection and after travelling away. The target must
remain fixed.

### Task 9: Package, deploy, and document

**Files:**
- Build: `<repo-root>\build\mod\darkpassengertest-world-selection.pak`
- Deploy: dev and retail `b_DarkPassengerTest`
- Document: `<local-wiki-root>\kcd2-modding-technical-reference.md`

**Step 1: Run the full suite**

```powershell
pwsh -NoProfile -File "<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1"
```

Expected: `RESULT: PASS`.

**Step 2: Rebuild from scratch**

Use 7-Zip ZIP mode with `-mtc=off`, test the archive, and verify generated XML
and Lua are present.

**Step 3: Deploy safely**

Require the game closed, back up both installed paks, deploy identical bytes,
and compare SHA-256.

**Step 4: Update Wiki after retail confirmation**

Record only empirically confirmed extraction sources, selector behavior,
PlayerEventDispatcher dependency, graph-size findings, and remaining limits.

## Unresolved questions

- Reliable main-story and immortality fields in extracted data.
- First side-quest resident safe enough for the Pritoky acceptance test.
- Regional graph-size limit before quest subdivision.

## Unresolved questions

- Which local files/database expose the complete persistent Soul roster?
- Which source gives authoritative settlement centers or boundaries?
- Which fields reliably identify quest-critical and immortal NPCs?
- How many generated candidate states load safely per regional quest?
