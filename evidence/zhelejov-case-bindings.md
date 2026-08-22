# Zhelejov Case Bindings

Verified against the current Trosky world export and native soul registry.
These identifiers are authored settlement bindings, not inferred runtime
fallbacks.

## Semantic roles

| Role | Binding | Evidence |
| --- | --- | --- |
| innkeeper | `tzel_vavrinec` | `char_HOSPODSKY_VAVRINEC_TICHOTA`; faction `trosecko_settlements_zelejov_commonFolk_tavern_staff`; layer `Main/tzel_zelejov/inn/_script/npc/vavrinec` |
| witness | `tzel_bretislav` | `char_PACHOLEK_BRETISLAV`; faction `trosecko_settlements_zelejov_commonFolk_tavern_staff`; layer `Main/tzel_zelejov/inn/_script/npc/bretislav` |
| document container | `aaf89994-e94b-0309` | `Stash` at `1657.628,2145.149,38.70087`; layer `Main/tzel_zelejov/inn/_common`; locked, difficulty `0.5` |
| document item | `d5833fd4-f7bf-4957-86f5-d661db38bcf3` | mod-owned stable item GUID allocated for the forged guest-ledger note |

## Sources

- `H:\KCD2Mod\_reference-mods\_extracted\AssetLinker\InternalData\trosecko\tros_objects_mission0.xml`
- `H:\SteamLibrary\steamapps\common\KCD2Mod\Data\Libs\CryHttp\xzar2\table-souls.json`
- `config/victim-candidates.json`

## Policy

Named inn staff such as `tzel_bretislav` are already outside the generated
victim pool. The enabled Zhelejov pool remains unchanged and contains generic,
killable, living, non-main-story male residents. This avoids renumbering stable
candidate slots and preserves save compatibility.
