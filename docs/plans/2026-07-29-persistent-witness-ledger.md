# Dark Passenger Persistent Witness Ledger Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add conservative real-witness detection, a persistent witness ledger, anonymous native quest feedback, and correct clean/controlled/noisy Case resolution.

**Architecture:** Keep the native quest graph responsible for journal and banner presentation. Put game-independent witness state and numeric `Variables` persistence in a new `dpwitness.lua` module, keep KCD2 runtime signal detection in a separate adapter, and let `dpaftermath.lua` orchestrate the Case. Production behavior may use only signals proven by the dev probe matrix.

**Tech Stack:** KCD2 Lua, Skald quest XML, RPG buff/AI-tag tables, numeric `Variables` save globals, PowerShell 7 generation/tests, 7-Zip packaging, dev runtime probes, retail quest validation.

---

## Constraints

- Work directly on `feature/aftermath`; no worktree.
- Preserve commit `484fb0e` as the last live-proven gameplay baseline and
  `0ed28d2` as the approved design checkpoint.
- Do not hand-edit generated regional quest XML or generated candidate Lua.
- Do not treat proximity, line of sight, corpse discovery, or unrelated
  hostility as witness proof.
- Keep `Variables` as the single persistence source. Buffs remain projections
  and quest signals.
- Dev proves Lua bindings and state recovery. Retail proves banners, journal
  state, and quest completion.
- Back up an installed mod before every table/XML deployment.

### Task 1: Freeze baseline and extend the read-only witness probe

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\darkpassengertest.lua`
- Create: `H:\KCD2Mod\DarkPassenger\evidence\witness-probe-matrix-2026-07-29.md`

**Step 1: Record the clean baseline**

Run:

```powershell
pwsh -NoProfile -File 'H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1' `
  -ReferenceDataRoot 'H:\KCD2Mod\_reference-mods\_extracted\AssetLinker\InternalData' `
  -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
```

Expected: `RESULT: PASS (560 checks)`.

**Step 2: Write failing structural checks**

Require these read-only commands and functions:

```text
dp_witness_probe_arm
dp_witness_probe_sample
dp_witness_probe_clear
DarkPassengerAftermathProbe.WitnessArm
DarkPassengerAftermathProbe.WitnessSample
DarkPassengerAftermathProbe.WitnessClear
```

Also assert that probe code never calls `AddBuff`, `SetEntityContext`,
`RecordSuspicion`, or `Resolve`.

**Step 3: Run the suite**

Expected: only the new witness-probe checks fail.

**Step 4: Implement snapshot/diff probes**

Extend the existing safe `pcall` helpers. `WitnessArm(radius)` records a
read-only baseline for every nearby NPC:

```lua
{
    identity = ProbeEntityName(entity),
    entityId = entity.id,
    dead = ProbeEntityDead(entity),
    hostile = SafeAiFlag("Hostile", entity),
    personallyHostile = SafeAiFlag("IsPersonallyHostile", entity),
    contexts = ReadKnownContexts(entity),
    links = ReadKnownLinks(entity),
}
```

`WitnessSample(radius)` captures the same fields and logs only changes plus
player crime-context changes. `WitnessClear()` drops the in-memory baseline.
No function changes the game state.

**Step 5: Add the evidence template**

Include columns for:

```text
scenario | NPC identity stable | reaction delta | Henry link | report/alarm
save/load | false positives | accepted production predicate
```

**Step 6: Run tests and commit**

Expected: baseline plus the new probe checks passes.

```powershell
git add -- `
  'H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1' `
  'H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\darkpassengertest.lua' `
  'H:\KCD2Mod\DarkPassenger\evidence\witness-probe-matrix-2026-07-29.md'
git commit -m 'test: add witness signal probes'
```

