# KCD2 Retail RCON Bridge Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add one local PowerShell command bridge that works with both KCD2 dev REST and retail XML-RPC RCON.

**Architecture:** A tracked bridge module owns transport selection and the XML-RPC authentication contract. The existing root helper remains a thin compatibility entrypoint. Unit-style contract checks run offline; one live smoke crosses the real retail boundary.

**Tech Stack:** PowerShell 5.1+, .NET `HttpClient`, XML-RPC, MD5 challenge response, Windows Firewall.

---

### Task 1: Lock the bridge contract

**Files:**
- Create: `H:\KCD2Mod\DarkPassenger\tests\Test-KCD2LiveBridge.ps1`
- Create: `H:\KCD2Mod\DarkPassenger\tools\KCD2-LiveBridge.ps1`

1. Add failing checks for hash output, XML escaping, localhost-only endpoints, password resolution, and exported commands.
2. Run `powershell -NoProfile -ExecutionPolicy Bypass -File H:\KCD2Mod\DarkPassenger\tests\Test-KCD2LiveBridge.ps1`; expect RED because the module is absent.
3. Implement only pure helpers and rerun; expect GREEN.

### Task 2: Add dev and retail transports

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\tools\KCD2-LiveBridge.ps1`
- Modify: `H:\KCD2Mod\dp-dev.ps1`

1. Implement dev REST detection and command execution.
2. Implement retail challenge/auth/command on one `HttpClient` with one connection.
3. Preserve reload wrapper functions and make the root helper import the tracked module.
4. Add a firewall helper that blocks inbound TCP 1404 while retaining loopback use.
5. Run the offline contract test; expect GREEN.

### Task 3: Cross the real retail boundary and document it

**Files:**
- Modify: `C:\Users\Vladislav\Obsidian Vaults\LLM Wiki\kcd2-modding-technical-reference.md`
- Modify: `C:\Users\Vladislav\Obsidian Vaults\LLM Wiki\log.md`

1. Dot-source `H:\KCD2Mod\dp-dev.ps1` and send a Lua log canary to the running retail game.
2. Verify the canary in both the returned XML-RPC output and `H:\SteamLibrary\steamapps\common\KingdomComeDeliverance2\kcd.log`.
3. Record `sys_PakPriority 0`, the XML-RPC wire contract, and local-only security constraints in Wiki.
4. Run final offline and live checks; expect GREEN.

## Unresolved questions

- None.
