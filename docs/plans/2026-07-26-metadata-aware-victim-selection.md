# Metadata-Aware Victim Selection Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let Lua select a safe living Pritoky victim from metadata, then switch one tracked objective to the generated native marker state for that exact NPC.

**Architecture:** `config/victim-candidates.json` is the single source of truth. A PowerShell build generator produces both a Lua catalogue and the repeated Skald XML needed for static marker slots. Lua performs selection and applies `dp_is_target`; the quest graph resolves the tagged fixed alias and activates `TargetNNN`.

**Tech Stack:** KCD2 Lua, Skald quest XML, PowerShell 7, JSON, 7-Zip, retail runtime testing.

---

## Preconditions

- Work in `<repo-root>`.
- The project is not a Git repository. Commit steps are intentionally omitted.
- Do not deploy while either game build or `trace_server.run` holds the mod.
- Use PowerShell 7 (`pwsh`) for tests because the test file is UTF-8 without BOM.

### Task 1: Verify three safe Pritoky slots

**Files:**
- Create: `<repo-root>\evidence\pritoky-poc-candidates.md`
- Inspect: `<repo-root>\build\mod\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml`

**Step 1: Launch the dev build and connect to the HTTP bridge**

Run a harmless command:

```powershell
curl.exe --get --data-urlencode "command=wh_quest_ListQuests" `
  "http://127.0.0.1:1403/api/System/Console/ExecuteString"
```

Expected: HTTP 200 and a matching line in `kcd.log`.

**Step 2: Probe candidate identity and safety**

For three loaded Pritoky aliases, log:

- internal entity name;
- entity id;
- display name;
- Soul and actor presence;
- current dead state;
- available immortality/killability methods;
- available faction, role, gender, shop, and hobby methods.

Use single-quoted Lua string literals inside the `#` console command because
the HTTP console strips double quotes.

**Step 3: Select only verified candidates**

Reject:

- story or quest NPCs;
- entities with unknown killability;
- dead or missing entities;
- candidates without a Soul.

Record the three accepted alias/GUID/name tuples and the evidence used.

## Task 2: Add the single-source candidate catalogue

**Files:**
- Create: `<repo-root>\config\victim-candidates.json`
- Modify: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`

**Step 1: Write failing catalogue assertions**

Add checks that require:

- exactly three enabled `pritoky` PoC candidates;
- unique `slot`, `alias`, `guid`, and `entityName`;
- `gameRegion`, `settlement`, `weight`, and `killableVerified`;
- no candidate marked story-critical, quest-critical, immortal, or dead.

**Step 2: Run RED**

```powershell
pwsh -NoProfile -File "<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1"
```

Expected: failures because the catalogue does not exist.

**Step 3: Create the minimal catalogue**

Use this shape with the three verified records from Task 1:

```json
{
  "schemaVersion": 1,
  "candidates": [
    {
      "slot": 1,
      "gameRegion": "kutnohorsko",
      "settlement": "pritoky",
      "alias": "PritokySoulNN",
      "guid": "verified-guid",
      "entityName": "verified-name",
      "tags": ["commoner"],
      "weight": 1,
      "enabled": true,
      "killableVerified": true,
      "storyCritical": false,
      "questCritical": false,
      "immortal": false
    }
  ]
}
```

**Step 4: Run GREEN**

Expected: catalogue assertions pass.

## Task 3: Generate Lua and Skald marker slots

**Files:**
- Create: `<repo-root>\tools\Generate-VictimArtifacts.ps1`
- Create: `<repo-root>\build\mod\Data\Scripts\mods\generated\dp_candidate_catalog.lua`
- Create: `<repo-root>\build\mod\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml.template`
- Generate: `<repo-root>\build\mod\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml`
- Modify: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`

**Step 1: Write failing generator assertions**

Require:

- deterministic output from the same catalogue;
- one Lua record per enabled candidate;
- one `SoulAsset`, `StateTypeEnumeration`, `EnumLog Marker`, tag-check branch,
  and death branch per slot;
- every generated marker references an existing alias;
- duplicate slot/GUID/alias/name causes generator failure.

**Step 2: Run RED**

Expected: generator/output checks fail.

**Step 3: Implement the generator**

The template contains explicit tokens:

```text
{{DP_TARGET_TYPE_ENUMS}}
{{DP_TARGET_STATE_EDGES}}
{{DP_TARGET_DETECTION_NODES}}
{{DP_TARGET_DEATH_NODES}}
{{DP_TARGET_ASSETS}}
{{DP_TARGET_LOGS}}
```

For slot `1`, generate:

```xml
<StateTypeEnumeration Name="Target001" ObjectiveValueType="Started" />
```

```xml
<EnumLog Type="Started" Name="Target001"
         IsTracked="true" Marker="PritokySoulNN">
  <Log StringName="dark_within_target"
       Text="The Dark Passenger has made its choice." />
</EnumLog>
```

Generate `SetTarget001` on the target objective state and a fixed-alias
`BuffTagCheck` that drives it when `dp_is_target` is present.

