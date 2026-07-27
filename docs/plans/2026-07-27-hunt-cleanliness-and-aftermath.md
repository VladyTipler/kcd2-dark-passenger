# Dark Passenger Hunt Cleanliness and Aftermath Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a 90-second silence check, witness-driven cleanup, graded satisfaction grace, and persistent settlement consequences without destabilizing the retail-confirmed hunger/target core.

**Architecture:** Keep the native quest graph responsible for objectives and quest presentation. Add an isolated Lua aftermath state machine for timing, exposure, zone exit, persistence, and result calculation; communicate its final result back to both regional graphs through proven hidden buff/tag signals. Generate regional quest changes from the existing template and catalogue generator rather than editing generated XML.

**Tech Stack:** KCD2 Skald quest XML, KCD2 Lua, `Variables` save globals, PowerShell generation/tests, 7-Zip pak packaging, dev runtime probes, retail quest validation.

---

## Safety constraints

- Preserve the current known-good pak before every deployment experiment.
- Change one runtime hypothesis per retail build.
- Never hand-edit generated `dark_within_k.xml`, `dark_within_t.xml`, or
  `dp_candidate_catalog.lua`.
- Dev validates Lua and API probes; retail validates quest graphs, objectives,
  markers, banners, and final integration.
- Work only on `feature/aftermath`. Keep `main` and the
  `core-v1-retail-confirmed` tag unchanged until retail acceptance.
- Edit authored files under `src`; `build\mod` is generated and ignored.
- Commit each verified task. Do not deploy an uncommitted build.

### Task 1: Freeze and verify the known-good baseline

**Files:**
- Test: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`
- Backup: `<repo-root>\deployment-backups`
- Source pak: `<repo-root>\build\mod\Data\darkpassengertest.pak`

**Step 1: Run the baseline structural suite**

Run:

```powershell
pwsh -NoProfile -File '<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1'
```

Expected: `RESULT: PASS (455 checks)` or a higher already-established count.

**Step 2: Record hashes**

Run:

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath '<repo-root>\build\mod\Data\darkpassengertest.pak'
Get-FileHash -Algorithm SHA256 -LiteralPath '<repo-root>\build\mod\Localization\English_xml.pak'
Get-FileHash -Algorithm SHA256 -LiteralPath '<repo-root>\build\mod\Localization\Russian_xml.pak'
```

Expected: three hashes captured in the implementation log.

**Step 3: Create a recoverable checkpoint**

Copy the stage manifest and three paks into a new explicit timestamped directory
under `deployment-backups`. Verify every copied hash matches.

### Task 2: Probe attribution, crime, witness, and zone APIs

**Files:**
- Modify: `<repo-root>\src\Data\Scripts\mods\darkpassengertest.lua`
- Test: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`
- Evidence: `<repo-root>\evidence`

**Step 1: Add failing structural assertions**

Assert that diagnostic commands exist for:

- `dp_aftermath_probe_status`;
- `dp_aftermath_probe_nearby`;
- `dp_aftermath_probe_crime`;
- `dp_aftermath_probe_attribution`.

Run the suite and confirm the four new checks fail.

**Step 2: Search local authoritative references**

Search the dev build and extracted reference mods for:

- player wanted/crime/bounty state;
- alarm, search, witness, perception, and hostility events;
- last attacker/killer/damage owner;
- entity position and player distance;
- corpse discovery events.

Prefer game scripts and Temptation's proven Lua/XML bridge over public
CryEngine assumptions.

**Step 3: Add read-only probe commands**

The probes may log candidate APIs and nearby entity state, but must not alter
quests, buffs, crime, AI, or the selected target.

**Step 4: Verify structural tests pass**

Run the PowerShell suite. Expected: baseline plus four passing checks.

**Step 5: Validate in dev**

Probe at least:

- unseen dagger kill;
- bow kill;
- delayed poison;
- public kill;
- NPC-on-NPC target death.

Save exact `kcd.log` excerpts in `evidence`. Do not gate production behaviour on
attribution or witnesses until the probe is conclusive.

### Task 3: Add a pure aftermath state machine

**Files:**
- Create: `<repo-root>\src\Data\Scripts\mods\dpaftermath.lua`
- Modify: `<repo-root>\src\Data\Scripts\mods\darkpassengertest.lua`
- Test: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`

**Step 1: Write failing state-contract tests**

Require these exported symbols:

```lua
DarkPassengerAftermath.PHASE_HUNTING
DarkPassengerAftermath.PHASE_SILENCE_CHECK
DarkPassengerAftermath.PHASE_CLEANUP
DarkPassengerAftermath.PHASE_RESOLVED
DarkPassengerAftermath.SILENCE_DURATION_MS
DarkPassengerAftermath.Begin
DarkPassengerAftermath.RecordSuspicion
DarkPassengerAftermath.RecordWitnessRemoved
DarkPassengerAftermath.OnPlayerPosition
DarkPassengerAftermath.Resolve
DarkPassengerAftermath.Status
```

Also assert `SILENCE_DURATION_MS = 90000`.

