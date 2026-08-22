---
title: Timed Area Native HUD Action Design
date: 2026-08-14
status: approved
---

# Timed Area Native HUD Action Design

## Goal

Show `Прислушаться` as a native lower-right interaction action while Henry is
inside the compiled listening area. Remove the central `SendInfoText` prompt.

## Contract

- CaseKit continues to own area, objective, hours, duration and localization.
- Lua publishes one `Action():hint(...):action("grab_body")` through the
  player's native `AddLuaActions` HUD path while the timed action is available.
- A real aimed vanilla interaction has priority; listening is not published
  while an interactor target exists.
- Leaving the area, discovering the evidence, entering dialogue/combat or
  leaving working hours removes the action on the next refresh.
- The proven raw `Player.OnAction` hook remains the execution path and fallback.

## Verification

1. Static RED/GREEN contract for native `Action` plus `AddLuaActions` and no
   `SendInfoText`.
2. LuaCompiler validation.
3. Retail live canary: lower-right action appears inside the area and F still
   completes the two-hour listening action once.
