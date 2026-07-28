# Witness Probe Matrix — 2026-07-29

## Purpose

Find a conservative KCD2 runtime predicate for a specific NPC who witnessed
Henry's involvement, and a separate predicate for a completed report.

Proximity, line of sight, corpse discovery, and unrelated hostility are not
accepted on their own.

## Static reference findings

The extracted game AI used by the Temptation reference contains:

- `amIWitness`;
- `reportDestination` and `reportDestinationType`;
- `crime_interruptReport`;
- `crime_disableReport`;
- `crime_stimulusKind.corpse`;
- `crime_reactionType.reportNonattributedCrime`;
- `Function_callInterrupt_report`;
- `freshlyAttributedCrime`, `reportedBy`, and `criminalFreshness`.

These names justify read-only probing only. They are not yet proven Lua
bindings or production signals.

## Commands

```text
dp_witness_probe_arm 50
dp_witness_probe_sample 50
dp_witness_probe_clear
dp_aftermath_probe_crime 50
```

Arm immediately before the incident. Sample after each visible AI transition
and again after any guard/alarm response.

## Matrix

| Scenario | NPC identity stable | Reaction delta | Henry link | Report/alarm | Save/load | False positive | Accepted predicate |
|---|---|---|---|---|---|---|---|
| Unseen kill; uninvolved NPC nearby | pending | pending | pending | pending | n/a | pending | pending |
| NPC discovers corpse only | pending | pending | pending | pending | n/a | pending | pending |
| NPC directly sees stealth kill | pending | pending | pending | pending | pending | pending | pending |
| Public melee kill and guard alarm | pending | pending | pending | pending | pending | pending | pending |
| Witness lives long enough to report | pending | pending | pending | pending | pending | pending | pending |
| Witness dies before report | pending | pending | pending | pending | pending | pending | pending |
| Save/load between reaction and report | pending | pending | pending | pending | pending | pending | pending |

## Acceptance gate

A production witness predicate must:

1. identify one stable NPC;
2. appear for direct witnessing or reporting;
3. remain absent for proximity-only and corpse-discovery-only cases;
4. distinguish a reversible unreported witness from irreversible report/alarm;
5. survive save/load or have a bounded recovery fallback.

If no per-NPC predicate passes, production witness registration stays disabled.
Only separately proven global alarm/report state may lock a Case as noisy.
