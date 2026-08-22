# CaseKit Evidence Placement Implementation Plan

**Goal:** Make evidence placement actor-aware and guarantee that trade storage
can never be selected as evidence storage.

**Architecture:** Add placement metadata to normalized StoryPacks, enrich the
semantic world index with shop and reviewed ownership relations, validate
cross-binding relationships in the compatibility solver, then preserve the
resolved placement through KCD2 materialization. Keep Lua deterministic and
keep the existing Missing Traveler canary on neutral `world-container` copy.

**Tech Stack:** PowerShell 7, JSON authoring, KCD2 XML/Lua materialization.

---

### Task 1: Lock the authoring contract

**Files:**
- Modify: `casekit/tests/Test-CaseBuilderContracts.ps1`
- Modify: `casekit/core/CaseKit.Authoring.psm1`
- Modify: `content/stories/missing-traveler/threads.json`

1. Add failing tests for the four placement modes, required actor/container
   references, and unknown-mode rejection.
2. Run `& 'C:\Program Files\PowerShell\7\pwsh.exe' -File
   'H:\KCD2Mod\DarkPassenger\casekit\tests\Test-CaseBuilderContracts.ps1'`.
3. Normalize placement metadata in the authoring deck.
4. Re-run the contract test.

### Task 2: Classify unsafe containers and profile relations

**Files:**
- Modify: `casekit/tests/Test-Kcd2WorldExporter.ps1`
- Modify: `casekit/tests/Test-WorldSemanticIndex.ps1`
- Modify: `tools/Export-WorldVictimCandidates.ps1`
- Modify: `casekit/adapters/kcd2/CaseKit.Kcd2World.psm1`
- Modify: `casekit/core/CaseKit.Profiles.psm1`

1. Add failing fixtures/tests proving `shopStash` becomes
   `container.shop`/`container.trade` and profile relations survive merge.
2. Export native container link metadata and shop-stash identity.
3. Add reviewed `personal-container-of` / `home-container-of` relations to the
   semantic entity representation.
4. Run both targeted tests.

### Task 3: Enforce placement during compatibility solving

**Files:**
- Modify: `casekit/tests/Test-CompatibilitySolver.ps1`
- Modify: `casekit/core/CaseKit.Compatibility.psm1`

1. Add failing cases for personal success, unrelated rejection, home success,
   and absolute shop-stash rejection.
2. Validate placement after a complete binding tuple is formed.
3. Report a precise incompatibility reason when no safe placement exists.
4. Re-run the solver tests.

### Task 4: Preserve placement across the KCD2 boundary

**Files:**
- Modify: `casekit/tests/Test-Kcd2Materializer.ps1`
- Modify: `casekit/tests/Test-Kcd2BackendAdapter.ps1`
- Modify: `casekit/adapters/kcd2/CaseKit.Kcd2Materializer.psm1`
- Modify: `casekit/adapters/kcd2/CaseKit.Kcd2Backend.psm1`

1. Add an integration test that compiles an authored evidence step and checks
   the concrete runtime actor/container destination.
2. Carry placement mode and resolved IDs through materialization/backend data.
3. Re-run both adapter tests.

### Task 5: Correct the Missing Traveler canary

**Files:**
- Modify: `content/stories/missing-traveler/threads.json`
- Modify: `content/stories/missing-traveler/localization.ru.json`
- Modify: `content/stories/missing-traveler/localization.en.json`
- Modify: related generated fixtures only through the compiler

1. Declare `world-container` explicitly.
2. Replace ownership claims with neutral upstairs-chest wording in RU/EN.
3. Compile the case deck and verify no unresolved tokens or missing native
   bindings.

### Task 6: Verify the full boundary

**Files:**
- Verify: `casekit/tests/*.ps1`
- Verify: relevant root `tests/*.ps1`

1. Run the focused tests from Tasks 1-5.
2. Run the CaseKit suite and relevant build-integration tests.
3. Build the mod once; do not force an extra game restart solely for unchanged
   live quest-item behavior.
4. Review `git diff` for accidental generated/region collisions.

## Unresolved questions

- Which exact Zhelejov chest, if any, should be manually certified as
  Lavrentiy's personal storage for a future actor-container variant?
