# CaseKit Interactive Eavesdropping Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Compile and run button-triggered overheard dialogues between two NPCs while retaining the existing proximity mode.

**Architecture:** Extend the StoryPack action contract with an explicit activation mode, materialize every overheard step as a finite compiled scene, and reuse the proven NonPlayer `switchdialog` path. A Lua interaction provider activates a deterministic scene signal; the existing evidence registry owns one-shot confidence and the cleanup manifest owns every generated signal.

**Tech Stack:** PowerShell 7 CaseKit/compiler modules, JSON StoryPacks, generated Skald XML/RPG tables, Lua runtime and script-based integration tests.

---

### Task 1: Authoring activation contract

**Files:**
- Modify: `casekit/core/CaseKit.Authoring.psm1`
- Modify: `content/stories/missing-traveler/threads.json`
- Modify: `casekit/tests/fixtures/authoring/v2/stories/composed-case-probe/threads.json`
- Test: `casekit/tests/Test-CaseBuilderContracts.ps1`

1. Add failing tests for required `interaction|proximity` activation and several overheard steps.
2. Run the contract suite and confirm failure on the missing contract.
3. Normalize and validate the activation mode; make existing fixtures explicit.
4. Run the contract suite and confirm green.

### Task 2: Finite overheard scene materialization

**Files:**
- Modify: `casekit/adapters/kcd2/CaseKit.Kcd2Materializer.psm1`
- Modify: `casekit/adapters/kcd2/CaseKit.Kcd2Backend.psm1`
- Modify: `casekit/adapters/kcd2/CaseKit.Legacy.psm1`
- Test: `casekit/tests/Test-Kcd2Materializer.ps1`
- Test: `casekit/tests/Test-Kcd2BackendAdapter.ps1`

1. Add failing tests for a collection of compiled scenes, concrete speakers and preserved legacy proximity behavior.
2. Run both suites and verify the expected missing fields.
3. Materialize stable step-scoped overheard scenes and adapt legacy input.
4. Run both suites and verify green parity.

### Task 3: Native compiler and real XML boundary

**Files:**
- Modify: `tools/CaseSpecCompiler.psm1`
- Modify: `tools/Compile-CaseSpecs.ps1`
- Modify: `tools/Generate-VictimArtifacts.ps1`
- Modify: `src/Data/Quests/darkpassengertest/kutnohorsko/dark_within_k.xml.template`
- Modify: `localization/Russian/text__darkpassengertest.xml`
- Modify: `localization/English/text__darkpassengertest.xml`
- Create: `tests/Test-InteractiveOverheardCompiler.ps1`

1. Write an integration test that compiles two scenes with different modes and asserts distinct signals, dialogues, ports and quest nodes.
2. Run it and confirm failure because only singular `native.overheard` exists.
3. Generalize the emitter to `overheardScenes`; retain the proximity scheduler and emit interaction-triggered state for interactive scenes.
4. Add the generic bilingual action hint.
5. Run the new test plus `tests/Test-OverheardEvidence.ps1` and legacy parity.

### Task 4: Lua interaction and one-shot state

**Files:**
- Modify: `src/Data/Scripts/mods/dpoverheardevidence.lua`
- Modify: `src/Data/Scripts/mods/darkpassengertest.lua`
- Test: `tests/Test-InteractiveOverheardRuntime.ps1`
- Test: `tests/Test-OverheardEvidence.ps1`

1. Add failing runtime contract tests for action eligibility, either-speaker dispatch, stale/dead/combat rejection and duplicate suppression.
2. Run them and confirm the interaction API is missing.
3. Register an `interactive_overheard` provider through `dpinteractions.lua`, activate the compiled scene buff and route completion through the existing evidence registry.
4. Run LuaCompiler plus both overheard suites.

### Task 5: Build, install and handoff

**Files:**
- Modify: `casekit/README.md`
- Modify: `docs/plans/2026-08-03-kcd2-casekit-design.md`

1. Run all CaseKit tests sequentially.
2. Run focused root compiler/runtime tests and `git diff --check`.
3. Run `tools/Build-Mod.ps1 -DevGameRoot H:\SteamLibrary\steamapps\common\KCD2Mod`.
4. Run the full packaged Dark Passenger regression.
5. Verify deployed files match the build and provide the exact live canary steps.

## Unresolved questions

- Exact Love Triangle overheard dialogue copy remains collaborative content work after the mechanism passes live acceptance.

