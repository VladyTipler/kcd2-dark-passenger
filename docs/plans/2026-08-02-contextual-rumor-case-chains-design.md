# Contextual Rumor Case Chains

**Date:** 2026-08-02
**Status:** approved
**Scope:** scalable evidence content model plus one complete canary case

## Goal

Turn the existing one-shot innkeeper evidence interaction into the entry point
of authored, context-dependent murder investigations. The first canary uses one
dialogue and one linear evidence chain; the same runtime contract must later
support roughly ten case templates without bespoke quest logic per story.

## Code rule

Every selected target is a murderer. General cruelty, theft, extortion or bad
reputation is not enough. Each case owns a concrete innocent victim, motive,
method, cover story and reason the killer escaped justice.

```text
innocent victim -> murder -> cover story -> impunity -> evidence chain
```

Rumors raise suspicion but never constitute sufficient proof by themselves.

## Persistent content model

Content is selected once when a new case generation opens, then persisted.
Save/load, Lua reload and repeated conversations must never reroll it.

```text
CaseTemplate {
  id,
  constraints,
  weight,
  crime_profile,
  rumor_pool,
  evidence_graph
}

RumorDefinition {
  id,
  purpose,
  constraints,
  source_stance,
  weight,
  confidence,
  reported_suspect,
  dialogue_lines,
  next_lead
}

EvidenceStep {
  id,
  kind,
  confidence,
  objective_copy,
  next_steps
}
```

Selection filters by target context before weighted random choice. Available
context starts with region, settlement, position, gender-like actor identity,
faction and character archetype. A small authored classification layer may add
stable social buckets such as commoner, guard, bandit or craftsman when raw
game metadata is not expressive enough.

## Source reliability

The innkeeper is a participant in the world, not an oracle. A source stance is
selected independently of the crime:

- `informed`: knows enough and cautiously helps;
- `neutral`: reports facts without judging;
- `ignorant`: repeats an incomplete or distorted version;
- `biased`: points at someone personally disliked;
- `afraid`: knows the truth but withholds identity;
- `deceptive`: the source is the murderer or accomplice and redirects Henry.

The dialogue must not reveal the stance through a special UI or obviously
different framing. An innkeeper may itself be the selected murderer. That case
uses a natural deceptive variant rather than hiding the rumor interaction.

## Rumor economy

One innkeeper provides one persisted rumor per case generation. Repeating the
conversation yields neither new content nor additional confidence.

Confidence is configured per rumor, not globally:

| Rumor purpose | Typical confidence |
|---|---:|
| Ambient fear | 5 |
| Strange death | 10 |
| Motive or material inconsistency | 15 |
| Circumstantial witness | 15-20 |
| Strong suspicion | 20 |
| Near-direct testimony | 25 |
| False lead | 0-5 |

A disproved false lead may award a later 10-15 points because exposing the lie
is new evidence. The current hard reveal threshold remains 70.

Cases contain two to four evidence steps. A main route must always be able to
reach 70. Future cases may branch and allow alternative routes; players do not
need to exhaust every clue. The first canary stays linear to isolate the
technical contracts.

Every rumor owns an actionable `next_lead`: a person to question, a place to
inspect or an object to find. An atmospheric paragraph without a next action is
invalid content.

## Canary: The Convenient Accident

### Flow

```text
innkeeper rumor +20
  -> inspect Vojtech's belongings +30
  -> question the tavern witness +20
  -> confidence 70, reveal the selected murderer
```

The canary uses the authored attic chest beside the sleeping places in the
Pritoky inn. Its vanilla ownership, lock and trespass rules remain untouched:
opening a locked evidence container may require lockpicking, stealing a key or
another ordinary game solution. The mod never silently unlocks the evidence.

## Evidence-site resolver

Stories request a semantic site role instead of hard-coding one world GUID:

- `inn_attic` or `inn_barn` for rumors tied to travelers and hired hands;
- `target_home` or `target_bedside` for personal evidence;
- `target_workplace` for ledgers, tools and professional traces;
- `public_cache` or `crime_scene` for later case families.

A build-time world index records each eligible `Stash` GUID, position, editor
layer, chest context label, generated inventory, lock state and relations to
beds, inns, NPC homes and workplaces. At case creation the resolver filters by
region, settlement, story role and technical safety, ranks candidates by
semantic fit, then selects one of the best two or three with persisted weighted
randomness. Save/load and Lua reload must not reroll the site.

