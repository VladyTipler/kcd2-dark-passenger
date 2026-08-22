# Timed Area Native HUD Action Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the timed listening central notice with the native lower-right action HUD.

**Architecture:** Reuse the game's `Action` and `Player:AddLuaActions` path without creating an entity or changing global action maps. Keep the existing compiled area context and raw F execution hook.

**Tech Stack:** KCD2 Lua, PlayerEventDispatcher, PowerShell contract tests, retail XML-RPC RCON.

---

### Task 1: Native HUD contract

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-TimedAreaActionRuntime.ps1`
- Modify: `H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dptimedareaaction.lua`

1. Add a failing assertion requiring `Action():hint`, `AddLuaActions`, the
   `grab_body` binding and removal of `SendInfoText`.
2. Run the focused test and confirm RED.
3. Live-probe the same native action through retail RCON.
4. Implement one reload-safe HUD publisher in the timed-area module.
5. Run focused compiler/Lua tests and confirm GREEN.
6. Hot-reload loose Lua and obtain player-visible retail confirmation.

## Current checkpoint - resume after voice pilot

This task is not complete. The latest build is installed, but the native HUD
action still needs a cold retail transition proof. The last observed failure
was an inconsistent prompt: it could remain after leaving the listening area
or appear only after leaving and entering again.

Temporary next task: generate the Beta and Henry OmniVoice dialogue pilot.
Immediately after the audio files are generated, return here and verify:

1. `Прислушаться` appears on the first entry into the listening area.
2. The action disappears after leaving the area.
3. The action appears again after re-entry.
4. `F` completes listening only while the action is genuinely available.

If any transition fails, continue diagnosis in
`src/Data/Scripts/mods/dptimedareaaction.lua`; do not mark the listening
mechanic complete from static tests or PAK inspection alone.

## Unresolved questions

- Which HUD state remains stale across the cold retail enter/exit/re-entry
  sequence?
