# Dark Passenger Persistent Witness Ledger Design

## Goal

Turn confirmed witnesses into persistent world actors that affect the current
Case and can later feed rumors, investigation pressure, the blood trail, and
the Nemesis system.

This design extends
`2026-07-27-hunt-cleanliness-and-aftermath-design.md`. The first delivery stays
small: reliable witness detection, anonymous player feedback, persistent
records, and the existing clean/controlled/noisy result. Witness investigation
and Nemesis behavior are later vertical slices.

## Design principles

- Mere proximity to the corpse never makes an NPC a witness.
- A witness requires evidence of an incident reaction linked to Henry.
- Explicit alarm, crime report, identification, or bounty always counts as
  exposure.
- The player's exact exposure score and witness identity remain hidden.
- Removing a witness can protect the current Case but creates a blood trail.
- Information already reported cannot be erased by killing its source.
- Persist data once so later systems consume the same ledger instead of
  duplicating witness state.

## Delivery strategy

The feature is built in vertical slices:

1. Detect and persist confirmed witnesses; resolve the Case.
2. Reveal witness identity through rumors and Henry's investigation.
3. Add ways to eliminate, intimidate, misdirect, or discredit a witness.
4. Convert testimony and blood-trail history into investigation pressure.
5. Let the Nemesis consume the accumulated history.

Only the first slice belongs to the initial implementation.

## Current Case lifecycle

```text
TARGET_DIES
  -> SILENCE_CHECK
     -> no confirmed witness for 90 seconds: CLEAN
     -> clean zone exit: CLEAN
     -> confirmed witness or suspicion: CLEANUP

CLEANUP
  -> all witnesses silenced before reporting, then zone exit: CONTROLLED
  -> living confirmed witness remains on zone exit: NOISY
  -> report, alarm, identification, or bounty: NOISY_LOCKED
  -> zone exit: resolve the already locked NOISY result
```

The native quest objective remains `Не оставить следов.` The Case still closes
after Henry leaves the encounter zone, even if the base game continues its own
crime, pursuit, reputation, or punishment flow.

## Witness confirmation

The classifier is deliberately conservative.

A nearby NPC becomes a confirmed witness only when runtime evidence proves both:

1. the NPC reacted to the death, attack, crime, or resulting incident; and
2. the reaction or report is linked to Henry.

Valid evidence may include a proven direct-witness event, crime report,
identification state, incident relationship, or an equivalent game-owned
signal discovered through dev probes.

The following are insufficient on their own:

- distance to the target;
- line of sight without a reaction;
- discovering a corpse;
- being hostile to Henry for an unrelated reason;
- being in the same settlement or encounter zone.

No unproven signal gates production behavior. Candidate APIs are first logged
and compared in controlled dev scenarios.

## Witness states

Each confirmed witness has one current state:

- `UNREPORTED` — saw enough to threaten Henry but has not reported;
- `REPORTED` — successfully passed information onward;
- `SILENCED_BEFORE_REPORT` — died before reporting;
- `SILENCED_AFTER_REPORT` — died after the information escaped;
- `LOST` — the saved NPC cannot currently be resolved.

Transitions are monotonic. In particular, `REPORTED` can never return to an
unreported state, and a Case with locked noisy exposure can never be cleaned.

## Persistent ledger

Store one versioned record per confirmed witness. A record contains:

- stable NPC identity, avoiding transient runtime handles;
- Case generation/id;
- region and settlement;
- target identity;
- incident time and position;
- what class of evidence confirmed the witness;
- whether the witness identified Henry;
- report state and timestamp;
- life state and removal timing;
- testimony strength reserved for future use;
- last successful entity resolution;
- whether the anonymous player notification was already emitted.

The active Case keeps a small index of its witness records. The global ledger
owns historical records so later rumor and Nemesis systems can query the same
source of truth.

Only confirmed witnesses enter the ledger. Old resolved records may later be
compacted into historical aggregates, but the first version should preserve
the individual records needed for live validation.

## Identity and save/load recovery

Persistence must use a stable game identity proven to survive save/load and
world streaming. A runtime entity handle may be cached only for the active
session.

On recovery:

- the Case generation prevents duplicate registration and stale timers;
- an already resolved Case cannot apply its outcome twice;
- a resolved witness record is never recreated as active;
- a missing unreported NPC becomes `LOST` and cannot block the Case forever;
- a missing reported NPC keeps its historical testimony because the
  information already exists.

The exact storage encoding must be selected only after probing which scalar or
string values KCD2 reliably persists through `Variables`.

## Player presentation

The first confirmed witness produces one anonymous quest update:

> Кто-то видел слишком много.

The update has no witness name, NPC marker, map marker, or compass marker.
Repeated witnesses in the same Case do not spam duplicate banners.

The player's first future task is not to follow a marker, but to determine who
the witness was through rumors, behavior, and investigation content.

## Immediate outcome rules

- No confirmed witness and no explicit exposure: `Clean`.
- Every confirmed witness silenced before reporting: `Controlled`.
- A living confirmed witness remains when Henry exits: `Noisy`.
- Any successful report, alarm, identification, or bounty:
  irreversibly `Noisy`.
- Killing a witness after reporting does not improve the current result.

Every Henry-attributed target death still resets hunger and grants base
satisfaction. The outcome only changes grace time and persistent consequences.

## Future investigation model

Investigation pressure will not be a raw count of living witnesses. It will be
a weighted result of:

- testimony strength and corroboration;
- whether Henry was identified;
- alarms, reports, and official crime state;
- missing or murdered witnesses;
- settlement attention;
- persistent blood trail;
- repeated Cases and geographic patterns.

Removing an unreported witness deletes their immediate testimony but adds a
smaller blood-trail event. Removing a reported witness stops future assistance
but does not erase the statement and adds a larger suspicious-disappearance
event.

This prevents killing every witness from becoming an automatic reduction
button and creates meaningful future alternatives such as intimidation,
misdirection, or discrediting.

## Failure boundaries

- A lost or unloaded NPC must not leave the Case permanently active.
- A witness must not be registered twice after save/load.
- Unrelated hostility or ordinary corpse discovery must not create exposure.
- One Case must not mutate witness records belonging to another generation.
- The ledger must remain valid when later schema versions add rumor or Nemesis
  fields.

## Validation

Automated checks must cover:

- legal witness state transitions;
- irreversible report and noisy-lock behavior;
- duplicate registration prevention;
- one anonymous notification per Case;
- save/load idempotency;
- missing-NPC recovery;
- clean, controlled, and noisy result mapping;
- separation of current exposure from persistent blood trail.

Live dev scenarios must compare:

- unseen kill with nearby uninvolved NPCs;
- NPC discovering only the corpse;
- direct witnessed stealth kill;
- open public kill and guard alarm;
- witness removed before reporting;
- witness removed after reporting;
- zone exit with a living witness;
- save/load during both silence check and cleanup.

Retail remains authoritative for quest banners, objective updates, journal
state, and final Case completion.

## Deferred work

- Exact rumor paths that reveal witness identity.
- Intimidation, bribery, misdirection, and discrediting mechanics.
- Testimony weights and investigation-pressure thresholds.
- Witness-led Nemesis travel and interrogation.
- Ledger compaction policy for very long playthroughs.
