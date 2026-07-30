# Pritoky Investigation Vertical Slice Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Prove the complete investigation loop in Pritoky: select and persist a hidden victim, show a genuine search area, accumulate hidden confidence through `dp_evidence`, reveal the exact NPC at 70%, and preserve every transition across save/load.

**Architecture:** Lua owns the persistent investigation state and applies one hidden reveal signal to the selected NPC. The generated Skald quest graph owns native objectives, area/NPC markers, banners, sound, and death routing. The existing target slot remains the target identity SSOT; the new investigation module stores only case generation, confidence, reveal state, and dispatch idempotency. The first slice deliberately pins Kuttenberg selection to Pritoky behind one removable override.

**Tech Stack:** KCD2 Lua 5.1, `Variables` save globals, KCD2 Skald quest XML, TriggerArea/AssetLinker level data, PowerShell generation and structural tests, LuaCompiler parse checks, 7-Zip pak packaging, dev-build live integration validation.

---

## Constraints

- Work on the current `feature/aftermath` branch; do not create a worktree.
- Edit authored files under `src`, `tools`, `tests`, `localization`, and `docs`; never hand-edit generated files under `build`.
- Keep `dp_active_target_slot` as the only persisted target identity.
- Keep legacy `DarkPassengerCase` only where kill-attribution code still needs it; investigation confidence must not depend on it.
- Do not expose confidence in the HUD or journal.
- Do not reveal the target before confidence reaches 70.
- A target dying before reveal must still enter the existing aftermath flow.
- A point marker does not satisfy the search-area requirement.
- Do not place `waitinglinks.xml` inside `Data\darkpassengertest.pak`; level assets belong in a Kuttenberg level pak.
- Commit each green task. Do not push or deploy to retail without explicit permission.
- Deploy to dev only from an exact committed build and only while the game is closed.

### Task 1: Freeze the baseline and add an implementation checklist

**Files:**
- Verify: `H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1`
- Verify: `H:\KCD2Mod\DarkPassenger\tools\Build-Mod.ps1`
- Create during execution: `H:\KCD2Mod\DarkPassenger\evidence\pritoky-investigation-validation.md`

**Step 1: Run the current baseline**

```powershell
$env:KCD2_DEV_ROOT='H:\SteamLibrary\steamapps\common\KCD2Mod'
$env:KCD2_REFERENCE_DATA_ROOT='H:\KCD2Mod\_reference-mods\_extracted\AssetLinker\InternalData'
pwsh -NoProfile -File 'H:\KCD2Mod\DarkPassenger\tools\Build-Mod.ps1'
pwsh -NoProfile -File 'H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1'
```

Expected: build succeeds and the suite ends with `RESULT: PASS`.

**Step 2: Record the baseline**

Record branch, commit, test count, and SHA-256 hashes of:

- `build\mod\Data\darkpassengertest.pak`;
- `build\mod\Localization\English_xml.pak`;
- `build\mod\Localization\Russian_xml.pak`.

Do not copy generated paks into Git.

**Step 3: Commit only if the evidence file was added**

```powershell
git add evidence/pritoky-investigation-validation.md
git commit -m "test: record investigation baseline"
```

### Task 2: Prove a genuine Pritoky TriggerArea binding

This is the technical gate. Stop broad implementation if the quest cannot render
a real area marker from a mod-owned level package.

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1`
- Modify: `H:\KCD2Mod\DarkPassenger\tools\Build-Mod.ps1`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml.template`
- Create from Sandbox/export: `H:\KCD2Mod\DarkPassenger\src\Data\Levels\kutnohorsko\...`
- Update: `H:\KCD2Mod\DarkPassenger\evidence\pritoky-investigation-validation.md`

**Step 1: Add failing structural/package assertions**

Require:

- a `TriggerAreaAsset` named `DP_PritokySearchArea` in the Kuttenberg quest;
- the active search log to use `Marker="DP_PritokySearchArea"`;
- a Kuttenberg level pak at
  `build\mod\Data\Levels\kutnohorsko\darkpassengertest.pak`;
- the level pak to contain the editor-produced level/link files;
- the main data pak not to contain level data or `waitinglinks.xml`;
- both paks to omit NTFS metadata and pass `7z t`.

Replace the old assertions that forbid any AssetLinker/level-pak dependency.

Run:

```powershell
pwsh -NoProfile -File 'H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1'
```

