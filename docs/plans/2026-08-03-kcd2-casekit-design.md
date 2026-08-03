# KCD2 CaseKit Design

**Date:** 2026-08-03
**Status:** approved
**Scope:** reusable build-time authoring and compilation toolchain for generated investigation cases

## Goal

Let authors create many coherent Dark Passenger investigations by supplying
reviewed story content and reusable gameplay archetypes. CaseKit resolves that
content against real KCD2 settlements, NPCs and places, rejects impossible
combinations, then emits finite native quest, dialogue, item, localization and
Lua artifacts.

## Product boundary

CaseKit has two public faces:

- **CaseBuilder** is the authoring surface: typed archetypes, story packs,
  evidence modules, settlement capabilities and template variables.
- **CaseCompiler** is the deterministic engine: validation, compatibility
  solving, concrete bindings, native materialization and reports.

Both initially live as a self-contained module inside the Dark Passenger
repository. They must not depend on Dark Passenger runtime globals or prose.
After several archetypes work across both regions, the module may be extracted
and published as a standalone KCD2 modding tool, tentatively **KCD2 CaseKit**,
then reused by the broader Quest SDK.

## Architecture principle

Reuse and replaceability are first-class requirements, not a later cleanup.
CaseKit follows a ports-and-adapters boundary:

- input adapters read KCD2 world catalogs and authored JSON;
- the pure domain core validates capabilities, resolves bindings and produces
  neutral CaseVariants;
- output adapters emit KCD2-specific XML, Lua, Storm, item and localization
  artifacts;
- Dark Passenger supplies content and consumes compiled output without being
  imported by the core.

The domain core must remain testable without an installed game. A different
world-index exporter, content format or native emitter can replace its adapter
without changing archetype and compatibility rules.

## Core decision

CaseKit is a constrained build-time assembler, not a runtime story generator.

```text
WorldSemanticIndex
  + SettlementProfile
  + CaseArchetype
  + StoryPack
  + EvidenceModules
  -> compatibility solver
  -> finite CaseVariants
  -> native KCD2 artifacts + runtime manifest
```

Runtime Lua selects only among compatible compiled variants and persists the
selected case, target and bindings. It never invents dialogue, substitutes an
arbitrary NPC into static XML or mutates a native quest graph.

## Inputs

### WorldSemanticIndex

Generated from game data and existing catalogs. Each entity records stable
GUIDs, engine name, localization key, faction, region, settlement membership,
position, home/work links, candidate policy and derived capabilities.

Capabilities describe usable story functions, for example:

```text
person.named
person.killable
role.innkeeper
role.tavern_worker
role.guard
role.farmhand
place.inn
place.stable
container.evidence
interaction.dialogue
interaction.overheard
```

Profession is not inferred from the entity name alone. It is resolved from
character localization, faction, work/home links, native role data and small
reviewed overrides.

### SettlementProfile

One central profile per supported settlement supplies only semantic facts that
cannot be derived safely. It may confirm a primary inn, identify an ambiguous
worker or exclude a bad container. Story packs do not repeat concrete GUIDs.

### CaseArchetype

An archetype defines the reusable grammar and outer gameplay topology rather
than one fixed clue route or prose:

- required and optional semantic slots;
- compatible evidence module kinds;
- allowed investigation-thread shapes and dependency rules;
- confidence budget and reveal threshold;
- opener and route diversity;
- marker, area and journal requirements.

### StoryPack

A story pack is one coherent authored case dossier. It supplies reviewed
Russian and English content plus the concrete investigation threads through
which that story is discovered:

- innocent victim, crime, motive, cover story and escaped justice;
- a shared fact graph and the relationships between people and events;
- several `InvestigationThread` chains built as lead, search or communication,
  and result;
- dialogue variants, documents, clue copy and journal revisions for every
  thread;
- typed template variables;
- compatible archetypes and optional constraints.

Text is authored, not generated during play. Russian and English keys are
validated together.

An `InvestigationThread` is not required to be strictly linear. Multiple leads
may converge on one clue, one result may unlock several next leads, and a clue
may be discovered before its intended hint. Every result reveals declared
facts, grants its one-shot confidence through an evidence module, optionally
unlocks another thread and produces visible journal feedback.

One StoryPack owns one canonical truth. Settlement, concrete world actors,
clue order and delivery may vary, but the compiler does not assemble the
crime, motive or causal history from unrelated random fragments. This is the
chosen balance between combinatorial volume and a deliberately written story.
The content target is approximately ten reviewed StoryPacks per archetype and
approximately ten mechanically distinct archetypes; this is a long-term
content scale, not a requirement for the first compiler slice.

### EvidenceModule

An evidence module is one reusable gameplay primitive such as source dialogue,
document in a container, witness testimony, looted item or overheard dialogue.
It declares required capabilities, placement, facts revealed, prerequisites,
one-shot confidence and journal feedback.

The boundary is intentional: CaseArchetype defines which thread grammar and
module kinds are legal, StoryPack arranges concrete story threads and authored
assets, and EvidenceModule implements the in-game action that discovers one
piece of evidence. StoryPack never owns KCD2 GUIDs or native XML wiring, while
EvidenceModule never owns the case lore.