### Task 2: Prove identity, reaction, report, and storage signals in dev

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\evidence\witness-probe-matrix-2026-07-29.md`
- Inspect: `H:\SteamLibrary\steamapps\common\KCD2Mod\kcd.log`

**Step 1: Deploy the Lua-only probe**

Build:

```powershell
pwsh -NoProfile -File 'H:\KCD2Mod\DarkPassenger\tools\Build-Mod.ps1'
```

When only Lua changed, copy the authored probe into the running dev mod and
reload `Scripts/mods/darkpassengertest.lua`. If the deployed package also
contains table/XML changes, close the game and deploy the full build instead.

**Step 2: Capture controlled scenarios**

For each scenario, arm immediately before the incident and sample repeatedly
after it:

1. unseen target kill with nearby uninvolved NPCs;
2. NPC discovers only the corpse;
3. NPC directly sees Henry perform a stealth kill;
4. public melee kill and guard alarm;
5. witness remains alive long enough to report;
6. witness dies before reporting;
7. save/load between witness reaction and report.

**Step 3: Verify stable identity**

For the same NPC, compare the candidate identity across:

- repeated samples;
- save/load;
- leaving and returning to the streamed area.

Prefer a stable Soul/entity identity exposed by the game. If only an internal
name survives, use two deterministic numeric hashes and resolve the NPC by
rescanning the saved settlement. Never persist a runtime userdata pointer.

**Step 4: Verify storage encoding**

Use the existing storage capability probe to test whether `Variables` preserves
string values. If it does not, record the two-hash numeric fallback in the
matrix. Dynamic key names plus numeric values are already the proven baseline.

**Step 5: Select the production predicate**

Accept a predicate only when it is present in direct-witness/report scenarios
and absent from both proximity-only and corpse-discovery-only scenarios.

If no per-NPC predicate is reliable:

- keep real witness registration disabled;
- allow only proven global alarm/report signals to lock `Noisy`;
- continue probing rather than shipping proximity heuristics.

**Step 6: Commit evidence**

```powershell
git add -- 'H:\KCD2Mod\DarkPassenger\evidence\witness-probe-matrix-2026-07-29.md'
git commit -m 'docs: record witness runtime evidence'
```

### Task 3: Add the pure persistent witness ledger

**Files:**
- Create: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpwitness.lua`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\darkpassengertest.lua`
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1`

**Step 1: Write failing ledger-contract checks**

Require:

```lua
DarkPassengerWitness.STATE_UNREPORTED
DarkPassengerWitness.STATE_REPORTED
DarkPassengerWitness.STATE_SILENCED_BEFORE_REPORT
DarkPassengerWitness.STATE_SILENCED_AFTER_REPORT
DarkPassengerWitness.STATE_LOST
DarkPassengerWitness.BeginCase
DarkPassengerWitness.Confirm
DarkPassengerWitness.MarkReported
DarkPassengerWitness.MarkDead
DarkPassengerWitness.MarkLost
DarkPassengerWitness.GetCaseOutcome
DarkPassengerWitness.Persist
DarkPassengerWitness.Restore
DarkPassengerWitness.Status
```

Require schema keys:

```text
dp_witness_schema_version
dp_witness_record_count
dp_witness_next_record_id
dp_witness_active_case_generation
dp_witness_noisy_locked
dp_witness_notification_emitted
dp_witness_v1_<record>_<field>
```

**Step 2: Run the suite**

Expected: missing module, functions, states, and keys fail.

**Step 3: Implement the minimal ledger**

Use append-only numeric records. Each record stores:

```text
recordId, identityCodeA, identityCodeB, caseGeneration, regionCode,
settlementCode, targetSlot, evidenceCode, identified, stateCode,
incidentTime, reportTime, deathTime, deathX, deathY, deathZ
```

Use `Variables.GetGlobal` and `Variables.SetGlobal` behind protected wrappers.
Do not enumerate variable names: persist `record_count` and restore the numeric
range. Keep an in-memory index by `identityCodeA:identityCodeB`.

`Confirm` is idempotent for the same identity and Case. `MarkReported` is
monotonic and sets `noisyLocked`. `MarkDead` maps:

```text
UNREPORTED -> SILENCED_BEFORE_REPORT
REPORTED   -> SILENCED_AFTER_REPORT
```

`GetCaseOutcome` returns:

```text
noisy       when noisyLocked is true
clean       when the Case has no confirmed witnesses
controlled  when every witness is SILENCED_BEFORE_REPORT
noisy       when any witness is UNREPORTED, REPORTED, LOST, or
            SILENCED_AFTER_REPORT
```

**Step 4: Add debug commands**

Register:

```text
dp_witness_status
dp_witness_confirm
dp_witness_report
dp_witness_dead
dp_witness_lost
```

