# Global Corpse Burial Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a safe global action that buries any dead human body and integrates clean target disposal with the active Case.

**Architecture:** Generate a base-game quest-item GUID catalog, inject one hot-reload-safe action through `BasicAIActions.GetActions`, keep the seven-second native SkipTime flow in `dpburial.lua`, and let `dpaftermath.lua` own Case resolution.

**Tech Stack:** KCD2 Lua, retail `Scripts.pak`/`Tables.pak`, PowerShell 7 tests and generation, native UIAction/Calendar/Audio APIs, 7-Zip packaging.

---

## Constraints

- Work directly on `feature/aftermath`; no worktree.
- TDD: structural/generator tests fail before implementation.
- Shovel GUID: `85409fc6-36ff-4de7-b337-e2889e435f1b`.
- Diggable surfaces: soil, mud, grass, forest, gravel, road, field.
- Seven real seconds, one game hour, energy `-10`, nourishment `-5`.
- Quest-item uncertainty fails closed.
- Burial never erases reports, alarms, wanted state, or testimony.
- Vanilla corpse actions remain on `E`; burial is a dedicated native
  hold-`F` secondary action.

### Task 1: Quest-item catalog

**Files:**
- Create: `H:\KCD2Mod\DarkPassenger\tools\Generate-QuestItemCatalog.ps1`
- Create: `H:\KCD2Mod\DarkPassenger\tests\Test-GenerateQuestItemCatalog.ps1`
- Generate: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\generated\dp_quest_item_catalog.lua`

Write a fixture-first parser test, implement deterministic extraction of every
`IsQuestItem="true"` GUID, then generate the current 293-entry base catalog.

### Task 2: Burial runtime

**Files:**
- Create: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpburial.lua`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\darkpassengertest.lua`
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1`

Add failing structural checks, then implement dead-human validation, shovel and
quest-item gates, physics surface validation, action injection, SkipTime,
costs, delayed entity removal, and failsafe cleanup.

For the interaction regression, assert that an eligible burial uses the native
`butcher` action with `AHT_HOLD`, and that fast-context injection does not skip
the action merely because the vanilla primary action already exists. Run the
structural suite red, remove that skip, then rerun green.

### Task 3: Case integration and localization

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpaftermath.lua`
- Modify: `H:\KCD2Mod\DarkPassenger\localization\English\text__darkpassengertest.xml`
- Modify: `H:\KCD2Mod\DarkPassenger\localization\Russian\text__darkpassengertest.xml`

Add the target-burial callback, preserve all noisy locks, and localize the
action, disabled reasons, and SkipTime line.

### Task 4: Verify and deploy

Run generator tests, 630+ structural checks, Lua parsing, build, PAK integrity,
and installed-tree comparison. Install to dev, reload, and live-test one
blocked and one successful burial. With a valid corpse and shovel, verify the
HUD keeps the vanilla `E` action and visibly exposes hold-`F` for burial.

### Task 5: Finish

Simplify `git diff`, commit locally, then crystallize and integrate the verified
contracts into `[[KCD2 Modding - Technical Reference]]`.

## Нерешённые вопросы

Нет.
