# Fast Level Registry Merge Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce the clean Dark Passenger build from 250 seconds by replacing per-link full-file regex scans with one indexed batch merge.

**Architecture:** Keep `Build-Mod.ps1` as the orchestrator. Extract the pure large-XML merge into a PowerShell module that locates every required source/target entity in one regex pass, groups links by source, patches each source entity once, then returns the merged registry. Do not add caching or a second language until the benchmark proves they are needed.

**Tech Stack:** PowerShell 7, .NET regular expressions and strings, executable PowerShell tests, 7-Zip packaging.

---

### Task 1: Specify the batch merge contract

**Files:**
- Create: `tests/Test-LevelRegistryMerge.ps1`
- Create: `tools/LevelRegistryMerge.psm1`

1. Build a small `Objects` fixture with a level holder, two target areas and unrelated entities.
2. Add a quest-holder patch and three waiting links, including two links with the same source.
3. Assert exact source/target resolution, one inserted quest holder, preservation of unrelated XML, missing-GUID failure and no input mutation.
4. Run the test before the module exists and confirm RED.

### Task 2: Implement one-pass indexing and grouped insertion

**Files:**
- Create: `tools/LevelRegistryMerge.psm1`
- Test: `tests/Test-LevelRegistryMerge.ps1`

1. Insert the quest-holder block once before `</Objects>`.
2. Build one alternation regex from all required GUIDs and scan the registry once.
3. Store entity index, length, text and numeric `EntityId` in a GUID dictionary.
4. Group waiting links by source GUID and inject the complete link block once per source.
5. Apply source replacements from highest index to lowest.
6. Run the focused test and confirm GREEN.

### Task 3: Replace the quadratic build loop

**Files:**
- Modify: `tools/Build-Mod.ps1`
- Test: `tests/Test-DarkPassengerSatisfaction.ps1`

1. Import `LevelRegistryMerge.psm1`.
2. Replace the per-link `Regex.Matches`/`Remove`/`Insert` loop with one `Merge-LevelMissionObjects` call.
3. Keep the existing identity, duplicate-link and final XML validation guards.
4. Add elapsed-time output around regional registry merging so future regressions are visible.
5. Run focused and main regression tests.

### Task 4: Benchmark the real clean build

**Files:**
- No source changes unless the benchmark exposes a defect.

1. Run one clean `Build-Mod.ps1 -DevGameRoot ...` build.
2. Compare wall time against the 250.8-second baseline.
3. Validate all generated pak files and hashes through the existing test suite.
4. If the clean build remains above 30 seconds, schedule caching or a C# merger as a separate optimization; do not expand this patch pre-emptively.

### Task 5: Review and publish

1. Run `git diff --check` and inspect the feature diff for simplification.
2. Update the technical Wiki with the measured result only if the benchmark is successful.
3. Commit the optimizer separately from the innkeeper evidence feature and push.

## Unresolved questions

None.
