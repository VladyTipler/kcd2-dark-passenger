# Dark Passenger

Dark Passenger is a gameplay mod for Kingdom Come: Deliverance II inspired by
the idea of a controlled, recurring hunger for guilty victims.

## Current status

The retail-confirmed core supports persistent hunger, nearest-settlement victim
selection in both regions, native quest objectives and markers, and automatic
post-target-death satisfaction reset.

## Roadmap

### Phase 1 — Core loop

- [x] Persistent hidden hunger driven by in-game time
- [x] Progressive satisfaction buffs and hunger penalties
- [x] Automatic recurring Case quest
- [x] Nearest-settlement victim selection in Kuttenberg and Trosky
- [x] Native journal objective and quest marker on the selected NPC
- [x] Target death completes the Case and resets hunger

### Phase 2 — The first rule: do not get caught

- [ ] Add a 90-second silence check after the target dies
- [ ] Enter cleanup when witnesses, suspicion, or an alarm appear
- [ ] Allow unreported witnesses to be removed before leaving the area
- [ ] Grade hunts as clean, controlled, or noisy without restricting kill method
- [ ] Extend satisfaction after cleaner hunts
- [ ] Persist settlement attention and the long-term blood trail

### Phase 3 — Investigation

- [ ] Reveal a search area before revealing the target
- [ ] Generate coherent clues, rumors, letters, and witness accounts
- [ ] Track hidden confidence while the player investigates
- [ ] Reveal the personal marker only after sufficient evidence
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

## Repository layout

- `src` — authored KCD2 Lua/XML mod sources;
- `localization` — authored English and Russian localization;
- `config` — victim catalogue and selection policy;
- `tools` — extraction, generation, build, and deployment scripts;
- `tests` — structural verification;
- `docs` — designs, plans, and reference notes;
- `build`, `dist`, `evidence` — generated or local-only data ignored by Git.

The game `Mods` directories are deployment targets, never source directories.
Reference mods and extracted game data are intentionally excluded.

## Local build

```powershell
$env:KCD2_DEV_ROOT = 'D:\path\to\KCD2Mod'
$env:KCD2_REFERENCE_DATA_ROOT = 'D:\path\to\AssetLinker\InternalData'
pwsh -NoProfile -File '.\tools\Build-Mod.ps1'
pwsh -NoProfile -File '.\tests\Test-DarkPassengerSatisfaction.ps1'
```

The first local build regenerates ignored extraction evidence from the KCD2 dev
data and the separately installed AssetLinker reference. Those external files
are prerequisites, not repository content.

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
