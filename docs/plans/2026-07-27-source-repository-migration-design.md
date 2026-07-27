# Dark Passenger Source Repository Migration Design

## Goal

Create the canonical mod source repository at
`<repo-root>`, separate from dev/retail game installations and
from the historical `_darkpassenger-satisfaction` workspace.

## Boundaries

- `<repo-root>` becomes the only authored source.
- Dev and retail `Mods\b_DarkPassengerTest` remain deployment targets only.
- `_darkpassenger-satisfaction` remains an untouched known-good archive until
  a build from the new repository passes the existing 455 checks and retail
  validation.
- Reference mods remain outside the repository under
  `<reference-mods-root>`.
- No game archives, third-party mods, logs, credentials, or deployment backups
  enter Git.

## Repository structure

```text
DarkPassenger/
  src/                 authored mod files and quest template
  localization/        authored English and Russian localization XML
  config/              victim catalogue and policy SSOT
  tools/               extraction, generation, build, deploy helpers
  tests/               structural verification
  docs/plans/           designs and implementation plans
  docs/references/      paths and notes for external references
  build/               generated staging tree, ignored
  dist/                packaged releases, ignored
  evidence/            runtime logs and probes, ignored by default
```

Generated regional quest XML, generated candidate Lua, localization paks, and
data paks belong to `build`/`dist`, not source control.

## Migration policy

Copy only authored files from the known-good workspace. Refactor hard-coded
workspace paths in copied tools/tests to derive the repository root from
`$PSScriptRoot`. Generate build artifacts in the new repository and compare
them against the known-good source tree before changing any deployment.

Initialize a local Git repository with branch `main` and create the first
commit only after tests pass. GitHub creation/push is a later explicit action;
the intended remote name is `kcd2-dark-passenger`, initially private.

## Validation

- No tracked `.pak`, logs, backups, extracted mods, or game files.
- No absolute reference to `_darkpassenger-satisfaction` remains in executable
  tools/tests.
- Generated outputs parse and contain no unresolved template tokens.
- Existing structural suite passes from the new repository.
- Old workspace and installed mods remain byte-for-byte untouched.

