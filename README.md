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
multi-area search districts for all supported settlements in both regions.

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

See `docs/plans/2026-07-31-kcd2-quest-sdk-design.md`.

## Repository layout

- `src` — authored KCD2 Lua/XML mod sources;
- `localization` — authored English and Russian localization;
- `config` — victim policy plus generated settlement-area selection manifest;
- `tools` — extraction, generation, build, and deployment scripts;
- `tests` — structural verification;
- `docs` — designs, plans, and reference notes;
- `build`, `dist`, `evidence` — generated or local-only data ignored by Git.

The game `Mods` directories are deployment targets, never source directories.
Reference mods and extracted game data are intentionally excluded.

Investigation stories are authored as bilingual CaseSpec JSON under
`content/cases`. Settlement-specific entity and container IDs live separately
in `config/case-settlement-bindings.json`. `Compile-CaseSpecs.ps1` validates
both sources and emits the runtime Lua catalog plus a compatibility report;
generated artifacts are never edited by hand.

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
pwsh -NoProfile -File '.\tools\Build-Mod.ps1'
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