Expected: only the new area/package contracts fail.

**Step 2: Reconstruct the proven vanilla binding**

Use these local references:

- Pritoky area candidate
  `kpri_publicEnemiesRepulsionZoneVillageArea_1`, entity GUID
  `d0fa0ece-6af5-19f6`, in
  `H:\KCD2Mod\_reference-mods\_extracted\AssetLinker\InternalData\kutnohorsko\kut_objects_mission0.xml`;
- quest asset/waiting-link pattern for `taTurnajOhrada` in
  `kutnohorskyTurnaj.xml` and `kut_waitinglinks.xml`;
- TriggerArea marker usage in the extracted Temptation quests.

In the official editor/Sandbox, create or export the minimum mod-owned
Kuttenberg quest anchor/link layer. Bind its quest asset alias
`DP_PritokySearchArea` to the existing Pritoky TriggerArea first.

Do not invent entity GUIDs or filenames. Record the exact editor-generated
source entity GUID, target GUID, layer filename, and `LinkDefinition` in the
evidence file.

If the existing area is the wrong shape in-game, create a mod-owned TriggerArea
covering Pritoky and bind that instead. Preserve the same quest alias.

**Step 3: Package the level layer separately**

Extend `Build-Mod.ps1` so:

- `AI`, `Libs`, `Quests`, and `Scripts` still enter
  `Data\darkpassengertest.pak`;
- Kuttenberg level/link files enter
  `Data\Levels\kutnohorsko\darkpassengertest.pak`;
- each archive is created with `-mtc=off`;
- each archive receives a `7z t` integrity check.

**Step 4: Add the area asset and marker to the authored template**

Declare `DP_PritokySearchArea` under quest assets and assign it only to the
search objective's active log. Do not change the NPC marker yet.

**Step 5: Build and run structural tests**

```powershell
$env:KCD2_DEV_ROOT='H:\SteamLibrary\steamapps\common\KCD2Mod'
$env:KCD2_REFERENCE_DATA_ROOT='H:\KCD2Mod\_reference-mods\_extracted\AssetLinker\InternalData'
pwsh -NoProfile -File 'H:\KCD2Mod\DarkPassenger\tools\Build-Mod.ps1'
pwsh -NoProfile -File 'H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1'
```

Expected: `RESULT: PASS`; main and level pak integrity checks pass.

**Step 6: Commit**

```powershell
git add src/Data/Levels src/Data/Quests tools/Build-Mod.ps1 tests/Test-DarkPassengerSatisfaction.ps1 evidence/pritoky-investigation-validation.md
git commit -m "feat: bind Pritoky search area"
```

### Task 3: Add a hidden target-revealed signal

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Libs\Tables\rpg\buff_ai_tag__darkpassengertest.xml`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Libs\Tables\rpg\buff__darkpassengertest.xml`
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1`

**Step 1: Add failing table assertions**

Require:

- AI tag id `30`, name `darkpassenger_target_revealed`;
- one unique custom buff GUID carrying tag 30;
- hidden, persistent, constant behavior;
- class id `1` and exclusivity `0`;
- no localization/UI entry for this transport signal.

Run the suite and confirm these checks fail.

**Step 2: Add the table rows**

Generate the buff GUID once, add it to the two authored table files, and define
the same GUID as a single test constant. Do not reuse any existing buff GUID.

The reveal buff is applied to the chosen NPC, not Henry.

**Step 3: Run tests**

Expected: the new table checks pass; all existing buff-tag checks remain green.

**Step 4: Commit**

```powershell
git add src/Data/Libs/Tables/rpg tests/Test-DarkPassengerSatisfaction.ps1
git commit -m "feat: add hidden victim reveal signal"
```

### Task 4: Build the persistent investigation state machine

**Files:**
- Create: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpinvestigation.lua`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\darkpassengertest.lua`
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1`

**Step 1: Add failing module-contract tests**

Require:

- `SCHEMA_VERSION = 1`;
- `REVEAL_THRESHOLD = 70`;
- `Open`, `Restore`, `AddEvidence`, `OnTargetDeath`, `Clear`, `Status`;
- one pure transition function used by a self-test;
- keys for schema, active generation, confidence, revealed, and
  reveal-dispatched;
- no second persisted target-slot key.

Also require `darkpassengertest.lua` to reload `dpinvestigation.lua` before
target lifecycle code runs.

