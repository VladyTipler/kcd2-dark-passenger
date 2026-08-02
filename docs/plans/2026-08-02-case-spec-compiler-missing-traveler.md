# CaseSpec Compiler and Missing Traveler Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the hand-wired Pritoky investigation content with a deterministic CaseSpec compiler, preserve existing saves, and prove the same universal quest container with the `missing_traveler` case in Zhelejov.

**Architecture:** Human-authored bilingual CaseSpec JSON and separate settlement bindings are the source of truth. A PowerShell compiler validates them and emits build-only Lua catalog, dialogue/quest fragments, native role/signal rows, localization, and a compatibility report. Runtime persists stable case identity plus generation and resolves all content through the compiled catalog; the existing quest graph remains universal.

**Tech Stack:** PowerShell 7, JSON, Lua 5.1/KCD2 bindings, KCD2 quest XML, Storm roles, RPG tables, localization XML, existing static and LuaCompiler tests.

---

### Task 1: Define and validate CaseSpec

**Files:**
- Create: `content/cases/convenient-accident.case.json`
- Create: `config/case-settlement-bindings.json`
- Create: `tools/CaseSpecCompiler.psm1`
- Create: `tests/Test-CaseSpecCompiler.ps1`
- Modify: `tests/Test-DarkPassengerSatisfaction.ps1`

**Steps:**
1. Write failing tests for required case identity, stable numeric code, supported region/settlement, unique evidence IDs, confidence total, bilingual text, semantic roles, and deterministic validation errors.
2. Run `pwsh -NoProfile -File H:\KCD2Mod\DarkPassenger\tests\Test-CaseSpecCompiler.ps1`; expect RED because compiler/schema do not exist.
3. Add the minimal validator and encode the current Pritoky story without changing its IDs, rewards, or text.
4. Re-run the focused test; expect PASS.
5. Commit: `feat: define case spec contract`.

### Task 2: Compile a deterministic runtime catalog

**Files:**
- Create: `tools/Compile-CaseSpecs.ps1`
- Create: `tests/Test-CaseSpecGeneration.ps1`
- Generated: `build/mod/Data/Scripts/mods/generated/dp_case_catalog.lua`
- Generated: `build/generated/cases/case-compatibility.json`

**Steps:**
1. Write failing golden assertions for deterministic order, Lua escaping, stable codes, evidence sequence, role bindings, and byte-identical repeated output.
2. Run the generation test; expect RED because no artifacts are emitted.
3. Implement pure render helpers plus the compiler entry point. Generated files stay under `build`; authored JSON stays the source of truth.
4. Run the compiler twice and focused test; expect PASS and identical hashes.
5. Commit: `feat: compile case specs`.

### Task 3: Cross the real build boundary

**Files:**
- Modify: `tools/Build-Mod.ps1`
- Modify: `tests/Test-DarkPassengerSatisfaction.ps1`
- Modify: `README.md`

**Steps:**
1. Add a failing integration assertion that a clean build invokes the real compiler and packages the generated catalog.
2. Run the master test; expect RED at the new boundary assertion.
3. Invoke `Compile-CaseSpecs.ps1` after staging source and before victim/quest generation. Package generated localization rather than reading case strings directly from source localization.
4. Run `Build-Mod.ps1 -SkipPackaging` and the master test; expect PASS.
5. Commit: `build: integrate case compiler`.

### Task 4: Migrate the live Pritoky case without rerolling

**Files:**
- Modify: `src/Data/Scripts/mods/darkpassengertest.lua`
- Modify: `src/Data/Scripts/mods/dpcasecontent.lua`
- Delete after parity: `src/Data/Scripts/mods/content/dp_case_convenient_accident.lua`
- Modify: `tests/Test-CaseContent.ps1`
- Create: `tests/Test-CaseContentMigration.ps1`

**Steps:**
1. Write failing Lua-state tests for schema v1 slot `1/1` migrating to stable `convenient_accident` code, unchanged generation, unchanged target/progress, and idempotent restore.
2. Run both case-content tests; expect RED.
3. Load the generated catalog, persist stable case/variant codes in schema v2, and add the explicit v1 migration. Fail closed when an ID cannot be resolved.
4. Prove the compiled Pritoky catalog matches existing rumor/evidence IDs and rewards; remove the authored Lua duplicate.
5. Run LuaCompiler plus focused tests; expect PASS.
6. Commit: `refactor: load compiled case content`.

### Task 5: Generate existing Pritoky native wiring

**Files:**
- Modify: `tools/Generate-VictimArtifacts.ps1`
- Modify: `tools/CaseSpecCompiler.psm1`
- Modify: `content/cases/convenient-accident.case.json`
- Modify: `config/case-settlement-bindings.json`
- Modify: `tests/Test-InnkeeperRumorDialog.ps1`
- Modify: `tests/Test-TavernWitnessDialog.ps1`
- Modify: `tests/Test-VojtechBelongingsEvidence.ps1`
- Modify: `tests/Test-CaseSpecGeneration.ps1`

