# Nonlinear Evidence Orchestration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Compile finite, order-independent Case evidence packages whose physical clues exist from Case start, whose directions react to Henry's knowledge, and whose first new native primitive is an overheard NPC conversation.

**Architecture:** CaseSpec remains the authored source of truth and compiles all native XML ahead of time. A persisted Case Snapshot selects one compiled package; a central Evidence Registry stores discovered clue codes and reconciles confidence idempotently; a Lead Planner projects finite knowledge states into the universal native journal. Existing dialogue, document and witness runtimes become thin adapters, while an authored `ingame` NPC-to-NPC dialogue proves the sixth evidence primitive.

**Tech Stack:** PowerShell 7 CaseSpec compiler/tests, KCD2 Lua, Skald quest/dialogue XML, Storm roles, ScriptContext/buff bridges, CryHttp live console, English/Russian localization.

---

## Preconditions

- Work directly in `H:\KCD2Mod\DarkPassenger`; no worktree by prior user decision.
- Do not rebuild or deploy while the current live canary is still being observed.
- Generated files under `build\` are outputs; edit CaseSpec, compiler, templates and runtime sources only.
- Every new evidence kind must compile into finite native artifacts and pass one live boundary canary before reuse.
- Use `C:\Program Files\PowerShell\7\pwsh.exe` for repository tests and UTF-8 without BOM for Lua/XML.

### Task 1: Lock content correctness and remove the unsafe reaction pool

**Files:**
- Modify: `content/cases/missing-traveler.case.json`
- Modify: `tests/Test-MissingTravelerCase.ps1`
- Modify: `tests/Test-MissingTravelerGeneration.ps1`
- Modify: `tests/Test-EvidenceReaction.ps1`
- Modify: `src/Data/Scripts/mods/dpevidencereaction.lua`

**Step 1: Write failing copy and safety tests**

Assert that the active stablehand direction cites Lavrentiy's riderless-horse fact, does not claim Matej's note identified a stablehand, and has English parity. Assert that `HRAC_VYPNUL_PHOTOMODE` is forbidden because its random pool contains sightseeing lines.

**Step 2: Run focused tests and confirm RED**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tests\Test-MissingTravelerCase.ps1'
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tests\Test-EvidenceReaction.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
```

Expected: failures for stale journal attribution and the photo-mode metarole.

**Step 3: Apply the minimal correction**

Use copy equivalent to:

```text
RU: Лаврентий сказал, что конь Матея вернулся без всадника. Конюх мог видеть, кто привёл его обратно.
EN: Lavrentiy said Matej's horse returned without its rider. The stablehand may have seen who brought it back.
```

Remove the photo-mode metarole from the reaction dispatcher. Until a narrow,
live-proven neutral Henry event is identified, return `no_safe_reaction`
without persisting a successful dispatch; silence is preferable to a false
line.

**Step 4: Regenerate and confirm GREEN**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tools\Compile-CaseSpecs.ps1'
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tests\Test-MissingTravelerGeneration.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
```

**Step 5: Commit**

```powershell
git add content/cases/missing-traveler.case.json tests/Test-MissingTravelerCase.ps1 tests/Test-MissingTravelerGeneration.ps1 tests/Test-EvidenceReaction.ps1 src/Data/Scripts/mods/dpevidencereaction.lua
git commit -m "fix: align missing traveler clue copy"
```

### Task 2: Extend the finite CaseSpec evidence contract

**Files:**
- Modify: `content/cases/missing-traveler.case.json`
- Modify: `content/cases/convenient-accident.case.json`
- Modify: `tools/CaseSpecCompiler.psm1`
- Modify: `tests/Test-CaseSpecCompiler.ps1`
- Modify: `tests/Test-CaseSpecGeneration.ps1`

**Step 1: Write failing compiler tests**

Require every evidence entry to compile these fields:

```json
{
  "placement": "case_start",
  "discoverableWithoutHint": true,
  "hintsUnlockedBy": [],
  "reveals": ["forged_departure"]
}
```

Accept `placement` only as `case_start` or `on_event`. Reject missing required
bindings, unknown evidence kinds and hint references to nonexistent evidence
ids. Allow optional `claimId` and `claimCap` but do not require them in the
first canary.

**Step 2: Run compiler tests and confirm RED**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tests\Test-CaseSpecCompiler.ps1'
```

