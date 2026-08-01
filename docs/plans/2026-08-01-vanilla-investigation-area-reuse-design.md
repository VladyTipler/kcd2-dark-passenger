# Vanilla Investigation Area Reuse Design

## Goal

Restore a stable quest search area by binding `DP_PritokySearchArea` to a
collection of compiled vanilla `TriggerArea` entities instead of shipping an
incomplete custom runtime layer.

## Evidence

- Two cold starts with the custom runtime layer crashed at the same load boundary.
- With the custom `leveldata.xml` and `whdata_1` registration removed, the same
  build reached `LEVEL_LOAD_COMPLETE` and stayed alive.
- Vanilla `TriggerArea` XML carries identity, links, and properties, while its
  polygon is compiled into `areasmission0.bai`.
- Vanilla quest `uchazec` proves that one `TriggerAreaAsset` and one objective
  marker alias can resolve to multiple simultaneous `TriggerArea` links.
- All three selected Pritoky areas resolve in the live dev build without their
  source quests being active:
  - village: GUID `d0fa0ece-6af5-19f6`, entity ID `17080`;
  - inn: GUID `d2fc29a3-6787-141c`, entity ID `14696`;
  - deserter camp: GUID `1b6b6d4e-905c-4f9e`, entity ID `4803`.

## Design

The Kuttenberg quest holder keeps one alias, `DP_PritokySearchArea`. Static
`waitinglinks.xml` and the mission-object patch bind that alias three times to
the village, inn, and deserter-camp areas. Lua treats the targets as a
collection and repairs any missing runtime link individually.

The objective therefore remains one journal row while the map renders the
union as several irregular search patches. Static candidate positions confirm
that all 37 currently enabled Pritoky candidates fall inside at least one of
the three selected polygons.

The active build packages only merged `objects_mission0.xml` and
`waitinglinks.xml` for this link. It does not package a custom runtime layer,
editor layer, `leveldata.xml`, or `whdata_1`. The existing geometry generator
stays in the repository as research groundwork for a later supported pipeline:
generated `.lyr` -> official compiler/editor -> `areasmission0.bai`.

The later settlement-wide generator should select only loaded vanilla areas
that contain eligible settlement candidates, then exclude candidates outside
the resulting union. Pritoky needs no exclusion because the three-area union
covers its current pool completely.

## Verification

Automated tests prove all three same-alias GUID links, absence of custom
layer/profile artifacts, minimal level PAK contents, and dev overlay scope.
Live proof is one cold dev start plus the existing quest restart scenario
showing all applicable irregular vanilla patches without a crash.
