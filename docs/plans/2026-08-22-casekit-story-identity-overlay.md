# CaseKit Story Identity Overlay Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Give every authored case character one fixed localized identity that overlays any compatible runtime-selected NPC from case start while keeping name-bearing content locked behind a hard identity fact.

**Architecture:** StoryPack owns the fictional identity; compatibility binds it to a physical actor without altering engine IDs or voice selection. CaseSpecCompiler emits localized `SoulUiNameOverride` nodes gated by the existing case-active state and selected target-slot buff, so save/load and cleanup reuse the proven lifecycle without a schema bump.

**Tech Stack:** PowerShell 7 modules/tests, CaseKit schema-v2 JSON, KCD2 Skald/Haste XML, Lua lifecycle, KCD2 localization XML.

---

### Task 1: Add the authored story-identity contract

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\casekit\core\CaseKit.Authoring.psm1`
- Modify: `H:\KCD2Mod\DarkPassenger\casekit\tests\fixtures\authoring\v2\stories\composed-case-probe\case.json`
- Test: `H:\KCD2Mod\DarkPassenger\casekit\tests\Test-CaseBuilderContracts.ps1`

**Step 1: Write the failing contract tests**

Add a valid identity fixture shaped as:

```json
"storyIdentities": [
  {
    "id": "culprit",
    "bindingSlot": "target",
    "revealFact": "culprit_identified",
    "localized": {
      "ru": {"name": "Микулаш", "displayTemplate": "{{occupation}} Микулаш"},
      "en": {"name": "Mikulas", "displayTemplate": "Mikulas, {{occupation}}"}
    }
  }
]
```

Assert rejection of duplicate IDs/slots, missing RU or EN values, unknown binding slots, unknown reveal facts and a reveal fact without `hardIdentity: true`.

**Step 2: Run the focused test and prove RED**

Run:

```powershell
pwsh -NoProfile -File H:\KCD2Mod\DarkPassenger\casekit\tests\Test-CaseBuilderContracts.ps1
```

Expected: new story-identity assertions fail while the existing suite still loads.

**Step 3: Implement minimal normalization and validation**

Normalize `storyIdentities` into the authored deck without inventing defaults for name, reveal fact or localization. Preserve the existing `named/titled/anonymous` world identity unchanged; story identity is a separate overlay.

**Step 4: Run focused test and prove GREEN**

Run the command from Step 2. Expected: all checks pass.

**Step 5: Commit**

```powershell
git add -- casekit/core/CaseKit.Authoring.psm1 casekit/tests/Test-CaseBuilderContracts.ps1 casekit/tests/fixtures/authoring/v2/stories/composed-case-probe/case.json
git commit -m "feat: add authored story identity contract"
```

### Task 2: Enforce investigation-time name visibility

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\casekit\core\CaseKit.Authoring.psm1`
- Modify: `H:\KCD2Mod\DarkPassenger\casekit\core\CaseKit.Templates.psm1`
- Test: `H:\KCD2Mod\DarkPassenger\casekit\tests\Test-CaseBuilderContracts.ps1`

**Step 1: Write failing reveal-gate tests**

Use `{{target.storyName}}` in one localization asset reachable before `culprit_identified`; assert the deck is rejected. Gate the owning step/presentation with `requiresFacts` or `when.allKnown: ["culprit_identified"]`; assert it is accepted. Cover dialogue turns, journal assets and objective/state assets.

**Step 2: Run focused test and prove RED**

Run `Test-CaseBuilderContracts.ps1`. Expected: the pre-reveal reference is currently accepted.

**Step 3: Implement conservative reachability validation**

For every content asset that references `<bindingSlot>.storyName`, require its owning step or presentation to guarantee the configured hard identity fact. Treat uncertain reachability as pre-reveal and fail with the asset key, identity ID and missing fact.

**Step 4: Run focused test and prove GREEN**

Run `Test-CaseBuilderContracts.ps1`. Expected: unsafe asset rejected, gated asset accepted.

**Step 5: Commit**

```powershell
git add -- casekit/core/CaseKit.Authoring.psm1 casekit/core/CaseKit.Templates.psm1 casekit/tests/Test-CaseBuilderContracts.ps1
git commit -m "feat: gate story names behind identity facts"
```

