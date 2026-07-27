# Regional Victim Marker Implementation

## Completed

- [x] Added hidden `dp_is_target` buff and AI tag `24`.
- [x] Extracted the Pritoky Soul IDs from retail `Tables.pak`.
- [x] Registered a compact 42-Soul regional pool.
- [x] Added persistent random victim index and typed Soul switch.
- [x] Applied the target tag from the quest graph.
- [x] Resolved the tagged Soul by iterating only the selected region pool.
- [x] Bound `ShowMapMarker` and `SoulDeathTrigger`.
- [x] Wired target death to objective completion and satisfaction.
- [x] Added target-tag cleanup.
- [x] Kept a Lua `dp_target_select` diagnostic fallback.
- [x] Passed XML parsing and 92 structural checks.
- [x] Rebuilt a ZIP-compatible pak without NTFS metadata.
- [x] Backed up and deployed the mod to retail.

## Retail verification

1. Load a save where the hunt is not already active.
2. Stand in Pritoky.
3. Remove/wait out `Тишина внутри`.
4. Wait for the delayed quest-start banner.
5. Confirm a Pritoky NPC receives a map/compass marker.
6. Kill that NPC by any method.
7. Confirm objective and quest completion.
8. Confirm the marker disappears.
9. Confirm `Тишина внутри` appears.

If automatic selection fails, run `dp_target_select` only as a diagnostic. It
uses the same hidden target buff but is not required by the automatic path.

## Unresolved

- Retail acceptance of pointer state and dynamic marker input.
- Dead/essential NPC filtering.
- Exact final marker style.
- Multi-region selection and investigation-area phase.

