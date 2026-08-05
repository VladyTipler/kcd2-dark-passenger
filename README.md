# Dark Passenger

> Darkness has rules. The first is simple: do not get caught.

Dark Passenger is a gameplay mod for Kingdom Come: Deliverance II inspired by
Dexter. Henry carries a hunger that cannot be silenced forever. To keep it
under control, he must follow the Code: investigate the guilty, choose those
who deserve his blade, and leave no witnesses who can reveal what he truly is.

Every hunt is a new Case. Hunger grows with in-game time, evidence leads to a
victim, and the method is yours—poison, arrows, stealth, or open combat. What
matters is not how the sentence is carried out, but whether Henry gets caught.

## Current status

The retail-confirmed core supports persistent hunger, nearest-settlement victim
selection in both regions, native quest objectives and markers, and automatic
post-target-death satisfaction reset. The dev-confirmed aftermath layer tracks
witness outcomes and adds global hold-to-bury corpse disposal with native
SkipTime presentation. The investigation pipeline generates settlement-sized
multi-area search districts for all supported settlements in both regions. A
declarative CaseSpec compiler now emits the Lua, quest dialogue, Storm-role,
script-context, item-table, and bilingual localization artifacts used by the
same universal quest container. Its first Trosky story, **Missing Traveler**,
is structurally verified and live-validated in Zhelejov. CaseKit also
emits a finite runtime variant catalog: one compatible variant and all concrete
bindings are persisted before presentation, then restored without reroll.
Each compiled variant also owns an exact cleanup manifest. A single runtime
lifecycle clears only generation-scoped presentation and evidence, preserves
permanent trophies and replay history, then republishes the journal after the
native quest graph is active.

## Roadmap

### Phase 1 — Core loop

- [x] Persistent hidden hunger driven by in-game time
- [x] Progressive satisfaction buffs and hunger penalties
- [x] Automatic recurring Case quest
- [x] Nearest-settlement victim selection in Kuttenberg and Trosky
- [x] Native journal objective and quest marker on the selected NPC
- [x] Target death completes the Case and resets hunger
- [x] Any player-caused human kill caps hunger at 50 without completing the Case

### Phase 2 — The first rule: do not get caught

- [x] Add a 90-second silence check after the target dies
- [x] Enter cleanup when witnesses, suspicion, or an alarm appear
- [x] Allow unreported witnesses to be removed before leaving the area
- [x] Grade hunts as clean, controlled, or noisy without restricting kill method
- [x] Extend satisfaction after cleaner hunts
- [x] Persist settlement attention and the long-term blood trail
- [x] Bury suitable human bodies with a shovel and native SkipTime

### Phase 3 — Investigation

- [x] Reveal a search area before revealing the target
- [ ] Generate coherent clues, rumors, letters, and witness accounts
- [x] Track hidden confidence while the player investigates
- [x] Reveal the personal marker only after sufficient evidence
- [ ] Add multiple investigation archetypes and complications
- [x] Compile authored CaseSpec data into the universal quest container
- [x] Persist one compiled CaseVariant and materialize its scenes idempotently
- [x] Clear generation-scoped Case artifacts from compiler-owned manifests
- [x] Place one shared-class, weightless quest trophy on every target corpse
- [x] Block target burial until the current trophy is collected
- [x] Live-validate the generated Missing Traveler case in Zhelejov
- [ ] Prevent quest presentation when no living `native_ready` variant exists;
      fall back to another compatible StoryPack or keep the cycle dormant

### Phase 4 — A world that notices

- [ ] React to discovered bodies and repeated deaths
- [ ] Add settlement rumors, fear, and increased scrutiny
- [ ] Turn the blood trail into regional legends and escalating complications
- [ ] Spawn a persistent custom Nemesis who investigates the pattern

### Phase 5 — Content and release

- [ ] Expand authored targets, clues, and Case variations
- [ ] Balance hunger timing, rewards, and consequences
- [ ] Complete English and Russian localization
- [ ] Package public test builds and collect feedback
- [ ] Prepare Nexus Mods and Steam Workshop releases

