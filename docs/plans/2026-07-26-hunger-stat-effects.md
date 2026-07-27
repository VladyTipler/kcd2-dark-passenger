# Hunger Stat Effects Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Apply the approved eight-stat hunger matrix and show exact effects at
the end of every RU/EN tier description.

**Architecture:** Keep the existing hunger clock and tier-switching Lua
unchanged. Change only the ten RPG buff definitions and their localization
copy. Treat the buff table as the mechanical source and verify localization
against the approved matrix.

**Tech Stack:** KCD2 RPG buff XML, KCD2 localization XML, PowerShell regression
suite, 7-Zip PAK.

---

### Task 1: Lock the approved matrix in tests

**Files:**
- Modify: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`
- Reference: `<repo-root>\docs\plans\2026-07-26-hunger-stat-effects-design.md`

**Steps:**

1. Add exact assertions for `buff_params` on tiers
   `0,10,20,30,40,60,70,80,90,100`.
2. Assert every tier uses only `strength`, `agility`, `vitality`,
   `marksmanship`, `stealth`, `thievery`, `speech`, and `charisma`.
3. Assert RU/EN descriptions contain a final effects paragraph for every tier.
4. Run:
   `pwsh -NoProfile -File "<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1"`.
5. Require RED only for the new matrix/copy assertions.

### Task 2: Apply the mechanical effects

**Files:**
- Modify: `<repo-root>\build\mod\Data\Libs\Tables\rpg\buff__darkpassengertest.xml`

**Steps:**

1. Replace each tier's `buff_params` with the approved exact matrix.
2. Keep tier GUIDs, icons, UI types, persistence, duration, and AI tags
   unchanged.
3. Keep hunger 50 without a buff.
4. Parse the XML and run the suite.
5. Require the mechanical matrix assertions to pass.

### Task 3: Append exact RU/EN effects

**Files:**
- Modify: `<repo-root>\localization\English\text__darkpassengertest.xml`
- Modify: `<repo-root>\localization\Russian\text__darkpassengertest.xml`

**Steps:**

1. Preserve every existing lore paragraph.
2. Append `&#10;&#10;Effects: ...` to each English tier description.
3. Append `&#10;&#10;Эффекты: ...` to each Russian tier description.
4. List only non-zero effects and use the same order in both languages:
   strength, agility, vitality, marksmanship, stealth, thievery, speech,
   charisma.
5. Parse both localization XML files and run the suite.
6. Require all localization assertions and the complete regression suite to
   pass.

### Task 4: Package and accept

**Files:**
- Build: `<repo-root>\build\mod\Data\darkpassengertest.pak`
- Build: `<repo-root>\build\mod\Localization\English_xml.pak`
- Build: `<repo-root>\build\mod\Localization\Russian_xml.pak`
- Deploy: dev and retail `Mods\b_DarkPassengerTest`

**Steps:**

1. Run the full suite and require PASS.
2. Build new ZIP-mode PAKs from scratch with `-mtc=off`.
3. Test every archive with `7z.exe t`; require no NTFS metadata.
4. After the game is closed, back up and deploy byte-identical archives.
5. In dev, inspect tiers 0, 40, 60, and 100.
6. Confirm displayed effects match actual stats and quest lifecycle remains
   unchanged.

## Unresolved questions

- None.

Note: this workspace is not a Git repository, so commit steps are unavailable.
