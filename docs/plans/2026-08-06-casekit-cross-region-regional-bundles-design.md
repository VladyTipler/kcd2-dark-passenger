# CaseKit Cross-Region Regional Bundles Design

**Date:** 2026-08-06

## Goal

Every StoryPack is evaluated against every compatible settlement in both game
regions. Runtime selects the nearest compatible settlement and a playable story.
The KCD2 backend still emits exactly one native quest container per region.

## Rejected approaches

1. **Pin each StoryPack to one region.** Simple, but contradicts semantic
   compatibility and wastes reusable content.
2. **Create one quest graph per StoryPack and region.** Causes quest/container
   duplication, save-state collisions and violates the universal-container
   contract.
3. **Recommended: story modules inside regional bundles.** One logical CaseSpec
   per StoryPack, concrete bindings for every compatible settlement, one
   story-qualified native module per supported region and one merged quest shell
   per region.

## Contracts

- Compatibility has no hidden adapter region filter. Only authored coverage and
  semantic requirements may reject a region or settlement.
- `caseSpecs` contains one entry per StoryPack and unique `caseCode`.
- `bindings` remains keyed by `caseCode + region + settlement` and contains exact
  covered variant IDs.
- Adapter metadata separates physical regional shells from story content:
  `nativeRegions` owns quest name/folder; `stories[].native` owns dialogues,
  evidence scenes and presentation.
- `legacyVariant` becomes migration-only `migrationAnchor`; it never filters
  compatibility.
- The native compiler creates story-qualified node/type/asset names and an
  active-case gate, then merges all story modules into one regional wiring.
- Runtime catalog resolves CaseSpec by `caseCode`, binding by exact region and
  settlement, and marks a variant native-ready only when its regional module and
  binding both exist.

## Data flow

```text
StoryPack deck + complete world index
  -> semantic compatibility across both regions
  -> one logical CaseSpec per story
  -> scoped settlement bindings in both regions
  -> story x region native modules
  -> one merged dark_within_k / dark_within_t bundle
  -> runtime selects story + settlement + target
  -> selected case signal enables only that story module
```

## Safety

- Fail build on duplicate case codes, regional shell definitions, dialogue files,
  graph types, generated node names or objective assets.
- Preserve stable case/evidence/variant IDs; cross-region variants are additive.
- Keep profile metadata optional and authoritative only as a concrete binding
  override.
- Keep one fallback generic shell presentation only when a region has no native
  story module; playable native variants always use StoryPack-owned copy.

## Tests

- Core RED: one StoryPack materializes compatible variants in both regions.
- Backend RED: two logical CaseSpecs remain unique while bindings cover both
  regions.
- Native RED: two StoryPacks in one region produce one regional manifest entry,
  unique story modules and active-case gating.
- Integration RED: authored world-to-quest build produces cross-region
  `native_ready` variants and exactly one `dark_within_*` graph per region.

## Unresolved questions

None.