**Step 2: Implement pure transition semantics first**

The pure transition must cover:

- new case starts at confidence 0 and unrevealed;
- invalid or non-positive evidence is rejected;
- confidence clamps to 100;
- 69 → 70 reveals exactly once;
- evidence after reveal never emits a second transition;
- restore does not change confidence/generation;
- a new case generation cannot consume an old callback.

Expose these checks through `DarkPassengerInvestigation.RunSelfTest()` so the
same Lua 5.1 code can be exercised inside the game.

**Step 3: Implement scalar persistence**

Use protected `Variables.GetGlobal`/`SetGlobal` calls following the proven hunger
module pattern. Persist state before applying the reveal buff. Set
`revealDispatched` only after the target entity accepts the reveal buff.

`Restore(candidate, entity)` derives target identity/region/settlement from the
existing generated candidate catalogue and `dp_active_target_slot`; it must not
persist duplicate identity data.

**Step 4: Add diagnostics**

Add:

- `dp_investigation_status`;
- `dp_investigation_selftest`.

Status must log case active flag, generation, region, settlement, slot,
confidence, revealed, dispatched, and whether target/reveal buffs are present.

**Step 5: Parse and test**

```powershell
& 'H:\SteamLibrary\steamapps\common\KCD2Mod\Bin\Win64SharedPrivate\LuaCompiler.exe' -p 'H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpinvestigation.lua'
& 'H:\SteamLibrary\steamapps\common\KCD2Mod\Bin\Win64SharedPrivate\LuaCompiler.exe' -p 'H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\darkpassengertest.lua'
pwsh -NoProfile -File 'H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1'
```

Expected: both parse checks succeed; suite ends with `RESULT: PASS`.

**Step 6: Commit**

```powershell
git add src/Data/Scripts/mods tests/Test-DarkPassengerSatisfaction.ps1
git commit -m "feat: persist investigation confidence"
```

### Task 5: Integrate investigation with target selection and recovery

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\darkpassengertest.lua`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpinvestigation.lua`
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1`

**Step 1: Add failing lifecycle assertions**

Require:

- successful new target selection calls `Open` after target slot persistence;
- every recovered target calls `Restore`;
- target death notifies investigation before target state is cleared;
- reset/abandon removes reveal buff and clears investigation state;
- an already valid active target is restored, never rerolled;
- the legacy `dp_evidence` handler delegates only to
  `DarkPassengerInvestigation.AddEvidence`.

**Step 2: Add a single Pritoky slice override**

For Kuttenberg only, route the automatic selection request to settlement
`pritoky`. Keep the override in one named table/function in
`dpinvestigation.lua`, for example `GetSettlementOverride(gameRegion)`.

Do not scatter `pritoky` literals through target selection or quest code.
Trosky remains on its current behavior in this slice.

**Step 3: Wire target lifecycle**

Integrate:

- `Select` → persist target slot → `Open`;
- `BindRecoveredTarget`/`RestoreExisting` → `Restore`;
- `OnTargetDeath` → investigation notification → existing aftermath;
- `ResetCase`/replacement → remove both target and reveal signals safely.

Preserve existing target selection filters and kill-attribution behavior.

**Step 4: Replace the debug evidence bridge**

`dp_evidence <amount> [label]` must:

- reject use without an active case;
- parse amount through `tonumber`;
- concatenate the optional label for diagnostics only;
- report old value, accepted delta, new value, generation, and reveal result;
- never grant satisfaction or finish the quest.

**Step 5: Parse and test**

Run both Lua parse checks and the PowerShell suite.

Expected: `RESULT: PASS`; no direct `DarkPassengerCase.AddEvidence` call remains
in console command handling.

**Step 6: Commit**

```powershell
git add src/Data/Scripts/mods tests/Test-DarkPassengerSatisfaction.ps1
git commit -m "feat: connect target lifecycle to investigation"
```

### Task 6: Decouple hidden selection from visible quest reveal

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\tools\Generate-VictimArtifacts.ps1`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml.template`
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1`

**Step 1: Add failing generated-graph assertions**

For every Kuttenberg candidate require:

- tag 24 selects an internal candidate state without exposing an NPC marker;
- tag 30 on that same candidate activates its visible target objective state;
- the search objective completes on reveal, not on tag 24;
- the exact NPC marker appears only in the reveal branch;
- the death trigger listens to the internal selected-candidate state;
- pre-reveal death still raises the existing death request;
- a repeated reveal signal cannot create two objective updates.

