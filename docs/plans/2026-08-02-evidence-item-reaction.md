# Evidence Item And Henry Reaction Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ship a custom quest document whose first accepted reading awards confidence once and makes Lua choose one neutral native Henry monologue.

**Architecture:** `dpbelongings.lua` remains the evidence transaction owner and calls a reusable Lua reaction dispatcher after persisting the read. Three short-lived hidden buff tags carry the Lua choice into the Kuttenberg quest graph, where registered ingame-monologue definitions call `RequestMonologue` on the player. A custom `Document` table row supplies an independent unopened state and quest-inventory classification.

**Tech Stack:** KCD2 Lua, Skald XML, RPG/item tables, XML localization, PowerShell 7 contract tests, LuaCompiler, 7-Zip mod packaging.

**Execution:** Current checkout only. No worktree or delegated agents.

---

### Task 1: Lock the custom document and reaction contracts

**Files:**

- Modify: `tests/Test-VojtechBelongingsEvidence.ps1`
- Create: `tests/Test-EvidenceReaction.ps1`

1. Add failing checks for custom document GUID `73762008-de9b-4c42-b509-235e63e60840`, `IsQuestItem="true"`, localization parity and exact-one placement cleanup.
2. Add failing checks for three reaction IDs/GUIDs, Lua-only selection, one-shot generation state, graph definitions/triggers and native `RequestMonologue` aliases.
3. Run both focused tests and confirm RED for missing item/reaction artifacts.
4. Commit tests with the implementation after GREEN.

### Task 2: Add the custom quest document

**Files:**

- Create: `src/Data/Libs/Tables/item/item__darkpassengertest.xml`
- Modify: `localization/English/text__darkpassengertest.xml`
- Modify: `localization/Russian/text__darkpassengertest.xml`
- Modify: `src/Data/Scripts/mods/dpbelongings.lua`

1. Add a folded-parchment `Document` with custom name, description, content and `IsQuestItem="true"`.
2. Replace the borrowed vanilla GUID in the runtime.
3. Add inventory helpers that remove legacy/custom copies from Henry and the controlled chest before creating exactly one chest copy during explicit canary reset.
4. Preserve chest lock, ownership and trespass state.
5. Run the belongings test and LuaCompiler until GREEN.

### Task 3: Add Lua-selected Henry reactions

**Files:**

- Create: `src/Data/Scripts/mods/dpevidencereaction.lua`
- Modify: `src/Data/Scripts/mods/darkpassengertest.lua`
- Modify: `src/Data/Scripts/mods/dpbelongings.lua`
- Modify: `src/Data/Libs/Tables/rpg/buff_ai_tag__darkpassengertest.xml`
- Modify: `src/Data/Libs/Tables/rpg/buff__darkpassengertest.xml`

1. Implement a pure chooser accepting an injectable roll and returning only `interesting`, `useful` or `hmm`.
2. Map the choices to short-lived hidden signal buffs `882e2544-63d3-400a-b28c-bff3d5afd6cb`, `066bdb65-b78d-4a1b-80e7-e23110fc77c3` and `c1c4877a-6f8b-49d9-819f-740d910dbc34`.
3. Persist reaction delivery by evidence ID plus case generation; retry failed delivery without re-awarding confidence.
4. Call the dispatcher only after the belongings read state has persisted.
5. Run focused tests and both LuaCompiler checks until GREEN.

### Task 4: Register native monologues and graph playback

**Files:**

- Create: `src/Data/Quests/darkpassengertest/kutnohorsko/dark_within_k/evidence_reaction_interesting.xml`
- Create: `src/Data/Quests/darkpassengertest/kutnohorsko/dark_within_k/evidence_reaction_useful.xml`
- Create: `src/Data/Quests/darkpassengertest/kutnohorsko/dark_within_k/evidence_reaction_hmm.xml`
- Modify: `src/Data/Quests/darkpassengertest/kutnohorsko/dark_within_k.xml.template`
- Modify: `tools/Generate-VictimArtifacts.ps1`

1. Register three reusable `ingame monolog` decisions using verified vanilla Henry StringNames.
2. Extend the Kuttenberg-only generated definitions and copy all child XML files into the staged quest directory.
3. Add tags 33-35, player `BuffTagTrigger` nodes and one `RequestMonologue` per alias with forced subtitles.
4. Run XML parsing, the generator contract and focused graph test until GREEN.

### Task 5: Add a safe live canary reset

**Files:**

- Modify: `src/Data/Scripts/mods/dpinvestigation.lua`
- Modify: `src/Data/Scripts/mods/dpbelongings.lua`
- Modify: `tests/Test-VojtechBelongingsEvidence.ps1`

1. Add an explicitly debug-named investigation confidence setter guarded to the active generation.
2. Add `dp_belongings_reset_canary`: set confidence to 20, clear read/reaction state, delete legacy/custom duplicates and place one fresh custom document in the correct chest.
3. Log player/chest counts and resulting confidence for live verification.
4. Run focused tests and LuaCompiler until GREEN.

### Task 6: Verify, build and deploy once

**Files:**

- Modify only if a discovered contract requires it: `tools/Build-Mod.ps1`

1. Run focused tests, then the full static suite.
2. Run `git diff --check` and simplify the feature diff without changing behavior.
3. Build with explicit dev root and deploy to `H:\SteamLibrary\steamapps\common\KCD2Mod\Mods\b_DarkPassengerTest`.
4. Restart dev build once because item tables and quest graph definitions are static.
5. Through the HTTP bridge reset the canary and verify player count 0, chest count 1 and confidence 20.
6. Read once: confidence 50 plus one Henry line. Reopen and save/load: no second reward or line.

### Task 7: Preserve the verified result

**Files:**

- Modify after live proof: existing `KCD2 Modding - Technical Reference` wiki page
- Modify if applicable: `README.md`

1. Crystallize only live-confirmed item/read/monologue contracts and failure modes.
2. Integrate backlinks without creating a duplicate KCD2 page.
3. Commit implementation and documentation separately; push only after requested/appropriate.

## Unresolved questions

None for implementation. Live proof determines whether `OnAdded` needs an extra graph-frame delay before `RequestMonologue`.
