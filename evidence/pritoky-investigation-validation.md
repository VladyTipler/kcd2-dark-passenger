# Pritoky Investigation Validation

## Baseline - 2026-07-31

- Branch: `feature/aftermath`
- Commit: `26f80b7ac44b509a359bd1b46bdc2418f9cfd1d4`
- Generated candidates: 819 Kuttenberg, 140 Trosky, 959 total
- Structural/build suite: `RESULT: PASS (687 checks)`

### Packaged artifact SHA-256

| Artifact | SHA-256 |
|---|---|
| `Data\darkpassengertest.pak` | `A2515944C72261F6FF08D7FF61D3F4585806C323E8A6CA0ABD303975414A0375` |
| `Localization\English_xml.pak` | `4A85B079D52898E9D746CFCD03215F6A0E7010A31C3E4CF4D47FC601EFC5A761` |
| `Localization\Russian_xml.pak` | `31EC84FE38E8F4088AAF8E1B42B1AD64D10DDE0A5B0ED89D90E31F3D652A61CB` |

## TriggerArea / AssetLinker proof

- Existing Pritoky area: `kpri_publicEnemiesRepulsionZoneVillageArea_1`
- Existing `TriggerArea` target: entity id `17080`, guid `d0fa0ece-6af5-19f6`
- Area position: `2298.979,1694.99,101.3639`; scale `6.673498`
- Quest alias: `DP_PritokySearchArea`
- Mod-owned holder: `dark_within_k`, guid `9da1237b-bbc0-49f5`
- Mod-owned layer: `darkpassengertest_pritoky_area_797243b2-16ed-4fcd-afe4-4987b6c55416`
- Binding uses both a direct entity link and a streaming-safe waiting link.
- Authored identifiers above were generated for this mod; they were not exported by Sandbox Editor.
- Structural validation: `RESULT: PASS (694 checks)`.
- Level pak SHA-256: `6C969E45374F64F0422A536FF50127F08CD81FA4163A878A625F5B50DE825F6E`
- Structural validation proves the quest declaration, layer binding, package paths and archive integrity.
- Runtime marker resolution remains pending live validation.

## Investigation slice static validation - 2026-07-31

- Commit: `4469e23fedbf3396f23e3f4122bbb24007c8b1a7`
- Generated candidates: 819 Kuttenberg, 140 Trosky, 959 total
- `dpinvestigation.lua`: parsed by the KCD2 Lua compiler
- `darkpassengertest.lua`: parsed by the KCD2 Lua compiler
- Full build: passed
- Structural/build suite: `RESULT: PASS (843 checks)`
- `git diff --check 6a33836..HEAD`: passed
- Simplification review found no safe behavior-preserving cleanup in the feature diff.

### Current packaged artifact SHA-256

| Artifact | SHA-256 |
|---|---|
| `Data\darkpassengertest.pak` | `195FBF84E913FA2BD77B1E9E0F33D43D7258818533D2AE7753D96952A6EBCEAE` |
| `Data\Levels\kutnohorsko\darkpassengertest.pak` | `13A852B361D7A7CAD9E6C883E350C11A26A8760D7D632A7AE2DE7A91A1238D6F` |
| `Localization\English_xml.pak` | `FEF98176D7E62C9641A865272EE7B0943C0E810CA47C16E08EB23BE2772C121C` |
| `Localization\Russian_xml.pak` | `F4987AB0DB5F6F3C80400F6A987A27485DAB577A57666C12187B9923F1A4270E` |

## Live integration

- Dev target: `H:\SteamLibrary\steamapps\common\KCD2Mod\Mods\b_DarkPassengerTest`
- Pre-deployment backup: `H:\KCD2Mod\_deployment-backups\DarkPassenger\dev-20260731-014955`
- Deployment comparison: 29 source files, 29 target files, no extras, all SHA-256 hashes equal.
- Post-deployment structural/build suite: `RESULT: PASS (843 checks)`.
- Runtime validation remains pending.

## Waiting-links live correction - 2026-07-31

