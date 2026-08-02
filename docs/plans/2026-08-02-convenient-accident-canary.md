# Convenient Accident Canary Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the technical innkeeper rumor action with one native authored investigation chain that awards 20 + 30 + 20 confidence and reveals the already selected murderer at 70.

**Architecture:** Keep reusable case/evidence state in Lua, authored content in a separate content catalog, and presentation/progression in the live Skald quest graph. Native dialogue outputs cross into Lua through a player `ScriptContext`; Lua persists the content/evidence transaction and returns journal changes through hidden buff tags. The existing short-F action remains a debug fallback until the native dialogue passes live save/load proof.

**Tech Stack:** KCD2 Lua, Skald quest XML, Storm roles, RPG/item tables, XML localization, PowerShell contract tests and build tooling.

**Execution:** Current checkout only. No worktree, no delegated agents, dev build only.

---

## Task 1: Lock the persistent case-content contract

**Files:**

- Create: `tests/Test-CaseContent.ps1`
- Create: `src/Data/Scripts/mods/dpcasecontent.lua`
- Create: `src/Data/Scripts/mods/content/dp_case_convenient_accident.lua`
- Modify: `src/Data/Scripts/mods/darkpassengertest.lua`
- Modify: `src/Data/Scripts/mods/dpevidence.lua`
- Modify: `tests/Test-InnkeeperRumorEvidence.ps1`

1. Add failing checks for a stable case identity, rumor identity, `source_stance`, `next_lead`, reward `20`, deterministic restore and one selection per investigation generation.
2. Run `powershell -ExecutionPolicy Bypass -File tests\Test-CaseContent.ps1`; confirm RED because the content runtime does not exist.
3. Implement a pure selector/state transition API in `dpcasecontent.lua`; keep the canary prose and numbers in the separate content file.
4. Persist `case_template_id`, `rumor_id` and generation through `Variables.GetGlobal/SetGlobal`; migrate an old active case to the canary without replacing its target.
5. Make `dpevidence.lua` consume the selected rumor reward/id instead of hard-coded `30`/`innkeeper_rumor`.
6. Run the focused tests and LuaCompiler; commit `feat: add persistent case content runtime`.

## Task 2: Add the native innkeeper dialogue boundary

**Files:**

- Create: `src/Data/Quests/darkpassengertest/kutnohorsko/dark_within_k/innkeeper_rumor_dialog_k.xml`
- Create: `src/Data/Libs/Storm/storm__darkpassengertest.xml`
- Create: `src/Data/Libs/Storm/roles/quests/darkpassengertest.xml`
- Create: `src/Data/Libs/Tables/rpg/role__darkpassengertest.xml`
- Modify: `src/Data/Quests/darkpassengertest/kutnohorsko/dark_within_k.xml.template`
- Modify: `src/Data/Libs/Tables/ai/ScriptContext__darkpassengertest.xml`
- Modify: `src/Data/Scripts/mods/darkpassengertest.lua`
- Modify: `src/Data/Scripts/mods/dpevidence.lua`
- Modify: `localization/English/text__darkpassengertest.xml`
- Modify: `localization/Russian/text__darkpassengertest.xml`
- Create: `tests/Test-InnkeeperRumorDialog.ps1`

1. Add failing XML contract tests for the custom role, `hasName kpri_innkeeper`, FaderDialog definition/node, active-case input gate, authored output trigger, ScriptContext bridge and localization parity.
2. Run the focused test; confirm RED.
3. Add the custom NPC role through Storm and a FaderDialog containing the approved eight-line exchange.
4. Drive its sequence with an input boolean connected to active investigation plus unconsumed rumor state; do not make the prompt available outside that state.
5. On dialogue completion, activate `dp_rumor_heard_kutnohorsko` on the player. Extend the existing polling bridge with rising-edge handling that calls a new idempotent `DarkPassengerEvidence.OnRumorCompleted` transaction.
6. Keep `AddRumorAction` only behind an explicit debug flag until the new dialogue passes live proof.
7. Run XML parse, focused tests and LuaCompiler; commit `feat: add authored innkeeper rumor dialogue`.

## Task 3: Prove Vojtech's belongings through live Lua

**Files:**

- Create: `src/Data/Scripts/mods/dpbelongings.lua`
- Create: `tests/Test-VojtechBelongingsEvidence.ps1`
- Modify: `src/Data/Scripts/mods/darkpassengertest.lua`
- Modify: `src/Data/Scripts/mods/dpevidence.lua`