Write all generated text as UTF-8 without BOM.

**Step 4: Generate artifacts**

```powershell
pwsh -NoProfile -File `
  "<repo-root>\tools\Generate-VictimArtifacts.ps1"
```

Expected: both generated files change only when catalogue/template changes.

**Step 5: Run GREEN**

Expected: all generator and structural XML checks pass.

## Task 4: Replace XML random selection with Lua policy selection

**Files:**
- Modify: `<repo-root>\build\mod\Data\Scripts\mods\darkpassengertest.lua`
- Modify template: `<repo-root>\build\mod\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml.template`
- Regenerate: `<repo-root>\build\mod\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml`
- Modify: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`

**Step 1: Write failing selector tests**

Require Lua to:

- load the generated catalogue;
- filter by game region and settlement;
- reject player, missing entity, missing Soul, dead entity, and every safety
  exclusion flag;
- perform weighted random selection over the remaining candidates;
- clear the previous target tag;
- apply `dp_is_target` to exactly one candidate;
- return failure without tagging anyone when the pool is empty.

**Step 2: Run RED**

Expected: selector assertions fail against the current name-pattern selector.

**Step 3: Implement minimal selector**

Expose:

```lua
DarkPassengerTarget.Select("kutnohorsko", "pritoky")
```

Use runtime entity lookup by the verified internal name. Treat missing or
unknown safety data as ineligible.

**Step 4: Trigger selection from the quest**

On hunt activation, use:

```xml
<Function MethodName="wh::conceptmodule::ExecuteConsoleString"
          DeclaringType="wh::conceptmodule">
  <Constant Name="Command"
            Value="dp_target_select kutnohorsko pritoky" />
</Function>
```

Remove the current XML `RandomIntegerRange` and `Switch` selection path after
the new selector test is green.

**Step 5: Regenerate and run GREEN**

Expected: selection and all previous lifecycle tests pass.

## Task 5: Enforce living-target and kill-attribution rules

**Files:**
- Modify: `<repo-root>\build\mod\Data\Scripts\mods\darkpassengertest.lua`
- Modify template: `<repo-root>\build\mod\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml.template`
- Modify: `<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1`

**Step 1: Write failing lifecycle assertions**

Require:

- revalidation immediately before `SetTargetNNN`;
- dead target causes tag clear and bounded reselection;
- no valid candidate leaves the target objective inactive;
- target death grants satisfaction only through the verified Henry kill event;
- non-Henry death clears the case and requests replacement;
- retries have a fixed maximum and delayed fallback.

**Step 2: Run RED**

Expected: current graph fails because `rewardTargetDeath` grants satisfaction
for any death.

**Step 3: Remove unconditional death reward**

Delete the graph edge that directly grants satisfaction from
`SoulDeathTrigger.OnDeath`.

Keep correct-kill reward in the Lua/player-event path. After a target death,
delay briefly, check the satisfaction tag, then:

- satisfaction present: complete objective and quest;
- satisfaction absent: clear target state/tag and request reselection.

**Step 4: Run GREEN**

Expected: all lifecycle assertions pass.

## Task 6: Package and retail acceptance

**Files:**
- Generate: `<repo-root>\build\mod\Data\darkpassengertest.pak`
- Deploy: `<kcd2-retail-root>\Mods\b_DarkPassengerTest\Data\darkpassengertest.pak`
- Deploy: `<kcd2-dev-root>\Mods\b_DarkPassengerTest\Data\darkpassengertest.pak`

**Step 1: Run the full suite**

```powershell
pwsh -NoProfile -File "<repo-root>\tests\Test-DarkPassengerSatisfaction.ps1"
```

Expected: `RESULT: PASS`.

**Step 2: Validate source XML and generated files**

Check XML parsing, no UTF-8 BOM, no unresolved template tokens, unique generated
slots, and exact candidate count.

**Step 3: Rebuild the pak from scratch**

Use 7-Zip ZIP mode with `-mtc=off`. Never update the existing pak in place.

**Step 4: Test the archive**

```powershell
7z.exe t "<repo-root>\build\mod\Data\darkpassengertest.pak"
```

Expected: `Everything is Ok`; no `Characteristics = NTFS`.

**Step 5: Deploy after the game is closed**

Back up the previous dev and retail pak, copy the staged pak, and verify all
SHA-256 hashes are identical.

**Step 6: Retail acceptance**

Verify:

1. repeated fresh cases mark more than one of the three candidates;
2. Lua log target matches the map/compass marker;
3. a dead candidate is skipped;
4. killing a non-target does nothing;
5. Henry killing the target completes the case and grants satisfaction;
6. another actor killing the target grants nothing and causes replacement.

## Unresolved questions

- Exact two additional safe Pritoky aliases for the three-candidate PoC; resolve
  with the dev Lua probe in Task 1.
- Exact runtime binding for immortality; until verified, only explicit
  `killableVerified=true` catalogue entries are eligible.

