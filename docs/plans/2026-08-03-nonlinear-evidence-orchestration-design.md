# Nonlinear Evidence Orchestration

**Date:** 2026-08-03
**Status:** approved
**Scope:** order-independent evidence, parallel leads and an overheard-dialogue canary

## Goal

Make a Case feel like an investigation rather than a fixed quest checklist.
Facts that already exist in the world are seeded when the Case starts, Henry
may discover them in any order, and the journal reports only what he currently
knows or has reason to pursue.

## Decisions

- One universal native quest container remains the journal projection.
- The complete Case identity and its concrete bindings are persisted before
  any clue, dialogue or objective is exposed.
- Physical evidence that already exists in the story is placed at Case start.
- A hint reveals a direction; it does not create an already-existing fact.
- Every clue has a stable evidence id and awards confidence at most once per
  Case generation.
- Clues may be discovered without first receiving their intended hint.
- Journal directions are derived from known facts and discovered evidence.
- Finding a clue early suppresses later obsolete directions to that clue.
- The target is revealed at 70 confidence, while each Case offers roughly
  105-140 confidence so no single route is mandatory.
- Russian and English content remain authored together.

## Runtime model

### Case Snapshot

Case creation persists one immutable snapshot:

```text
generation
caseId
region + settlement
target
semantic role bindings
selected story variant
selected clue set
placement bindings
```

Save/load, streaming, Lua reload and player movement restore this snapshot;
they never reroll the target, sources or clue locations.

### World Seeder

An idempotent seeder places every `case_start` physical clue after the snapshot
is stored. Placement is keyed by `generation + clueId` and checks both the
bound container and Henry's inventory before creating anything. Unloaded
bindings retry later without choosing a replacement.

Items that do not exist until a later event use `placement: on_event`. This is
reserved for genuinely created or handed-over evidence, not ordinary gating.

### Evidence Registry

Every clue owns an independent ledger:

```text
pending -> placed -> discovered
```

Dialogue-only clues may move directly from `pending` to `discovered`.
Discovery persists before confidence or presentation is projected into the
native graph. Repeated reads, dialogue, proximity ticks and save/load restore
the stored result without awarding confidence twice.

### Lead Planner

The planner derives currently useful directions from:

- facts known from acquired evidence;
- clue discovery state;
- authored `hintsUnlockedBy` relationships;
- concrete bindings in the Case Snapshot.

It controls hints and journal presentation only. It never places evidence.
The journal keeps one umbrella investigation objective and exposes concise
directions beneath it. A direction disappears or completes once its clue is
already discovered. Presentation retries must not repeat the center-screen
notification for the same state revision.

### Discovery Router

All evidence primitives report the same transaction:

```text
Discover(generation, clueId, sourceContext)
  -> reject stale or duplicate input
  -> persist discovered state
  -> add confidence once
  -> reveal authored facts and directions
  -> reveal target once at threshold
  -> request one presentation update
```

The router contains no assumed clue order. Tests run the same clue set through
multiple permutations and require the same final domain state.

## CaseSpec contract

Each clue declares at least:

```text
id
kind
confidence
placement: case_start | on_event
discoverableWithoutHint
hintsUnlockedBy[]
reveals[]
bindingRole
Russian and English content
```

Optional `claimId` groups sources that repeat the same fact. They may remain
available as narrative corroboration, while an authored cap prevents farming
one claim through several equivalent tellings.

The compiler rejects duplicate ids, missing localization, unresolved required
bindings, impossible placements and Case packages whose valid routes cannot
reach the reveal threshold.

## Generatability boundary

Every accepted design must compile into a finite package using proven engine
primitives. The authoring system may generate static XML roles, dialogues,
objectives, aliases, bridge signals, localization and Lua manifests. Runtime
Lua may select a compiled package, resolve persisted bindings and drive domain
state; it must not invent native quest or dialogue graphs during play.

The compiler validates every enabled `case x settlement` package before the
mod can build. A story is disabled for an incompatible settlement rather than
shipping an unresolved runtime promise.

Ideas that require any of the following are explicitly reported as unproven or
unsupported until a focused canary demonstrates them:

- arbitrary native quest-graph mutation at runtime;
- arbitrary dialogue graphs or voice lines created at runtime;
- new rendered search-area geometry without required compiled world assets;
- a new 3D clue model without an existing reusable asset;
- a dynamic marker binding with no proven alias or engine API boundary.

Overheard dialogue remains generatable because CaseSpec emits a finite authored
NPC-to-NPC dialogue and its static role/signal wiring. Lua only activates the
already compiled variant selected for the persisted Case.

## Missing Traveler correction

