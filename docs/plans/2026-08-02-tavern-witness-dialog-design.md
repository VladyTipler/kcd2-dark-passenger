# Tavern Witness Dialogue Design

**Date:** 2026-08-02  
**Status:** approved  
**Scope:** text-only RU/EN canary dialogue and witness objective after Vojtech's letter

## Goal

Continue the convenient-accident case after the player reads Vojtech's letter.
The player must find the correct tavern worker without a direct NPC marker,
question her, and receive the final evidence needed to reveal the selected
suspect.

## Canary witness

Use `kpri_woman_10`. The entity belongs to the Pritoky inn layer, follows the
village-service work schedule, and is linked to `tavern_shop`. Assign only this
entity the `DP_TAVERN_WITNESS` Storm role. Other workers remain ordinary
conversation candidates and do not expose the case dialogue.

Future content generation selects and persists a witness matching the story
variant's eligibility requirements. This authored variant requires a living
female inn worker. If a settlement has no eligible entity, the case generator
must choose another clue variant.

## Player flow

1. The first accepted reading of Vojtech's letter awards its existing `+30`
   confidence transaction.
2. `Собрать доказательства вины` completes and a separate objective starts:
   `Расспросить работников корчмы` / `Question the inn workers`.
3. No quest marker is attached to the witness. The player checks workers in
   the inn; only the selected witness has the custom dialogue option.
4. The dialogue awards `+20` confidence exactly once.
5. Confidence reaches the existing reveal threshold of 70. The witness
   objective completes and the existing target objective and NPC marker take
   over.
6. The dialogue is unavailable after completion and remains completed across
   save/load.

## Runtime and graph bridge

Use a reusable `DarkPassengerWitnessLead` Lua runtime with a per-investigation
generation ledger. Reading the document adds one hidden availability signal
buff to Henry. The quest graph uses its buff tag to start the witness objective
and enable the `FaderDialog`.

The dialogue's `heard` output activates a registered ScriptContext on Henry.
The existing quest-context poll detects it and calls the Lua runtime, which
awards the evidence transaction and removes availability. Duplicate context
polls, repeated conversations, and save/load restoration cannot award twice.

The reveal buff already emitted by `DarkPassengerInvestigation` completes the
witness objective and activates the existing target-marker flow. No second
reveal mechanism is introduced.

## Russian copy

Objective: `Расспросить работников корчмы`

Initial log: `Войтех написал, что одна из служанок видела его разговор с
убийцей. Возможно, она сможет опознать этого человека.`

Dialogue:

> **Генри:** Ты работала здесь в тот вечер, когда к Войтеху подсел один человек.
>
> **Служанка:** Я много вечеров здесь работаю. И много кто подсаживается к пьяным батракам.
>
> **Генри:** Войтех оставил письмо. Написал, что ты видела их вместе.
>
> **Служанка:** Дурак… Я велела ему молчать.
>
> **Генри:** Теперь он мёртв.
>
> **Служанка:** Думаешь, я не знаю? После того вечера я каждое утро смотрела на ручей и боялась увидеть там ещё кого-нибудь.
>
> **Генри:** Что ты слышала?
>
> **Служанка:** Тот человек заказал две кружки. Войтех к своей даже не притронулся. Он наклонился к нему и сказал: «У воды ноги скользят даже у трезвых». Потом оставил монету и ушёл.
>
> **Генри:** Кто это был?
>
> **Служанка:** Не заставляй меня произносить его имя здесь.
>
> **Генри:** Тогда скажи, где его искать.
>
> **Служанка:** Я расскажу, как он выглядит и где его найти. Но если он спросит — мы никогда не разговаривали.

Completed log: `Служанка подтвердила, что Войтеху угрожали, и опознала
подозреваемого.`

## English copy

Objective: `Question the inn workers`

Initial log: `Vojtech wrote that one of the maids witnessed his conversation
with the killer. She may be able to identify the man.`

Dialogue:

> **Henry:** You were working here the night a man sat down with Vojtech.
>
> **Maid:** I work here most nights. Plenty of men sit down with drunken farmhands.
>
> **Henry:** Vojtech left a letter. He wrote that you saw them together.
>
> **Maid:** Fool… I told him to keep quiet.
>
> **Henry:** Now he is dead.
>
> **Maid:** You think I do not know? Every morning since that night, I have looked at the stream and feared I would see someone else in it.
>
> **Henry:** What did you hear?
>
> **Maid:** The man ordered two mugs. Vojtech never touched his. He leaned close and said, “Even sober men lose their footing by the water.” Then he left a coin and walked away.
>
> **Henry:** Who was he?
>
> **Maid:** Do not make me say his name in here.
>
> **Henry:** Then tell me where to find him.
>
> **Maid:** I will tell you what he looks like and where to find him. But if he asks, we never spoke.

Completed log: `The maid confirmed that Vojtech had been threatened and
identified the suspect.`

## Localization and audio

Quest XML contains localization keys only. Russian and English localization
must have exact key parity for the objective, logs, prompt, and every response.
This slice is intentionally text-only. Custom voice acting is out of scope;
the absence of audio must not block or change progression.

## Verification

- focused static test covers role assignment, dialogue XML, RU/EN key parity,
  ScriptContext registration, generated graph wiring, and LuaCompiler;
- Lua transition tests cover first award, duplicate context polls, stale
  generations, and restore;
- live test covers no witness marker, one visible dialogue option, objective
  transition, `50 -> 70` confidence, target reveal, repeat silence, and
  save/load persistence.