### Future developer tooling — KCD2 Quest SDK

- [ ] Extract the proven Lua↔quest bridges into a developer-first QuestKit
- [ ] Compile a declarative `.quest.lua` spec into native XML, localization and signals
- [ ] Provide save-safe events, objectives, markers, diagnostics and packaging
- [ ] Prove the framework on Dark Passenger and a second independent quest

### Engineering cleanup before public release

- [ ] Inventory `H:\KCD2Mod`, the source repository, deployed mods, generated output, backups and extracted references
- [ ] Classify every non-source artifact as keep, archive, reproducible-generated or remove
- [ ] Separate opt-in debug tooling from production assets and remove automatic test/probe triggers
- [ ] Add a build gate that rejects hardcoded test actors, proximity auto-starts and other probe-only wiring in production packages
- [ ] Remove approved obsolete artifacts only after reviewing the cleanup manifest; retain the bridge and useful diagnostics

See `docs/plans/2026-07-31-kcd2-quest-sdk-design.md`.

## Repository layout

- `src` — authored KCD2 Lua/XML mod sources;
- `localization` — authored base English and Russian localization;
- `content/archetypes`, `content/evidence-modules`, `content/stories` — reusable
  investigation grammar and bilingual StoryPacks;
- `config/settlements` — reviewed semantic world bindings and localized actor
  identities;
- `config/casekit-stable-ids.json` — save-sensitive case/evidence identity;
- `config/casekit-kcd2-native.json` — KCD2 presentation adapter metadata;
- `evidence/*-case-bindings.md` — reviewed native entity/container bindings;
- `tools` — extraction, generation, build, and deployment scripts;
- `tests` — structural verification;
- `docs` — designs, plans, and reference notes;
- `build`, `dist`, and raw evidence — generated or local-only data ignored by
  Git.

The game `Mods` directories are deployment targets, never source directories.
Reference mods and extracted game data are intentionally excluded.

Investigation stories are authored as schema-v2 StoryPack packages under
`content/stories`. Reusable mechanics live in archetypes and EvidenceModules;
reviewed entity/container IDs live only in settlement profiles. CaseKit
validates and resolves finite settlement-compatible variants, then the KCD2
adapter feeds the proven native compiler. It emits the runtime Lua catalog,
dialogue XML, Storm roles, script contexts, item rows, bilingual localization,
compatibility manifests, and the finite CaseVariant catalog. At runtime the
nearest supported settlement and live candidate pool select one `native_ready`
variant. Its stable identity and bindings are saved before the quest, marker or
evidence presentation begins. The quest shell must not activate until that
selection succeeds; the currently exposed exhausted-pool edge case is tracked
in the roadmap. Generated artifacts are never edited by hand.

### CaseKit workflow

1. Write canonical truth, threads, dialogues, documents and RU/EN assets in
   `content/stories/<story-id>/`.
2. Reuse or extend `content/archetypes` and `content/evidence-modules`.
3. Put reviewed world IDs and actor identities in `config/settlements`.
4. Register numeric case/evidence codes in `config/casekit-stable-ids.json`;
   they are save schema.
5. Run the CaseKit contract, compatibility, adapter and parity tests.
6. Build the mod with an explicit dev-game root; packaging consumes
   `build/generated/localization`, not the
   authored base localization directly.
7. Test a new case on a disposable save in its target settlement. Do not reuse
   an already serialized quest instance as proof of cold-start behavior.

One quest graph remains the lifecycle owner per region. StoryPacks add stories
as data; they do not create a separate quest project for every story. Archived
legacy CaseSpecs under `content/migration` are parity fixtures, not production
inputs.

