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
dp_witness_probe_watch 30
dp_witness_probe_stop
dp_aftermath_probe_crime 50
```

Arm immediately before the incident. Sample after each visible AI transition
and again after any guard/alarm response.

`dp_witness_probe_watch` arms a baseline and samples context/link changes every
500 ms for 45 seconds. It skips noisy brain-variable reads.

## Live findings

### Public unarmed assault and completed guard report

- victim: `kmis_man_29`;
- direct witness: `kmis_injured`;
- guard accepting the report: `kmis_man_21`;
- native dialogue sequence:
  `SVEDEK_VIDI_JAK_NPC_DOSTALO_ZASAH_(UNARMED)` ->
  `SVEDEK_REPORTUJE_STRAZI_(ASSAULT__UNARMED)` ->
  `STRAZ_REAGUJE_NA_REPORT_(ASSAULT__UNARMED)`;
- victim independently emitted
  `OBET_REPORTUJE_STRAZI_(ASSAULT__UNARMED)`;
- later guard dialogue identified Henry as the wanted player.

The first link probe was invalid because it passed the runtime Entity ID to
`XGenAIModule.FindLinks`. Temptation and live entity inspection proved that the
binding requires the Soul/WUID (`entity.this.id`).

After correcting the ID:

- `kmis_injured`: `crime_npcCooldowns=1`, no remaining
  `crime_playerAwareness` after the completed report;
- `kmis_man_29`: `crime_anchor=1`, `crime_playerAwareness=1`,
  `crime_npcCooldowns=1`;
- `kmis_man_21`: `crime_anchor=1`, `crime_playerAwareness=1`,
  `crime_npcCooldowns=1`.

This post-report snapshot is not sufficient to recover the reporting witness:
the witness-specific awareness link has already cleared. The live watcher must
capture the reversible `crime_interruptReport` phase before the guard accepts
the report.

### Directly witnessed target murder

- target: `kpri_man_35`, killed by Henry with a stealth dagger;
- Dark Passenger aftermath began for slot `897`;
- direct witnesses:
  - `kpri_woman_18`, Soul/WUID `05000000000007A2`;
  - `kpri_woman_2`, Soul/WUID `05000000000010CC`;
- both witnesses transitioned to:
  `crime_interruptReport=true`, `crime_preventDespawn=true`,
  `crime_anchor=1`, `crime_playerAwareness=1`;
- both received native role
  `SVEDEK_VIDI_VRAZDU_SPOLUBYDLICIHO`;
- both later emitted `NPC_BEZI_HLASIT_(VRAZDA)`;
- `kpri_woman_18` completed `NPC_REPORTUJE_STRAZI_(VRAZDA)`;
- guard `kpri_man_11` accepted it through
  `STRAZ_REAGUJE_NA_REPORT_(VRAZDA)`.

The target itself briefly had broad crime reaction state, but became dead
before witness registration. Therefore an alive filter removes the victim
without special-casing the selected target.

Brain variables had already cleared by the time a manual query ran after the
report. The watcher now reads brain state only while an NPC has
`crime_interruptReport=true`; calm NPCs remain skipped.

## Matrix

| Scenario | NPC identity stable | Reaction delta | Henry link | Report/alarm | Save/load | False positive | Accepted predicate |
|---|---|---|---|---|---|---|---|
| Unseen kill; uninvolved NPC nearby | pending | pending | pending | pending | n/a | pending | pending |
| NPC discovers corpse only | pending | pending | pending | pending | n/a | pending | pending |
| NPC directly sees stealth kill | two stable Soul/WUIDs confirmed | both entered `crime_interruptReport` | both retained `crime_playerAwareness`; attribution brain sample pending | one completed murder report and guard accepted | pending | dead target filtered; corpse-only comparison pending | candidate: alive + active report + attributed brain state |
| Public melee kill and guard alarm | partial: assault witness/guard identities confirmed | `crime_interrupt`, `crime_preventDespawn` are broad | victim/guard have crime links after report | native report chain confirmed; Lua predicate pending | pending | broad reaction contexts include non-witnesses | pending live watcher capture |
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
