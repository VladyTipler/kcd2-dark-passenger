# Static Objective Marker Control Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a second tracked objective with a fixed vanilla-style NPC marker to isolate marker plumbing from dynamic victim selection.

**Architecture:** Keep the existing quest-start lifecycle. Transition from the search objective to a target objective, and bind both marker and death trigger directly to static `SoulAsset` alias `PritokySoul28`. Treat this as a disposable control build.

**Tech Stack:** KCD2 Skald XML, RPG `SoulAsset`, localization XML, PowerShell verification, 7-Zip PAK.

---

### Task 1: Add failing structural checks

**Files:**
- Modify: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`

1. Assert a second `dark_within_targetk` objective exists.
2. Assert search progress completes before target progress activates.
3. Assert `ShowMapMarker` uses static alias `PritokySoul28`.
4. Assert the death trigger uses the same static alias.
5. Run the test and confirm these checks fail.

### Task 2: Implement the control objective

**Files:**
- Modify: `<repo-root>\build\mod\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml`

1. Add `targetObjectiveProgress`.
2. Complete `objectiveProgress` after target selection.
3. Activate `targetObjectiveProgress` after the search objective completes.
4. Bind a new visual objective node to target progress.
5. Change quest completion to target-objective completion.
6. Bind marker and death trigger statically to `PritokySoul28`.

### Task 3: Add lore localization

**Files:**
- Modify: `<repo-root>\localization\Russian\text__darkpassengertest.xml`
- Modify: `<repo-root>\localization\English\text__darkpassengertest.xml`

1. Add target objective title and active log keys.
2. Use Russian title `Настигнуть избранную жертву`.
3. Run structural tests and XML parsing.

### Task 4: Package and deploy after game closes

**Files:**
- Rebuild: `<repo-root>\build\mod\Data\darkpassengertest.pak`
- Replace: `<kcd2-retail-root>\Mods\b_DarkPassengerTest\Data\darkpassengertest.pak`

1. Build a store-mode ZIP without NTFS metadata.
2. Verify packaged objective and static marker.
3. Wait for `KingdomCome` to exit.
4. Back up the current retail mod.
5. Deploy and verify SHA256 equality.

## Unresolved questions

- Does the static objective marker appear on both map and compass?
- Which runtime binding can replace `PritokySoul28` after the control succeeds?