**Step 3: Implement validation and generated Lua fields**

Update `ConvertTo-DpRuntimeEvidence` and validation so the compiled catalog
contains only normalized finite values. Add compatibility diagnostics naming
the exact `case.evidence` path.

**Step 4: Model Missing Traveler as parallel evidence**

- ledger: `placement=case_start`, discoverable without hint;
- stablehand: dialogue-only, hint unlocked by the innkeeper rumor;
- ledger and stablehand must not depend on each other;
- total available confidence must exceed 70 after later optional sources are
  added; the current three-source canary remains valid during migration.

**Step 5: Run focused tests and commit**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tests\Test-CaseSpecCompiler.ps1'
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tests\Test-CaseSpecGeneration.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
git add content/cases tools/CaseSpecCompiler.psm1 tests/Test-CaseSpecCompiler.ps1 tests/Test-CaseSpecGeneration.ps1
git commit -m "feat: compile nonlinear evidence contracts"
```

### Task 3: Add the central Evidence Registry and confidence reconciliation

**Files:**
- Create: `src/Data/Scripts/mods/dpevidenceregistry.lua`
- Create: `tests/Test-NonlinearEvidenceRuntime.ps1`
- Modify: `src/Data/Scripts/mods/dpinvestigation.lua`
- Modify: `src/Data/Scripts/mods/darkpassengertest.lua`

**Step 1: Write failing pure-transition tests**

Cover `pending -> placed -> discovered`, stale generations, duplicate
discovery, and clue-order permutations. The same discovered set must produce
the same confidence total regardless of order.

Required runtime API:

```lua
DarkPassengerEvidenceRegistry.Transition(state, event)
DarkPassengerEvidenceRegistry.MarkPlaced(generation, evidenceCode)
DarkPassengerEvidenceRegistry.Discover(generation, evidenceCode, context)
DarkPassengerEvidenceRegistry.GetCaseState(generation)
DarkPassengerEvidenceRegistry.Restore(generation)
```

**Step 2: Run the new test and confirm RED**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tests\Test-NonlinearEvidenceRuntime.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
```

**Step 3: Implement persisted finite evidence state**

Store by numeric evidence code and investigation generation. Persist discovery
before presentation. Compute confidence from the complete discovered set,
including optional claim caps, rather than incrementing blindly.

**Step 4: Add idempotent investigation reconciliation**

Add `DarkPassengerInvestigation.ReconcileEvidence(total, generation)` as a
pure monotonic domain transition. It sets the authoritative evidence total,
requests reveal once at 70 and makes repeated reconciliation a no-op. Do not
use source-local `AddEvidence` after adapters migrate.

**Step 5: Load registry before evidence adapters**

In `darkpassengertest.lua`, reload the registry after the compiled case catalog
and investigation runtime, before rumor/document/witness consumers.