Debug commands accept explicit numeric identity codes and never guess a nearby
NPC.

**Step 5: Load the module before aftermath**

In `darkpassengertest.lua`:

```lua
Script.ReloadScript("Scripts/mods/dpwitness.lua")
Script.ReloadScript("Scripts/mods/dpaftermath.lua")
```

**Step 6: Run tests and commit**

```powershell
pwsh -NoProfile -File 'H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1' `
  -ReferenceDataRoot 'H:\KCD2Mod\_reference-mods\_extracted\AssetLinker\InternalData' `
  -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
```

Expected: all existing 560 checks plus ledger checks pass.

```powershell
git add -- `
  'H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpwitness.lua' `
  'H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\darkpassengertest.lua' `
  'H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1'
git commit -m 'feat: add persistent witness ledger'
```

### Task 4: Make aftermath resolve from witness state

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpaftermath.lua`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpwitness.lua`
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1`

**Step 1: Write failing outcome checks**

Require:

- `Begin` starts the matching ledger Case;
- confirmation enters `CLEANUP` without locking noisy;
- report/alarm/identification/bounty locks noisy;
- removing every unreported witness yields controlled on zone exit;
- a living/lost/reported witness yields noisy on zone exit;
- cleanup no longer means unconditional noisy;
- save/load restores the same outcome;
- result and hunger reset remain idempotent.

**Step 2: Run the suite**

Expected: new outcome checks fail against the current
`CLEANUP -> Resolve("noisy")` behavior.

**Step 3: Split reversible suspicion from irreversible exposure**

Add:

```lua
DarkPassengerAftermath.RecordWitness(identity, evidence, identified)
DarkPassengerAftermath.RecordReport(identity, reason)
DarkPassengerAftermath.LockNoisy(reason)
```

Keep `RecordSuspicion(reason)` as a debug-compatible transition to cleanup, but
do not let generic suspicion erase the distinction between an unreported
witness and a completed report.

**Step 4: Resolve zone exit through the ledger**

Replace unconditional cleanup resolution with:

```lua
local result = DarkPassengerWitness.GetCaseOutcome(
    DarkPassengerAftermath.generation
)
return DarkPassengerAftermath.Resolve(result)
```

Map a confirmed witness death through `MarkDead`. Increment collateral and
blood trail only when the removal is reliably Henry-attributed; an external or
unknown death may silence testimony without inventing Henry attribution.

**Step 5: Restore idempotently**

After `dpaftermath.lua` restores an active generation, restore the witness
ledger and verify both modules agree on generation. Ignore stale records from
older Cases.

**Step 6: Run tests and commit**

Expected: clean baseline remains green; new controlled and locked-noisy
contracts pass.

```powershell
git add -- `
  'H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpaftermath.lua' `
  'H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpwitness.lua' `
  'H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1'
git commit -m 'feat: resolve aftermath from witness state'
```

### Task 5: Add one anonymous native quest update

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Libs\Tables\rpg\buff__darkpassengertest.xml`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Libs\Tables\rpg\buff_ai_tag__darkpassengertest.xml`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpaftermath.lua`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml.template`
- Modify: `H:\KCD2Mod\DarkPassenger\localization\English\text__darkpassengertest.xml`
- Modify: `H:\KCD2Mod\DarkPassenger\localization\Russian\text__darkpassengertest.xml`
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1`

**Step 1: Write failing signal and journal checks**

Require:

```text
AI tag 29: darkpassenger_witness_detected
buff GUID: 4804f2b2-1462-44f1-b76d-5602426bcc1
buff name: dp_witness_detected
buff_ui_visibility_id="0"
buff_exclusivity_id="0"
```

Require a player `BuffTagTrigger`, a `Witnessed` started state in
`DP_CleanupProgress`, and no marker asset or marker attribute for witnesses.

**Step 2: Add the hidden one-shot signal**

The buff uses the proven hidden constant-buff pattern. At `Begin`, remove any
old witness signal. On the first confirmed witness only:

```lua
DarkPassengerAftermath.EmitWitnessSignal()
DarkPassengerWitness.SetNotificationEmitted()
```

The persisted notification flag prevents duplicate banners after save/load or
multiple witnesses.

**Step 3: Add native quest state**