**Step 2: Run tests and confirm failure**

Expected: missing module/symbol assertions fail without changing existing
checks.

**Step 3: Implement the isolated state machine**

Keep transitions explicit:

```text
HUNTING -> SILENCE_CHECK
SILENCE_CHECK -> RESOLVED_CLEAN on timer or clean zone exit
SILENCE_CHECK -> CLEANUP on first suspicion
CLEANUP -> RESOLVED_* on zone exit
```

Use a generation token with `Script.SetTimerForFunction` so cancelled or stale
90-second callbacks cannot resolve a newer Case.

**Step 4: Add debug-only signal injection**

Add commands to:

- begin a synthetic Case;
- inject suspicion;
- remove a synthetic witness;
- simulate zone exit;
- print phase, generation, timer state, exposure flags, and collateral count.

These commands must not grant the satisfaction gate.

**Step 5: Run structural tests**

Expected: all new state-contract checks pass and all baseline checks remain
green.

### Task 4: Persist aftermath and settlement state

**Files:**
- Modify: `<repo-root>\src\Data\Scripts\mods\dpaftermath.lua`
- Modify: `<repo-root>\src\Data\Scripts\mods\dphunger.lua`
- Test: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`

**Step 1: Write failing persistence assertions**

Require namespaced `Variables` keys for:

- aftermath schema and phase;
- region, settlement, target slot;
- death position and zone radius;
- silence deadline/generation;
- exposure flags and collateral count;
- resolved generation;
- per-settlement attention and blood trail.

Do not create a second configuration source; constants stay in the Lua module
and persisted values stay in `Variables`.

**Step 2: Implement scalar serialization**

Use the same protected `Variables.GetGlobal`/`SetGlobal` pattern already proven
in `dphunger.lua`. Persist only scalar values supported by runtime probes.

**Step 3: Implement idempotent recovery**

On load:

- resume `SILENCE_CHECK` from remaining active-play time;
- restore `CLEANUP` without restarting the timer;
- ignore stale callbacks using generation;
- never apply a resolved result twice;
- close unresolved missing-witness state through a bounded fallback.

**Step 4: Add settlement metrics**

Persist short-term `attention` and long-term `bloodTrail` by stable settlement
id. Version their key format so later content can migrate it.

**Step 5: Run tests**

Expected: persistence-key, generation, and idempotency assertions pass.

### Task 5: Add hunger grace without duplicating hunger state

**Files:**
- Modify: `<repo-root>\src\Data\Scripts\mods\dphunger.lua`
- Modify: `<repo-root>\src\Data\Scripts\mods\dpaftermath.lua`
- Test: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`

**Step 1: Add failing tests for the grace contract**

Require:

```lua
DarkPassengerHunger.ResetAfterHunt(graceDays)
```

Expected mapping:

- clean -> `2`;
- controlled -> `1`;
- noisy -> `0`;
- external death -> no reset call.

**Step 2: Extend the existing timestamp SSOT**

Represent grace through the existing hunger time anchor rather than a second
incrementing hunger value. Clamp elapsed time to zero until the grace period
ends.

**Step 3: Keep the gate lifecycle unchanged**

`ResetAfterHunt(graceDays)` must retain:

- direct timestamp reset;
- `satisfactionGateExpected = true`;
- idempotent tier evaluation;
- no `HasBuffDebug` dependency.

**Step 4: Add status logging**

`dp_hunger_status` must show grace days/result and the effective hunger-growth
anchor.

**Step 5: Run tests**

Expected: all existing hunger boundaries still pass plus grace mappings.

### Task 6: Establish the Lua-to-quest outcome signal

**Files:**
- Modify: `<repo-root>\src\Data\Libs\Tables\rpg\buff__darkpassengertest.xml`
- Modify: `<repo-root>\src\Data\Libs\Tables\rpg\buff_ai_tag__darkpassengertest.xml`
- Modify: `<repo-root>\src\Data\Scripts\mods\dpaftermath.lua`
- Test: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`

**Step 1: Add failing table assertions**

Require hidden non-exclusive one-shot result signals for:

- clean;
- controlled;
- noisy;
- external death.

Use new unique GUIDs and AI tags. Result buffs must have
`buff_ui_visibility_id="0"` and `buff_exclusivity_id="0"`.

**Step 2: Add the hidden rows**

Follow the proven hidden `dp_satisfaction_gate` table pattern. Do not reuse tag
23 or target tag 24.

**Step 3: Emit exactly one result**

`DarkPassengerAftermath.Resolve` applies one result signal once per generation.
Repeated callbacks log and return without applying another signal.

**Step 4: Run table tests**

Expected: XML parses, GUIDs/tags are unique, signals are hidden/non-exclusive.

**Step 5: Prove the signal in one minimal retail graph**

Before full graph generation, wire only a debug/probe objective to one result
tag. Confirm native journal transition once. Roll back the probe before Task 7.

### Task 7: Generate the cleanup objective and defer quest completion

**Files:**
- Modify: `<repo-root>\src\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml.template`
- Modify: `<repo-root>\tools\Generate-VictimArtifacts.ps1`
- Generate: `<repo-root>\build\mod\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml`
- Generate: `<repo-root>\build\mod\Data\Quests\darkpassengertest\trosecko\dark_within_t.xml`
- Test: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`