- The first deployed two-link `waitinglinks.xml` failed live validation.
- `dark_within_k` loaded as `SmartObjectHolder`, but `CountLinks()` returned `0`.
- The Kuttenberg `LevelHolder` had `342` links and no `module` link to the custom holder.
- The base `level.pak` also contains exactly `342` links sourced from the Kuttenberg holder and no reference to the custom holder.
- The quest restore added one `unable to resolve marker:'DP_PritokySearchArea'` error.
- Root cause evidence: the engine resolved the vanilla `waitinglinks.xml`; the small mod-owned file did not merge with the same virtual path in the base level pak.
- The build now extracts the current game's full Kuttenberg `waitinglinks.xml`, appends exactly the two Dark Passenger links, preserves all vanilla links and streamable targets, and packages the merged result.
- Generated merge: `142411` waiting links, `343` Kuttenberg holder sources, `2` custom-holder references, `62160` streamable targets.
- Dev-only `user.cfg` uses `sys_PakPriority = 3` (`not-in pak mod file first`) so loose mod level data remains compatible with Lua hot reload. This setting is not shipped in the mod or retail deployment.
- Structural/build suite: `RESULT: PASS (847 checks)`.
- Repeated builds produced identical hashes for the main pak, level pak, merged waiting links and `whdata_1`.
- New main pak SHA-256: `8D0AD17B2EB6F2AE2F4627009E09EF1DB20227752E929404754EDEC7A93640A6`.
- New level pak SHA-256: `E9C77C22F36085C81DE7C98DD1718466F212AC34801A08E0AA1E497BB839D84A`.
- New merged waiting-links SHA-256: `FEAC7BE5C9B302B8F42F67B4D16972732CFCF5D61EAD391BBB610553C17EFD2F`.
- Transactional dev deployment completed at `2026-07-31 17:50:47`.
- Recoverable deployment backup: `H:\KCD2Mod\_deployment-backups\deploy-20260731-175047`.
- Deployment contains `30` Dark Passenger files and `5` Skip Time Extreme files; the previous Dark Passenger and Skip Time Fast folders are preserved in the backup.
- All four Dark Passenger source/deployment archive hashes are equal; all four Dark Passenger and both Skip Time Extreme pak files open successfully as ZIP archives.
- Deployed level pak contains the expected `24600140`-byte merged waiting-links entry with `142411` waiting links, `343` Kuttenberg holder sources, `2` custom-holder references and `62160` streamable targets.
- Post-deployment structural/build suite: `RESULT: PASS (847 checks)`; `dpinvestigation.lua` and `darkpassengertest.lua` pass the KCD2 Lua compiler parse check.
- Corrected runtime marker validation remains pending one dev launch.

## Native search-area marker live proof - 2026-08-01

- The Pritoky search area was visibly rendered in a cold dev-build quest cycle.
- The active objective uses `Marker="DP_PritokySearchArea"`; the fresh log slice
  contains `PlayAudio: quest_started` and no
  `unable to resolve marker:'DP_PritokySearchArea'` error.
- A complete runtime link chain under the standalone
  `darkpassengertest.kutnohorsko` project was not sufficient. The marker
  resolver still rejected the alias even when live diagnostics proved the
  Project, Level, Quest holder and TriggerArea links existed.
- The working quest path is `Barbora.kutnohorsko.dark_within_k`. The build
  extracts the current vanilla `Quests/Final/Barbora/kutnohorsko.xml` from the
  installed `Scripts.pak`, injects one definition and one quest node, validates
  the result as XML, and never ships the small patch descriptor itself.
- The world-side contract is:
  `kutnohorsko` LevelHolder `10702dff-9271-4a74` ->
  `dark_within_k` SmartObjectHolder `f4a73e20-28c5-4bd2` via `module` ->
  Pritoky TriggerArea `d0fa0ece-6af5-19f6` via
  `asset['DP_PritokySearchArea']`.
- `DarkPassengerAreaBridge` only repairs or verifies those live links after
  streaming; it does not create the quest namespace. A fresh load logged
  `[DarkPassengerArea] ready attempt=0`.
- Compatibility caveat: the generated regional Barbora parent is a full
  current-base merge. Another mod replacing the same virtual
  `Quests/Final/Barbora/kutnohorsko.xml` path can conflict and will eventually
  need a deterministic shared merger or Quest SDK integration layer.
- Fresh post-proof verification: `RESULT: PASS (853 checks)` and
  `RESULT: PASS (dev loose level overlay)`.

## Investigation threshold end-to-end proof - 2026-08-01

- A live Pritoky case persisted its investigation state across save/load:
  `generation=5`, `target slot=905`, `confidence=69`, `revealed=false`, and
  `revealDispatched=false` remained unchanged after loading.
- Adding one evidence point through
  `DarkPassengerInvestigation.AddEvidence(1, "live_70")` crossed the configured
  threshold exactly once.
- The runtime logged `target revealed generation=5 confidence=70` and persisted
  `revealed=true` plus `revealDispatched=true`.
- The quest completed the search-area objective, advanced to the selected-target
  objective, played the native objective sound, and visibly rendered the marker
  on the selected NPC.
- No fresh marker-resolution error appeared in the test log.
- This proves the complete investigation spine in the dev build:
  search area -> persistent hidden confidence -> threshold 70 -> quest progress
  -> native target marker.
