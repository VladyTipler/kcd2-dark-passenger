# Vojtech Letter Copy Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the canary document draft with the approved darker unsent letter in Russian and equivalent English localization.

**Architecture:** Keep the existing custom quest-document GUID and first-read runtime unchanged. Treat localization as the content source of truth and protect the approved title and distinctive narrative lines with focused static assertions.

**Tech Stack:** KCD2 localization XML, PowerShell 7 static tests, existing PAK build pipeline.

---

### Task 1: Lock the approved copy with a failing test

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-VojtechBelongingsEvidence.ps1`

**Step 1:** Assert the Russian title `Неотправленное письмо Войтеха`, the threat about drunken farmhands, and the final stone-scraping image. Assert equivalent English title and distinctive lines.

**Step 2:** Run:

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File 'H:\KCD2Mod\DarkPassenger\tests\Test-VojtechBelongingsEvidence.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
```

Expected: FAIL because localization still contains the original draft.

### Task 2: Replace Russian and English localization

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\localization\Russian\text__darkpassengertest.xml`
- Modify: `H:\KCD2Mod\DarkPassenger\localization\English\text__darkpassengertest.xml`

**Step 1:** Replace only `dp_vojtech_letter_name` and `dp_vojtech_letter_content`. Preserve `dp_vojtech_letter_info`, the document GUID, item metadata, and evidence runtime.

**Step 2:** Keep paragraph markup encoded as `&lt;p&gt;...&lt;/p&gt;` and UTF-8 without BOM.

**Step 3:** Parse both XML files and rerun the focused test. Expected: PASS.

### Task 3: Build and deploy once

**Files:**
- Build: `H:\KCD2Mod\DarkPassenger\build\mod`
- Deploy: `H:\SteamLibrary\steamapps\common\KCD2Mod\Mods\b_DarkPassengerTest`

**Step 1:** Build with explicit dev root:

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -ExecutionPolicy Bypass -File 'H:\KCD2Mod\DarkPassenger\tools\Build-Mod.ps1' -DevGameRoot 'H:\SteamLibrary\steamapps\common\KCD2Mod'
```

**Step 2:** Verify the three PAK archives and confirm the Russian/English localization PAKs contain the approved title.

**Step 3:** Copy the build into the stopped dev game and compare source/target SHA-256 hashes.

### Task 4: Live canary

**Step 1:** Launch Steam app `2429020`, load the test save, and reset the fresh document canary through the HTTP bridge.

**Step 2:** Read the document and verify the approved copy, one confidence award, and exactly one random Henry reaction.

**Step 3:** Reopen and save/load; verify no second reward or reaction.

## Unresolved questions

None.
