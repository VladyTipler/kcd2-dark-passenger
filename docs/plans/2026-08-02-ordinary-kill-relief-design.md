# Ordinary Kill Hunger Relief

**Date:** 2026-08-02
**Status:** approved
**Scope:** partial hunger relief from any player-caused human kill

## Goal

Let an ordinary human kill remove the negative hunger pressure without
rewarding Henry as if he completed a righteous Case.

## Rules

- Current hunger above 50 becomes exactly 50.
- Hunger at or below 50 is unchanged, including its timestamp, positive buff
  and satisfaction gate.
- Killing the selected Case target never uses partial relief; the existing
  target death, aftermath and full satisfaction path remains authoritative.
- Animals, knockouts, unresolved entities and deaths not credited to Henry are
  ignored.
- Active Case identity, target, settlement, confidence and evidence remain
  unchanged.

## Runtime design

`DarkPassengerHunger.RelieveFromOrdinaryKill()` owns the one-way transition.
It reads current hunger first and writes a five-day-old world-time anchor only
when hunger is above 50, then re-evaluates the visible tier.

The preferred event boundary is the live binding
`g_gameRules.game.SPNotifyPlayerKill(targetId, weaponId, headshot)`. A
hot-reload-safe wrapper must preserve the original method, resolve the target,
require a human entity, and exclude the selected target before calling hunger
relief. The wrapper is accepted only after a live combat kill proves that the
engine actually performs the call through the Lua table.

If the engine bypasses the Lua table, the wrapper is removed and no partial
implementation ships. A death-attribution observer becomes a separate task.

## Reaction cleanup in the same restart batch

Remove the superseded tags 33-35, hidden buffs, three custom monologue XML
files and generated `RequestMonologue` nodes. Evidence reactions use only the
live-proven global metarole call:

```lua
DialogUtils.RequestPlayerMonologByMetarole("HRAC_VYPNUL_PHOTOMODE")
```

The evidence item remains a normal `Document`; quest-item classification is
deferred.

## Verification

- Pure transitions: 40 and 50 are no-op; 60 and 100 become 50.
- A selected target bypasses partial relief.
- Duplicate notification is idempotent after the first transition.
- Non-human and unresolved targets are ignored.
- Targeted and full static suites stay green.
- Live canary proves a normal weapon kill crosses the callback and changes
  hunger above 50 to 50.
- The next single restart verifies the fresh evidence read, voiced Henry line
  and absence of obsolete reaction graph errors.

## Unresolved questions

- Does KCD2 invoke `SPNotifyPlayerKill` through the writable Lua table? Live
  canary decides; no assumption is shipped.
