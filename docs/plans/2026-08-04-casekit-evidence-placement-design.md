# CaseKit Evidence Placement Design

## Problem

CaseKit can place a native quest item into a concrete world container, but the
current binding says only `container.evidence`. That proves the technical path,
not the narrative claim. A line such as "in my chest" must resolve to that
actor's personal storage. A merchant shop stash is never valid evidence
storage: exposing evidence through the trade inventory would break both the
story and gameplay.

## Goals

- Make evidence placement intent explicit in StoryPack content.
- Reject shop/trade storage for every evidence placement mode by default.
- Distinguish a generic world chest from an actor's inventory, personal chest,
  and home-area storage.
- Fail incompatible authored variants instead of silently changing the story.
- Keep runtime placement deterministic: the compiled case contains concrete
  entity IDs; Lua does not guess ownership.

## Authoring contract

Evidence steps declare one placement policy:

| Mode | Meaning | Required binding |
|---|---|---|
| `world-container` | Any compatible non-shop container in the selected scope | container slot |
| `actor-inventory` | The bound actor's inventory | actor slot |
| `actor-container` | A container explicitly marked as personal storage of the bound actor | actor + related container |
| `actor-home-container` | A non-shop container inside the bound actor's home scope | actor + related container |

Example:

```json
{
  "placement": {
    "mode": "actor-container",
    "actor": "rumorSource"
  }
}
```

`actor-container` is the strongest narrative statement: the item is in that
person's own chest. `actor-home-container` permits a weaker phrase such as "in
their house". `world-container` must use neutral copy and must not imply
ownership.

## Container safety

World indexing marks any container reached by native shop links, including
`shopStash`, with `container.shop` and `container.trade`. These are forbidden
for evidence placement even if another heuristic also classifies the chest as
residential or nearby.

Personal ownership is never inferred from distance alone. Exact personal and
home relationships may come from proven native links or explicit settlement
profile annotations:

- `personal-container-of`
- `home-container-of`

An ambiguous chest is valid only for `world-container`. A missing relationship
makes the actor-specific variant incompatible; CaseKit must not fall back to a
generic chest while keeping actor-specific dialogue.

## Compilation and runtime

1. The world exporter records native shop-stash identity.
2. Settlement profiles add reviewed personal/home relations where native data
   is ambiguous.
3. The compatibility solver binds actors and containers, then validates the
   requested relationship and forbidden capabilities.
4. The materialized variant carries the selected placement mode and concrete
   actor/container IDs.
5. The KCD2 runtime places the item only at the compiled destination.

The current Missing Traveler canary remains `world-container`. Its dialogue is
made neutral: Lavrentiy hid the ledger in one of the upstairs chests, not in
"his chest". This preserves the already-proven live quest-item path without
making a false ownership claim.

## Verification

- Unit: shop-stash links produce `container.shop` / `container.trade`.
- Unit: actor-container accepts an explicit personal relation.
- Unit: actor-container rejects a shop stash and an unrelated chest.
- Unit: actor-home-container accepts only an explicit home relation.
- Integration: authored StoryPack -> world/profile merge -> compatibility
  variant -> KCD2 materialization preserves the placement contract.
- Live proof already obtained: the generated document appears in the chest,
  is highlighted as a quest item, and appears under inventory quests.

## Deferred

- Automatic discovery of every actor's personal chest across both regions.
- Alternate authored fallback branches with different dialogue.
- Better player feedback for overheard evidence.
