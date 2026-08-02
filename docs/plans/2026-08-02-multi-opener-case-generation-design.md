# Multi-Opener Case Generation

**Date:** 2026-08-02
**Status:** approved
**Scope:** authored case archetypes with multiple discoverable entry points across every supported settlement

## Goal

Let one persistent murder case be discovered through several natural world
interactions instead of one mandatory quest opener. New stories should be
authored as content inside reusable archetypes, then compiled for every
supported settlement without hand-written quest graphs per settlement.

## Decisions

- One universal quest container remains the native journal projection.
- A case selects and persists its target, settlement, archetype and story once.
- Each case activates two to four compatible openers at the same time.
- The first consumed opener selects the initial investigation route.
- Remaining openers stay available as optional corroborating evidence.
- Every opener awards confidence at most once per case generation.
- Exact opener markers are hidden until an acquired lead explicitly reveals a
  person, place or object.
- Content is authored in Russian and English from the start.

## Layered content model

The system has four independent layers:

1. **Case archetype** defines the reusable investigation topology, supported
   evidence primitives, branches and confidence budget.
2. **Story variant** supplies the innocent victim, murder, motive, cover story,
   dialogue, documents and evidence details.
3. **Opener set** defines several ways to discover that same story.
4. **Settlement binding** maps semantic roles onto real NPCs, sites and objects
   available in the selected settlement.

An archetype is reusable across many story variants. A story may support
multiple opener kinds without duplicating its later evidence graph.

## Opener contract

Each opener definition contains:

- stable id and opener kind;
- semantic source role such as `herald`, `guard_pair`, `resident`, `innkeeper`,
  `world_item` or `crime_scene`;
- target, region, settlement and source constraints;
- Russian and English content;
- one-shot confidence reward;
- next evidence step;
- duplicate group for narratively equivalent information;
- compatible archetypes and story variants;
- fallback source role and fallback content where required.

Two openers in the same duplicate group may both remain readable, but only the
first may award their shared evidence. Openers that reveal distinct facts keep
independent evidence ids and rewards.

## Build-time generation

The build pipeline maintains a generated world index for both game regions.
For every supported settlement it records semantic capabilities such as
eligible residents, guards, tavern workers, heralds, inns, homes, containers
and reusable investigation areas.

For each compatible `story x settlement` pair the compiler:

1. filters opener definitions by available semantic capabilities;
2. requires at least two distinct viable opener kinds;
3. generates static aliases, roles, dialogues, objectives and bridge signals;
4. emits a Lua runtime manifest for dynamic selection and persistence;
5. emits matching Russian and English localization;
6. proves that every allowed entry route can reach the reveal threshold;
7. rejects unresolved aliases, insufficient confidence paths or missing
   localization during the build.

Small settlements do not need every opener kind. A village without a herald
may use resident gossip, an overheard conversation and a physical clue. A
story that cannot produce two coherent entry routes for a settlement is not
eligible there until authored fallbacks exist.

## Runtime flow

When hunger starts a new case, Lua selects one eligible case package and
persists its complete identity before exposing content. It then selects two to
four compatible openers with category diversity and persists their concrete
NPC or site bindings plus reserved fallbacks.

All selected openers become discoverable. The first consumed opener records
the case `entryPath`, awards its evidence and activates its `nextStep` in the
shared evidence graph. Later openers may corroborate the case, open an
alternative branch or converge on an already active step. The evidence ledger
prevents duplicate confidence.

Save/load, Lua reload, player movement and repeated interactions never reroll
the case, opener set or concrete sources.

## Source loss and recovery

- A dead or permanently unavailable NPC does not reroll the story.
- A preselected compatible fallback may replace only that opener source while
  preserving the opener id, text purpose and evidence reward.
- An already acquired item remains valid if it moved from its original site to
  the player's inventory.
- Missing streamed entities retry resolution without changing persistent
  bindings.
- If fewer than two viable routes can be guaranteed at build time, the story is
  disabled for that settlement instead of failing during play.
- Old saves without opener state migrate to the current linear canary package
  and never replace an existing target or settlement.

## Player experience

The investigation area is a space to explore, not a single waypoint. Henry may
hear a herald, overhear guards, question locals, enter a house or discover an
item accidentally. The world interaction itself supplies the first lead.

After a lead is acquired, later objectives may become more precise and reveal
a person, container or smaller area. Optional openers remain useful for
confidence and narrative corroboration but are never required to exhaust if
another valid route reaches the reveal threshold.

## Verification

Automated generation tests cover the complete enabled
`story x settlement` matrix:

- at least two distinct viable openers;
- deterministic output and persistent selection;
- a reachable confidence path to 70 from every allowed entry route;
- no duplicate evidence rewards;
- valid static aliases and bridge signals;
- exact Russian and English key parity;
- safe source-loss fallback behavior;
- no reroll after save/load or Lua reload.

Each new opener primitive receives one focused live canary proving its real
KCD2 boundary. Once a primitive is proven, later stories use it as content and
need structural tests rather than a fresh manual engine experiment in every
settlement.

## Delivery order

1. Live-prove the current Pritoky chain: innkeeper, Vojtech document, tavern
   witness and target reveal.
2. Extract the current dialogue and document steps into reusable opener and
   evidence definitions without changing behavior.
3. Generate a multi-opener Pritoky case using only proven primitives.
4. Add the settlement capability catalog and validate all supported
   settlements in both regions.
5. Add new opener adapters one at a time: resident dialogue, overheard guards,
   herald announcement, world item and crime scene.
6. Author several archetypes and story variants after the compiler contract is
   stable.

## Non-goals

- Runtime creation of arbitrary Skald nodes or native quest graphs.
- Procedurally generated prose without authored narrative constraints.
- A separate quest graph for every story or settlement.
- Requiring every settlement to expose every opener kind.
- Voice acting in the current content pipeline.

## Open questions

None block the first extraction. Exact opener weights, anti-repeat windows and
the initial content deck will be tuned after the Pritoky multi-opener canary.
