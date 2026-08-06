# CaseKit Cross-Region Regional Bundles Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use test-driven-development task-by-task.

**Goal:** Make every StoryPack playable in every semantically compatible
settlement while retaining one native quest container per region.

**Architecture:** Compatibility is region-neutral. Backend emits one logical
CaseSpec per StoryPack plus exact regional settlement bindings. Compiler emits
case-gated story modules and merges them into one regional native bundle.

**Tech Stack:** PowerShell 7, JSON contracts, Lua runtime catalogs, KCD2
Skald/Concept XML, existing integration harness.

---

### Task 1: Remove hidden regional compatibility policy

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\casekit\cli\Compile-CaseKit.ps1`
- Modify: `H:\KCD2Mod\DarkPassenger\casekit\core\CaseKit.Compatibility.psm1`
- Test: `H:\KCD2Mod\DarkPassenger\casekit\tests\Test-CompatibilitySolver.ps1`
- Test: `H:\KCD2Mod\DarkPassenger\casekit\tests\Test-AuthoredCompilerCli.ps1`

1. Add failing assertions for both StoryPacks in both regions.
2. Run focused tests and confirm adapter filtering causes RED.
3. Remove `StoryRegionMap` from production compatibility.
4. Re-run focused tests.

### Task 2: Split logical stories from regional native shells

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\config\casekit-kcd2-native.json`
- Modify: `H:\KCD2Mod\DarkPassenger\casekit\adapters\kcd2\CaseKit.Kcd2Backend.psm1`
- Test: `H:\KCD2Mod\DarkPassenger\casekit\tests\Test-Kcd2BackendAdapter.ps1`

1. Add RED for one CaseSpec per case code and bindings in both regions.
2. Add `nativeRegions` and migration-only anchors.
3. Emit region-neutral CaseSpecs plus scoped bindings for every region.
4. Validate deterministic output and exact binding coverage.

### Task 3: Compile story modules and regional bundles

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\tools\CaseSpecCompiler.psm1`
- Modify: `H:\KCD2Mod\DarkPassenger\tools\Compile-CaseSpecs.ps1`
- Modify: `H:\KCD2Mod\DarkPassenger\tools\Generate-VictimArtifacts.ps1`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml.template`
- Test: `H:\KCD2Mod\DarkPassenger\tests\Test-CaseSpecCompiler.ps1`
- Test: `H:\KCD2Mod\DarkPassenger\tests\Test-CaseSpecBuildIntegration.ps1`

1. Add RED proving two stories merge into one regional manifest entry.
2. Allocate deterministic active-case signals and story namespaces.
3. Gate story-specific dialogue/evidence/objective nodes by active case.
4. Merge definitions, nodes, assets, types, objectives and dialogue files.
5. Reject all native-name collisions before build.

### Task 4: Cross-boundary verification

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\casekit\tests\Test-AuthoredCompilerCli.ps1`
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-CaseVariantSelection.ps1`
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-CaseSpecBuildIntegration.ps1`

1. Prove cross-region variants are `native_ready`.
2. Prove exact case/region/settlement bindings and cleanup manifests.
3. Prove one `dark_within_k` and one `dark_within_t` output.
4. Run focused, integration, master and package-build suites.

### Task 5: Deliver

**Files:**
- Update: `H:\KCD2Mod\DarkPassenger\casekit\README.md`
- Update: `H:\KCD2Mod\DarkPassenger\docs\plans\2026-08-03-kcd2-casekit.md`
- Update: LLM Wiki KCD2 pages.

1. Run simplification review on the feature diff.
2. Build and install the retail package after game-process safety check.
3. Record hashes, test counts and live acceptance steps.

## Unresolved questions

None.