Keep deterministic generation and XML validity checks.

**Step 2: Introduce separate generated enum state**

Generate two concepts:

- `DP_SelectedTarget`: internal identity/death routing;
- existing `DP_TargetProgress`: visible objective and NPC marker.

Tag 24 sets only `DP_SelectedTarget`. Tag 30 sets the matching
`DP_TargetProgress` and completes the area-search objective.

**Step 3: Keep area and victim presentation native**

Expected quest presentation:

1. quest starts with the Pritoky search objective and area marker;
2. confidence remains invisible;
3. reveal signal produces one native objective update/banner/sound;
4. area objective completes;
5. “hunt the chosen victim” activates with the exact NPC marker.

Do not issue HUD marker calls from Lua.

**Step 4: Regenerate twice and prove determinism**

```powershell
pwsh -NoProfile -File 'H:\KCD2Mod\DarkPassenger\tools\Build-Mod.ps1' -SkipPackaging
$first = (Get-FileHash -Algorithm SHA256 -LiteralPath 'H:\KCD2Mod\DarkPassenger\build\mod\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml').Hash
pwsh -NoProfile -File 'H:\KCD2Mod\DarkPassenger\tools\Build-Mod.ps1' -SkipPackaging
$second = (Get-FileHash -Algorithm SHA256 -LiteralPath 'H:\KCD2Mod\DarkPassenger\build\mod\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml').Hash
if ($first -ne $second) { throw 'Generated Kuttenberg quest is not deterministic' }
```

Expected: hashes match.

**Step 5: Build and test**

Expected: full build succeeds and suite ends with `RESULT: PASS`.

**Step 6: Commit**

```powershell
git add tools/Generate-VictimArtifacts.ps1 src/Data/Quests tests/Test-DarkPassengerSatisfaction.ps1
git commit -m "feat: reveal victim through quest graph"
```

### Task 7: Add investigation copy in English and Russian

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\localization\English\text__darkpassengertest.xml`
- Modify: `H:\KCD2Mod\DarkPassenger\localization\Russian\text__darkpassengertest.xml`
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1`

**Step 1: Add failing localization assertions**

Require localized strings for:

- initial search-area objective;
- reveal/update line;
- selected-victim hunt objective.

Require identical key sets in English and Russian and forbid raw `@key` output
for these entries.

**Step 2: Add final copy**

Keep confidence hidden. Suggested intent:

- search: the Passenger has sensed rot near Pritoky; Henry must determine who
  deserves the Code;
- reveal: fragments now point to one person;
- hunt: the chosen victim has been identified.

Use lore, not explicit Dexter terminology or modern percentages.

**Step 3: Build and test**

Expected: both localization paks build; suite ends with `RESULT: PASS`.

**Step 4: Commit**

```powershell
git add localization tests/Test-DarkPassengerSatisfaction.ps1
git commit -m "feat: localize Pritoky investigation"
```

### Task 8: Run complete static verification and simplify the feature diff

**Files:**
- Review all files changed since commit `6a33836`

**Step 1: Run parsers, build, and tests**

```powershell
& 'H:\SteamLibrary\steamapps\common\KCD2Mod\Bin\Win64SharedPrivate\LuaCompiler.exe' -p 'H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpinvestigation.lua'
& 'H:\SteamLibrary\steamapps\common\KCD2Mod\Bin\Win64SharedPrivate\LuaCompiler.exe' -p 'H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\darkpassengertest.lua'
$env:KCD2_DEV_ROOT='H:\SteamLibrary\steamapps\common\KCD2Mod'
$env:KCD2_REFERENCE_DATA_ROOT='H:\KCD2Mod\_reference-mods\_extracted\AssetLinker\InternalData'
pwsh -NoProfile -File 'H:\KCD2Mod\DarkPassenger\tools\Build-Mod.ps1'
pwsh -NoProfile -File 'H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1'
git diff --check 6a33836..HEAD
```

Expected: parsers and build succeed, `RESULT: PASS`, no whitespace errors.

**Step 2: Run the required simplification pass**

Review `git diff 6a33836..HEAD` for duplicated persistence helpers, duplicate
Pritoky literals, dead legacy confidence paths, and generator/template
duplication. Apply only behavior-preserving simplifications.

