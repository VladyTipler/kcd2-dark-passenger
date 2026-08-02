# Innkeeper Rumor Evidence Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add one persistent, repeatable-case rumor interaction at the Pritoky innkeeper that awards 30 confidence once and creates a native journal update.

**Architecture:** A single hot-reload-safe `dpinteractions.lua` owns NPC action hooks. `dpburial.lua` and new `dpevidence.lua` register named providers. Evidence state is persisted by investigation generation; a hidden buff/tag only signals the quest graph after the authoritative confidence write succeeds.

**Tech Stack:** KCD2 Lua, Skald quest XML, RPG buff tables, PowerShell generators/tests, LuaCompiler.

**Execution note:** Implement in the current `feature/aftermath` checkout; no worktree and no delegated agent.

---

### Task 1: Lock the contract with failing tests

**Files:**
- Create: `tests/Test-InnkeeperRumorEvidence.ps1`
- Modify: `tests/Test-DarkPassengerSatisfaction.ps1`

1. Assert shared-provider hook ownership, burial registration, evidence eligibility/one-shot persistence, init order, tag 31, both regional quest listeners/objective logs, localization parity, and Lua compilation.
2. Run focused tests and confirm RED only because the feature is absent.

### Task 2: Introduce the shared contextual-action registry

**Files:**
- Create: `src/Data/Scripts/mods/dpinteractions.lua`
- Modify: `src/Data/Scripts/mods/dpburial.lua`
- Modify: `src/Data/Scripts/mods/darkpassengertest.lua`

1. Add a reload-safe named provider registry and one wrapper for `NPC`, `NPC_Female`, and `NPC_NAI.GetActions`.
2. Replace burial-owned class wrappers with provider registration while preserving its existing action callback.
3. Run focused burial/registry checks and LuaCompiler.

### Task 3: Implement the rumor evidence runtime

**Files:**
- Create: `src/Data/Scripts/mods/dpevidence.lua`
- Modify: `src/Data/Scripts/mods/darkpassengertest.lua`
- Modify: `src/Data/Scripts/mods/dpinvestigation.lua`

1. Add pure eligibility/transition logic for `kutnohorsko/pritoky`, `kpri_innkeeper`, current generation, living source, and not-yet-awarded state.
2. Persist awarded generation and journal-signal state. Award through `DarkPassengerInvestigation.AddEvidence(30, "innkeeper_rumor", generation)` before signalling.
3. Resolve rumor copy at action time, register a short-F `butcher`/`AHT_RELEASE` provider, expose status/self-test commands, and make reload replace behavior without stacking hooks. (`talk` and `use_other` were live-disproven: both stay on E for this NPC.)
4. Reset the signal on a new case and retry only journal dispatch after partial failure.

### Task 4: Bridge the first lead into both quest graphs

**Files:**
- Modify: `src/Data/Libs/Tables/rpg/buff_ai_tag__darkpassengertest.xml`
- Modify: `src/Data/Libs/Tables/rpg/buff__darkpassengertest.xml`
- Modify: `src/Data/Quests/darkpassengertest/kutnohorsko/dark_within_k.xml.template`
- Modify: `tools/Generate-VictimArtifacts.ps1`
- Modify: `localization/English/text__darkpassengertest.xml`
- Modify: `localization/Russian/text__darkpassengertest.xml`

1. Add hidden generic first-lead buff/tag 31.
2. Add a player `BuffTagTrigger`, dedicated evidence progress state/objective, and one native journal update while leaving the settlement area objective tracked.
3. Generate both regional graphs and verify XML/localization parity.

### Task 5: Build, deploy, and live-test once

**Files:**
- Update generated/build output only through existing scripts.

1. Run focused tests, `Build-Mod.ps1 -SkipPackaging`, LuaCompiler, then the full suite.
2. Run the full package/deploy once with the game closed.
3. Live-test: Pritoky action visible only on the innkeeper; short F; confidence `0 -> 30`; journal update; no reveal; repeat/reload stays 30.
4. Edit one rumor line, run `lua_reload_script Scripts/mods/dpevidence.lua`, and verify changed text on a fresh case without restarting KCD2.

### Task 6: Document and publish

**Files:**
- Modify: existing Dark Passenger technical Wiki pages.
- Modify: `Tasks.md` if this feature is tracked there.

1. Record the proven shared-action and Lua-to-quest evidence pattern, including hot-reload limits.
2. Run simplify review, `git diff --check`, final tests, commit, and push.

## Unresolved questions

None for this vertical slice.
