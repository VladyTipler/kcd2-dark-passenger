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

The retail `Scripts.pak` provides a stronger distinction:

- `handleStimulusMurder.xml` creates `information` labelled `murder`, writes
  the victim, calls `Function_crime_addEyeWitness` for `$this.id`, and
  propagates both `crime_stimulusKind.murder` and
  `$stimulus.freshlyAttributedCrime`;
- `handleStimulusCorpse.xml` uses `crime_stimulusKind.corpse`, propagates
  `freshlyAttributedCrime=false`, and never calls
  `Function_crime_addEyeWitness`;
- `interrupt_report.xml` enables `crime_interruptReport_reporting` only while
  information is transferred to the destination, then reaches
  `crimeCheckpoint_crimeReportedToGuard`.

This proves that the native murder and corpse handlers are separate. It does
not prove that every call to `handleStimulusMurder` is direct perception:
other awareness handlers can reconstruct murder information after discovery
or information transfer. The exact source fields remain local to AI behavior
and are not exposed by `GetBrainVariable`.

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

A second hands-free replay separated report intent from report completion:

- `kpri_woman_18`, Soul/WUID `05000000000007A2`, entered
  `crime_interruptReport=true` while running to `kpri_man_11`;
- immediately before her report bark and information transfer she entered
  `crime_interruptReport_reporting=true`;
- after the transfer, `crime_interruptReport_reporting` returned to false;
- the guard then started dialogue with Henry.

The rising edge of `crime_interruptReport_reporting` is therefore accepted as
the irreversible report handoff for that specific reporter. The broader
`crime_interruptReport` phase is accepted only as reversible report intent.

The target itself briefly had broad crime reaction state, but became dead
before witness registration. Therefore an alive filter removes the victim
without special-casing the selected target.

Brain variables had already cleared by the time a manual query ran after the
report. The watcher now reads brain state only while an NPC has
`crime_interruptReport=true`; calm NPCs remain skipped.

Even during the active report interrupt, `GetBrainVariable` returned `nil` for
`stimulusKind`, `freshlyAttributedCrime`, `information`, `reportDestination`,
and the other candidate names. They are local variables of nested behavior
trees, not exported brain variables.

`interrupt_report.xml` creates a temporary `crime_reportSource` link from the
report destination to the reporter. The link is removed after the report
interrupt finishes; a query during the subsequent guard dialogue correctly
returned zero links. This is useful as a live transition probe, not as durable
state.

### Rejected native murder hook

A diagnostic hook placed immediately after
`Function_crime_addEyeWitness` produced one event:

- witness reported by the hook: guard `kpri_man_11`,
  Soul/WUID `05000000000005D8`;
- victim: active target `kpri_man_35`;
- time: after `kpri_woman_18` had transferred assault information to the
  guard;
- distance from the corpse: about 49 metres.

The reporter herself did not reach that hook because the murder handler exits
early for recognition levels I and II. Base-game caller inspection also found
that `handleStimulusMurder` is invoked from hit-volume, corpse, carried-body,
held-body, hot-entity, and queued-stimulus paths.

Therefore `Function_crime_addEyeWitness` is not a safe direct-perception
boundary for the mod. The diagnostic AI override is rejected and removed.

## Matrix

| Scenario | NPC identity stable | Reaction delta | Henry link | Report/alarm | Save/load | False positive | Accepted predicate |
|---|---|---|---|---|---|---|---|
| Unseen kill; uninvolved NPC nearby | pending | pending | pending | pending | n/a | pending | pending |
| NPC discovers corpse only | stable reporter WUID confirmed in replay | report intent can start after discovery or a related assault | direct Henry attribution remains unavailable | exact report handoff captured | n/a | must not label as direct eyewitness | report intent/report only |
| NPC directly sees stealth kill | two stable Soul/WUIDs confirmed | both entered `crime_interruptReport` | attribution brain fields unavailable | two completed murder-report chains; guard response confirmed | pending | `addEyeWitness` hook also fired for a downstream guard | report intent/report accepted; direct-eyewitness subtype pending |
| Public melee kill and guard alarm | assault witness/guard identities confirmed | `crime_interrupt`, `crime_preventDespawn` are broad | victim/guard have crime links after report | native report chain confirmed | pending | broad reaction contexts include non-witnesses | reporter context only |
| Witness lives long enough to report | stable reporter WUID confirmed | `crime_interruptReport` then reporting edge | n/a | `crime_interruptReport_reporting` exact handoff | pending | 500 ms watcher captured the short edge | accepted |
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

## Current root-cause conclusion

Polling broad contexts cannot reconstruct direct eyewitness attribution. The
game stores the decisive murder/corpse/source distinction inside
behavior-local `stimulus` and `information` values, and the public Lua
brain-variable binding does not expose them.

The evidence-backed production slice is narrower:

1. during `SILENCE_CHECK` and `CLEANUP`, scan only loaded living NPCs inside
   the aftermath zone;
2. a rising `crime_interruptReport` registers that NPC as an unreported,
   reversible witness/reporting actor;
3. a rising `crime_interruptReport_reporting` for that NPC marks the report
   irreversible and locks the Case noisy;
4. persist identity as the two 32-bit halves of the stable Soul/WUID;
5. keep direct-eyewitness subtype disabled until a source-specific signal is
   proven.
