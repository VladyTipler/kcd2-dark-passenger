# Metadata-Aware Victim Selection Design

## Goal

Select a living, killable, non-quest NPC with Lua, then expose that runtime
choice through a native tracked quest objective and marker.

The selector must later support evidence and rumor content derived from NPC
metadata such as settlement, occupation, faction, shop ownership, social
importance, and prior case history.

## Confirmed engine constraints

- A tracked objective marker is declared statically on an `EnumLog`:
  `Marker="<asset alias>"`.
- The marker attribute cannot evaluate Lua or accept a runtime Soul pointer.
- One objective may have multiple `Started` enum states, each with a different
  marker. Vanilla uses this pattern for objectives whose destination changes.
- Lua can choose and tag a loaded NPC.
- A hidden buff tag is a working Lua-to-quest-graph signal.

## Architecture

Use a hybrid selection system:

1. A build-time generator reads one candidate catalogue.
2. It produces the Lua candidate data and generated quest XML.
3. Lua acts as the policy and metadata layer.
4. Quest XML acts as the lifecycle, journal, marker, and completion layer.

The candidate catalogue is the single source of truth. Generated Lua and XML
must not be edited manually.

## Candidate catalogue

Each candidate record contains at least:

- stable slot id;
- game region (`kutnohorsko` or `trosecko`);
- settlement/pool id;
- quest alias;
- Soul GUID;
- internal entity name;
- content tags;
- selection weight;
- safety flags and optional exclusion reason.

Future metadata may include gender, faction, superfaction, occupation, shop,
social importance, evidence archetypes, rumor sources, and case history.

The generator partitions the catalogue by game region and settlement. It
creates one region-level quest graph for Kuttenberg and one for Trosky.
Settlement groups are generated data, not separately hand-written quests.

## Generated quest representation

For every candidate slot, the generator emits:

- a static `SoulAsset`;
- a target objective enum state such as `Target017`;
- an `EnumLog Type="Started"` whose marker points at that Soul alias;
- a fixed-alias `BuffTagCheck` branch that recognizes `dp_is_target`;
- a transition to `SetTarget017`;
- a fixed-alias death/validity branch where required.

All target states share the same localized journal text. Only their marker
alias differs.

## Runtime flow

1. The hunt lifecycle requests victim selection for the current settlement.
2. Lua builds a candidate set from the matching catalogue pool.
3. Lua applies hard safety filters.
4. Lua scores the remaining candidates and performs weighted random selection.
5. Lua applies the hidden `dp_is_target` buff to the winner.
6. The quest graph checks generated static aliases.
7. The matching branch transitions the objective to `TargetNNN`.
8. The native quest system displays the marker on the selected Soul.
9. The target's death is attributed and handled by the case lifecycle.

Initial weighting should prefer narratively useful occupations while keeping
ordinary residents possible. Example baseline: bailiff 5, innkeeper 4,
craftsman 2, commoner 1.

## Safety invariants

A candidate is eligible only if all of these are true:

- belongs to the selected region and settlement pool;
- not the player;
- not story-critical or quest-critical;
- not immortal or otherwise unkillable;
- exists, has a Soul, and is currently alive;
- is not already assigned to an unresolved Dark Passenger case;
- is not excluded by catalogue overrides.

The graph revalidates life state before activating the marker. A failed
validation clears the target tag and requests another selection.

Selection retries are bounded. If no eligible victim exists, the case remains
inactive and retries later instead of exposing an invalid objective.

If another actor kills the revealed victim, Henry receives no satisfaction.
The invalid case is cleared and a replacement victim is selected.

## Metadata strategy

Metadata support is incremental:

1. Use currently verified runtime fields: entity identity, display name,
   position, Soul presence, and death state.
2. Probe dev-build Lua bindings for faction, role, gender, shop, hobby,
   superfaction, and immortality.
3. Where runtime bindings are absent, extract stable metadata from game data at
   build time and store it in the candidate catalogue.
4. Allow small manual overrides for safety and narrative classification.

Unknown metadata must not make a candidate unsafe. Missing safety information
excludes the candidate until verified.

## First proof of concept

Generate three safe Pritoky candidates:

- Lua selects one candidate and applies `dp_is_target`;
- XML resolves the corresponding fixed alias;
- one objective switches between `Target001`, `Target002`, and `Target003`;
- the native marker follows the selected NPC;
- already-dead candidates are skipped;
- killing the selected NPC completes the test lifecycle;
- killing a different candidate does not complete it.

After this proof, expand to the full Pritoky catalogue, then generate the
remaining settlements for both game regions.

## Testing

Automated checks must verify:

- generated Lua and XML both derive from the same catalogue;
- every candidate slot has exactly one Soul alias and marker state;
- no marker references a missing alias;
- every marker state has a matching target-detection branch;
- duplicate slots, GUIDs, and aliases fail the build;
- excluded candidates never appear in the runtime selection table;
- archives contain compatible ZIP metadata and valid XML.

Retail acceptance checks:

1. Three restarts produce more than one possible marked NPC.
2. The marked NPC matches the Lua selection log.
3. A dead candidate is never selected.
4. Killing a non-target changes nothing.
5. Killing the target completes the objective and grants satisfaction.
6. A target killed by another actor grants no satisfaction and is replaced.

