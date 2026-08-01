# Automatic Settlement Investigation Area Selection Design

## Goal

Generalize the live-proven Pritoky pilot into deterministic investigation
areas for every supported settlement in Kuttenberg and Trosky.

Pritoky remains the golden fixture: one journal objective resolves one marker
alias linked to the village, inn, and deserter-camp vanilla TriggerAreas.

## Constraints

- New TriggerArea geometry cannot ship safely without the official compiler
  pipeline that produces `areasmission0.bai`.
- The active build may reuse only already compiled vanilla TriggerAreas.
- One settlement may need several disconnected irregular map patches.
- The quest must still show one search objective for the selected settlement.
- Arbitrary technical, interior, audio, stealth, door, and oversized world
  triggers must never be selected merely because they contain an NPC point.
- The output must cover both game regions and remain deterministic.

## Source data

The generator joins four authoritative inputs:

1. `config/victim-candidates.json` for enabled victim slots, settlement and
   authored position.
2. `evidence/world-candidates.raw.json` for the original NPC EditorLayer.
3. Asset Linker `objects_mission0.xml` for TriggerArea name, short GUID,
   EntityId, position and EditorLayer.
4. Dev-build `Layers/**/*.lyr` for the real polygon `Points`, `Pos`, `Rotate`,
   `Scale`, height, label and full editor identity.

The layer polygon is converted into world XY coordinates by applying local
scale, Z rotation and translation. Geometry is validated before containment
checks.

## Generated area inventory

A build-time extractor creates one normalized record per usable vanilla area:

- game region;
- entity name, short GUID and EntityId;
- editor layer and label;
- world polygon, bounding box and surface area;
- semantic classification;
- settlements and candidate slots contained by the polygon.

The generated inventory is derived data. Manual policy lives only in
`config/investigation-area-overrides.json`, which is the single source for:

- forced primary areas;
- forced supplemental areas;
- denied areas or patterns;
- optional evidence POIs;
- explicit candidate exclusions when no safe coverage exists.

## Hybrid selection algorithm

### 1. Primary area

Each settlement receives one mandatory primary area. Selection preference:

1. manually forced primary area;
2. same-settlement `publicEnemiesRepulsionZone` containing the settlement
   center;
3. same-settlement outdoor area containing the center and the largest number
   of enabled candidates;
4. otherwise fail with a diagnostic requiring an override.

The primary area represents the social center even when every victim happens
to live in a satellite location.

### 2. Supplemental candidates

An area may supplement the primary area when it:

- contains at least one still-uncovered enabled candidate or approved evidence
  POI;
- has a valid compiled polygon;
- passes the map-area safety policy or is manually forced;
- is geographically plausible for the settlement.

Cross-layer quest or camp areas are allowed. This is required for cases such
as the Pritoky deserter camp. They receive a scoring penalty rather than a hard
ban because they can be legitimate homes, workplaces and evidence locations.

### 3. Weighted set cover

Starting with the primary area, the selector repeatedly adds the area with the
best deterministic score:

1. number of newly covered candidate and evidence anchors;
2. stable settlement/crime semantics;
3. smaller excess surface and distance from the settlement cluster;
4. lower quest/interior risk;
5. GUID lexical order as the final tie-breaker.

Selection stops when every required anchor is covered. The aim is the smallest
useful social investigation district, not every TriggerArea intersecting an
NPC position.

If an enabled candidate remains uncovered, generation fails and prints the
candidate, nearby rejected areas and rejection reasons. The build never
silently emits a broken marker. A maintainer must add a safe supplemental
override or explicitly exclude that candidate from the victim pool.

## Quest graph

The current fixed `DP_PritokySearchArea` marker is replaced with generated
settlement states.

Each regional quest receives:

- one `TriggerAreaAsset` per supported settlement;
- one `DP_SearchProgress` enum state per settlement;
- one search `EnumLog` per settlement with its own marker alias and localized
  copy;
- generated edges from every selected candidate slot to its settlement search
  state.

The existing hidden target tag already identifies the selected static
candidate. Therefore no new Lua-to-quest bridge is needed:

```text
Lua selects and tags candidate
  -> candidate BuffTagCheck becomes true
  -> selectedTarget stores the candidate slot
  -> searchProgress switches to the candidate's settlement state
  -> journal shows that settlement's multi-area marker
```

Target reveal still completes the search state and activates the existing NPC
marker objective. The player sees one search objective, not one row per area.

Kuttenberg and Trosky use the same generated investigation flow. Pritoky is no
longer hard-coded as the only search-area settlement.

## World links and runtime repair

For each settlement, every selected vanilla area is linked to the settlement
alias with the same `asset['...']` link name. Regional `waitinglinks.xml`
contains the complete static contract.

The generated Lua area catalogue groups identities by region and settlement.
After Lua selects or restores a case, the bridge repairs only the active
settlement's module and area links. Missing streamed entities are retried with
the existing bounded generation-safe polling pattern.

The shipping level pak remains minimal:

- merged `objects_mission0.xml` with quest-holder links;
- `waitinglinks.xml` with module and vanilla area links;
- no custom Layers, `whdata`, `leveldata.xml`, or generated TriggerArea.

## Evidence integration

Every selected polygon becomes an approved evidence territory. Future clue,
rumor and observation generators may choose authored POIs or safe positions
inside this union. Supplemental zones are therefore gameplay content space,
not marker-only exceptions.

Evidence placement is outside this implementation slice, but the area catalog
must preserve polygon and semantic metadata so the later system can reuse it
without another world scan.

## Localization

Settlement search states use generated stable localization keys. Display names
come from an explicit bilingual settlement-name table, not raw internal IDs.
Missing display text fails validation.

## Failure policy

- Invalid or self-intersecting polygon: reject area with reason.
- Missing layer or matching editor object: reject area with reason.
- No primary area: fail settlement generation and request override.
- Uncovered enabled candidate: fail generation and request override or explicit
  victim exclusion.
- Runtime optional area not yet streamed: retry without replacing the target.
- Restored active case: restore the same settlement state and links; never
  recompute nearest settlement until a new quest cycle.

## Test strategy

### Pure tests

- layer-local polygon transform including scale and quaternion Z rotation;
- point-in-polygon and boundary behavior;
- semantic filter and rejection reasons;
- deterministic weighted set-cover ordering;
- manual include/exclude precedence;
- stable aliases and localization keys.

### Feature tests

- every enabled candidate in both regions is covered by its selected union;
- every settlement has exactly one primary area;
- every emitted area exists in both mission objects and a parsed layer;
- no denied technical area is emitted without a force-include override;
- Pritoky golden result is exactly village + inn + deserter camp;
- generated quest maps every candidate slot to the correct settlement state;
- generated waiting links repeat the correct settlement alias for every area;
- level paks contain only the approved minimal files.

### Live acceptance

Test at least:

1. Pritoky as the golden regression;
2. one dense settlement such as Kuttenberg;
3. one sparse settlement requiring supplemental coverage;
4. one Trosky settlement;
5. save/load of an active case without area or target replacement.

For each case confirm the correct journal copy, irregular map union, transition
to the target marker, no marker-resolution errors and no crash.

## Out of scope

- Compiling original custom TriggerArea geometry.
- Evidence spawning and authored clue content.
- Replacing the current victim safety policy.
- Multiple simultaneously active regional cases.

## Unresolved questions

None for the design. Concrete safety thresholds and overrides are derived by
running the extractor across both regions and reviewing its diagnostics before
shipping the generated catalogue.