Add:

```xml
<StateTypeEnumeration Name="Witnessed" ObjectiveValueType="Started" />
```

and:

```xml
<Edge From="witnessDetectedTrigger.OnAdded" To="SetWitnessed" />
```

Result triggers must still move the same objective to its completed epilogue
and complete the Case.

**Step 4: Add localization**

Russian:

```text
Кто-то видел слишком много.
```

English:

```text
Someone saw too much.
```

Do not reveal the witness name, number, identity, or location.

**Step 5: Regenerate and test**

```powershell
pwsh -NoProfile -File 'H:\KCD2Mod\DarkPassenger\tools\Generate-VictimArtifacts.ps1'
pwsh -NoProfile -File 'H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1' `
  -ReferenceDataRoot 'H:\KCD2Mod\_reference-mods\_extracted\AssetLinker\InternalData' `
  -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
```

Expected: both regional graphs contain the signal and remain valid XML.

**Step 6: Commit**

```powershell
git add -- `
  'H:\KCD2Mod\DarkPassenger\src\Data\Libs\Tables\rpg\buff__darkpassengertest.xml' `
  'H:\KCD2Mod\DarkPassenger\src\Data\Libs\Tables\rpg\buff_ai_tag__darkpassengertest.xml' `
  'H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpaftermath.lua' `
  'H:\KCD2Mod\DarkPassenger\src\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml.template' `
  'H:\KCD2Mod\DarkPassenger\localization\English\text__darkpassengertest.xml' `
  'H:\KCD2Mod\DarkPassenger\localization\Russian\text__darkpassengertest.xml' `
  'H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1'
git commit -m 'feat: show anonymous witness update'
```

### Task 6: Prove the state machine with synthetic witnesses

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\evidence\witness-probe-matrix-2026-07-29.md`
- Build: `H:\KCD2Mod\DarkPassenger\build\mod`
- Deploy: `H:\SteamLibrary\steamapps\common\KCD2Mod\Mods\b_DarkPassengerTest`

**Step 1: Run full structural verification**

Expected: zero failures and more than 560 checks.

**Step 2: Build and test archives**

```powershell
pwsh -NoProfile -File 'H:\KCD2Mod\DarkPassenger\tools\Build-Mod.ps1'
7z.exe t 'H:\KCD2Mod\DarkPassenger\build\mod\Data\darkpassengertest.pak'
7z.exe t 'H:\KCD2Mod\DarkPassenger\build\mod\Localization\English_xml.pak'
7z.exe t 'H:\KCD2Mod\DarkPassenger\build\mod\Localization\Russian_xml.pak'
```

Expected: all archives report `Everything is Ok`.

**Step 3: Back up and deploy while the game is closed**

Create an explicit timestamped backup under:

```text
H:\KCD2Mod\_deployment-backups\DarkPassenger
```

Copy the exact built tree to:

```text
H:\SteamLibrary\steamapps\common\KCD2Mod\Mods\b_DarkPassengerTest
```

Verify SHA-256 equality for every deployed file.

**Step 4: Run synthetic scenarios**

Use explicit debug identities:

1. no witness -> timer/exit -> clean;
2. confirm -> remove before report -> exit -> controlled;
3. confirm -> exit alive -> noisy;
4. confirm -> report -> remove -> exit -> noisy;
5. two witnesses -> remove one -> exit -> noisy;
6. two witnesses -> remove both before report -> exit -> controlled;
7. save/load in cleanup -> same witness count and outcome.

Confirm one and only one `Кто-то видел слишком много.` banner per Case.

**Step 5: Record evidence and commit**

```powershell
git add -- 'H:\KCD2Mod\DarkPassenger\evidence\witness-probe-matrix-2026-07-29.md'
git commit -m 'test: verify persistent witness outcomes'
```

### Task 7: Enable only the proven real-witness classifier

**Files:**
- Create: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpwitnessdetector.lua`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\darkpassengertest.lua`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpaftermath.lua`
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1`

**Step 1: Write failing detector checks**

Require:

```lua
DarkPassengerWitnessDetector.Scan
DarkPassengerWitnessDetector.Classify
DarkPassengerWitnessDetector.Status
```

Assert that scanning occurs only during `SILENCE_CHECK` or `CLEANUP`, uses the
encounter-zone radius, and never confirms from distance alone.

