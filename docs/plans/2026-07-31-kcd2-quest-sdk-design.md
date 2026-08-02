# KCD2 Quest SDK Design

**Status:** Parked future project; prove inside Dark Passenger before extraction.

**Goal:** Make native KCD2 quests comfortable to author through a small,
developer-first API while preserving the game's journal, banners, sounds,
markers and save behaviour.

## Decision

Build a hybrid SDK. A build-time compiler generates static Skald XML and game
data. A Lua runtime owns events, persistence, timers and domain state. Proven
bridges connect both halves.

A pure runtime Lua quest engine is not sufficient: the mod Lua VM cannot
create arbitrary native quest graph nodes or call the unavailable Quest/HUD
APIs. Runtime operations therefore activate pre-generated graph states rather
than mutating graph structure.

## Developer experience

One declarative `.quest.lua` file is the single source of truth. The public DSL
should favour readable domain events over engine concepts:

```lua
local q = QuestKit

return q.quest({
    id = "dark_within",
    title = "@dark_within_name",
    description = "@dark_within_description",

    start = q.when("hunger.changed", q.gte("value", 50)),

    objectives = {
        q.objective({
            id = "investigate",
            text = "@dark_within_investigate",
            activateOn = "case.opened",
            completeOn = "target.revealed",
            marker = q.area("pritoky_search_area")
        }),
        q.objective({
            id = "kill_target",
            text = "@dark_within_target",
            activateOn = "target.revealed",
            completeOn = "target.dead",
            marker = q.entity("selected_target")
        }),
        q.objective({
            id = "leave_no_traces",
            text = "@dark_within_cleanup",
            activateOn = "target.dead",
            completeOn = "aftermath.resolved"
        })
    },

    completeOn = "aftermath.resolved"
})
```

Gameplay code publishes events and does not know about buff tags or XML ports:

```lua
QuestKit.emit("target.revealed", { entity = victim })
QuestKit.emit("target.dead", { entity = victim, method = "stealth_kill" })
QuestKit.emit("aftermath.resolved", { outcome = "controlled" })
```

The exact fluent/table syntax is provisional. The contract is not: one spec,
domain events, deterministic generation and no duplicated quest configuration.

## Components

1. **QuestSpec DSL** - quest metadata, objectives, conditions, events, markers,
   localization keys and save schema.
2. **Compiler** - validates the spec and generates quest/project XML, aliases,
   graph states, hidden signal buffs/tags, script contexts, localization stubs,
   deterministic GUIDs and a runtime manifest.
3. **Lua runtime** - registry, event bus, reducers/state machines, generation-
   guarded timers, idempotency, persistence and save migrations.
4. **Bridge adapters** - Lua to graph through tagged buffs/script contexts;
   graph to Lua through `ExecuteConsoleString`, `executelua` or
   `executeluawuid` where appropriate.
5. **Native capability adapters** - quest lifecycle, objectives, entity and
   area markers, notifications, audio, buffs and generated static entity pools.
6. **Tooling** - `new`, `build`, `validate`, `pack`, `deploy` and `doctor`
   commands plus editor schema/autocomplete.
7. **Diagnostics** - event trace, current state, generated signal map and dev
   bridge commands such as `qk_status`, `qk_emit` and `qk_trace`.
8. **DialogueSpec** - a declarative dialogue and reply model compiled into
   native FaderDialog, Storm roles, quest-graph wiring, localization and
   runtime events.

## Future dialogue generator

Dialogue authoring belongs in the SDK, but not in the current Dark Passenger
implementation scope. The intended model is a build-time compiler over one
small declarative source:

```lua
q.dialogue({
    id = "pritoky_innkeeper_rumor",
    actor = q.actor.named("kpri_innkeeper"),
    availableWhen = q.caseStep("innkeeper_rumor"),
    lines = {
        q.player("@dp_rumor_ask"),
        q.actor("@dp_rumor_answer")
    },
    onComplete = q.emit("evidence.found", {
        evidence = "innkeeper_rumor",
        confidence = 20
    })
})
```

The syntax is provisional. One DialogueSpec remains the source of truth and
the compiler generates:

- native FaderDialog definition, sequences, prompts, replies and output ports;
- the quest-project `Definition` and node wiring;
- Storm actor-role assignment and required RPG role rows;
- ScriptContext or generated bridge signal for completion and selected reply;
- Russian and English localization stubs with parity checks;
- a runtime manifest mapping dialogue outputs to domain events;
- structural validation for duplicate identifiers, missing roles, missing
  localization, unreachable replies and unconnected outputs.

Static dialogue structure is generated ahead of time because mod Lua cannot
create arbitrary Skald/Storm graph nodes during gameplay. Runtime Lua may
control availability, case state, one-shot guards and consequences. Dynamic
content therefore selects among generated branches or variants; it does not
inject arbitrary new native lines at runtime unless a future live proof finds
a supported engine boundary.

The current Pritoky innkeeper canary is the first integration fixture for this
future subsystem: it already crosses Storm role -> FaderDialog -> quest output
-> ScriptContext -> Lua evidence state. Do not extract the generator until
that round trip has passed live save/load testing.

## Generated contract

The compiler owns all fragile engine wiring:

- `QuestProgress` and `ObjectiveProgress` states and guarded transitions;
- `RequiredForOutput`, quest hierarchy and both regional registration paths;
- hidden signal buff/tag allocations without class collisions;
- static aliases for every possible native marker target;
- localization key parity and package-safe paths;
- deterministic identifiers and collision checks;
- runtime manifest mapping domain events to generated graph signals.

Generated files are never hand-edited. Authoring files and localization are
the only source inputs.

## Runtime guarantees

- Every event has a stable name, schema and optional case generation.
- Duplicate events are safe; transitions and rewards are idempotent.
- Save state is versioned and migratable.
- Timers survive save/load through world time and generation guards.
- Missing capabilities fail closed and produce a diagnostic, never silent
  quest corruption.
- Native UI remains graph-owned; Lua owns orchestration and domain data.

## Explicit non-goals

- No graphical quest editor.
- No arbitrary creation of graph nodes during gameplay.
- No replacement for every Skald or Storm feature.
- No promise that dev-build behaviour proves retail behaviour.
- No public extraction until two independent real quests use the same core.

## Delivery path

1. Extract event bus, store, timer and bridge interfaces inside Dark Passenger
   without changing behaviour.
2. Compile one small linear quest from QuestSpec and prove native start,
   objective progression and completion in retail.
3. Migrate one Dark Passenger slice and validate save compatibility.
4. Build a second independent proof quest to expose false abstractions.
5. Add a minimal linear DialogueSpec compiler from the proven innkeeper
   canary; add branching, conditions and reply consequences only after a
   second native dialogue proves the same contract.
6. Add dynamic entity/area marker pools, localization tooling and diagnostics.
7. Extract a standalone repository, documentation and distributable CLI.

## Success criteria

A mod author can create a journal quest with native banner/sound, three
objectives, a marker, one native dialogue and save-safe progression without
writing quest XML, Storm role XML or manually allocating bridge signals. The
same spec passes structural tests and a real retail integration scenario.

## Open questions

1. Build host: start with the existing PowerShell toolchain internally, then
   choose a bundled Lua host or standalone executable for public distribution.
2. Public scope: Dark Passenger-first is recommended; publish only after the
   second independent quest.
3. Identifier registry and third-party mod collision policy.
4. Licensing and redistribution boundaries for generated templates and tools.
5. Which actor selectors can be bound generically beyond named Storm roles;
   this needs two live dialogue proofs before the public API is frozen.
