# Dark Passenger Permanent Settlement Investigation Areas Design

## Goal

Replace the narrow vanilla Pritoky search area with one permanent irregular
area that represents Pritoky and its surroundings. The pilot must include the
village, inn, deserter camp, outlying homes, and every enabled victim while
preserving the proven investigation flow:

```text
search area -> persistent hidden confidence -> threshold 70
            -> quest objective transition -> native target marker
```

After live proof, the same build-time mechanism can generate one stable area
for every supported settlement in Kuttenberg and Trosky.

## Decision

Use a hybrid build-time system:

- generate a deterministic baseline polygon from settlement residents and
  explicitly associated points of interest;
- add a configurable outward margin, initially about 100 metres;
- simplify and shape the boundary into an irregular 10-20 vertex polygon;
- allow a settlement-specific manual polygon or point override;
- reject invalid generated output before packaging or deployment.

Each settlement owns one permanent area. Cases change their victim, clues, and
complications, but never regenerate the settlement boundary at runtime.

## Source of truth

`config/investigation-areas.json` is the single authored source of truth for
area policy. It records:

- settlement and game-region identifiers;
- stable area alias and deterministic identifier seed;
- default padding and simplification limits;
- explicitly associated POIs such as inns, camps, mills, executioners, and
  isolated homes;
- optional include/exclude anchors;
- optional manual polygon override;
- review status for generated outliers.

Resident coordinates come from the existing generated victim catalogue. The
area config references that catalogue instead of duplicating NPC positions.

## Pritoky pilot anchors

The Pritoky baseline uses:

- all enabled Pritoky resident candidates;
- the village core;
- the Pritoky inn;
- the deserter camp containing valid Pritoky targets;
- outlying homes or social POIs assigned to Pritoky.

The resulting area includes the traversable space between these anchors. It is
settlement-centric, not centred on the selected victim.

## Polygon generation

The generator performs these deterministic stages:

1. load resident positions and explicit POI anchors;
2. reject missing, duplicate, or non-finite coordinates;
3. build an enclosing boundary around the anchors;
4. expand it by the configured settlement margin;
5. add bounded deterministic irregularity so the border is not a perfect
   circle or mechanical rectangle;
6. simplify it to the configured vertex range without excluding anchors;
7. apply a manual override when the settlement policy requires one;
8. emit the world-asset descriptor and validation manifest.

The implementation may change the exact geometry algorithm after fixtures are
tested. The stable contract is deterministic containment, irregular visual
shape, configurable padding, and manual correction without duplicated data.

## World and quest integration

The quest keeps the proven alias `DP_PritokySearchArea`. Lua investigation
state, confidence persistence, reveal buff, quest progression, and target
marker generation remain unchanged.

The first world-asset candidate is an irregular `SmartAreaShape` based on the
vanilla polygon schema. Its support by the native quest marker resolver is not
yet proven. The build attaches the generated area through the existing chain:

```text
Barbora.kutnohorsko quest module
  -> vanilla Kuttenberg LevelHolder
  -> Dark Passenger quest holder
  -> asset['DP_PritokySearchArea']
  -> generated Pritoky area entity
```

If `SmartAreaShape` does not render as a quest marker, only the emitted
world-entity type and schema change. The alias, quest XML, Lua state, and save
contract remain stable. A circular fallback is not accepted without a separate
design decision.

## Validation and failure handling

The build fails closed when:

- the polygon has fewer than 3 or more than the configured maximum vertices;
- edges self-intersect or winding is invalid;
- an enabled victim or required POI is outside the padded polygon;
- aliases, entity IDs, or GUIDs collide;
- repeated generation produces different output;
- width, height, or area crosses a reviewed anomaly threshold;
- the generated world entity cannot be merged into the regional level data.

Failure leaves the previous deployed build untouched. Runtime code does not
silently substitute the exact victim marker or select another victim when an
area asset is missing.

## Testing

Pure geometry tests are written before the generator implementation. Fixtures
cover containment, deterministic output, padding, simplification, winding,
self-intersection rejection, and manual overrides.

The integration test crosses the build boundary and verifies that the real
generated Pritoky asset, regional level merge, waiting links, alias, entity ID,
GUID, and quest reference agree. It also verifies that the established
confidence and target-marker XML remains unchanged.

## Live acceptance

The Pritoky pilot succeeds only when a cold dev-build cycle proves:

1. the investigation starts with one visibly irregular search area;
2. the village, inn, deserter camp, outlying anchors, and selected target are
   inside the displayed area;
3. save/load below 70 preserves the same area, target, and confidence;
4. crossing confidence 70 completes the area objective once;
5. the area disappears and the exact selected NPC marker appears with the
   native objective presentation and sound;
6. no fresh marker-resolution or world-link error appears in `kcd.log`.

The first screenshot is a tuning checkpoint. Padding and manual Pritoky points
may be adjusted without changing the architecture.

## Scope

Included:

- Pritoky irregular-area generation and live proof;
- one SSOT area-policy file;
- geometry and integration tests;
- a reusable build output shape for later settlements;
- manual override support.

Excluded:

- generated areas for every settlement;
- authored rumors, letters, clues, or dialogue;
- runtime-generated or target-centred area boundaries;
- confidence or quest-flow changes;
- automatic road, terrain, or navmesh-aware contour routing.