**Step 6: Run tests and commit**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tests\Test-NonlinearEvidenceRuntime.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tests\Test-DarkPassengerSatisfaction.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
git add src/Data/Scripts/mods/dpevidenceregistry.lua src/Data/Scripts/mods/dpinvestigation.lua src/Data/Scripts/mods/darkpassengertest.lua tests/Test-NonlinearEvidenceRuntime.ps1 tests/Test-DarkPassengerSatisfaction.ps1
git commit -m "feat: persist order-independent evidence"
```

### Task 4: Persist the Case Snapshot and seed world facts at Case start

**Files:**
- Create: `src/Data/Scripts/mods/dpcasesnapshot.lua`
- Create: `src/Data/Scripts/mods/dpevidenceseeder.lua`
- Modify: `src/Data/Scripts/mods/dpcasecontent.lua`
- Modify: `src/Data/Scripts/mods/dpbelongings.lua`
- Modify: `src/Data/Scripts/mods/darkpassengertest.lua`
- Modify: `tests/Test-CaseContentMigration.ps1`
- Modify: `tests/Test-VojtechBelongingsEvidence.ps1`
- Modify: `tests/Test-NonlinearEvidenceRuntime.ps1`

**Step 1: Write failing snapshot and seeding tests**

Prove that generation, case code, target slot, region, settlement and binding
package restore without reroll. Prove that a `case_start` document is placed
before the innkeeper rumor and is not duplicated across its chest and Henry's
inventory.

**Step 2: Run focused tests and confirm RED**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tests\Test-CaseContentMigration.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tests\Test-VojtechBelongingsEvidence.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
```

**Step 3: Implement the immutable snapshot**

Persist stable numeric references only. Resolve text, GUIDs and generated
content through the catalog on restore. Existing save fields migrate once;
never replace an active target or Case.

**Step 4: Implement generic idempotent seeding**

The seeder enumerates compiled `case_start` evidence, dispatches to the adapter
for its finite kind, and records `placed` through the registry. Expose
`DarkPassengerBelongings.EnsurePlaced(generation)` and remove rumor completion
as the only placement trigger.

**Step 5: Start seeding immediately after snapshot persistence**

On investigation open/restore, persist snapshot first, then seed. Missing
streamed containers schedule a retry without changing bindings.

**Step 6: Run focused tests and commit**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tests\Test-NonlinearEvidenceRuntime.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tests\Test-VojtechBelongingsEvidence.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
git add src/Data/Scripts/mods/dpcasesnapshot.lua src/Data/Scripts/mods/dpevidenceseeder.lua src/Data/Scripts/mods/dpcasecontent.lua src/Data/Scripts/mods/dpbelongings.lua src/Data/Scripts/mods/darkpassengertest.lua tests
git commit -m "feat: seed persisted case evidence"
```

### Task 5: Route existing sources through the registry and unlock parallel leads

**Files:**
- Create: `src/Data/Scripts/mods/dpleadplanner.lua`
- Modify: `src/Data/Scripts/mods/dpevidence.lua`
- Modify: `src/Data/Scripts/mods/dpbelongings.lua`
- Modify: `src/Data/Scripts/mods/dpwitnesslead.lua`
- Modify: `src/Data/Scripts/mods/darkpassengertest.lua`
- Modify: `tests/Test-InnkeeperRumorEvidence.ps1`
- Modify: `tests/Test-VojtechBelongingsEvidence.ps1`
- Modify: `tests/Test-TavernWitnessDialog.ps1`
- Modify: `tests/Test-NonlinearEvidenceRuntime.ps1`

**Step 1: Write failing adapter and permutation tests**

Cover these paths:

```text
rumor -> ledger -> stablehand
rumor -> stablehand -> ledger
ledger -> contextual rumor -> stablehand
```

All routes must award each clue once and converge on the same confidence.

**Step 2: Run focused tests and confirm RED**

Run the four tests listed above with PowerShell 7.

**Step 3: Make adapters report only discovery**

Replace source-local `AddEvidence` and separate awarded-generation ledgers with
`EvidenceRegistry.Discover`. Preserve old persisted fields only as migration
inputs. Remove `DarkPassengerWitnessLead.Start` from document completion.

**Step 4: Implement the pure Lead Planner**

`Evaluate(caseTemplate, evidenceState)` returns finite direction ids. For
Missing Traveler:

- before rumor: ledger may still be discovered silently in the world;
- after rumor: expose ledger and stablehand directions in parallel;
- if ledger is already read: expose only stablehand;
- if stablehand is already complete: expose only ledger;
- never resurrect a discovered direction.

**Step 5: Apply availability from planner output**

Availability buffs/tags remain native presentation adapters. Repeated planner
evaluation must not add duplicate buffs or dialogue rewards.

**Step 6: Run tests and commit**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tests\Test-InnkeeperRumorEvidence.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tests\Test-VojtechBelongingsEvidence.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tests\Test-TavernWitnessDialog.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tests\Test-NonlinearEvidenceRuntime.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
git add src/Data/Scripts/mods tests
git commit -m "feat: unlock parallel investigation leads"
```