**Step 1: Replace obsolete test expectations**

New expected graph contract:

- target death completes only the target objective;
- target death disables victim selection;
- target death activates `Не оставить следов`;
- target death dispatches `death|region|settlement|slot` through
  `dp_lua_call`;
- result tag completes the cleanup objective and the Case;
- clean/controlled/noisy add the satisfaction gate;
- external death completes the Case without adding the gate.

Run tests and confirm failure.

**Step 2: Update the template**

Add:

- a cleanup objective and progress state;
- four result `BuffTagTrigger` paths;
- quest completion edges from resolved cleanup;
- satisfaction edges only for Henry-attributed results.

Remove immediate quest completion and immediate satisfaction from candidate
death edges.

**Step 3: Update the generator**

Generate per-slot death bridge nodes and action strings. Keep all per-candidate
content generated from `config\victim-candidates.json`.

**Step 4: Regenerate both regional graphs**

Run:

```powershell
pwsh -NoProfile -File '<repo-root>\tools\Generate-VictimArtifacts.ps1'
```

Expected: both XML files parse, contain no unresolved template tokens, and stay
under configured graph-size limits.

**Step 5: Run the full suite**

Expected: baseline contracts unrelated to target-death completion remain green;
new aftermath contracts pass.

### Task 8: Add localization and lore epilogues

**Files:**
- Modify: `<repo-root>\localization\English\text__darkpassengertest.xml`
- Modify: `<repo-root>\localization\Russian\text__darkpassengertest.xml`
- Modify: `<repo-root>\src\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml.template`
- Test: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`

**Step 1: Add failing localization checks**

Require English and Russian entries for:

- cleanup objective name and log;
- clean epilogue;
- controlled epilogue;
- noisy epilogue;
- external-death epilogue.

**Step 2: Add concise lore text**

Russian cleanup objective:

> Не оставить следов.

Keep outcome text qualitative. Do not expose timers, ranks, percentages,
attention, or blood-trail values.

**Step 3: Regenerate graphs and localization paks**

Use the existing localization packaging procedure. Verify UTF-8/no BOM where
required and test each archive with `7z t`.

**Step 4: Run tests**

Expected: keys exist in both languages and generated graphs reference them.

### Task 9: Package and validate incrementally

**Files:**
- Build: `<repo-root>\build\mod\Data\darkpassengertest.pak`
- Deploy dev: `<kcd2-dev-root>\Mods\b_DarkPassengerTest`
- Deploy retail: `<kcd2-retail-root>\Mods\b_DarkPassengerTest`
- Log: each build under `<repo-root>\evidence`

**Step 1: Run all structural tests**

Expected: zero failures and a higher check count than the preserved baseline.

**Step 2: Build deterministic paks**

Use `7z a -tzip -mx=9 -mtc=off`, then `7z t`. Reject NTFS metadata entries.

**Step 3: Validate Lua state transitions in dev**

Use debug commands to prove:

- timer expiry -> clean;
- injected suspicion cancels timer;
- cleanup never restarts timer;
- zone exit resolves once;
- save/load restores both phases.

**Step 4: Deploy to retail only while the game is closed**

Back up the installed retail mod first. Copy the exact tested stage artifacts
and verify hashes after deployment.

**Step 5: Validate one retail scenario per build**

Order:

1. unseen kill -> cleanup objective -> clean resolution after 90 seconds;
2. clean exit from zone before timeout;
3. witnessed kill -> cleanup -> exit -> controlled/noisy;
4. witness removal before report;
5. delayed poison/arrow attribution;
6. external death;
7. save/load during silence check;
8. save/load during cleanup.

Do not combine failing hypotheses. Restore the previous known-good retail build
when a build crashes or corrupts tables.

### Task 10: Document only retail-confirmed findings

**Files:**
- Modify: `<local-wiki-root>\kcd2-modding-technical-reference.md`
- Modify: `<local-wiki-root>\game-modding-design-docs.md`
- Modify: `<local-wiki-root>\Overview.md`
- Modify: `<local-wiki-root>\log.md`

**Step 1: Separate facts from proposals**

Record runtime APIs and graph behaviour as confirmed only after retail
evidence. Keep unproven witness/attribution assumptions labelled experimental.

**Step 2: Update the design source**

Add the approved silence-check, cleanup, exposure, blood-trail, grace, and
external-death rules. Link back to the technical reference.

**Step 3: Validate Wiki structure**

Preserve versioning, schema, index integration, and backlinks. Do not create a
parallel Dark Passenger design page.

## Unresolved questions

- Reliable API/event for direct witnesses and report completion?
- Reliable Henry attribution for arrow, poison, and provoked deaths?
- Exact encounter radius: fixed 100–150 m or settlement-sensitive?
- Can body discovery be observed after the quest resolves?
- Exact attention decay and blood-trail deltas?
