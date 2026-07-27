# Dark Passenger Source Repository Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Establish `<repo-root>` as a clean, reproducible local Git repository without modifying the known-good workspace or installed mods.

**Architecture:** Copy authored sources into a source-only layout, derive every tool path from the repository root, generate transient files under ignored build directories, then run the existing verification suite before the initial commit.

**Tech Stack:** Git, PowerShell, KCD2 Lua/XML, 7-Zip.

---

### Task 1: Create repository skeleton

- Verify `<repo-root>` does not exist.
- Create source, config, tools, tests, docs, build, dist, and evidence folders.
- Add `.gitignore`, `.gitattributes`, and `README.md`.
- Initialize `git init -b main`.

### Task 2: Copy authored sources only

- Copy Lua, authored tables, quest indexes, Lua bridge module, AI scheduler,
  manifest, and regional quest template into `src`.
- Copy localization XML, config, tools, tests, and plans.
- Exclude paks, generated regional XML, generated candidate Lua, backups, logs,
  and reference mods.

### Task 3: Make tools/tests repository-relative

- Replace executable hard-coded `_darkpassenger-satisfaction` paths with paths
  derived from `$PSScriptRoot`.
- Point generated quest/Lua output at `build`.
- Keep external game/reference paths explicit and read-only where unavoidable.

### Task 4: Generate a clean build tree

- Copy authored `src` into `build\mod`.
- Generate both regional quest XML files and candidate Lua into `build\mod`.
- Copy localization source into its packaging staging layout.
- Do not deploy.

### Task 5: Verify migration

- Run the structural suite against the new build tree.
- Compare authored source hashes with the old workspace.
- Confirm `git status` contains no ignored artifacts.
- Scan tracked candidates for paks, logs, credentials, and third-party files.

### Task 6: Create initial commit

- Stage only intended source/documentation files.
- Review `git diff --cached --stat` and tracked file list.
- Commit: `chore: initialize Dark Passenger source repository`.

## Unresolved questions

- GitHub owner/account for the future private remote?
- Keep historical plans with old absolute paths or mark them archived?
- Add deterministic pak packaging now or after the repository migration commit?
