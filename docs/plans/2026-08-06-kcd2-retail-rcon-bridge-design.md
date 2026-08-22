# KCD2 Local Live Bridge Design

## Goal

One local PowerShell interface for executing console and Lua commands in either the KCD2 dev build or retail `-DEVMODE`, without manual console input.

## Design

- Keep `H:\KCD2Mod\dp-dev.ps1` as the familiar entrypoint.
- Put the tracked implementation in `tools\KCD2-LiveBridge.ps1`; the entrypoint only imports it.
- `Send-KCD2Command` auto-detects dev REST on `localhost:1403` (required Host header), otherwise uses retail XML-RPC RCON on `127.0.0.1:1404`.
- Retail RCON performs `challenge -> MD5("uptime:password") -> authenticate -> command` on one persistent HTTP connection.
- Read the retail password from `KCD2_RCON_PASSWORD` by default; allow an explicit parameter for one-off diagnostics. Never store it in Git.
- Bind the client only to loopback. Because the game listener itself binds `0.0.0.0`, provide a separate local firewall setup helper for TCP 1404.
- Keep `Reload-DarkPassenger`, `Reload-Case`, and `Reload-All` compatible with existing usage.

## Verification

- Pure contract tests cover hashing, XML escaping, loopback endpoints, password precedence, and auto mode selection seams.
- A live smoke test crosses the actual retail XML-RPC boundary and executes a Lua canary.
- Wiki records the exact launch, authentication, loose-Lua, and security contracts.

## Non-goals

- No DLL transplant.
- No replacement for dev RTTR `/api` browsing.
- No Concept hot-reload automation; it remains unsafe for ordinary saves.
