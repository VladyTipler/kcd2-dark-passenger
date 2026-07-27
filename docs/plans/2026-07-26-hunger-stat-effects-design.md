# Dark Passenger: hunger stat effects

## Goal

Make rising hunger materially affect normal gameplay and motivate the player to
finish the hunt. Satisfaction should feel rewarding, but must not become a
reason to farm kills solely for an overpowered buff.

## Design principles

- Hunger remains hidden; the active buff/debuff communicates its qualitative
  state.
- Positive effects are useful but moderate.
- Negative effects grow faster and become difficult to ignore at 80–100.
- The same inner calm affects physical control, stealth, ranged accuracy, and
  Henry's social mask.
- Hunger tremor is represented by `marksmanship` for now. Camera or weapon-sway
  effects are explicitly out of scope.
- Hunger 50 remains neutral and has no buff.

## Approved tiers

| Hunger | Strength | Agility | Vitality | Marksmanship | Stealth | Thievery | Speech | Charisma |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 0 | +2 | +2 | +2 | +2 | +3 | +2 | +2 | +2 |
| 10 | +1 | +2 | +1 | +2 | +2 | +2 | +2 | +2 |
| 20 | +1 | +1 | +1 | +1 | +2 | +1 | +1 | +1 |
| 30 | +1 | +1 | +1 | +1 | +1 | +1 | +1 | +1 |
| 40 | — | — | — | +1 | +1 | — | +1 | +1 |
| 50 | — | — | — | — | — | — | — | — |
| 60 | -1 | — | — | -1 | -1 | — | -1 | -1 |
| 70 | -1 | -1 | -1 | -1 | -1 | -1 | -1 | -2 |
| 80 | -2 | -2 | -1 | -2 | -2 | -2 | -2 | -3 |
| 90 | -2 | -2 | -2 | -3 | -3 | -3 | -3 | -4 |
| 100 | -3 | -3 | -3 | -4 | -4 | -3 | -4 | -5 |

KCD2 table parameters:

- `strength`
- `agility`
- `vitality`
- `marksmanship`
- `stealth`
- `thievery`
- `speech`
- `charisma`

## UI copy

Every existing lore description keeps its narrative paragraph. A final,
separate paragraph lists the exact mechanical effects:

- Russian: `Эффекты: Сила +2, ловкость +2, ...`
- English: `Effects: Strength +2, agility +2, ...`

The neutral 50 state has no buff and therefore no effect description.

## Acceptance

- Every tier uses exactly the approved parameters and values.
- English and Russian descriptions list the same values as the buff table.
- Positive tier swaps preserve AI tag 23 without restarting the quest.
- Natural game-time progression, save/load, quest start at 50, and the
  target-kill reset remain unchanged.
- No camera shake or bow/crossbow sway is introduced in this iteration.
