# Generated Case Lifecycle Cleanup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Generate and execute exact, idempotent cleanup manifests so repeated investigations start with fresh dialogue, evidence, items, and presentation state.

**Architecture:** CaseKit emits ownership data per compiled variant. A shared Lua lifecycle executor clears that data and uses a next-tick activation barrier before republishing the new generation. Existing content selection and replay history remain authoritative.

**Tech Stack:** PowerShell 7 compiler/tests, Lua runtime, Skald/CryEngine buff and context bridges.

---

### Task 1: Compiler cleanup manifest contract

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\tools\CaseSpecCompiler.psm1`
- Test: `H:\KCD2Mod\DarkPassenger\tests\Test-CaseLifecycleCompiler.ps1`

1. Write a failing test compiling `missing_traveler` and asserting every variant has a schema-versioned manifest.
2. Assert manifest owns evidence codes, availability roles, temporary signal buffs, entity contexts, scene IDs, and physical items.
3. Assert `retention = case` evidence is removable and `retention = permanent` trophy is preserved.
4. Implement manifest construction from CaseSpec, stable signal definitions, variant bindings, scenes, and trophy metadata.
5. Run the focused compiler test; expect all assertions to pass.

### Task 2: Runtime lifecycle executor

**Files:**
- Create: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpcaselifecycle.lua`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\darkpassengertest.lua`
- Test: `H:\KCD2Mod\DarkPassenger\tests\Test-CaseLifecycleRuntime.ps1`

1. Write failing structural and Lua self-test assertions for manifest resolution, idempotent cleanup, retention filtering, and a delayed activation barrier.
2. Implement `ClearCaseArtifacts`, `PrepareCaseGeneration`, `ActivatePreparedGeneration`, and `Reconcile`.
3. Use existing evidence/witness/overheard adapters to disable availability; remove generated temporary buffs directly.
4. Remove player items only for manifest entries with `retention = case`; preserve permanent/loot entries.
5. Load the lifecycle module before content/evidence modules.
6. Run focused runtime tests; expect all assertions to pass.

### Task 3: Cross-boundary lifecycle wiring

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\darkpassengertest.lua`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpevidence.lua`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dphunger.lua`
- Test: `H:\KCD2Mod\DarkPassenger\tests\Test-ReplayableCaseLoop.ps1`

1. Extend the integration test to load generated catalog data and exercise close -> select -> open -> delayed activate.
2. Verify the old generation is cleaned before selection.
3. Verify new evidence is pending and Lavrentiy's availability is republished only after the cleanup barrier.
4. Verify hunt completion clears case-retained inventory evidence but preserves the trophy.
5. Implement minimal lifecycle calls at target replacement, evidence open, and resolved hunt.
6. Run the integration test; expect pass.

### Task 4: Build and regression verification

**Files:**
- Modify if needed: `H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1`

1. Run focused compiler/runtime/replay tests.
2. Run all CaseKit compiler boundary tests.
3. Run `Test-DarkPassengerSatisfaction.ps1` and require every assertion green.
4. Build the mod once and verify generated manifests in staged Lua catalogs.

### Task 5: Cold deployment and live replay proof

**Files:**
- Deploy from: `H:\KCD2Mod\DarkPassenger\build\mod`
- Deploy to: `H:\SteamLibrary\steamapps\common\KCD2Mod\Mods\b_DarkPassengerTest`

1. Back up and cold-deploy the verified build.
2. Launch the dev game directly through `KingdomCome.exe`.
3. Start a fresh 50% hunger cycle in Zhelejov.
4. Verify native graph state, generated case/variant IDs, active area, and Lavrentiy's dialogue availability over the bridge.
5. Complete or reset the case, repeat it, and verify fresh availability and evidence state.

### Task 6: Repository and knowledge cleanup

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\README.md`
- Modify: relevant page under `C:\Users\Vladislav\Obsidian Vaults\LLM Wiki`

1. Audit probes, build outputs, deployment backups, and obsolete generated artifacts.
2. Keep reusable debug tools clearly separated; remove only proven obsolete source artifacts.
3. Update README roadmap and Wiki with the lifecycle contract and live evidence.
4. Run final verification on the exact staged diff.
5. Commit the clean project update and push the current branch.

## Unresolved questions

None.