The current linear canary incorrectly waits for the ledger before exposing the
stablehand. The correct flow begins after Lavrentiy's rumor:

1. Lavrentiy says Matej vanished and his horse returned riderless.
2. Henry may inspect the guest ledger or question the stablehand in either
   order.
3. The ledger independently proves the departure entry was forged and that a
   local offered Matej a shortcut past the old willow.
4. The stablehand independently identifies who returned Matej's horse.
5. Either route may reveal further authored clues; neither is a prerequisite
   for the other.

The active journal copy must cite the actual known fact:

> Lavrentiy said Matej's horse returned without its rider. The stablehand may
> have seen who brought it back.

The old willow remains a separate possible search direction, not the reason
Henry knows to question the stablehand.

## Supported evidence primitives

The first nonlinear Case uses only mechanics already proven or bounded by a
focused canary:

1. authored source dialogue;
2. document read to completion;
3. authored witness dialogue;
4. item found in a bound container;
5. item stolen or looted from a bound NPC;
6. overheard NPC-to-NPC dialogue.

Exact markers are optional. The investigation area and journal direction may
be enough until an authored fact justifies a precise person or object marker.

## Overheard-dialogue canary

Local vanilla quest sources prove the native boundary:

- an `ingame` `Dialog` with `Initiator="NonPlayer"` and two NPC roles;
- `utils.speech.switchdialog` schedules it with `playerdistance`,
  `playerinarea`, `perceivingplayer` and subtitle controls;
- authored output ports can signal the exact clue line.

The Dark Passenger canary uses that pattern instead of inferring a generic NPC
conversation from Lua:

1. bind two persistent local NPC roles from the Case Snapshot;
2. schedule one authored rumor conversation while both roles are available;
3. emit `clue_spoken` on the exact informative response;
4. at that moment require Henry to be within the authored hearing distance,
   initially 12-15 metres;
5. award the clue once only when the distance gate passes;
6. otherwise leave the conversation repeatable for a later opportunity;
7. disable it for the current generation after discovery.

The first live canary proves scheduling, audibility, exact-line signaling,
one-shot confidence and save/load persistence. Later overheard stories become
content definitions and do not repeat the engine experiment.

## Contextual dialogue

One semantic source may have several authored variants chosen from current
Evidence Registry state. For example, Lavrentiy uses the ordinary missing-
guest conversation before the ledger is read and a forgery-focused response
after an early discovery. Variants share one evidence id and confidence award;
they do not become separate farmable sources.

## Failure handling

- Persist the Case Snapshot before world placement.
- Never reroll after a missing or unloaded source.
- Retry unresolved streamed bindings without duplicating items.
- Treat container and player inventory as one placement domain.
- Log a runtime binding failure and preserve the Case.
- Fail CaseSpec compilation for a missing required binding.
- Keep confidence hidden and unchanged on failed discovery transactions.

## Verification

Automated tests cover:

- deterministic snapshot and idempotent world seeding;
- physical evidence present before its intended hint;
- ledger/stablehand completion in either order;
- early discovery suppressing obsolete directions;
- contextual dialogue variant selection after early discovery;
- save/load and Lua reload without item duplication;
- no duplicate confidence from repeat interaction;
- identical final state across clue-order permutations;
- one target reveal at 70;
- Russian/English key parity;
- generated native overheard-dialogue contracts.
- complete `case x settlement` compilation with no unresolved capabilities.

Live acceptance covers:

1. Lavrentiy unlocks ledger and stablehand directions together.
2. Either direction can be completed first and the other remains optional.
3. A pre-seeded physical clue can be found before its hint and still counts.
4. Two NPCs deliver the authored rumor; only nearby Henry receives evidence.
5. Repetition and save/load do not award confidence twice.

## Delivery order

1. Correct the misleading Missing Traveler journal copy and isolate the
   inappropriate photo-mode evidence reaction.
2. Add the pure Evidence Registry, Discovery Router and permutation tests.
3. Persist the complete Case Snapshot and add idempotent world seeding.
4. Replace the current ordered ledger-to-witness gate with parallel leads.
5. Derive journal directions from known facts and clue state.
6. Add contextual dialogue variants.
7. Build and live-prove the overheard-dialogue canary.
8. Update the technical Wiki only after the runtime boundaries are proven.

## Non-goals

- Runtime creation of arbitrary Skald quest graphs.
- A separate native quest for each story.
- Uncontrolled procedural prose.
- New custom 3D evidence assets in this slice.
- Voice synthesis or authored voice acting.

## Open questions

No architecture question blocks implementation. Exact NPC pair, rumor copy,
hearing distance and confidence value for the first overheard canary are
content choices to tune during its focused live test.
