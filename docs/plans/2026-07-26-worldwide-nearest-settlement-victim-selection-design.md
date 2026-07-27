# Worldwide Nearest-Settlement Victim Selection Design

## Goal

Select one safe random victim from the settlement nearest to Henry anywhere in
Kuttenberg or Trosky, while preserving the native tracked quest objective and
NPC marker already proven in retail.

## Confirmed constraints

- Runtime Lua sees loaded entities, not a trustworthy complete world roster.
- Native quest markers still require generated static `SoulAsset` aliases and
  marker states.
- `EntityGuid` waiting links exposed by Asset Linker bind entities to the
  regional `LevelHolder`; they do not populate a custom quest `SoulAsset`.
- A native marker therefore requires the full persistent SharedSoul GUID in
  the generated quest XML.
- Lua can choose a loaded eligible NPC and apply the hidden `dp_is_target`
  buff.
- The quest graph can detect that tag, activate the matching generated marker
  state, and persist the objective.
- `PlayerEventDispatcher` is a required runtime dependency for lifecycle
  events. Kill attribution may be recorded as optional metadata, but no longer
  gates completion.

## Chosen architecture

Keep the hybrid generated architecture:

1. Extract persistent NPC and settlement data at build time.
2. Produce one safety-reviewed world catalogue as the single source of truth.
3. Generate Lua candidate data and regional quest XML from that catalogue.
4. Let Lua choose the nearest settlement and weighted random eligible victim.
5. Let the regional quest graph own the journal state and native marker.

Runtime discovery alone is rejected because streaming exposes only loaded
entities and cannot safely classify every NPC. Pure handwritten XML is rejected
because it duplicates hundreds of aliases and selection branches.

## World catalogue

Evolve `config/victim-candidates.json` to schema version 2:

- regions: `kutnohorsko`, `trosecko`;
- settlements with stable id, display name, region, and center coordinates;
- persistent candidates referencing one settlement;
- Soul GUID, entity name, generated alias, tags, weight, and source evidence;
- safety flags for story critical, quest critical, immortal, temporary, dead,
  and manually excluded;
- residency and quest-risk fields distinguishing permanent residents,
  main-story actors, and side-quest actors;
- optional narrative metadata: occupation, faction, social class, shop,
  hobbies, rumor and evidence archetypes.

This file remains the only authored selection source. Generated Lua and quest
XML are never edited manually.

## Extraction pipeline

The authoritative static entity sources are:

- `InternalData/kutnohorsko/kut_objects_mission0.xml`;
- `InternalData/trosecko/tros_objects_mission0.xml`.

The extractor combines their persistent entity, SharedSoul, position, home,
schedule, role, archetype, and quest-reference data with:

- quest references used to identify story and quest dependencies;
- role, archetype, faction, shop, hobby, and immortality metadata where
  available.

Dev runtime API probes validate bindings and representative records but do not
serve as the complete roster source.

The raw extractor output is diagnostic. Only safety-reviewed candidates enter
the shipping catalogue. Unknown safety data means excluded by default.

## Runtime selection

1. The active regional quest exposes a victim-selection request.
2. Lua identifies the requesting region.
3. Lua reads Henry's world position.
4. Settlement centers in that region are sorted by planar distance.
5. The nearest settlement with at least one catalogue-eligible permanent
   resident is fixed for the case.
6. Lua resolves candidates from that settlement and applies runtime filters:
   entity exists, Soul exists, alive, not Henry, not already assigned.
7. Weighted random selection chooses one candidate.
8. Lua removes any previous target tag and applies `dp_is_target` to the winner.
9. Generated XML detects the tagged static alias and activates its marker state.

If the chosen settlement's candidates are temporarily unloaded, the settlement
remains fixed and selection retries are bounded and delayed. This is acceptable
for the final investigation loop because the settlement search area appears
before the personal marker. During the current direct-marker test, the first
objective remains active until a candidate becomes resolvable.

If a settlement has no safe candidates in the shipping catalogue, selection
falls through to the next-nearest eligible settlement.

## Case state and future regional split

Represent state as:

```text
cases[region] = {
  settlement,
  target,
  status
}
```

The first release policy permits one active case globally. The data model and
generated graphs remain region-indexed, so a later policy can allow one
independent active case per region without replacing the catalogue or selector.

Once selected, the victim and settlement remain fixed until the case resolves
or the victim becomes invalid before selection is committed. Any death of the
committed target resolves the case and grants satisfaction. Travelling to
another region does not silently replace the active target.

## Safety rules

Every candidate must be:

- persistent and addressable by stable Soul GUID;
- classified as a permanent resident of the selected settlement;
- explicitly verified killable;
- not main-story critical;
- not immortal, temporary, already dead, or manually excluded;
- alive and resolvable at final runtime selection;
- not Henry and not assigned to another unresolved case.

Side-quest participation is recorded as a risk flag, not an automatic
exclusion. The policy catalogue may enable such residents deliberately to
create unexpected consequences. Unknown main-story relevance remains excluded
by default.

A selected target's death always closes the Case so it cannot become stuck.
Henry-attributed deaths grant satisfaction; external deaths close the Case
without resetting hunger and permit a later target request. Because indirect
kill attribution is not yet proven reliable, production keeps the
retail-confirmed any-death fallback until attribution passes runtime probes.
The full aftermath policy is defined in
`2026-07-27-hunt-cleanliness-and-aftermath-design.md`.

## Scaling strategy

Do not jump directly from three candidates to the whole game:

1. Expand Pritoky to a complete resident pool with explicit story exclusions
   and side-quest risk flags.
2. Add several Kuttenberg settlements and validate nearest-center selection.
3. Generate all Kuttenberg settlements.
4. Add Trosky and generate its regional graph.
5. Run archive-size and graph-load tests before enabling every candidate.

This exposes graph-size or load-time limits before the catalogue becomes large.

## Testing

Automated checks must cover:

- schema validation and unique region/settlement/candidate identifiers;
- every candidate references an existing settlement;
- deterministic extraction and generation;
- every enabled candidate has exactly one regional Soul alias and marker state;
- no candidate appears in the wrong regional graph;
- nearest-settlement calculation for representative coordinates;
- fallback to the next eligible settlement;
- fixed case settlement across later player movement;
- static and runtime safety filters;
- bounded retry for unloaded candidates;
- one globally active case despite region-indexed state;
- required `PlayerEventDispatcher` dependency documented and deployed.

Retail acceptance must cover both regions, boundary positions between
settlements, distant wilderness, save/reload persistence, dead candidates,
non-target deaths, selected-target deaths by multiple causes, and clean
selection after the satisfaction buff expires.

## Unresolved questions

- Authoritative settlement centers or boundaries for both regions.
- Reliable build-time fields for main-story relevance and immortality.
- Which side-quest residents should be enabled by default.
- Practical generated graph-size limit before regional subdivision is needed.