### Task 6: Generate finite journal knowledge states

**Files:**
- Modify: `tools/CaseSpecCompiler.psm1`
- Modify: `tools/Compile-CaseSpecs.ps1`
- Modify: `src/Data/Quests/darkpassengertest/kutnohorsko/dark_within_k.xml.template`
- Modify: `src/Data/Scripts/mods/dpleadplanner.lua`
- Modify: `tests/Test-CaseNativeWiring.ps1`
- Modify: `tests/Test-MissingTravelerGeneration.ps1`
- Modify: `tests/Test-NonlinearEvidenceRuntime.ps1`

**Step 1: Write failing generated-state tests**

For a finite clue set, generate deterministic journal states for every
reachable direction combination. Missing Traveler needs states equivalent to
`ledger+witness`, `ledger`, `witness`, and `none`; no handwritten state per
story is allowed in the shared template.

**Step 2: Run generation tests and confirm RED**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tests\Test-CaseNativeWiring.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
```

**Step 3: Generate enum, logs and bridge signals**

Compiler output owns all states and localization keys. The planner emits one
state code plus a monotonic presentation revision. The graph updates the
umbrella objective only when the revision changes, preventing duplicate
center-screen objective lines.

**Step 4: Run tests and commit**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tests\Test-CaseNativeWiring.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tests\Test-MissingTravelerGeneration.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
git add tools src/Data/Quests src/Data/Scripts/mods/dpleadplanner.lua tests
git commit -m "feat: generate evidence-aware journal states"
```

### Task 7: Generate contextual source-dialogue variants

**Files:**
- Modify: `content/cases/missing-traveler.case.json`
- Modify: `tools/CaseSpecCompiler.psm1`
- Modify: `src/Data/Scripts/mods/dpleadplanner.lua`
- Modify: `tests/Test-CaseSpecCompiler.ps1`
- Modify: `tests/Test-MissingTravelerGeneration.ps1`
- Modify: `tests/Test-InnkeeperRumorDialog.ps1`

**Step 1: Write failing variant tests**

Add one innkeeper variant for `ledger discovered && rumor undiscovered`.
Require both variants to share the same evidence id and one-shot reward.

**Step 2: Implement finite variant compilation**

CaseSpec supplies authored `when` conditions over known evidence ids. The
compiler emits static FaderDialog sequences and required variant signal tags.
Lua selects only a compiled variant; it never creates dialogue text or nodes.

**Step 3: Verify early-ledger behavior**

An early read keeps the innkeeper available with forgery-aware copy. Finishing
either dialogue variant awards the rumor once and unlocks the riderless-horse
direction.

**Step 4: Run tests and commit**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tests\Test-InnkeeperRumorDialog.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tests\Test-MissingTravelerGeneration.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
git add content/cases/missing-traveler.case.json tools/CaseSpecCompiler.psm1 src/Data/Scripts/mods/dpleadplanner.lua tests
git commit -m "feat: compile contextual clue dialogue"
```

### Task 8: Build the overheard-dialogue engine canary

**Files:**
- Modify: `config/case-settlement-bindings.json`
- Modify: `content/cases/missing-traveler.case.json`
- Modify: `tools/CaseSpecCompiler.psm1`
- Modify: `tools/Compile-CaseSpecs.ps1`
- Create: `src/Data/Scripts/mods/dpoverheardevidence.lua`
- Modify: `src/Data/Scripts/mods/darkpassengertest.lua`
- Create: `tests/Test-OverheardEvidence.ps1`
- Modify: `tests/Test-ZhelejovBindings.ps1`
- Modify: `tests/Test-MissingTravelerGeneration.ps1`

**Step 1: Resolve and record a safe Zhelejov speaker pair**

Use the live bridge only for read-only identity/availability probes. Bind two
ordinary non-story locals plus finite fallbacks; reject a package if the pair
collides with the selected target and no compiled fallback exists.

**Step 2: Write failing native-boundary tests**

Require generated artifacts to contain:

```xml
<Dialogue Type="ingame" Initiator="NonPlayer" ...>
```

with two NPC roles, a `utils.speech.switchdialog` scheduler, an authored
`clue_spoken` output, player-distance configuration, ScriptContext bridge and
one-shot disable signal.

**Step 3: Run the canary test and confirm RED**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tests\Test-OverheardEvidence.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
```