1. Add failing contract tests for chest GUID
   `43e3efd7-6727-0f88`, vanilla document GUID
   `08a31823-a5c6-43f9-9b4b-27b8230a352f`, reward `30`, generation guards,
   one-shot persistence, `Stash.inventory:CreateItem` and
   `Minigame.WasBookOpened(documentGuid)`.
2. Run `C:\Program Files\PowerShell\7\pwsh.exe -ExecutionPolicy Bypass -File tests\Test-VojtechBelongingsEvidence.ps1`; expect RED because
   `dpbelongings.lua` does not exist.
3. Implement the minimal pure transition plus runtime adapter in
   `dpbelongings.lua`: place once, poll the native opened flag, call
   `DarkPassengerInvestigation.AddEvidence(30, "vojtech_belongings", generation)`
   once and stop stale timers by generation/serial.
4. Load the module from `darkpassengertest.lua` and start it only after the
   persisted innkeeper rumor is awarded. Preserve vanilla lock, ownership and
   trespass state.
5. Run the focused test until GREEN, then LuaCompiler and the full static suite.
6. Copy only the loose Lua changes into the running dev mod, execute
   `lua_reload_script Scripts/mods/dpbelongings.lua` and start the current
   generation through the HTTP bridge. Do not rebuild quest XML or restart.
7. Verify in `kcd.log`: chest resolved, exactly one document inserted, opened
   baseline false, reading changes it to true, confidence moves `20 -> 50`, and
   a second poll/read awards nothing.
8. Save/load after reading and verify the persisted generation suppresses both
   reinsertion and duplicate confidence; commit `feat: add Vojtech belongings clue`.

## Task 4: Add and persist the tavern witness

**Files:**

- Create: `src/Data/Quests/darkpassengertest/kutnohorsko/dark_within_k/tavern_witness_dialog_k.xml`
- Modify: `src/Data/Scripts/mods/dpcasecontent.lua`
- Modify: `src/Data/Scripts/mods/dpevidence.lua`
- Modify: `src/Data/Libs/Storm/roles/quests/darkpassengertest.xml`
- Modify: `src/Data/Libs/Tables/rpg/role__darkpassengertest.xml`
- Modify: `src/Data/Quests/darkpassengertest/kutnohorsko/dark_within_k.xml.template`
- Modify: `localization/English/text__darkpassengertest.xml`
- Modify: `localization/Russian/text__darkpassengertest.xml`
- Create: `tests/Test-TavernWitnessEvidence.ps1`

1. Add failing tests for witness eligibility, exclusion of player/source/target/dead NPCs, stable WUID across save/load, one-shot `20` and total confidence `70`.
2. Select once from nearby eligible tavern inhabitants and persist the WUID with the case generation.
3. Expose the witness dialogue only after Vojtech's clue is read; its output awards `20` exactly once.
4. Reuse the existing reveal tag/alias path at 70; do not create a second marker system.
5. Run focused tests, save/load self-test and LuaCompiler; commit `feat: complete convenient accident evidence chain`.

## Task 5: Build, deploy and prove the real boundaries

**Files:**

- Modify if needed: `tools/Build-Mod.ps1`
- Modify: existing focused tests only for discovered live contracts

1. Run every focused evidence/dialogue/item test, then the full static suite.
2. Run `git diff --check` and a manual simplification pass over the feature diff.
3. Build once and deploy only to `H:\SteamLibrary\steamapps\common\KCD2Mod\Mods\b_DarkPassengerTest`.
4. In a fresh Pritoky case prove, in order: native dialogue availability, one +20 award, exact next objective, document read +30, stable witness after save/load, witness +20, confidence 70 and the existing native NPC marker.
5. Reload the same saves and repeat interactions; verify no reroll and no duplicate reward.
6. Remove/disable the technical short-F fallback only after the native dialogue boundary is proven.

## Task 6: Preserve the result

**Files:**

- Modify: the existing KCD2 technical Wiki page via `wiki-crystallize` and `wiki-integrate`
- Modify: `README.md` roadmap if the canary milestone is tracked there

1. Document the verified Storm role + FaderDialog + ScriptContext + Lua + hidden-buff round trip, including failure modes and live log evidence.
2. Record the document-read and persistent-witness contracts only after live proof.
3. Run final tests and `git status`; commit docs separately and push the branch.

## Unresolved questions

- Exact tavern witness pool: choose from live eligible residents after the first two steps work.
- Production exact-container marker alias: defer until the no-restart Lua canary passes.