### Task 3: Resolve localized overlay labels for physical actors

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\casekit\core\CaseKit.Identity.psm1`
- Modify: `H:\KCD2Mod\DarkPassenger\casekit\core\CaseKit.Compatibility.psm1`
- Test: `H:\KCD2Mod\DarkPassenger\casekit\tests\Test-IdentityResolver.ps1`
- Test: `H:\KCD2Mod\DarkPassenger\casekit\tests\Test-CompatibilitySolver.ps1`

**Step 1: Write failing pure-logic tests**

Assert:

```text
anonymous occupation=батрак + name=Микулаш -> Батрак Микулаш
named vanilla=Лаврентий + occupation=корчмарь + name=Микулаш -> Корчмарь Микулаш
unresolved occupation='' + name=Микулаш -> Микулаш
```

Also assert the original entity identity and engine identifiers remain byte-equivalent after resolution.

**Step 2: Run focused tests and prove RED**

```powershell
pwsh -NoProfile -File H:\KCD2Mod\DarkPassenger\casekit\tests\Test-IdentityResolver.ps1
pwsh -NoProfile -File H:\KCD2Mod\DarkPassenger\casekit\tests\Test-CompatibilitySolver.ps1
```

**Step 3: Implement `Resolve-CaseKitStoryIdentity`**

Render each language's authored `displayTemplate` using the selected actor's verified semantic occupation. If occupation is absent, return the authored name alone. Attach the result to the finite variant binding as `storyIdentity`; do not overwrite `identity`, `identityMode`, `entityName`, `entityGuid`, `soulGuid` or voice metadata.

**Step 4: Run focused tests and prove GREEN**

Run both commands from Step 2.

**Step 5: Commit**

```powershell
git add -- casekit/core/CaseKit.Identity.psm1 casekit/core/CaseKit.Compatibility.psm1 casekit/tests/Test-IdentityResolver.ps1 casekit/tests/Test-CompatibilitySolver.ps1
git commit -m "feat: resolve story identity overlays"
```

### Task 4: Materialize deterministic identity-overlay definitions

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\casekit\adapters\kcd2\CaseKit.Kcd2Materializer.psm1`
- Modify: `H:\KCD2Mod\DarkPassenger\casekit\adapters\kcd2\CaseKit.Kcd2Backend.psm1`
- Test: `H:\KCD2Mod\DarkPassenger\casekit\tests\Test-Kcd2Materializer.ps1`
- Test: `H:\KCD2Mod\DarkPassenger\casekit\tests\Test-Kcd2BackendAdapter.ps1`

**Step 1: Write failing adapter tests**

Assert that every native-ready variant with a story identity emits exactly one overlay containing:

```text
storyId, identityId, bindingSlot, targetSlot, soulGuid,
localized.ru.displayLabel, localized.en.displayLabel,
deterministic localization key
```

Assert two physical actors share the authored personal name but may have different role-bearing display labels. Rebuild twice and compare exact JSON bytes.

**Step 2: Run focused tests and prove RED**

```powershell
pwsh -NoProfile -File H:\KCD2Mod\DarkPassenger\casekit\tests\Test-Kcd2Materializer.ps1
pwsh -NoProfile -File H:\KCD2Mod\DarkPassenger\casekit\tests\Test-Kcd2BackendAdapter.ps1
```

**Step 3: Implement the materializer/backend bridge**

Add `identityOverlays` to compiled definitions and backend CaseSpec input. Derive keys only from stable story/identity/variant data; do not allocate new save codes or GUIDs.

**Step 4: Run focused tests and prove GREEN**

Run both commands from Step 2.

**Step 5: Commit**

```powershell
git add -- casekit/adapters/kcd2/CaseKit.Kcd2Materializer.psm1 casekit/adapters/kcd2/CaseKit.Kcd2Backend.psm1 casekit/tests/Test-Kcd2Materializer.ps1 casekit/tests/Test-Kcd2BackendAdapter.ps1
git commit -m "feat: materialize KCD2 identity overlays"
```

### Task 5: Generate native `SoulUiNameOverride` nodes and localization

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\tools\CaseSpecCompiler.psm1`
- Modify: `H:\KCD2Mod\DarkPassenger\tools\Compile-CaseSpecs.ps1`
- Create: `H:\KCD2Mod\DarkPassenger\tests\Test-StoryIdentityOverlayCompiler.ps1`
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-CaseKitRegionalBundleIntegration.ps1`

**Step 1: Write the failing cross-boundary test**

Compile a fixture with anonymous and named candidate variants. Parse the real emitted regional quest XML and localization XML. Require one node per story/candidate:

```xml
<And Name="case...IdentityActive">
  <Edge From="case...Active.State" To="A" />
  <Edge From="targetSlot...TagState.State" To="B" />
</And>
<SoulUiNameOverride Name="case...IdentityOverride">
  <Asset Name="Soul" Alias="targetSlot..." />
  <Constant Name="Name" Value="dp_case_..._identity_..." />
  <Edge From="case...IdentityActive.bool" To="IsActive" />
</SoulUiNameOverride>
```

Assert each `Name` key exists exactly once in Russian and English localization and targets the expected Soul alias. Assert graph XML never mutates entity/Soul IDs.

