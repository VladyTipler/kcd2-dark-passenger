# Innkeeper Rumor Evidence Vertical Slice

**Date:** 2026-08-02  
**Status:** approved  
**Scope:** first real, repeatable evidence interaction for Dark Passenger

## Goal

Let Henry obtain the first lead for an active Pritoky case by asking the local
innkeeper about rumors. The interaction awards 30 hidden confidence exactly
once per case generation, creates a native journal update, survives save/load,
and keeps new rumor copy hot-reloadable.

## Player flow

1. Hunger starts the hunt and the case selects Pritoky plus a hidden victim.
2. The search objective tells Henry to investigate the settlement.
3. `kpri_innkeeper` exposes **Ask about local rumors** while the matching case
   is active and its first rumor is still unknown.
4. The action displays one short lore rumor from the Lua content catalogue.
5. The rumor awards `+30` confidence and emits a generic first-lead signal.
6. The quest graph records a native journal update without revealing the
   victim. Repeating the action or reloading the save cannot award it again.

The first source is public by design. Target inventory, private letters and
victim belongings are later corroborating evidence, never the blind entry
point that would force the player to rob every resident.

## Architecture

### Hot-reloadable content

`dpevidence.lua` owns the rumor catalogue and runtime state. Copy is ordinary
Lua data and is resolved when the action executes, not when the hook is
installed. Editing a line followed by:

```text
lua_reload_script Scripts/mods/dpevidence.lua
```

changes the next presentation without restarting the game. Stable interaction
labels and native journal copy may remain localization keys. New rumor variants
must not require new quest XML, tags or table rows.

### Shared contextual-action registry

Burial already wraps `NPC`, `NPC_Female` and `NPC_NAI.GetActions`. A second
independent wrapper would create reload-order bugs and wrapper chains. Introduce
one small `dpinteractions.lua` registry that owns the class wrappers and calls
named providers. Burial registers `burial`; evidence registers
`innkeeper_rumor`. Reload replaces a provider function in place and never
re-wraps the NPC classes.

### Source routing

The pilot uses the authoritative world identity `kpri_innkeeper`, which is
present in the Pritoky settlement layer and excluded from the victim pool.
Eligibility requires:

- active persistent investigation;
- active candidate settlement `kutnohorsko/pritoky`;
- living matching source entity;
- rumor not awarded for the current investigation generation.

Unsupported settlements expose no action and only produce diagnostic logs.
The later worldwide layer will generate an evidence-source catalogue from
innkeeper/editor-layer/faction metadata with explicit fallbacks.

The pilot uses the native secondary-action mapping `use_other` with
`AHT_RELEASE`, shown as a short **F** press. It must not reuse `talk`: the
vanilla dialogue already owns **E**, and sharing that mapping makes the two
actions visually ambiguous.

### Evidence and journal bridge

The action calls the existing authoritative
`DarkPassengerInvestigation.AddEvidence(30, "innkeeper_rumor", generation)`.
A new hidden player buff/tag is only a Lua-to-quest signal; it is not the source
of confidence truth. Both regional graphs listen for the same generic first-lead
signal and update a dedicated evidence objective/log while the settlement area
objective remains tracked.

Runtime persistence stores the awarded generation and signal-dispatched state.
Confidence is awarded before the journal signal. If journal dispatch is
temporarily impossible, restore retries only the signal and never confidence.

## Persistence and failure handling

- No active/matching case: action hidden.
- Source unloaded or dead: action unavailable; case remains valid.
- Evidence rejected or stale generation: no state is marked complete.
- Confidence accepted, signal failed: `awarded` remains true and
  `signalDispatched` remains false; restore retries dispatch.
- Save/load or Lua reload: compare stored generation, restore state and do not
  duplicate rewards.
- New case generation: the same innkeeper can provide a newly generated rumor.

## Scope limits

This slice does not add a full Skald dialogue, voice acting, dynamic prose in
the native journal, physical notes, container placement or all-settlement
source selection. The contextual action plus hot-reloadable text proves the
gameplay boundary first. Physical evidence follows on the same persistent
evidence contract.

## Verification

### Automated

- pure eligibility matrix: region, settlement, generation and awarded state;
- one-shot award and stale-generation rejection;
- accepted confidence followed by retryable journal dispatch;
- shared action registry remains single-installed across reloads;
- structural quest/buff/tag/localization checks in both regions;
- LuaCompiler and existing full suite.

### Live dev integration

1. Load the proven Pritoky save with an active investigation.
2. Confirm the action appears only on `kpri_innkeeper`.
3. Trigger it and verify rumor text, confidence `0 -> 30`, native journal update
   and no target reveal.
4. Trigger/reload again and verify confidence remains 30.
5. Edit the Lua rumor text, hot-reload only `dpevidence.lua`, start a fresh test
   generation and confirm the changed copy without restarting KCD2.

## References

- Temptation: runtime inventory creation and authored `Document` items.
- Mercenaries: inventory monitoring and timer-safe Lua runtime patterns.
- Dark Passenger burial: proven live contextual-action boundary.
- `KCD2 Modding - Technical Reference`: persistent investigation and
  buff-driven Lua-to-quest bridge.