**Step 2: Implement the evidence-backed adapter**

`Scan` returns events, not state mutations:

```lua
{ type = "confirmed", identity = identity, evidence = evidence }
{ type = "reported", identity = identity, evidence = evidence }
{ type = "alarm", evidence = evidence }
{ type = "dead", identity = identity, attribution = attribution }
```

`dpaftermath.lua` consumes the events and mutates the ledger. Global alarm or
report signals may lock noisy without inventing an identifiable NPC record.

**Step 3: Bound runtime cost**

Reuse the one-second aftermath heartbeat. Scan only loaded entities inside the
zone, cache stable identities, and log scan duration/count in dev mode. Do not
run any world-wide NPC loop.

**Step 4: Run tests and commit**

```powershell
pwsh -NoProfile -File 'H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1' `
  -ReferenceDataRoot 'H:\KCD2Mod\_reference-mods\_extracted\AssetLinker\InternalData' `
  -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
```

```powershell
git add -- `
  'H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpwitnessdetector.lua' `
  'H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\darkpassengertest.lua' `
  'H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpaftermath.lua' `
  'H:\KCD2Mod\DarkPassenger\tests\Test-DarkPassengerSatisfaction.ps1'
git commit -m 'feat: detect confirmed witnesses'
```

### Task 8: Validate real witnesses in dev, then retail

**Files:**
- Build: `H:\KCD2Mod\DarkPassenger\build\mod`
- Deploy dev: `H:\SteamLibrary\steamapps\common\KCD2Mod\Mods\b_DarkPassengerTest`
- Deploy retail: the installed retail `Mods\b_DarkPassengerTest`
- Modify: `H:\KCD2Mod\DarkPassenger\evidence\witness-probe-matrix-2026-07-29.md`

**Step 1: Rebuild and deploy to dev**

Back up the previous dev install, deploy only while closed, and verify hashes.

**Step 2: Validate real dev scenarios**

Repeat the Task 2 matrix using actual detection instead of synthetic commands.
Require zero false witnesses in proximity-only and corpse-discovery-only cases.

**Step 3: Save/load validation**

Save and load with:

- one living unreported witness;
- one reported witness;
- one silenced-before-report witness;
- a locked noisy Case.

Expected: no duplicate record, banner, result signal, hunger reset, or blood
trail increment.

**Step 4: Retail checkpoint**

Only after dev classification is stable:

- back up retail;
- deploy identical hashes;
- verify native objective update and sound;
- verify clean, controlled, and noisy Case completion;
- verify base-game crime consequences continue independently.

**Step 5: Commit the accepted evidence**

```powershell
git add -- 'H:\KCD2Mod\DarkPassenger\evidence\witness-probe-matrix-2026-07-29.md'
git commit -m 'test: confirm witness system in retail'
```

### Task 9: Update technical reference and project history

**Files:**
- Modify: the existing Dark Passenger pages inside
  `C:\Users\Vladislav\Obsidian Vaults\LLM Wiki`
- Modify: `H:\KCD2Mod\DarkPassenger\README.md`

**Step 1: Separate evidence from design**

Document as confirmed only:

- stable witness identity source;
- accepted reaction/report signals;
- persistence encoding;
- native witness-update graph;
- save/load behavior;
- retail result transitions.

Keep unimplemented rumors, pressure weights, and Nemesis behavior explicitly
marked as future design.

**Step 2: Update the Roadmap**

Mark the first witness-ledger slice complete and retain later slices:

```text
identity rumors -> witness interaction -> investigation pressure -> Nemesis
```

**Step 3: Run final verification**

Run the full suite, build all paks, test archives, and run `git diff --check`.

**Step 4: Commit and push**

```powershell
git add -- 'H:\KCD2Mod\DarkPassenger\README.md'
git commit -m 'docs: document witness system'
git push
```

Do not push until the retail checkpoint is accepted.

## Unresolved questions

- Which KCD2 signal reliably proves direct witnessing and Henry linkage?
- Which signal proves that a specific witness has reported?
- Which NPC identity survives save/load and streaming?
- Does `Variables` persist strings, or must identity use two numeric hashes?
- Can witness-death attribution distinguish Henry from external causes?
