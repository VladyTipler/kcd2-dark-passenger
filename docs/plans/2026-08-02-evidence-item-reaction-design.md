# Evidence Item And Henry Reaction

**Date:** 2026-08-02  
**Status:** approved  
**Scope:** reusable first-read reaction and quest-item canary for physical evidence

## Goal

Turn Vojtech's belongings into a real quest document and make its first
accepted reading trigger one randomly selected neutral Henry monologue. The
same read awards confidence once per case generation; reopening the document
is silent and never awards confidence again.

## Player flow

1. The innkeeper lead starts the belongings step.
2. One custom quest document is placed in the selected locked chest.
3. Henry reads it for the first time.
4. Lua awards the configured evidence transaction and persists the read.
5. Lua immediately selects one neutral Henry reaction and dispatches its
   matching native monologue signal.
6. Reopening the same document produces neither confidence nor a reaction.

## Quest document

Use a custom `Document` item instead of the previously borrowed vanilla
letter. The row carries `IsQuestItem="true"`, custom name/description/content
localization and the standard folded-parchment asset. This gives the clue its
own unopened state and places it in the quest section of the inventory.

Placement is idempotent. Before inserting the canary, the runtime removes the
old borrowed letter and the custom document from Henry and from the controlled
chest, then creates exactly one custom document in the chest. It does not
unlock the chest or alter ownership/trespass rules.

## Runtime reaction selection

Lua owns the random choice. On the first accepted read it chooses one entry
from a stable pool:

- `interesting`: `Интересно...`
- `useful`: `Это может пригодиться...`
- `hmm`: `Хм...`

The choice happens at read time and does not need to be predetermined when the
case is generated. `Хм. Странно...` is excluded because the located vanilla
line is voiced for the Kuttenberg bailiff, not Henry.

The selected reaction is delivered through one of three short-lived hidden
buff tags:

```text
first accepted read
  -> Lua random(1..3)
  -> add matching hidden signal buff to Henry
  -> BuffTagTrigger.OnAdded
  -> RequestMonologue(player, DecisionAlias, ForceSubtitles=true)
  -> Lua removes the signal after delivery
```

Each DecisionAlias is registered ahead of time in a small custom ingame
monologue definition using an existing voiced Henry localization key. XML owns
only native playback; it never chooses the reaction.

## Persistence and ordering

Confidence is accepted first. The belongings read generation is persisted
before dispatching the monologue, so a repeat poll or save/load cannot award or
speak twice. A separate reaction-dispatched generation records successful
delivery for diagnostics and allows a failed signal to be retried without
re-awarding confidence.

The runtime state is scoped by evidence identity plus investigation generation.
Future physical clues reuse the same reaction dispatcher while retaining their
own one-shot evidence ledgers.

## Debug reset

A canary-only command resets the current belongings transaction to unread,
restores investigation confidence to the value before this clue, removes all
legacy/custom copies from Henry and the controlled chest, and inserts exactly
one fresh custom document. This command exists only to reproduce the live
first-read boundary; production progression never rolls evidence backward.

## Canonical canary document

The canary uses an authored unsent letter rather than a generic generated
template. Vojtech witnessed the culprit deliberately drown a merchant's
apprentice, hid instead of intervening, and was later threatened in the
tavern. The threat foreshadows Vojtech's staged drunken accident without
giving him impossible knowledge of his future death. A tavern worker who saw
the confrontation remains the next lead.

Title: `Неотправленное письмо Войтеха`

> Марта,
>
> ты спрашивала, отчего я больше не сплю. Я солгал тебе. Дело не в выпивке.
>
> Три ночи назад у старого брода я видел того человека с купеческим
> подмастерьем. Парень стоял на коленях и просил отпустить его. Тот затащил
> его в воду и прижал лицом ко дну. Дважды позволил ему поднять голову и
> вдохнуть — только затем, чтобы снова погрузить. На третий раз руки мальчишки
> перестали скрести камни.
>
> Я прятался за ивами. Я мог позвать людей. Мог броситься на него. Но я лежал
> в грязи, зажав себе рот, и ждал, пока всё закончится.
>
> Вчера он нашёл меня в корчме. Сел рядом, заказал две кружки и сказал, что с
> пьяными батраками постоянно случаются несчастья: один упадёт с откоса,
> другой захлебнётся в ручье. Потом улыбнулся и заплатил за моё пиво.
>
> Он знает, что я видел.
>
> На рассвете я уйду. Если не доберусь до тебя, отдай это письмо тому, кто не
> побоится произнести его имя. Женщина, убиравшая столы после заката, видела
> нас вместе. Возможно, она слышала достаточно.
>
> Прости меня. Когда закрываю глаза, я всё ещё слышу, как тот мальчик скребёт
> ногтями по камням.
>
> Войтех

Future cases follow the approved hybrid content model: authored case
archetypes with several authored document variants, not sentence-level random
assembly. Every variant declares its evidence value and next lead.

## Verification

### Automated

- custom item is a parseable `Document` with `IsQuestItem="true"`;
- English/Russian item and document localization are complete;
- Lua chooses only registered reactions;
- first read awards once, persists before reaction and emits one signal;
- repeated reads and stale generations are silent;
- reset removes duplicates and restores exactly one chest copy;
- generated Kuttenberg quest includes all monologue definitions, triggers and
  `RequestMonologue` calls;
- LuaCompiler, XML parsing and the full static suite remain green.

### Live dev proof

1. Reset the active canary to confidence 20 and one unread chest document.
2. Read it and verify confidence `20 -> 50` plus exactly one Henry line.
3. Reopen it and verify confidence remains 50 and Henry says nothing.
4. Save/load and verify the same one-shot state persists.

## Scope limits

This slice reuses vanilla Henry audio. Authored voice acting and per-archetype
reaction pools remain later content work. Container markers and the next
witness clue are not part of this change.
