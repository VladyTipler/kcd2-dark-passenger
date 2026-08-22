# CaseKit Area Listening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace NPC-pair overhearing with a reusable F-bound timed investigation action inside a compiled quest area.

**Architecture:** StoryPack data compiles an area-action descriptor into the regional bundle and generated runtime catalog. The native graph exposes active-area state; one hot-reload-safe Lua handler validates context, runs the two-hour fade/time effect and forwards completion through the existing evidence signal. The obsolete NPC action, pair poller and staging watchdog are removed.

**Tech Stack:** PowerShell CaseKit compiler/tests, KCD2 Skald XML, Lua, PlayerEventDispatcher, retail RCON acceptance.

---

### Task 1: Lock the replacement contract in tests

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-InteractiveOverheardRuntime.ps1`
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-CaseGuidanceCompiler.ps1`
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-CaseKitRegionalBundleIntegration.ps1`

1. Replace NPC-pair/action expectations with area-action schema, compiled catalog and regional signal assertions.
2. Add negative assertions for obsolete `Action():action("butcher")`, pair readiness and staging/watchdog exports.
3. Run focused tests and confirm RED for the missing area-action runtime.

### Task 2: Compile the reusable timed area action

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\tools\CaseSpecCompiler.psm1`
- Modify: `H:\KCD2Mod\DarkPassenger\tools\Compile-CaseSpecs.ps1`
- Modify: `H:\KCD2Mod\DarkPassenger\tools\Generate-VictimArtifacts.ps1`
- Modify: regional quest template(s) under `H:\KCD2Mod\DarkPassenger\src\Data\Quests\darkpassengertest\`

1. Preserve an authored `timed-area-action` descriptor with prompt/message keys, `10:00-22:00`, duration `2` and completion signal.
2. Emit deterministic regional graph/catalog data connected to the already compiled local guidance area.
3. Fail the build when a mandatory action has no resolvable area or completion signal.
4. Run compiler and regional integration tests to GREEN.

### Task 3: Implement isolated F handling and time passage

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpoverheardevidence.lua`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\darkpassengertest.lua`
- Modify only if shared dispatcher wiring requires it: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpinteractions.lua`

1. Add pure validation tests for active token, time boundary, one-shot and unsafe contexts.
2. Register one hot-reload-safe F event trampoline.
3. Show/hide the localized prompt only while the action is eligible in the active area.
4. On F, run fade/message/two-hour passage and dispatch existing evidence completion exactly once.
5. Outside hours, show the authored denial without changing time or progress.
6. Run runtime tests to GREEN.

### Task 4: Remove the superseded NPC-pair implementation

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpoverheardevidence.lua`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpinteractions.lua`
- Modify: compiler/generator files owning pair-only output
- Modify: affected tests and docs

1. Delete NPC action injection, distance gate, pair polling, staging/watchdog commands and pair-only state.
2. Retain shared dialogue/NPC debug facilities only when referenced by another live feature.
3. Regenerate artifacts and prove no stale pair interaction survives in source, build or installed package.

### Task 5: Build, review and retail acceptance

**Files:**
- Regenerate: `H:\KCD2Mod\DarkPassenger\build\`
- Update after live proof: `C:\Users\Vladislav\Obsidian Vaults\LLM Wiki\kcd2-modding-technical-reference.md`
- Update after live proof: `C:\Users\Vladislav\Obsidian Vaults\LLM Wiki\kcd2-quest-sdk.md`

1. Run all focused tests, then the relevant master suite and production build.
2. Run `/simplify` against the feature diff and repeat focused verification.
3. Install the generated mod and launch retail with dev mode/bridge.
4. Prove: prompt only in area; F without aim; no extended rob/knockout interactions; two hours and one clue; outside-hours denial; save/load cleanup.
5. Crystallize and integrate the proven mechanism into the existing Wiki pages.

## Unresolved questions

- Exact native prompt API for showing the F glyph without taking ownership of unrelated F actions; resolve from vanilla reference before Task 3 implementation.
- Exact safe-context probe for yielding to higher-priority vanilla F actions; prove in retail acceptance.
