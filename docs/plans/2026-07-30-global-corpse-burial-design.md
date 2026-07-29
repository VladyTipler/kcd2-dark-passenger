# Dark Passenger Global Corpse Burial Design

## Goal

Let Henry bury any dead human body as a global Dark Passenger mechanic. Burial
removes the corpse and its ordinary loot, advances one game hour, costs energy
and nourishment, and can improve an active Case only when exposure has not
already escaped Henry's control.

## Player flow

1. Look at a dead human body.
2. Keep the vanilla `E` corpse action for looting or carrying.
3. Hold the dedicated `F` action `Закопать тело` / `Bury the body`.
4. The action is disabled with a reason when:
   - Henry has no shovel;
   - the ground cannot be dug;
   - the corpse carries a quest item;
   - another burial is running.
5. The native SkipTime presentation runs for seven real seconds with digging
   audio and `Земля умеет хранить тайны...`.
6. One game hour passes, energy drops by 10, nourishment by 5, then the corpse
   and its remaining ordinary loot disappear.

The shovel is required but never consumed.

## Runtime architecture

`dpburial.lua` owns validation, the contextual action, SkipTime presentation,
costs, corpse removal, and the aftermath callback.

`BasicAIActions.GetActions` is wrapped because
`PlayerEventDispatcher:BasicAIActionsGetActions` does not include the NPC
`self`. The wrapper is hot-reload-safe. An eligible burial is appended as the
native secondary `butcher` action even for the fast contextual query, so the
HUD can expose hold-`F` beside the untouched vanilla `E` action.

Suitable ground is proven by a downward physics ray. Diggable surface families
are soil, mud, grass, forest, gravel, road, and field. Wood, stone, rock, water,
and missing collision data are rejected.

## Quest-item safety

The Lua item API exposes inventory entries and item class GUIDs but not the
`IsQuestItem` flag. A generated catalog therefore contains every quest-item
class from the authoritative base-game `Tables.pak`.

Inventory inspection is fail-closed: missing catalog, unreadable inventory, or
unknown item metadata blocks burial. The catalog generator is deterministic
and can be rerun after a game update.

## Case integration

- Burying an unrelated body changes no Case state.
- Burying the selected target during `SILENCE_CHECK`, with no witness or locked
  exposure, resolves the Case immediately as `clean`.
- Burial never clears a report, alarm, wanted state, or persistent testimony.
- During `CLEANUP`, the existing witness ledger still decides
  `controlled/noisy`.
- Witness death remains the event that changes witness state; burying the body
  cannot erase information already reported.

## Failure boundaries

- The corpse is removed only after the presentation completes.
- Validation runs both when the action is built and when it is invoked.
- Save locking and audio are always released by normal and failsafe cleanup.
- Stale timers cannot complete a newer burial.
- A missing corpse at completion cannot mutate the current Case.

## Validation

Automated checks cover catalog generation, action injection, all validation
gates, time and stat costs, native UI/audio cleanup, delayed removal, and
aftermath rules. The interaction contract asserts that the fast corpse action
list retains its vanilla primary action and also receives the dedicated
hold-`F` burial action.

Live dev validation covers visible action reasons, one successful burial on
soil, body and loot removal, one-hour advancement, audio stop, and no duplicate
actions after reload.
