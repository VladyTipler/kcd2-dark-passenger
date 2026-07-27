# Persistent Dark Passenger Hunger Design

## Goal

Replace the temporary satisfaction timer with a hidden 0–100 hunger value
derived from KCD2 world time and persisted in Henry's save.

## Source of truth

The source of truth is not a buff or quest state. It is a namespaced record on
the player AI table:

```text
g_localActor.AI.DarkPassenger = {
  schemaVersion = 1,
  lastSatisfactionWorldTime = <number>
}
```

KCD2's `Player:OnSaveAI(save)` serializes `self.AI`, and `Player:OnLoadAI`
restores it. A probe must confirm that an added nested numeric field survives
save/load before the full mechanic is enabled.

Quest history is rejected because the Lua quest binding exposes active and
completed states but no completion timestamp. The hunt is also repeatable and
reset between cycles. Buff duration is rejected as storage because the Lua
binding exposes presence but not a reliable absolute start or expiry time.

## Clock

The preferred clock is `Calendar.GetWorldTime()`, because hunger must advance
with game-world time, including sleep and waiting. Before shipping, a runtime
probe must log and compare:

- `Calendar.GetWorldTime()`;
- `Calendar.GetGameTime()`;
- `Calendar.GetWorldDay()` plus `Calendar.GetWorldHourOfDay()`;
- the persisted value before and after save/load, sleep/wait, and regional
  travel.

The full hunger loop must not be enabled until one monotonic world-time source
is confirmed across both regions. A clock rollback is clamped and logged rather
than creating negative hunger.

## Hunger calculation

```text
elapsedSeconds = max(0, now - lastSatisfactionWorldTime)
completedDays = floor(elapsedSeconds / 86400)
hunger = clamp(completedDays * 10, 0, 100)
```

The value changes in ten-percent steps, reaches 50 after five game days, and
100 after ten game days. It is recalculated rather than incremented, preventing
timer drift and save/reload duration resets.

When no persisted record exists, initialize
`lastSatisfactionWorldTime = now - 5 * 86400`. This starts an existing or new
save at 50 hunger and lets the first hunt begin after the normal startup delay.

## Buff projection

Buffs are derived presentation and modifiers only:

- 0, 10, 20, 30, 40: five progressively weaker positive satisfaction tiers;
- 50: no hunger buff;
- 60, 70, 80, 90, 100: five progressively stronger negative hunger tiers.

Exactly one tier buff may be active. All positive tiers expose the existing
satisfaction AI tag `23`, so the established quest trigger remains suppressed
until hunger reaches 50. Negative tiers do not expose that tag.

The exact percentage remains hidden. Buff names and descriptions communicate
Henry's condition qualitatively. `dp_hunger_status` logs the exact clock,
elapsed time, hunger, tier, and active buff for testing.

The existing quest reward buff becomes a durable reward signal:

1. Quest graph grants it on successful target death.
2. Lua detects the signal.
3. Lua writes the current world time to the player record.
4. Lua removes the signal.
5. Lua applies the 0-tier satisfaction buff.

Consuming the signal prevents repeated timestamp resets on every poll and still
survives a save made before Lua processes it.

## Runtime lifecycle

The hunger module evaluates:

- after mod initialization once Henry is available;
- after player initialization and reload;
- every second through the existing lightweight polling lifecycle;
- immediately when a debug reset command is used.

Buff writes occur only when the derived tier changes. Crossing from 40 to 50
removes the positive tag; the existing live quest graph then starts the hunt
with its native banner and sound. Successful target death resets hunger to 0
through the reward signal.

## Failure handling

- Missing player or Soul: retry without initializing storage.
- Missing/invalid persisted number: use the first-install 50-hunger policy.
- Clock rollback: preserve the last valid state, clamp elapsed to zero, log.
- Duplicate tier buffs: remove every Dark Passenger hunger-tier GUID, then
  apply the single derived tier.
- Reload during reward processing: persistent reward signal is consumed on the
  next successful evaluation.

## Validation

Automated structural tests cover persistence field names, pure hunger
calculation boundaries, exactly one buff per non-neutral tier, shared positive
tag, reward-signal consumption, debug commands, and unchanged target-selection
artifacts.

Runtime acceptance is split:

1. Persistence/clock probe in dev: save/load, one-hour wait, sleep, and travel
   between Trosky and Kuttenberg.
2. Accelerated hunger test: debug-sized thresholds or timestamp offsets verify
   all transitions, quest start at 50, target death reset, and reload.
3. Retail test with production ten-day timing constants and native quest UI.

## Unresolved questions

- Exact stat modifiers for each positive and negative tier.
- Final lore names/descriptions for all ten visible tiers.