**Steps:**
1. Add failing parity tests for the current FaderDialog nodes, Storm/RPG roles, ScriptContexts, hidden signal GUIDs/tags, document data, and RU/EN localization keys.
2. Generate these fragments from CaseSpec plus bindings into the staging tree; preserve every live-proven Pritoky GUID and key.
3. Remove Kuttenberg/Pritoky-specific string assembly from `Generate-VictimArtifacts.ps1`; consume compiler outputs instead.
4. Run focused dialogue/evidence tests and full master suite; expect PASS with no Pritoky artifact drift.
5. Commit: `refactor: generate pritoky case wiring`.

### Task 6: Generalize evidence runtime adapters

**Files:**
- Create: `src/Data/Scripts/mods/dpcaseevidence.lua`
- Modify: `src/Data/Scripts/mods/dpevidence.lua`
- Modify: `src/Data/Scripts/mods/dpbelongings.lua`
- Modify: `src/Data/Scripts/mods/dpwitnesslead.lua`
- Modify: `src/Data/Scripts/mods/darkpassengertest.lua`
- Create: `tests/Test-CaseEvidenceRuntime.ps1`
- Modify: existing evidence tests

**Steps:**
1. Write failing state-machine tests proving evidence is selected from the active compiled case, awarded once per generation, ordered by prerequisites, and restored without replay.
2. Implement a generic manifest-driven adapter while retaining legacy commands and v1/v2 persisted-state migration.
3. Make innkeeper, readable document, and witness handlers resolve semantic bindings from the active case instead of Pritoky constants.
4. Run focused runtime tests and LuaCompiler; expect PASS.
5. Commit: `refactor: generalize case evidence runtime`.

### Task 7: Discover and lock the Zhelejov bindings

**Files:**
- Modify: `config/case-settlement-bindings.json`
- Create: `evidence/zhelejov-case-bindings.md`
- Create: `tests/Test-ZhelejovBindings.ps1`

**Steps:**
1. Extract Zhelejov residents, innkeeper candidates, guest-ledger containers, and stablehand/regular candidates from current world exports and native registries.
2. Add failing validation for entity existence, correct `trosecko/zhelejov` ownership, enabled/alive-capable male target pool, and unique semantic roles.
3. Record only evidence-backed IDs/GUIDs; reject unresolved bindings instead of guessing.
4. Run the binding test; expect PASS.
5. Commit: `data: bind zhelejov case roles`.

### Task 8: Add Missing Traveler

**Files:**
- Create: `content/cases/missing-traveler.case.json`
- Modify: `tests/Test-CaseSpecCompiler.ps1`
- Modify: `tests/Test-CaseSpecGeneration.ps1`
- Create: `tests/Test-MissingTravelerCase.ps1`

**Steps:**
1. Write failing content assertions for Zhelejov-only eligibility, male non-story target policy, confidence `20 + 30 + 20 = 70`, three-step ordering, and bilingual localization.
2. Author the approved case: innkeeper rumor, Matej's forged guest-ledger note, Henry reaction, stablehand/regular witness, then target reveal.
3. Compile and verify deterministic GUID/key generation and zero collision with Pritoky.
4. Run focused tests; expect PASS.
5. Commit: `feat: add missing traveler case`.

### Task 9: Generate Trosky quest and dialogue artifacts

**Files:**
- Modify: `tools/Generate-VictimArtifacts.ps1`
- Modify: universal Trosky quest template under `src/Data/Quests/darkpassengertest/trosecko/`
- Modify: `tests/Test-DarkPassengerSatisfaction.ps1`
- Modify: `tests/Test-QuestSaveCompatibility.ps1`

**Steps:**
1. Add failing integration assertions for generated Zhelejov dialogues, contexts, roles, region/settlement selection, evidence signals, and final native target reveal in the existing universal graph.
2. Emit the Trosky fragments from compiler outputs without creating a story-specific quest graph.
3. Build twice; confirm identical artifacts and no missing placeholders.
4. Run the full suite with real AssetLinker data; expect all checks PASS.
5. Commit: `feat: wire missing traveler into universal quest`.

### Task 10: Package and live-prove the cross-region case

**Files:**
- Modify only if evidence requires fixes.

**Steps:**
1. Run `git diff --check` and the full master suite.
2. Build/package with explicit dev root and deploy to the dev build.
3. Use a dedicated disposable save started directly in Trosky/Zhelejov; do not touch the user's inventory-rich save.
4. Verify: first launch selects `missing_traveler`; save/load keeps case, target, confidence, and bindings; each clue awards once; 70 reveals the same living target; kill/aftermath/hunger/burial remain intact.
5. Re-run focused tests for any live fix, then full suite.
6. Commit: `test: prove missing traveler live flow`.

### Task 11: Document and publish the milestone

**Files:**
- Modify: `README.md`
- Modify: existing Dark Passenger technical Wiki page
- Modify: roadmap/task file if present

**Steps:**
1. Run a manual simplification review over the feature diff; remove duplication without changing behavior.
2. Update README roadmap and Wiki with the proven CaseSpec contract, generated-vs-authored boundary, migration rule, Zhelejov bindings, build command, and live acceptance evidence.
3. Run `git diff --check`, focused tests, then full suite one final time.
4. Commit: `docs: document case compiler workflow`.
5. Push the branch after all checks are green.

## Unresolved questions

- Exact Zhelejov innkeeper, ledger container, and witness IDs: resolve from world data in Task 7.
- Exact disposable dev-save bootstrap command: resolve immediately before Task 10.