Re-run every command from Step 1 after any simplification.

**Step 3: Commit cleanup only if needed**

```powershell
git add src tools tests localization
git commit -m "refactor: simplify investigation slice"
```

### Task 9: Cross the real quest/Lua/game integration boundary in dev

**Files:**
- Deploy from: `H:\KCD2Mod\DarkPassenger\build\mod`
- Deploy to: `H:\SteamLibrary\steamapps\common\KCD2Mod\Mods\darkpassengertest`
- Update: `H:\KCD2Mod\DarkPassenger\evidence\pritoky-investigation-validation.md`

**Step 1: Prepare a recoverable dev deployment**

Wait until the user confirms the game is closed. Verify the exact deploy target,
back up the installed mod, copy the committed build, and compare SHA-256 hashes.
Do not touch the retail installation.

**Step 2: Validate the Lua state machine in-game**

Run:

```text
dp_investigation_selftest
dp_investigation_status
```

Expected: self-test passes; status is internally consistent.

**Step 3: Validate the normal reveal path**

1. Start/reset a case while in Kuttenberg.
2. Confirm a living Pritoky victim is selected internally.
3. Confirm the journal/map shows only the genuine Pritoky search area.
4. Run `dp_evidence 60 rumor`.
5. Confirm no NPC marker and no reveal update.
6. Save and load.
7. Confirm slot, confidence 60, and unrevealed state persist.
8. Run `dp_evidence 10 proof`.
9. Confirm one native update/banner/sound.
10. Confirm the area objective completes and the exact selected NPC marker
    appears.
11. Save and load again.
12. Confirm the same target/marker persists and no duplicate update fires.
13. Add more evidence and confirm no duplicate reveal.

Capture the relevant `kcd.log` lines and screenshots in the evidence record.

**Step 4: Validate pre-reveal death**

Start a fresh case, keep confidence below 70, kill the selected hidden target,
and confirm:

- death is detected without revealing a replacement NPC first;
- the existing aftermath/cleanup flow begins;
- no stale reveal appears after evidence or reload;
- the next hunger cycle may create a new case normally.

**Step 5: Validate target recovery**

Reload an active pre-reveal save and move around. Confirm the target is restored,
not rerolled, and the area marker remains singular.

This live run is the required feature/integration test across Lua persistence,
buff signals, Skald graph, level AssetLinker data, and native UI.

**Step 6: Commit evidence**

```powershell
git add evidence/pritoky-investigation-validation.md
git commit -m "test: validate Pritoky investigation in dev"
```

### Task 10: Document only live-confirmed behavior

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\README.md`
- Modify existing Dark Passenger pages under:
  `C:\Users\Vladislav\Obsidian Vaults\LLM Wiki`

**Step 1: Update repository documentation**

Document:

- hidden selection versus revealed marker;
- confidence threshold and debug command;
- save/load guarantees;
- Pritoky-only scope;
- TriggerArea/level-pak packaging rule;
- confirmed limitations and next expansion step.

Do not present real clues or world-wide areas as implemented.

**Step 2: Update the Wiki**

Use `wiki-crystallize`, then `wiki-integrate`. Prefer updating
`KCD2 Modding - Technical Reference` and the existing Dark Passenger page over
creating duplicates. Mark editor/AssetLinker details as confirmed only if the
live marker test passed.

**Step 3: Final verification**

Run the full build/test suite once more and verify `git status --short` contains
only intentional Wiki changes outside the repository, if any.

**Step 4: Commit repository docs**

```powershell
git add README.md
git commit -m "docs: describe investigation vertical slice"
```

Do not push. Report the commit range and ask separately before GitHub push or
retail deployment.

## Definition of done

- Kuttenberg case selects a hidden, living Pritoky target.
- The journal/map initially exposes a true Pritoky search area, not the NPC.
- `dp_evidence` persists confidence; 70 reveals exactly once.
- Reveal uses native quest update presentation and the exact NPC marker.
- Save/load never rerolls the active target or duplicates the transition.
- Target death before 70 still reaches aftermath.
- Main and level paks are correctly separated and validated.
- Static tests, Lua parsers, generated determinism, and live dev integration are
  green.
- README and Wiki contain only live-confirmed facts.

## Unresolved questions

None for implementation. The exact editor-generated layer/anchor identifiers
must be discovered and recorded during Task 2; that is the first technical gate,
not a design decision.
