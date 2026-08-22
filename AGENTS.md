# Dark Passenger agent rules

## Parallel research by default

- When two or more independent research questions exist, run read-only background agents in parallel while the primary agent continues the main task.
- Prefer research splits by subsystem: Lua/ScriptBind, Skald/Concept/XGenAI, vanilla/reference implementations, build/runtime diagnostics.
- Background agents report evidence, exact source paths, signatures, limits, and confidence. They do not edit project files unless explicitly assigned ownership.
- The primary agent owns architecture decisions, validates cross-agent conclusions, writes shared files, runs tests, and integrates results.
- Do not parallelize work with sequential dependencies or overlapping mutable files.
- Keep one concurrency slot for the primary agent. Avoid worktrees unless Vladislav explicitly requests them.

## Reverse-engineering evidence

- Distinguish official/generated documentation, source-confirmed behavior, live-proven behavior, and hypotheses.
- Record durable, live-proven KCD2 techniques in the LLM Wiki after meaningful work.
- Prefer reusable debug helpers and catalogs over rediscovering APIs ad hoc.
