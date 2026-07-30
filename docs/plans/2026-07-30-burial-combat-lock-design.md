# Dark Passenger Burial Combat Lock Design

## Goal

Prevent Henry from starting corpse burial while combat danger is active, without
hiding the contextual burial action or changing the normal burial flow.

## Player flow

- Outside combat, `Закопать тело` / `Bury the body` behaves unchanged.
- In combat danger, the action remains visible but disabled.
- The disabled reason is `Нельзя закапывать тело в бою.` /
  `You cannot bury a body during combat.`
- No separate centered HUD notification is shown.
- If combat starts after the action was rendered but before invocation, burial
  is rejected by the same validation gate.

## Runtime design

`dpburial.lua` reads the native `actor.soul:IsInCombatDanger()` predicate from
inside `CanBury`. The combat gate runs before inventory and ground checks so the
HUD reports the most immediate blocker.

`AddBuryAction` already maps `CanBury` into native `UIAction` enabled state and
disabled reason. `OnBuryBody` already calls `CanBury` again, providing the
execution-time race guard without a second source of truth.

If the native predicate is unavailable or errors, the check fails open and the
existing burial validations remain authoritative.

## Validation

Automated regression checks cover:

- use of the native combat-danger predicate;
- combat reason localization in English and Russian;
- combat validation inside `CanBury`;
- invocation-time validation through `OnBuryBody`.

Live dev validation covers a visible disabled hold-`F` action during combat and
unchanged successful burial after combat danger ends.
