# Burial Combat Lock Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep corpse burial visible but disabled while Henry is in combat danger.

**Architecture:** Extend the existing `CanBury` single source of truth with the
native Soul combat predicate. Existing action construction and invocation-time
revalidation propagate the result to both HUD and execution without another
state machine.

**Tech Stack:** KCD2 Lua, native Soul/UIAction APIs, XML localization, PowerShell
structural regression tests.

---

### Task 1: Add red combat-lock regressions

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1`

1. Assert that `dpburial.lua` calls `actor.soul:IsInCombatDanger()`.
2. Assert that `CanBury` returns `@dp_burial_in_combat` for combat danger.
3. Assert that English and Russian localization contain
   `dp_burial_in_combat`.
4. Run:
   `powershell -ExecutionPolicy Bypass -File H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1`
5. Expected: only the new combat-lock assertions fail.

### Task 2: Implement the minimal combat gate

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpburial.lua`
- Modify: `H:\KCD2Mod\DarkPassenger\localization\English\text__darkpassengertest.xml`
- Modify: `H:\KCD2Mod\DarkPassenger\localization\Russian\text__darkpassengertest.xml`

1. Add a protected native combat-danger helper that fails open when the binding
   is unavailable.
2. Call it from `CanBury` before inventory and ground checks.
3. Return `@dp_burial_in_combat` when active.
4. Add localized disabled reasons.
5. Rerun the structural suite; expected: PASS.

### Task 3: Verify, simplify, build, and deploy

**Files:**
- Verify all modified source, tests, and package output.

1. Run the quest-item catalog tests.
2. Run the complete structural suite and XML parsing checks.
3. Run `git diff --check`, inspect the feature diff for simplification, and
   build the full mod.
4. Back up the installed dev mod and deploy the built package.
5. Compare installed and built trees.

### Task 4: Live validation and documentation

1. In dev build, enter combat near a corpse and verify that hold-`F` burial is
   visible but disabled with the localized reason.
2. Leave combat danger and verify that burial becomes available and completes.
3. Verify that a buried corpse clears native corpse-observer state.
4. Commit the validated code locally, then update
   `[[KCD2 Modding - Technical Reference]]`.

## Нерешённые вопросы

Нет.