## Typed bindings and identity

Slots are resolved to concrete entities before native files are emitted:

```text
{{settlement.displayName}}
{{witness.displayLabel}}
{{witness.directionLabel}}
{{evidenceContainer.locationHint}}
```

Identity has three modes:

- `named`: use the verified localized character name;
- `titled`: use a unique verified role or title;
- `anonymous`: never invent a name; describe profession, workplace and story
  function, then bind the interaction and later marker to the concrete GUID.

The compiler rejects `{{actor.name}}` when the bound actor is anonymous. For an
anonymous Zhelejov worker, valid direction copy is closer to "Question the
farmhand who tends the horses at the inn" than an invented personal name.

Static dialogue may mention a runtime-selected victim only when CaseCompiler
materializes a variant for that concrete target. Otherwise authored copy must
use a generic reference until the native target marker is revealed.

## Compatibility solver

For every `archetype x story x settlement` combination, the solver:

1. resolves required semantic slots from the world index and profile;
2. excludes dead, forbidden, story-critical or otherwise invalid actors;
3. prevents one entity from filling conflicting slots;
4. verifies that every clue can be placed and every interaction can run;
5. proves at least one route reaches confidence 70;
6. validates all typed variables and bilingual localization;
7. emits a compatible variant or a precise rejection reason.

The first version is strict: if a required role is absent, that combination is
not generated. Later archetypes may declare coherent fallback modules, such as
guard testimony instead of merchant testimony. Missing capabilities never
cause runtime improvisation.

To control combinatorial growth, the compiler ranks deterministic bindings and
emits a configurable maximum number of variants per
`archetype x story x settlement` combination.

## Materialization

Each accepted binding becomes an immutable `CaseVariant` containing:

```text
caseId + variantId + archetypeId + storyId
region + settlement + concrete target/source/place bindings
evidence graph + confidence values + presentation revisions
native aliases + stable numeric codes + localization keys
```

CaseCompiler adapts that variant into the already proven outputs:

- Lua case catalog;
- regional quest states and objectives;
- FaderDialog and ambient dialogue XML;
- Storm roles and ScriptContexts;
- item rows and document content;
- Russian and English localization;
- compatibility and rejection reports.

Generated files are disposable and never edited manually. Existing enum names,
aliases and numeric codes remain save schema.

## Runtime contract

When hunger opens a case, Lua filters compiled variants by current region,
settlement, target eligibility and anti-repeat policy. It persists the complete
snapshot before exposing an area, clue or dialogue.

Save/load, Lua reload, streaming and player movement never reroll the selected
variant or its concrete bindings. A missing streamed entity retries resolution;
it does not silently replace the authored source.

## Player feedback

Hidden confidence remains hidden, but accepted evidence must feel visible.
Each discovery transaction produces exactly one native journal revision and
its normal center-screen sound/banner, unless the interaction already caused
that same revision. Completed clue lines remain as a concise investigation
history while one active direction tells the player what can be pursued next.

Optional Henry reactions are presentation only and never control evidence
state.

## Repository boundary

The initial module lives under `casekit/` with its own source, schemas, tests
and README. Dark Passenger content and runtime consume its public ports and
outputs:

```text
casekit/                 reusable toolchain
  core/                  pure validation, binding and variant model
  adapters/              KCD2 inputs and native artifact emitters
  cli/                   build entry points
content/archetypes/      Dark Passenger gameplay templates
content/stories/         Dark Passenger authored narratives
config/settlements/      reviewed semantic overrides
build/generated/cases/   disposable materialized variants
```

The current `tools/CaseSpecCompiler.psm1` remains the proven native backend
during migration. CaseKit first produces normalized CaseVariants for it; only
after parity is proven may native emitters move behind the CaseKit boundary.

## Extraction criteria

CaseKit becomes a separate published tool only after all are true:

- at least three mechanically distinct archetypes compile;
- both KCD2 regions and several differently equipped settlements pass;
- at least one anonymous and one named identity path are live-proven;
- generated Pritoky and Zhelejov cases preserve current behavior and saves;
- the module has no Dark Passenger runtime or localization dependency;
- its README documents authoring, diagnostics and generated artifacts.

Until then, keeping it in the mod repository makes iteration and compatibility
changes cheap.

## Delivery order

1. Build the reusable semantic world index and identity resolver.
2. Replace per-case bindings with central Pritoky and Zhelejov profiles.
3. Add typed archetype, story and evidence-module contracts.
4. Implement the compatibility solver and rejection report.
5. Materialize finite CaseVariants into the existing compiler backend.
6. Migrate both current cases without changing generated native behavior.
7. Add several archetypes and settlement combinations.
8. Reassess standalone KCD2 CaseKit publication.

## Non-goals

- Uncontrolled runtime prose generation.
- Arbitrary runtime quest or dialogue graph mutation.
- Hand-authoring every NPC in both regions.
- Publishing a stable external SDK before multi-archetype proof.
- Replacing live-proven native emitters during the first migration step.

## Unresolved questions

- Final public name: CaseKit, CaseBuilder or another name.
- Variant cap and ranking weights require real content-volume data.
- Exact profession capability sources beyond faction and work links need a
  focused world-data audit.