**Step 2: Run the integration test and prove RED**

```powershell
pwsh -NoProfile -File H:\KCD2Mod\DarkPassenger\tests\Test-StoryIdentityOverlayCompiler.ps1
```

**Step 3: Implement native emission**

Reuse existing `targetSlotNNN` SoulAsset aliases, target-slot tag states and case-active state. Emit no new Lua state, buff, signal tag or save variable. Add localized overlay rows through the existing merged localization pipeline.

**Step 4: Run compiler and regional suites**

```powershell
pwsh -NoProfile -File H:\KCD2Mod\DarkPassenger\tests\Test-StoryIdentityOverlayCompiler.ps1
pwsh -NoProfile -File H:\KCD2Mod\DarkPassenger\tests\Test-CaseKitRegionalBundleIntegration.ps1
```

Expected: both suites pass and generated XML/localization joins are complete.

**Step 5: Commit**

```powershell
git add -- tools/CaseSpecCompiler.psm1 tools/Compile-CaseSpecs.ps1 tests/Test-StoryIdentityOverlayCompiler.ps1 tests/Test-CaseKitRegionalBundleIntegration.ps1
git commit -m "feat: generate native NPC identity overrides"
```

### Task 6: Prove lifecycle cleanup and save restoration

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-CaseLifecycleRuntime.ps1`
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-CaseContentMigration.ps1`
- Modify only if a failing test proves necessary: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpcasecontent.lua`
- Modify only if a failing test proves necessary: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpcaselifecycle.lua`

**Step 1: Add lifecycle assertions**

Prove existing lifecycle ordering persists the chosen variant before the target buff is applied, restores the same variant/buff after load, and removes the target buff on normal close, rollback and stale-generation recovery.

**Step 2: Run and prove current behavior**

```powershell
pwsh -NoProfile -File H:\KCD2Mod\DarkPassenger\tests\Test-CaseLifecycleRuntime.ps1
pwsh -NoProfile -File H:\KCD2Mod\DarkPassenger\tests\Test-CaseContentMigration.ps1
```

If already GREEN, make no Lua change. If RED, implement only the missing idempotent repair/cleanup branch, then rerun.

**Step 3: Commit only if files changed**

```powershell
git add -- tests/Test-CaseLifecycleRuntime.ps1 tests/Test-CaseContentMigration.ps1 src/Data/Scripts/mods/dpcasecontent.lua src/Data/Scripts/mods/dpcaselifecycle.lua
git commit -m "test: cover identity overlay lifecycle"
```

### Task 7: Build, inspect and perform a removable retail canary

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\tools\Build-Mod.ps1`
- Test: `H:\KCD2Mod\DarkPassenger\tests\Test-StoryIdentityOverlayCompiler.ps1`
- Temporary test input: use a fixture/dev-only canary excluded from the final shipping deck

**Step 1: Add clean-build artifact assertions**

Require the packaged quest PAK and RU/EN localization PAKs to contain every compiled overlay and no orphan keys.

**Step 2: Run relevant suites and clean build**

```powershell
pwsh -NoProfile -File H:\KCD2Mod\DarkPassenger\tests\Test-CaseBuilderContracts.ps1
pwsh -NoProfile -File H:\KCD2Mod\DarkPassenger\casekit\tests\Test-IdentityResolver.ps1
pwsh -NoProfile -File H:\KCD2Mod\DarkPassenger\casekit\tests\Test-CompatibilitySolver.ps1
pwsh -NoProfile -File H:\KCD2Mod\DarkPassenger\tests\Test-StoryIdentityOverlayCompiler.ps1
pwsh -NoProfile -File H:\KCD2Mod\DarkPassenger\tests\Test-CaseKitRegionalBundleIntegration.ps1
pwsh -NoProfile -File H:\KCD2Mod\DarkPassenger\tools\Build-Mod.ps1
```

Expected: all focused suites green; build archive tests pass.

**Step 3: Install only after static proof**

Install by full mod-directory replacement through the existing deployment script. Cold-start retail with `-devmode`, load the current save and start a fresh case.

**Step 4: Runtime acceptance**

Verify:

1. selected anonymous or named NPC shows the fixed story label from case start;
2. dialogue/voice/lip sync still resolve from the physical actor profile;
3. save/load preserves the same label;
4. ending/resetting the case restores the vanilla label;
5. no other NPC is renamed.

Remove the dev-only canary before the final clean build. The first permanent consumer should be the executable Love Triangle StoryPack.

**Step 5: Final verification and commit**

Run `/simplify` over the feature commits, rerun the focused suites and clean build, then commit any verified simplification separately.

## Unresolved questions

- Final localized culprit name for the Love Triangle StoryPack.
- Whether non-target story roles also receive overlays in the first slice or only `target`.

