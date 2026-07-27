# Persistent Dark Passenger Hunger Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Persist Henry's last satisfaction time and derive a hidden ten-day, 0–100 hunger cycle that controls buffs and starts the existing hunt at 50.

**Architecture:** Store one namespaced timestamp inside `g_localActor.AI`, which KCD2 already serializes with the player. A Lua hunger module derives the current tier from confirmed world time; XML buffs are projections only, while the existing quest reward emits a consumable reset signal.

**Tech Stack:** KCD2 Lua, Skald quest XML, KCD2 RPG buff tables, PowerShell 7 structural tests, dev HTTP console bridge, 7-Zip PAK packaging.

---

## Preconditions

- Work in `<repo-root>`.
- This directory is not a Git repository; commit/worktree steps are omitted.
- Preserve the current victim catalogue, generated marker graphs, and nearest
  settlement selector.
- Never deploy while the relevant game build is running.
- Do not enable production hunger until the persistence/clock probe passes.

### Task 1: Add persistence and clock probe

**Files:**
- Create: `<repo-root>\build\mod\Data\Scripts\mods\dphunger.lua`
- Modify: `<repo-root>\build\mod\Data\Scripts\mods\darkpassengertest.lua`
- Modify: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`

**Steps:**

1. Add failing structural tests for the namespaced
   `g_localActor.AI.DarkPassenger` record and probe commands.
2. Run the PowerShell suite and confirm RED.
3. Implement read/write helpers without changing buffs or quest state.
4. Add `dp_hunger_probe`, `dp_hunger_probe_set`, and
   `dp_hunger_probe_clear`; log all Calendar candidates and persisted data.
5. Load the module from the established runtime script.
6. Run the suite and confirm GREEN.
7. Build and deploy to dev only.
8. Runtime-test save/load, wait, sleep, and both-region travel.
9. Record the confirmed clock in the design document; stop if no clock is
   monotonic.

### Task 2: Add pure hunger calculation and first-install policy

**Files:**
- Modify: `<repo-root>\build\mod\Data\Scripts\mods\dphunger.lua`
- Modify: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`

**Steps:**

1. Add failing tests for 0/10/40/50/60/100 boundaries, clamping, invalid
   storage, and clock rollback.
2. Run RED.
3. Implement `Calculate(now, lastSatisfaction)` as a side-effect-free helper.
4. Initialize missing storage to five game days before `now`.
5. Add `dp_hunger_status` and a debug command that offsets the persisted
   timestamp without changing production constants.
6. Run GREEN.

### Task 3: Define reward signal and ten derived buff tiers

**Files:**
- Modify: `<repo-root>\build\mod\Data\Libs\Tables\rpg\buff__darkpassengertest.xml`
- Modify: `<repo-root>\build\mod\Data\Libs\Tables\rpg\buff_ai_tag__darkpassengertest.xml` only if a new negative tag is required
- Modify: `<repo-root>\localization\English\text__darkpassengertest.xml`
- Modify: `<repo-root>\localization\Russian\text__darkpassengertest.xml`
- Modify: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`

**Steps:**

1. Add failing tests requiring ten unique visible tier GUIDs, one reward-signal
   GUID, tag `23` on all five positive tiers, no positive tag at 50+, and one
   shared icon family.
2. Run RED.
3. Convert the current reward GUID into the persistent consumable signal.
4. Add positive tiers for 0–40 and negative tiers for 60–100; use constant
   lifetime because Lua owns transitions.
5. Add concise lore localization for each qualitative state.
6. Run GREEN and verify database XML parses.

### Task 4: Project hunger into buffs

**Files:**
- Modify: `<repo-root>\build\mod\Data\Scripts\mods\dphunger.lua`
- Modify: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`

**Steps:**

1. Add failing tests for the tier map, removal of all stale DP tier buffs, no
   buff at 50, and no repeated writes while a tier is unchanged.
2. Run RED.
3. Implement one GUID map and `ApplyDerivedTier`.
4. Remove all known tier GUIDs before applying a changed non-neutral tier.
5. Keep exact hunger hidden outside debug logging.
6. Run GREEN.

### Task 5: Consume successful-kill reward

**Files:**
- Modify: `<repo-root>\build\mod\Data\Scripts\mods\dphunger.lua`
- Modify: `<repo-root>\build\mod\Data\Scripts\mods\dpsatisfaction.lua`
- Verify: both generated regional quest XML files still grant the established reward GUID
- Modify: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`

**Steps:**

1. Add failing tests for signal detection, timestamp reset, signal removal,
   tier-0 application, and idempotence after the signal is consumed.
2. Run RED.
3. Implement `ResetNow(reason)` and signal consumption.
4. Route `dp_satisfaction_add` through the same reset path.
5. Preserve `dp_satisfaction_remove` as a debug cleanup command without
   silently changing the persisted timestamp.
6. Run GREEN.

### Task 6: Attach hunger evaluation to the proven lifecycle

**Files:**
- Modify: `<repo-root>\build\mod\Data\Scripts\mods\darkpassengertest.lua`
- Modify: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`

**Steps:**

1. Add failing tests for mod init, player init/reload, and periodic evaluation.
2. Run RED.
3. Call hunger evaluation from the existing one-second quest bridge poll.
4. Ensure missing Henry/Soul retries safely.
5. Ensure crossing 40→50 removes tag `23`, allowing the existing delayed quest
   startup to run exactly once.
6. Run GREEN and confirm no duplicate selection request is introduced.

### Task 7: Package and accelerated runtime acceptance

**Files:**
- Build: `<repo-root>\build\mod\Data\darkpassengertest.pak`
- Build localization PAKs under `<repo-root>\build\mod\Localization`
- Deploy: dev and then retail `b_DarkPassengerTest`

**Steps:**

1. Run:
   `pwsh -NoProfile -File "<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1"`.
2. Require `RESULT: PASS` and no regression in candidate/marker counts.
3. Rebuild PAKs, archive-test them, and compare deployed SHA-256.
4. In dev, force each hunger boundary through timestamp offsets.
5. Verify positive weakening, neutral 50, native quest banner/sound, negative
   escalation, successful target death reset, and save/reload.
6. Deploy identical bytes to retail and repeat the core cycle.

### Task 8: Document only confirmed behavior

**Files:**
- Modify: `<local-wiki-root>\kcd2-modding-technical-reference.md`
- Modify: `<local-wiki-root>\Overview.md`
- Modify: `<local-wiki-root>\log.md`

**Steps:**

1. Record the confirmed serialized player-field mechanism and clock.
2. Document the reward-signal pattern and derived-buff rule.
3. Record runtime acceptance evidence and remaining limitations.

## Unresolved questions

- Exact stat modifiers for ten tiers.
- Final tier names/descriptions.
