# Regional victim marker

## Goal

On hunt activation, select one random NPC from a compact settlement pool, mark
that Soul, show a moving map/compass marker, and complete the quest plus grant
`Тишина внутри` when the target dies.

This build is a technical vertical slice. Investigation areas, evidence,
rumors, and confidence remain out of scope.

## Implemented test scope

- Region: Pritoky, Kutnohorsko.
- Pool: 42 placed male human Souls from `soul__kpri.xml`.
- Guards, merchants, named NPCs, and quest-important NPCs are currently allowed.
- Any death of the selected target counts.

## Runtime flow

1. Existing delayed hunger lifecycle activates the quest.
2. `RandomIntegerRange(1, 42)` is persisted in `selectedVictimIndex`.
3. A typed Skald `Switch` maps the index to one static regional Soul alias.
4. The chosen Soul receives hidden buff `dp_is_target` / AI tag `24`.
5. `BuffTagTrigger` starts a `ForEach` over only `PritokySouls`.
6. `BuffTagCheck` resolves the tagged member back to `selectedVictim`.
7. `ShowMapMarker(PoiTipster)` and `SoulDeathTrigger` consume that runtime Soul.
8. Target death completes the objective and adds the satisfaction buff.
9. Objective completion removes the hidden target tag and marker.

## Why the static regional pool

Standalone quest projects have no generated AssetLinker binding for
`SmartAreaAsset` or `player_scheduler`. Soul assets are different: their
database `soul_id` can be declared directly through `SharedSoulGuids`.

This keeps the runtime scan regional and bounded while avoiding an unverified
Lua return channel. More settlements can be added as separate Soul pools and
selected with a first-stage region state.

## Runtime unknowns to verify

- Whether pointer state `wh::rpgmodule::I_Soul*` loads in retail Skald.
- Whether `ShowMapMarker` follows the selected moving Soul.
- Whether `PoiTipster` gives the desired compass presentation.
- Behavior when the randomly selected Soul is already dead or unavailable.
- Which Souls should be excluded as essential or narratively protected.

