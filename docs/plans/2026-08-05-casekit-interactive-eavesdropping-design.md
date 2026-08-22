# CaseKit Interactive Eavesdropping Design

## Status

Approved on 2026-08-05.

## Goal

Let a StoryPack expose an overheard dialogue as an explicit **Listen in** NPC
interaction. Preserve proximity-triggered overheard dialogue for future
directed scenes, but do not use it for the Love Triangle opener.

## Authoring contract

`overheard-dialogue` remains one EvidenceModule. Each authored step declares:

```json
"activation": {"mode": "interaction"}
```

Allowed modes are `interaction` and `proximity`. Existing authored content is
made explicit as `proximity`; missing or unknown modes fail validation. The
interaction hint is system copy, not story copy:

- Russian: `Прислушаться`;
- English: `Listen in`.

A StoryPack may contain several overheard steps. Each step keeps its own
evidence identity, dialogue turns, concrete speaker bindings, signal and
cleanup ownership.

## Compiled model

The singular legacy `native.overheard` representation becomes a finite
`overheardScenes` collection. Authored CaseKit variants emit one scene for
every compatible overheard step. The shipping Missing Traveler canary uses an
interactive scene; synthetic coverage preserves the legacy proximity path.

Each compiled scene contains:

- stable scene and evidence identity;
- activation mode;
- two bound speaker roles and concrete souls;
- generated NonPlayer ingame dialogue;
- deterministic activation buff/tag;
- evidence completion port and ScriptContext;
- cleanup ownership.

## Runtime flow

```text
active interactive scene + living bound pair
  -> action provider adds Listen in to either speaker
  -> player presses action
  -> Lua applies the scene activation buff to speaker A
  -> BuffTagTrigger enables the existing switchdialog
  -> both NPCs perform the generated NonPlayer dialogue
  -> clue port pulses the scene ScriptContext
  -> Lua discovers evidence once, updates confidence/journal
  -> activation signal and action disappear
```

The action is unavailable during combat, another active dialogue, missing or
dead speakers, stale Case generation, or after discovery. Repeated presses and
repeated graph pulses are idempotent.

`proximity` scenes retain the existing scheduler path. Interactive scenes never
start merely because Henry entered their hearing radius.

Missing Traveler also attaches one `GuidanceTarget kind=area` to the step. It
reuses the compiled Zhelejov `DP_SearchArea_*` alias while the step is active
and removes the guidance signal after the clue is discovered.

## Love Triangle opener UX

The opening objective is:

> Расспросить корчмаря или поискать другие зацепки в округе.

The innkeeper is the guaranteed marked opener. Up to five optional openers may
be discovered out of order. The first discovered opener completes the generic
opening objective and removes the innkeeper marker; unused opener content
remains available as additional evidence.

## Verification

Automated coverage must cross:

1. StoryPack JSON validation and normalization;
2. compatibility and finite materialization;
3. generated dialogue, signal, quest wiring and Lua catalog;
4. runtime interaction availability, activation and one-shot discovery;
5. full packaged build and existing regression suite.

Live acceptance uses two ordinary NPCs: the action appears, the dialogue runs
between them with subtitles, confidence changes once and the action disappears.
