# Dark Passenger Pritoky Investigation Vertical Slice Design

## Goal

Prove the complete investigation loop before authoring clue content:

1. select and persist a hidden victim in Pritoky;
2. show a genuine search-area marker instead of the victim marker;
3. raise hidden confidence through a debug command;
4. reveal the exact victim marker at 70 confidence;
5. preserve the result across save/load without duplicate quest updates.

After live validation, the same generated structure will scale to every
supported settlement in Trosky and Kuttenberg.

## Architecture decision

Lua owns the persistent Case state. Quest XML only presents that state through
native objectives, markers, banners, and sounds.

Victim selection and victim revelation are separate signals:

- the existing hidden selection signal binds the chosen NPC immediately so
  death tracking remains valid before revelation;
- a new monotonic `revealed` signal allows the quest graph to activate the
  exact target objective and marker only after confidence reaches 70.

This avoids delaying NPC binding until revelation and avoids making the quest
graph a second persistence source.

## Player flow

```text
HUNGER REACHES QUEST THRESHOLD
  -> select one living eligible Pritoky victim
  -> persist hidden target and confidence=0
  -> activate "Investigate the surroundings of Pritoky"
  -> show Pritoky search area

DEBUG EVIDENCE
  -> dp_evidence <amount> [label]
  -> confidence increases and clamps to 0..100
  -> values below 70 do not reveal the NPC

FIRST CROSSING OF 70
  -> persist revealed=true
  -> complete the search-area objective
  -> activate "Hunt down the chosen victim"
  -> show the normal quest marker on the selected NPC
  -> use the native objective update presentation and sound
```

Confidence controls available information, not whether the chosen victim is
valid. If the selected victim dies before 70 confidence, the existing death and
aftermath flow still handles the correct target.

## Persistent Case state

The production Case storage gains a versioned investigation record containing:

- Case generation/id;
- game region;
- settlement id;
- selected candidate slot and stable NPC identity;
- confidence, clamped to `0..100`;
- reveal threshold, initially `70`;
- monotonic `revealed` flag;
- whether the reveal transition was already dispatched to the quest graph.

The saved record is authoritative. Reload, player movement, repeated quest
polling, and repeated evidence commands must not replace the target or emit the
reveal transition twice.

The old in-memory `Startup/case_state.lua` prototype is not a second source of
truth. Its useful confidence behavior is migrated into the production Case
state or the prototype is reduced to a compatibility facade.

## Quest graph

The generated quest graph keeps the existing candidate-specific
`DP_TargetProgress` values so the exact marker can resolve to the already bound
NPC alias.

The initial investigation phase instead activates a search-area objective whose
marker points at a Pritoky `TriggerAreaAsset`. Candidate target objectives remain
inactive while `revealed=false`.

At the reveal edge:

1. the search objective reaches `Completed`;
2. the candidate-specific target progress becomes active;
3. the native journal update, centered objective presentation, sound, and NPC
   marker are emitted once.

Quest state is a projection of the persistent Lua record. Lua may reassert the
current state after load, but only idempotently.

## Pritoky search area

The first technical spike locates a suitable existing Pritoky
`TriggerAreaAsset` in extracted level or quest data and verifies that it renders
as the expected map/compass search area.

If no suitable vanilla asset exists, create one mod-owned area through the
official modding tools and bind that asset into the quest XML. A representative
NPC or point marker is not considered a successful area-marker proof.

Only Pritoky receives the area binding in this vertical slice. The data shape
must already support a later settlement catalog so scaling requires generated
entries rather than hand-written quest logic.

## Debug contract

`dp_evidence <amount> [label]` is the only evidence source in this slice.

It must:

- reject evidence when no active Case exists;
- parse and clamp numeric amounts safely;
- update the persistent production record;
- log old confidence, delta, new confidence, Case id, and reveal transition;
- trigger revelation only on the first threshold crossing.

A read-only diagnostic command reports Case id, region, settlement, candidate
slot, confidence, and reveal state. The normal game UI never exposes the hidden
confidence percentage or target identity before revelation.

## Failure handling

- Missing or unresolved target: retain the saved Case and report diagnostics;
  never silently select a replacement.
- Missing area asset: keep the investigation objective but fail the technical
  validation; do not substitute the exact victim marker.
- Target dead before reveal: skip revelation and continue through the existing
  aftermath path.
- Evidence after reveal: confidence may rise, but no objective or banner repeats.
- Save/load at any confidence: restore the same target, confidence, area phase,
  and reveal state.
- Stale saves with the older schema: migrate conservatively with confidence `0`
  and preserve any already selected target.

## Scope

Included:

- one real Pritoky search area;
- persistent confidence and reveal state;
- debug evidence command;
- native search-to-target quest transition;
- automated structural and pure-logic tests;
- live dev-build save/load validation.

Excluded:

- authored clues, rumors, letters, or witness dialogue;
- confidence loss, false evidence, and decoys;
- other settlements and both-region area catalogs;
- investigation archetypes and complications;
- blood-trail and Nemesis pressure changes.

## Validation

Automated checks cover:

- confidence clamping and one-shot threshold crossing;
- serialization and migration of investigation state;
- no target replacement on reload or movement;
- generated XML contains the search-area objective and separates it from the
  candidate marker;
- target death remains valid before revelation;
- repeated evidence and state restoration are idempotent.

Live dev validation covers:

1. start a Case while Pritoky is the selected settlement;
2. verify only the Pritoky area appears;
3. add evidence below 70 and verify no NPC marker;
4. save/load and verify target and confidence persistence;
5. cross 70 and verify the native objective update, sound, and exact marker;
6. save/load again and verify no duplicate update or target replacement;
7. separately kill the selected victim before 70 and verify the existing
   aftermath flow still starts.
