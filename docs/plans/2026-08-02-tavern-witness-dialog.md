# Tavern Witness Dialogue Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a text-only bilingual Pritoky maid dialogue that starts after Vojtech's letter and reveals the selected suspect after one `+20` evidence award.

**Architecture:** Register a fixed canary witness with Storm and expose a quest-owned `FaderDialog`. A reusable Lua ledger owns availability, evidence awarding, and save/load idempotency; hidden buff tag 36 and ScriptContext `dp_witness_heard_kutnohorsko` bridge Lua to the quest graph. The existing reveal threshold and target-marker flow remain the only reveal mechanism.

**Tech Stack:** KCD2 Lua, Skald XML, Storm roles, RPG/AI tables, PowerShell 7 generation and static tests.

---

### Task 1: Add the failing witness contract

**Files:**
- Create: `H:\KCD2Mod\DarkPassenger\tests\Test-TavernWitnessDialog.ps1`

**Step 1:** Assert:
- `kpri_woman_10 -> DP_TAVERN_WITNESS` Storm rule and role GUID `5fa9523d-330b-42a1-8b04-1fd7fe5fb84b`;
- hidden availability buff GUID `a823ebb8-f3e3-4437-b885-9fafea591858` with tag 36;
- `tavern_witness_dialog_k.xml` has an availability input, heard output, approved response order, and no audio dependency;
- ScriptContext and bridge polling use `dp_witness_heard_kutnohorsko`;
- `DarkPassengerWitnessLead` exposes pure transition, start/restore/completion, `+20`, and one-shot state;
- RU/EN contain every approved key and distinctive copy;
- generator copies the child XML and emits witness objective/dialogue wiring.

**Step 2:** Run the new test with `-DevGameRoot`. Expected: FAIL because the witness implementation does not exist.

### Task 2: Register the static witness and bilingual dialogue

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Libs\Storm\roles\quests\darkpassengertest.xml`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Libs\Tables\rpg\role__darkpassengertest.xml`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Libs\Tables\rpg\buff_ai_tag__darkpassengertest.xml`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Libs\Tables\rpg\buff__darkpassengertest.xml`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Libs\Tables\ai\ScriptContext__darkpassengertest.xml`
- Create: `H:\KCD2Mod\DarkPassenger\src\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k\tavern_witness_dialog_k.xml`
- Modify: `H:\KCD2Mod\DarkPassenger\localization\Russian\text__darkpassengertest.xml`
- Modify: `H:\KCD2Mod\DarkPassenger\localization\English\text__darkpassengertest.xml`

**Step 1:** Add the fixed role, hidden persistent availability signal, and ScriptContext.

**Step 2:** Add the approved linear dialogue with localization keys only. Emit `heard` exactly once at sequence start/completion according to the proven innkeeper pattern.

**Step 3:** Add matching RU/EN objective, logs, prompt, and response keys. Parse all XML and verify UTF-8 without BOM.

### Task 3: Implement the reusable Lua ledger and bridge

**Files:**
- Create: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpwitnesslead.lua`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\darkpassengertest.lua`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpbelongings.lua`

**Step 1:** Implement generation-scoped pure transitions for `open`, `award`, and `restore`; persist `availableGeneration` and `awardedGeneration`.

**Step 2:** `Start(generation)` adds the availability buff idempotently after the accepted document read. `OnDialogueCompleted('kutnohorsko')` awards `20` via `DarkPassengerInvestigation.AddEvidence`, persists first, and removes availability. Duplicate calls return success without re-awarding.

**Step 3:** Load `dpwitnesslead.lua` before `dpbelongings.lua`. On a persisted letter read, restore witness availability unless the dialogue was already awarded.

**Step 4:** Add `witnessContext` to the existing quest bridge and poll it like the proven rumor context.

**Step 5:** Run LuaCompiler and the focused test.

### Task 4: Generate the witness objective and graph wiring

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml.template`
- Modify: `H:\KCD2Mod\DarkPassenger\tools\Generate-VictimArtifacts.ps1`

**Step 1:** Add conditional Kuttenberg placeholders for witness definitions, nodes, objective visual/state/type, objective metadata, and the edge that completes the evidence objective when tag 36 appears.

**Step 2:** In the Kuttenberg graph:
- tag 36 starts `DP_WitnessProgress.Active` and enables the FaderDialog;
- reveal tag completes `DP_WitnessProgress.Done`;
- dialogue `heard` activates `dp_witness_heard_kutnohorsko` on Henry;
- completion/reveal disables dialogue availability.

**Step 3:** Copy `tavern_witness_dialog_k.xml` into the final child directory and keep Trosky output free of canary-only wiring.

**Step 4:** Run the focused test and existing evidence/dialogue tests.

### Task 5: Build, deploy, and live-test once

**Step 1:** Build with explicit `-DevGameRoot` and verify all three PAK archives.

**Step 2:** Inspect the main PAK for the item, both dialogue definitions, reaction definitions, witness runtime, objective, role, tag, and ScriptContext.

**Step 3:** Deploy to `H:\SteamLibrary\steamapps\common\KCD2Mod\Mods\b_DarkPassengerTest` while the game is stopped and compare SHA-256 hashes.

**Step 4:** Launch Steam app 2429020 and validate: letter copy, random Henry reaction, new witness objective, no witness marker, one maid dialogue, `50 -> 70`, target marker, repeat silence, and save/load persistence.

## Unresolved questions

None.