**Step 4: Compile the finite dialogue and scheduler**

Generate one authored conversation variant, semantic roles and bridge wiring.
Do not infer arbitrary ambient conversations or create runtime graph nodes.

**Step 5: Implement exact-line acceptance**

When `clue_spoken` reaches Lua, verify active generation, selected package,
speaker bindings and Henry's current distance (initially 15 metres). On pass,
call `EvidenceRegistry.Discover`; on failure leave the dialogue eligible to
repeat. After discovery disable it for that generation.

**Step 6: Run focused tests and commit**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tests\Test-OverheardEvidence.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tests\Test-ZhelejovBindings.ps1'
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tests\Test-MissingTravelerGeneration.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
git add config content tools src tests
git commit -m "feat: add overheard evidence canary"
```

### Task 9: Build, live-accept and document the proven boundaries

**Files:**
- Modify: `README.md`
- Modify: existing LLM Wiki page `KCD2 Modding - Technical Reference.md`
- Modify: existing LLM Wiki design overview page if architecture changed materially

**Step 1: Run every repository test**

```powershell
Get-ChildItem -LiteralPath '.\tests' -Filter 'Test-*.ps1' | Sort-Object Name | ForEach-Object {
  & 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File $_.FullName -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
  if ($LASTEXITCODE -ne 0) { throw "Failed: $($_.Name)" }
}
```

Expected: every relevant test passes; separately report tests that do not
accept `-DevGameRoot` if the loop requires a small runner adjustment.

**Step 2: Run simplification review**

Review `git diff 47f5842..HEAD` for duplicated source-local ledgers, handwritten
story state, unsafe runtime generation and dead bridge artifacts. Simplify
without changing behavior.

**Step 3: Build once after the game closes**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File '.\tools\Build-Mod.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
```

Inspect both PAKs/generated artifacts and deploy the completed build to the dev
mod directory.

**Step 4: Live acceptance**

Verify one Case generation through these paths without reroll:

1. confirm ledger exists before Lavrentiy;
2. hear Lavrentiy and see ledger/stablehand directions together;
3. complete each order and verify identical confidence;
4. reset to an early-read save and verify contextual Lavrentiy copy;
5. stand outside hearing range for the NPC conversation and receive nothing;
6. repeat within range and receive the overheard clue once;
7. save/load and verify no item, confidence or journal duplication;
8. reach 70 through a non-mandatory subset and reveal the target once.

**Step 5: Update Wiki and README**

Record only live-proven KCD2 boundaries. Clearly label generated architecture
separately from source-only hypotheses. Update the existing pages rather than
creating duplicate Wiki topics.

**Step 6: Final commit and push after user confirmation**

```powershell
git add README.md docs content config tools src tests
git commit -m "feat: ship nonlinear generated investigations"
git push
```

## Unresolved questions

- Which two Zhelejov locals and fallback pair should voice the first overheard rumor? Resolve by one read-only live probe in Task 8.
- What exact Russian/English overheard rumor copy and confidence value? Author before Task 8 generation; suggested 10-15 confidence.
- Which narrow vanilla Henry reaction is both correctly voiced and semantically neutral? Until live-proven, evidence reading stays silent rather than using the photo-mode pool.