StoryPacks classify every physical item as `quest` or `loot` and declare whether
it lasts for one case or permanently. Quest items are created by the live XML
graph through `AddQuestItem`, with `StartingLocation` and `BackupLocation`
pointing to the generated linked stash. Lua chooses the case and raises one
request signal per unique item class; the compiler must preserve the authored
item metadata in the runtime catalog. The authoritative quest-item catalog
prevents registered quest classes from falling through to manual `CreateItem`.

The semantic `bird-feather` trophy preset resolves to one shared, stable,
non-divisible, zero-weight loot class named `Trophy - Bloodied Feather` /
`Трофей - Окровавленное перо`. The runtime places one new instance on each
selected target corpse and reconciles `pending -> placed -> collected` across
save/load, Lua reload and entity streaming without confusing previously
collected feathers with the current case. The selected corpse cannot be buried
until that generation's feather has been collected; missing target identity
fails closed and is recovered from the immutable CaseSnapshot.

## Local build

```powershell
$env:KCD2_DEV_ROOT = 'D:\path\to\KCD2Mod'
$env:KCD2_REFERENCE_DATA_ROOT = 'D:\path\to\AssetLinker\InternalData'
pwsh -NoProfile -File '.\tests\Test-SettlementInvestigationAreas.ps1' `
  -ReferenceDataRoot $env:KCD2_REFERENCE_DATA_ROOT `
  -DevGameRoot $env:KCD2_DEV_ROOT
pwsh -NoProfile -File '.\tests\Test-CaseSpecCompiler.ps1'
pwsh -NoProfile -File '.\tests\Test-CaseSpecGeneration.ps1' `
  -DevGameRoot $env:KCD2_DEV_ROOT
pwsh -NoProfile -File '.\tests\Test-ZhelejovBindings.ps1'
pwsh -NoProfile -File '.\tests\Test-MissingTravelerCase.ps1'
pwsh -NoProfile -File '.\tests\Test-MissingTravelerGeneration.ps1' `
  -DevGameRoot $env:KCD2_DEV_ROOT
pwsh -NoProfile -File '.\tools\Build-Mod.ps1' `
  -DevGameRoot $env:KCD2_DEV_ROOT
pwsh -NoProfile -File '.\tests\Test-DarkPassengerSatisfaction.ps1' `
  -ReferenceDataRoot $env:KCD2_REFERENCE_DATA_ROOT `
  -DevGameRoot $env:KCD2_DEV_ROOT
pwsh -NoProfile -File '.\tests\Test-DevLevelOverlay.ps1'
pwsh -NoProfile -File '.\tests\Test-InvestigationAreaGeometry.ps1'
```

The normalized vanilla TriggerArea inventory under `build/generated` is a
build-time input, not a runtime dependency. Regenerate it only when the game
registries, settlement coverage, or area policy changes. The committed
settlement manifest then generates quest states, both regional world bindings,
and `dp_investigation_area_catalog.lua`; Node/.NET is never required by the
running game. `Test-SettlementInvestigationAreas.ps1` creates the ignored
inventory on its first run and validates the committed manifest thereafter.

The first local generation uses the KCD2 dev data and separately installed
AssetLinker reference. Those external files are prerequisites, not repository
content.

## Dev deployment

Close the game before deploying. The deployer validates and stages both
regional registries, stores one rollback-safe backup, installs exactly
`objects_mission0.xml` and `waitinglinks.xml` per region, and removes only the
two obsolete custom Pritoky layer artifacts.

```powershell
pwsh -NoProfile -File '.\tools\Deploy-DevLevelOverlay.ps1' `
  -DevGameRoot $env:KCD2_DEV_ROOT
```

## Dependencies and references

- Kingdom Come: Deliverance II and its official modding tools;
- PlayerEventDispatcher as the runtime event dependency;
- Temptation as a quest/Lua bridge reference;
- Mercenaries (Steam Workshop item `3689921142`) as a future NPC-spawning
  reference for the Nemesis system.

No third-party mod files or extracted game archives are included.

## License

No licence is currently granted. All rights are reserved by the repository
owner unless stated otherwise.
