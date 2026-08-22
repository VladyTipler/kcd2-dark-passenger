# CaseKit Automatic Settlement Semantics Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use test-driven-development to implement this plan task-by-task.

**Goal:** Compile compatible CaseKit stories for every indexed settlement without requiring a manual settlement profile.

**Architecture:** The KCD2 world adapter infers conservative semantic capabilities from native actor/container metadata. The authored compiler runs compatibility against the complete semantic index, then applies optional reviewed settlement profiles as overrides. The KCD2 backend consumes generated settlement metadata with profile overrides when present.

**Tech Stack:** PowerShell 7, JSON authoring contracts, existing CaseKit compiler/test harness.

---

### Task 1: Prove the missing boundary - completed

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\casekit\tests\Test-AuthoredCompilerCli.ps1`
- Modify: `H:\KCD2Mod\DarkPassenger\casekit\tests\Test-WorldSemanticIndex.ps1`

1. Add a failing real-CLI assertion that Troskovice is evaluated and produces a compatible variant without `troskovice.profile.json`.
2. Add focused semantic inference assertions for inn staff, dialogue eligibility, overheard actors and non-trade evidence containers.
3. Run both suites and confirm failures are caused by the profile whitelist and missing inference.

### Task 2: Remove the whitelist and infer conservative semantics - completed

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\casekit\adapters\kcd2\CaseKit.Kcd2World.psm1`
- Modify: `H:\KCD2Mod\DarkPassenger\casekit\core\CaseKit.Profiles.psm1`
- Modify: `H:\KCD2Mod\DarkPassenger\casekit\cli\Compile-CaseKit.ps1`

1. Expand deterministic role/place inference from native faction, character and editor-layer metadata.
2. Derive safe dialogue, overheard and evidence-container capabilities; never infer trade storage as evidence.
3. Preserve reviewed profiles as optional additive overrides.
4. Pass the complete world index to compatibility solving.
5. Re-run focused tests until green.

### Task 3: Generate backend metadata for unprofiled settlements - completed

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\casekit\adapters\kcd2\CaseKit.Kcd2Backend.psm1`
- Modify: `H:\KCD2Mod\DarkPassenger\casekit\tests\Test-Kcd2BackendAdapter.ps1`
- Modify: `H:\KCD2Mod\DarkPassenger\casekit\tests\Test-AuthoredCompilerCli.ps1`

1. Build required native settlement metadata from compiled bindings when no reviewed profile exists.
2. Keep profile-native values authoritative when supplied.
3. Prove the real CLI emits native-ready Troskovice output.

### Task 4: Regenerate, verify and document - completed

**Files:**
- Regenerate: `H:\KCD2Mod\DarkPassenger\config\world-semantic-index.json`
- Update: `H:\KCD2Mod\DarkPassenger\casekit\README.md`
- Update: `H:\KCD2Mod\DarkPassenger\docs\plans\2026-08-03-kcd2-casekit.md`

1. Rebuild the semantic index and CaseKit artifacts deterministically.
2. Run focused suites, real compiler boundary, master suite and build.
3. Run simplification review on the feature diff.
4. Update task progress and project Wiki.

## Result

- Manual settlement profiles are optional reviewed overrides, not a discovery
  whitelist.
- The world adapter infers conservative tavern roles, dialogue/overheard
  capabilities and non-trade evidence containers from indexed native data.
- The backend emits scoped bindings keyed by case, region and settlement while
  retaining one regional quest container.
- Runtime readiness requires an exact scoped binding and covered variant ID;
  quest-item placement targets only the selected settlement container.
- Every generated evidence-stash alias now receives a level-registry
  `WaitingLink`; reviewed native profiles override inference and alias/container
  conflicts fail the build.
- A binding covers only variants with the same concrete native-role signature;
  mixed-case item/request GUIDs resolve consistently in Lua.
- The current authored deck produces 56 native-ready variants across seven
  compatible settlements. Troskovice contributes eight variants without a
  settlement profile.
- Focused boundary/compiler/runtime suites pass and the retail-root package
  build completes. The installed retail package matches the build artifact.

## Unresolved questions

None.
