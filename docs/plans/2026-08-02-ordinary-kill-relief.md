# Ordinary Kill Hunger Relief Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Cap hunger at 50 after any non-target human kill credited to Henry, without disturbing positive satisfaction or the active Case.

**Architecture:** Add a pure one-way hunger transition and a hot-reload-safe `SPNotifyPlayerKill` adapter. Prove the adapter live before retaining it. Remove the obsolete buff/XML evidence-reaction bridge in the same static rebuild batch.

**Tech Stack:** KCD2 Lua, native GameRules binding, PowerShell 7 contract tests, generated Skald XML, LuaCompiler.

---

### Task 1: Lock hunger-relief behavior

**Files:**
- Modify: `tests/Test-DarkPassengerSatisfaction.ps1`
- Modify: `src/Data/Scripts/mods/dphunger.lua`

1. Add failing structural and self-test checks for `ReliefTransition` and
   `RelieveFromOrdinaryKill`.
2. Assert `40 -> unchanged`, `50 -> unchanged`, `60/100 -> 50`.
3. Run the focused test and confirm RED.
4. Implement the minimal timestamp update only for values above 50.
5. Run the test and LuaCompiler until GREEN.

### Task 2: Prove and install the global player-kill adapter

**Files:**
- Modify: `tests/Test-DarkPassengerSatisfaction.ps1`
- Modify: `src/Data/Scripts/mods/darkpassengertest.lua`

1. Add failing checks for a trampoline around
   `g_gameRules.game.SPNotifyPlayerKill` that preserves the original.
2. Require target resolution, `target.human`, selected-target exclusion and
   idempotent hunger relief.
3. Implement the minimal adapter and diagnostic status.
4. Copy/hot-reload Lua into the running dev build.
5. Set hunger above 50 and live-test one ordinary human kill. Retain the
   adapter only if the log proves the engine callback.

### Task 3: Delete the superseded reaction bridge

**Files:**
- Modify: `tests/Test-EvidenceReaction.ps1`
- Modify: `src/Data/Scripts/mods/dpevidencereaction.lua`
- Modify: `src/Data/Libs/Tables/rpg/buff_ai_tag__darkpassengertest.xml`
- Modify: `src/Data/Libs/Tables/rpg/buff__darkpassengertest.xml`
- Modify: `tools/Generate-VictimArtifacts.ps1`
- Delete: `src/Data/Quests/darkpassengertest/kutnohorsko/dark_within_k/evidence_reaction_interesting.xml`
- Delete: `src/Data/Quests/darkpassengertest/kutnohorsko/dark_within_k/evidence_reaction_useful.xml`
- Delete: `src/Data/Quests/darkpassengertest/kutnohorsko/dark_within_k/evidence_reaction_hmm.xml`

1. Change the test first to require only the global metarole route and absence
   of tags, buffs, definitions and `RequestMonologue` nodes; confirm RED.
2. Simplify reaction persistence to dispatched generation only.
3. Remove all obsolete artifacts and generator fragments.
4. Run reaction, belongings, generator and LuaCompiler checks until GREEN.

### Task 4: Verify and stage one restart

1. Run focused tests, full suite and `git diff --check`.
2. Run `/simplify` equivalent review on the feature diff.
3. Build once with explicit dev/reference roots after the game closes.
4. Deploy and verify PAK/tree hashes.
5. Restart once; test fresh note read, one voiced Henry line, ordinary-kill
   relief and no obsolete monologue errors.

## Unresolved questions

- `SPNotifyPlayerKill` Lua dispatch is subject to live proof in Task 2.
