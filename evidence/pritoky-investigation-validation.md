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

## Live integration

Pending dev validation.
