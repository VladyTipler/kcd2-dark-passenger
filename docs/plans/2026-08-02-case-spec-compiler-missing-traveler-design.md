# CaseSpec Compiler and Missing Traveler Canary

**Date:** 2026-08-02
**Status:** approved
**Scope:** internal build-time case compiler plus a second cross-region authored case

## Goal

Turn the live-proven Pritoky investigation into a reusable authoring system,
then prove it with a second complete case, **Missing Traveler**, in Zhelejov in
the Trosky region. New stories should be authored as declarative content and
compiled into native KCD2 quest/dialogue data without creating a separate
quest container per story.

## Decision

Build an internal CaseSpec compiler before extracting a public Quest SDK.

- One universal native quest container remains the journal projection.
- CaseSpec owns story content, evidence topology, confidence and localization.
- Settlement bindings map semantic roles onto concrete game entities.
- Existing world catalogs remain the source of truth for target candidates and
  investigation areas.
- The compiler generates fragile engine wiring deterministically.
- Lua selects one eligible compiled package and persists its complete identity.

This is preferable to either cloning Pritoky XML by hand or attempting a pure
runtime quest graph. A hand-written clone proves no reuse; runtime graph
mutation is outside the proven KCD2 mod boundary.

## Authoring model

Future content authoring should require only stable declarative inputs:

```text
ArchetypeSpec + StoryVariant + SettlementBinding + optional Complication
    -> compiled CasePackage
```

For compiler v0, one CaseSpec contains:

- stable case and evidence identifiers;
- target and settlement constraints;
- the innocent victim, murder, motive, cover story and escaped-justice logic;
- ordered or branching evidence steps;
- one-shot confidence rewards and reveal threshold;
- required semantic roles such as innkeeper, evidence container and witness;
- Russian and English dialogue, document and journal copy;
- fallback behavior for unavailable sources.

Text remains authored and reviewed content. The compiler packages it into
localization and native dialogue structures; it does not generate uncontrolled
runtime prose. Generated XML and manifests are never edited by hand.

## Single sources of truth

The compiler consumes the existing target and investigation-area catalogs
rather than duplicating them. A new settlement capability layer adds semantic
roles that those catalogs do not describe. Authored overrides contain only
exceptions that cannot be derived safely from world data.

Story specs never contain concrete world GUIDs. A settlement binding resolves:

- `innkeeper`;
- `evidence_container`;
- `witness_pool`;
- the existing settlement search-area alias;
- eligible targets matching story constraints.

## Compiler outputs

One deterministic build pass emits:

- a Lua runtime manifest containing compiled case packages;
- regional quest and dialogue fragments;
- Storm roles and Lua/graph bridge signals;
- Russian and English localization XML;
- deterministic GUID allocations;
- a compatibility report for every enabled `case x settlement` pair.

The compiler rejects the build for duplicate identifiers, GUID collisions,
missing semantic bindings, empty eligible-target pools, localization mismatch,
unreachable steps or a maximum confidence below 70. Diagnostics identify the
exact CaseSpec path, for example:

```text
missing_traveler.steps.witness: missing Russian localization
missing_traveler: maximum reachable confidence is 50, expected >= 70
```

## Runtime contract

When hunger opens a new case, Lua selects one eligible compiled package and
persists before exposing any content:

```text
caseId + generation + settlement + target + concrete bindings + evidence ledger
```

Save/load, Lua reload, streaming and player movement never reroll that identity.
Evidence awards are one-shot and generation-scoped. A transaction writes the
domain result once; if the native quest signal fails, only presentation is
retried and confidence is not awarded again.

Runtime failures are fail-closed: preserve the selected case and target, award
nothing automatically, avoid fallback rerolls and emit a precise diagnostic.

## Save compatibility

- An existing active Pritoky investigation migrates to `convenient_accident`
  without replacing its target, confidence or acquired evidence.
- A new eligible Zhelejov investigation may select `missing_traveler`.
- Other settlements retain their current behavior during compiler v0.
- Existing quest enum values, marker aliases and bridge identifiers remain
  public save schema and are not renamed or removed.

## Canary story: Missing Traveler

Matej, a poor travelling merchant, carried money to the widow of a dead
companion. An eligible male resident of Zhelejov lured him away from the inn,
killed him and stole the purse. A forged guest-ledger entry claimed that Matej
left before dawn, although his horse remained in the stable.

### Evidence chain

1. **Innkeeper rumor, +20.** Matej paid several nights in advance, disappeared
   abruptly and left his horse. The innkeeper points Henry to the guest ledger.
2. **Ledger and hidden note, +30.** The departure line is in a different hand.
   Matej wrote that a local asked too many questions about the money and offered
   a shortcut. Reading the clue triggers one proven voiced Henry reaction.
3. **Stablehand or regular witness, +20.** The persisted witness saw the chosen
   target return Matej's horse without him and later burn something near the
   road. The static dialogue does not need a dynamic name: the witness offers
   to point the person out. Confidence reaches 70 and the existing native
   target marker activates.

Dialogue receives a dedicated later writing pass. Russian prose is authored
first; English is adapted for tone rather than translated mechanically.

## Verification

Development follows TDD and protects the current live-proven quest:

- CaseSpec schema and diagnostics tests;
- unique evidence and deterministic GUID tests;
- Russian/English parity tests;
- confidence reachability tests;
- semantic binding and eligible-target tests;
- deterministic clean regeneration tests;
- a snapshot/contract fixture for `convenient_accident`;
- build integration proving the real compiler is invoked by `Build-Mod.ps1`;
- package inspection for every generated native file.

Live acceptance proves:

1. An old Pritoky save continues the reference case without lost progress.
2. A new Zhelejov case selects `missing_traveler`.
3. The innkeeper awards exactly 20 once.
4. Reading the clue awards exactly 30 once and triggers Henry's reaction.
5. The witness remains stable across save/load and awards exactly 20 once.
6. Confidence 70 activates the existing native marker on the selected target.
7. Repeated interactions, reload and movement cause no reroll or duplicate reward.

## Delivery order

1. Checkpoint the current live-proven mod and roadmap.
2. Introduce CaseSpec schema, validator and deterministic compiler shell.
3. Express `convenient_accident` as a spec and prove generated behavior parity.
4. Add the Zhelejov settlement binding and `missing_traveler` spec.
5. Generate the Trosky native wiring and complete the live acceptance matrix.
6. Preserve the proven contracts in the technical Wiki.

## Immediate next milestone

After this canary, build an archetype library whose entries differ in primary
gameplay rather than prose alone. Planned gameplay verbs include questioning
and comparing testimony, stealing documents, following a suspect, searching a
crime scene, identifying an accomplice, provoking a reaction and matching a
visible trait.

The later generator composes archetype, story variant, opener, settlement
binding and complication. Dynamic map/compass markers become a reusable
capability requested by individual archetypes, not a separate quest system.

## Non-goals

- Public Quest SDK extraction in this iteration.
- Runtime creation of arbitrary Skald nodes.
- Procedurally generated prose during gameplay.
- Multiple native quest containers for individual stories.
- New evidence primitives before the compiler passes with proven primitives.

## Unresolved questions

- Exact Zhelejov innkeeper, container and witness bindings must be resolved
  from world data and verified live during implementation.
- Final Russian and English dialogue copy is intentionally deferred to a
  dedicated content-polish pass after the technical round trip works.
