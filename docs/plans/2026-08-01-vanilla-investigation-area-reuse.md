# Vanilla Investigation Area Reuse Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the crashing custom investigation layer with a three-area vanilla Pritoky search union.

**Architecture:** Bind one marker alias to the village (`d0fa0ece-6af5-19f6`), inn (`d2fc29a3-6787-141c`), and deserter-camp (`1b6b6d4e-905c-4f9e`) TriggerAreas. Keep custom geometry tooling dormant; active build and dev overlay contain only mission objects and waiting links.

**Tech Stack:** PowerShell 7, Lua, Skald quest XML, KCD2 level registries, Pester-style executable test scripts.

---

### Task 1: Lock the vanilla-link contract

**Files:**
- Test: `tests/Test-DarkPassengerSatisfaction.ps1`
- Test: `tests/Test-DevLevelOverlay.ps1`

1. Restore assertions for all three vanilla GUIDs/names under one alias and no quest profile.
2. Assert level PAK and dev overlay exclude custom layer, `whdata_1`, and `leveldata.xml`.
3. Run both tests and confirm failures reference current custom runtime-layer output.

Run:
`pwsh -NoProfile -File tests/Test-DarkPassengerSatisfaction.ps1`

Run:
`pwsh -NoProfile -File tests/Test-DevLevelOverlay.ps1`

Expected: FAIL before implementation.

### Task 2: Restore the proven static binding

**Files:**
- Restore: `src/Data/Levels/kutnohorsko/waitinglinks.xml`
- Modify: `src/Data/Scripts/mods/darkpassengertest.lua`
- Modify: `src/Data/Quests/darkpassengertest/kutnohorsko/dark_within_k.xml.template`
- Modify: `tools/Build-Mod.ps1`
- Modify: `tools/Deploy-DevLevelOverlay.ps1`
- Revert experimental edits: `config/investigation-areas.json`
- Revert experimental edits: `tools/Generate-InvestigationAreas.ps1`
- Revert experimental edits: `tools/InvestigationAreaGeometry.psm1`
- Revert experimental edits: `tests/Test-InvestigationAreaGeometry.ps1`

1. Point the static alias and Lua fallback collection to all three vanilla Pritoky areas.
2. Remove the custom profile layer from the quest template.
3. Stop build/deploy from generating or copying runtime-layer registries.
4. Preserve the committed standalone geometry generator for future compiler work.
5. Run area, build, and overlay tests until green.

Run:
`pwsh -NoProfile -File tests/Test-InvestigationAreaGeometry.ps1`

Run:
`pwsh -NoProfile -File tests/Test-DarkPassengerSatisfaction.ps1`

Run:
`pwsh -NoProfile -File tests/Test-DevLevelOverlay.ps1`

Expected: PASS.

### Task 3: Build, deploy, and prove live

**Files:**
- Generated: `build/mod/**`
- Deploy: dev build loose Kuttenberg overlay and mod package

1. Build the mod and inspect archive contents.
2. Back up and deploy the minimal dev overlay.
3. Cold-start dev build once.
4. Confirm bridge availability, `LEVEL_LOAD_COMPLETE`, no custom-layer warnings/crash, and visible Pritoky search area after quest restart.
5. Only after live proof, update the Wiki and commit/push.

Unresolved questions: none for this slice. Automatic area discovery for other settlements is next task.
