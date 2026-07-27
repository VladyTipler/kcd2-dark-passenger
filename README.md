# Dark Passenger

Dark Passenger is a gameplay mod for Kingdom Come: Deliverance II inspired by
the idea of a controlled, recurring hunger for guilty victims.

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

## Current status

The retail-confirmed core supports persistent hunger, nearest-settlement victim
selection in both regions, native quest objectives and markers, and automatic
post-target-death satisfaction reset.
