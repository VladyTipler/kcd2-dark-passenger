# Dark Passenger Hunt Cleanliness and Aftermath Design

## Goal

Preserve freedom in how Henry kills a selected victim while making the first
rule of the Code — do not get caught — mechanically meaningful.

Every hunger cycle remains a separate Case quest. Killing the selected victim
completes its main objective, but the Case itself resolves only after a short
silence check or cleanup phase.

## Design principles

- Poison, arrows, stealth, melee, duels, and indirect methods are all valid.
- The method never determines whether the Case succeeds.
- The system evaluates exposure and consequences, not adherence to one ritual.
- A Henry-attributed target death always resets hunger and grants base
  satisfaction.
- Clean execution extends satisfaction but is never required to continue the
  core loop.
- Extra deaths can protect Henry from immediate exposure while creating
  long-term consequences.
- Exact scores remain hidden and are communicated through journal text, buffs,
  rumors, and world reactions.

## Case lifecycle

```text
HUNTING
  -> target dies
  -> target-death attribution
     -> Henry-attributed: SILENCE_CHECK
     -> external death: EXTERNAL_RESOLUTION

SILENCE_CHECK
  -> 90 seconds pass without suspicion: CLEAN_RESOLUTION
  -> Henry leaves the encounter zone without suspicion: CLEAN_RESOLUTION
  -> suspicion event: cancel timer and enter CLEANUP

CLEANUP
  -> Henry leaves the encounter zone: evaluate exposure and resolve Case
```

The existing quest continues to represent one Case, not the Dark Passenger
condition as a whole. It therefore still completes after each hunt and may use
the native quest-complete presentation.

## Silence check

After a Henry-attributed target death:

1. Complete the target-kill objective.
2. Activate the objective `Не оставить следов.`
3. Start a 90-second active-gameplay timer.
4. Observe crime, alarm, witness, and detection signals.

If no suspicion appears, the Case resolves cleanly when the timer expires.
Leaving the encounter zone before expiry also resolves the Case from the
evidence accumulated so far.

Any suspicion event immediately cancels the timer. It is never restarted for
that Case; the Case enters cleanup instead.

The encounter zone is centered on the target's death position. Its final
radius is configurable and must be established by retail testing; the expected
starting range is 100–150 metres.

## Cleanup

Cleanup is an improvisational aftermath phase, not a mandatory ritual.

- A direct witness who has not yet reported can be eliminated.
- Eliminating the last unreported witness can restore low exposure.
- Once a witness reports the crime, guards identify Henry, or a bounty is
  created, that exposure cannot be erased by later killing the witness.
- The timer remains cancelled throughout cleanup.
- The Case resolves when Henry leaves the encounter zone.

Witnesses are not given quest markers. The player must read the encounter and
decide who saw enough to become a threat.

## Two independent consequence axes

### Exposure

Exposure represents whether the current death can be connected to Henry.

Signals include:

- direct witnesses to Henry's involvement;
- alarm or active search;
- crime report, identification, or bounty;
- public discovery of the killing while Henry remains implicated.

Exposure determines the immediate hunt result and satisfaction grace period.

### Blood trail

Blood trail represents the long-term pattern left in a settlement.

It increases from:

- the selected victim's death;
- additional deaths during cleanup;
- discovered bodies;
- repeated Cases in the same settlement;
- conspicuous or clustered deaths that suggest a pattern.

Killing a witness before a report may keep exposure low but still increases the
blood trail. This makes witness removal a valid application of the first rule
without making it consequence-free.

## Hunt results

| Result | Immediate effect | Hunger grace | Persistent consequence |
|---|---|---:|---|
| Clean | Hunger resets; satisfaction applied | 2 additional game days | Minimal attention; baseline blood trail |
| Controlled | Hunger resets; satisfaction applied | 1 additional game day | Some settlement attention and normal blood trail |
| Noisy | Hunger resets; satisfaction applied | No additional days | Strong attention and increased blood trail |

The exact numeric thresholds remain implementation details. The player sees a
lore journal epilogue rather than a rank, letter grade, or percentage.

## Persistent settlement state

Each settlement maintains two hidden values:

- **attention** — short-term concern caused by recent visible incidents;
- **blood trail** — long-term recognition of a recurring pattern.

Attention decays over game time. Blood trail decays very slowly or not at all
in the first version.

Future content may project these values into:

- tavern and herald rumors;
- increased guard presence or scrutiny;
- different investigation complications;
- regional fear and legends;
- Nemesis eligibility and behaviour.

The first implementation only needs to persist and log both values. World
reactions are separate later features.

## External target death

If the target dies without Henry's involvement:

- close the current Case so it cannot become stuck;
- do not reset hunger;
- do not grant satisfaction or a grace period;
- do not add Henry-related attention or blood trail;
- allow the hunger system to request another target after a short safe delay.

Poison, delayed projectiles, provoked combat, and other indirect actions count
as Henry-attributed when the game exposes reliable attribution.

Attribution must be probed before it gates production behaviour. If KCD2 cannot
reliably attribute indirect deaths, the compatibility fallback is the
retail-confirmed current rule: any committed target death counts.

## Persistence and recovery

The Case must persist enough state to recover after save/load:

- phase;
- target and settlement;
- death position and encounter-zone radius;
- remaining silence-check time;
- observed exposure flags;
- tracked direct witnesses and report state where available;
- collateral death count;
- computed result once resolved.

Recovery must be idempotent. A loaded resolved Case must not grant satisfaction,
grace time, attention, or blood-trail changes twice.

If a witness disappears, unloads, or cannot be resolved reliably, a bounded
fallback closes the Case from the evidence already collected rather than
leaving it active forever.

## Presentation

During silence check and cleanup, the active objective is:

> Не оставить следов.

The final journal update describes the outcome without exposing numbers:

- clean: nobody connected the death to Henry;
- controlled: the death caused suspicion, but Henry escaped identification;
- noisy: too many people understood what happened.

Method-specific variants may mention poison, distance, a blade, or open combat,
but these variants remain flavour only.

## Validation

Automated checks must cover:

- legal state transitions and timer cancellation;
- timer never restarting after cleanup begins;
- idempotent Case resolution;
- clean, controlled, noisy, and external-death outcomes;
- hunger reset and grace-period assignment;
- attention and blood-trail deltas;
- save/load in both silence-check and cleanup phases;
- bounded recovery for missing witnesses;
- no change to victim selection or marker ownership.

Retail scenarios must cover:

- unseen melee kill;
- distant arrow;
- delayed poison;
- witnessed kill followed by witness removal before report;
- witness successfully reporting;
- public fight and escape from the zone;
- external NPC killing the selected target;
- save/load during the 90-second check;
- regional travel after Case resolution.

## Deferred questions

- Which KCD2 events reliably distinguish seeing a corpse from witnessing
  Henry's involvement?
- Can witness report state and player attribution be read reliably in Lua?
- What encounter-zone radius feels natural in villages, towns, and wilderness?
- How should attention decay and blood-trail thresholds map to later content?