Locked or trespass-protected containers remain eligible. Only quest-owned,
unresolvable or technically unsafe containers are excluded. A small authored
deny/override list may repair exceptional world data without replacing the
automatic catalog.

Dialogue and objective copy describe the selected site category rather than
assuming every case uses a hayloft. If the preferred category is unavailable,
the resolver chooses a declared story fallback and the matching authored text;
it must never direct the player to a place that was not selected.

Navigation is progressive: the initial case marks the settlement search area;
an acquired lead should normally reveal the exact evidence container. The first
live canary may omit that exact marker so item placement and reading can be
proved without a quest-graph restart. Production marking reuses generated
static aliases for indexed containers instead of inventing a second runtime
marker system.

### Innkeeper action

UI prompt: **Ask about the unease in the area**.

Russian authored dialogue:

> **Генри:** Люди здесь будто чего-то опасаются. Стряслось что?
>
> **Корчмарь:** Боятся? Здесь каждый кого-нибудь боится: один сборщика
> податей, другой собственной жены. Но есть кое-кто, при ком даже пьяные
> говорят тише.
>
> **Генри:** Почему?
>
> **Корчмарь:** С месяц назад у ручья нашли батрака Войтеха. Рихтарж решил,
> что тот свалился с откоса по пьяни. Удобное объяснение - мёртвые ведь не
> спорят.
>
> **Генри:** А кто ему угрожал?
>
> **Корчмарь:** Кое-кто из здешних. Имени от меня не жди - не хочу однажды
> тоже свалиться с откоса по пьяни.
>
> **Генри:** Тогда что мне искать?
>
> **Корчмарь:** Войтех ночевал на сеновале за корчмой. Его сундук до сих пор
> там. Рихтарж даже не потрудился заглянуть внутрь. Если парень понимал, что
> ему грозит, может, что-нибудь оставил. Поспеши, пока мыши не научились
> читать.

The dialogue output awards 20 confidence once and activates the belongings
objective. Later content variants may replace the generic suspect description
with a generated social bucket without changing the dialogue runtime API.

### First physical clue

Vojtech's accessible belongings contain an authored document. Reading, not
merely looting, awards 30 confidence exactly once and activates the witness
lead. The text must connect the threatened victim to the selected target's
context without directly revealing the final marker.

### Witness

One appropriate tavern visitor is selected and persisted for the case. Its
dialogue corroborates the threat or exposes a material contradiction, awards
20 confidence once and crosses the existing reveal threshold.

## Future case-template deck

1. Convenient accident: rumor, belongings, witness.
2. Missing traveler: guest ledger, abandoned cart, stolen keepsake.
3. Poisoned cup: herbalist, symptoms, poison cache.
4. Lawful killing: guard's story, false order, fellow guard.
5. Hunting accident: arrow evidence, weapon match, poacher witness.
6. Fatal fire: survivor rumor, lamp oil, victim's letter.
7. Missing apprentice: workshop traces, forged departure, hidden ledger.
8. Drowned debtor: widow, debt note, struggle near the water.
9. Bandit contact: robbed convoy, stolen goods, stable witness.
10. Fresh grave: gravedigger, missing person's belongings, night surveillance.

These are content families, not ten new engines. They should recombine a small
set of reusable evidence primitives: dialogue, document, inventory/container,
world interaction, observation and contextual NPC selection.

## Failure and compatibility rules

- No applicable rumor: use an authored generic fallback, never reroll the case.
- Source is dead or unavailable: preserve the selected rumor and expose a later
  fallback source; do not silently award confidence.
- Evidence already consumed: keep the narrative state, award nothing again.
- Partial failure after confidence write: retry only the journal/objective
  signal, following the existing evidence contract.
- Old saves without content identity migrate to the canary fallback for their
  current generation; never replace an existing target or settlement.

## Verification boundary

The canary must prove the real game boundaries in sequence:

1. authored innkeeper dialogue is available only for an eligible active case;
2. its output reaches the existing evidence runtime once;
3. the next objective tells the player exactly where to go;
4. reading the physical clue, not possession alone, advances evidence;
5. the selected witness remains stable across save/load;
6. the third step reaches 70 and activates the existing native target marker.
