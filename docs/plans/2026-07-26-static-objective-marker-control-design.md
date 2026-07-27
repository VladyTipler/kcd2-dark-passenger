# Static Objective Marker Control Design

## Goal

Prove whether a vanilla-style objective with a static `SoulAsset` can display a
map/compass marker in the standalone Dark Passenger quest.

## Scope

This is a diagnostic build, not the final victim-selection architecture.
`kpri_man_23` (`PritokySoul28`) is the fixed control target. Regions and NPCs
must not become permanent hand-maintained lists.

## Flow

1. Start the hunt quest and activate the existing search objective.
2. After the target-selection delay, complete the search objective.
3. Activate a new tracked objective: `Настигнуть избранную жертву`.
4. Enable `ShowMapMarker` with static alias `PritokySoul28`.
5. Enable a static `SoulDeathTrigger` for the same alias.
6. On death, complete the target objective and quest, then grant satisfaction.

## Interpretation

- Marker appears: objective/marker plumbing works; continue research on the
  runtime Lua-to-quest entity bridge.
- Marker does not appear: the standalone quest registration or marker
  configuration is incomplete; dynamic selection is not the current blocker.

## Future Architecture

Store only region definitions (id, center/radius, eligibility rules). Lua
selects candidates dynamically. A verified runtime bridge supplies the chosen
entity to the precise target objective. No permanent per-NPC quest branches.
