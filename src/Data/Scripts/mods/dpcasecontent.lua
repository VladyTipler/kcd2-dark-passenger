DarkPassengerCaseContent = DarkPassengerCaseContent or {}

DarkPassengerCaseContent.SCHEMA_VERSION = 1

local KEYS = {
    schema = "dp_case_content_schema_version",
    generation = "dp_case_content_generation",
    templateSlot = "dp_case_content_template_slot",
    rumorSlot = "dp_case_content_rumor_slot",
}

local function Log(message)
    if System ~= nil and System.LogAlways ~= nil then
        System.LogAlways(
            "[DarkPassenger][CaseContent] " .. tostring(message)
        )
    end
end

local function ReadScalar(key)
    if Variables == nil or Variables.GetGlobal == nil then return nil end
    local ok, value = pcall(function()
        return Variables.GetGlobal(key)
    end)
    if not ok then
        Log("read failed key=" .. tostring(key) .. " error=" .. tostring(value))
        return nil
    end
    return value
end

local function WriteScalar(key, value)
    if Variables == nil or Variables.SetGlobal == nil then return false end
    local ok, errorMessage = pcall(function()
        Variables.SetGlobal(key, value)
    end)
    if not ok then
        Log(
            "write failed key=" .. tostring(key) ..
            " error=" .. tostring(errorMessage)
        )
    end
    return ok
end

local function DefaultState()
    return {
        generation = 0,
        templateSlot = 0,
        rumorSlot = 0,
    }
end

local function CopyState(state)
    return {
        generation = tonumber(state ~= nil and state.generation) or 0,
        templateSlot = tonumber(state ~= nil and state.templateSlot) or 0,
        rumorSlot = tonumber(state ~= nil and state.rumorSlot) or 0,
    }
end

local function ReadState()
    if tonumber(ReadScalar(KEYS.schema)) ~=
       DarkPassengerCaseContent.SCHEMA_VERSION then
        return DefaultState()
    end
    return {
        generation = tonumber(ReadScalar(KEYS.generation)) or 0,
        templateSlot = tonumber(ReadScalar(KEYS.templateSlot)) or 0,
        rumorSlot = tonumber(ReadScalar(KEYS.rumorSlot)) or 0,
    }
end

local function PersistState(state)
    local writes = {
        WriteScalar(KEYS.schema, DarkPassengerCaseContent.SCHEMA_VERSION),
        WriteScalar(KEYS.generation, state.generation),
        WriteScalar(KEYS.templateSlot, state.templateSlot),
        WriteScalar(KEYS.rumorSlot, state.rumorSlot),
    }
    for _, succeeded in ipairs(writes) do
        if not succeeded then return false end
    end
    return true
end

local function Catalog()
    local result = {}
    for _, caseId in ipairs(DarkPassengerCaseCatalogOrder or {}) do
        local caseTemplate =
            DarkPassengerCaseCatalog ~= nil and
            DarkPassengerCaseCatalog[caseId] or nil
        if caseTemplate ~= nil then table.insert(result, caseTemplate) end
    end
    return result
end

local function MatchesConstraints(constraints, context)
    if constraints == nil then return true end
    if context == nil then return false end
    if constraints.region ~= nil and
       constraints.region ~= context.region then
        return false
    end
    if constraints.settlement ~= nil and
       constraints.settlement ~= context.settlement then
        return false
    end
    return true
end

local function WeightedChoice(entries, roll)
    local total = 0
    for _, entry in ipairs(entries) do
        total = total + math.max(0, tonumber(entry.value.weight) or 0)
    end
    if total <= 0 then return nil end

    local normalizedRoll = tonumber(roll)
    if normalizedRoll == nil then
        normalizedRoll = random(1, 1000000) / 1000000
    end
    if normalizedRoll < 0 then normalizedRoll = 0 end
    if normalizedRoll >= 1 then normalizedRoll = 0.999999 end

    local threshold = normalizedRoll * total
    local cursor = 0
    for _, entry in ipairs(entries) do
        cursor = cursor + math.max(0, tonumber(entry.value.weight) or 0)
        if threshold < cursor then return entry end
    end
    return entries[#entries]
end

function DarkPassengerCaseContent.Select(catalog, context, roll)
    local eligibleCases = {}
    for templateSlot, caseTemplate in ipairs(catalog or {}) do
        if MatchesConstraints(caseTemplate.constraints, context) then
            table.insert(eligibleCases, {
                slot = templateSlot,
                value = caseTemplate,
            })
        end
    end
    local selectedCase = WeightedChoice(eligibleCases, roll)
    if selectedCase == nil then return nil, "no_case" end

    local eligibleRumors = {}
    for rumorSlot, rumor in ipairs(selectedCase.value.rumors or {}) do
        if MatchesConstraints(rumor.constraints, context) then
            table.insert(eligibleRumors, {
                slot = rumorSlot,
                value = rumor,
            })
        end
    end
    local selectedRumor = WeightedChoice(eligibleRumors, roll)
    if selectedRumor == nil then return nil, "no_rumor" end

    return {
        templateSlot = selectedCase.slot,
        rumorSlot = selectedRumor.slot,
        caseTemplate = selectedCase.value,
        rumor = selectedRumor.value,
    }, "selected"
end

function DarkPassengerCaseContent.Resolve(state, catalog)
    local source = catalog or Catalog()
    local templateSlot = tonumber(state ~= nil and state.templateSlot) or 0
    local rumorSlot = tonumber(state ~= nil and state.rumorSlot) or 0
    local caseTemplate = source[templateSlot]
    local rumor = caseTemplate ~= nil and
        (caseTemplate.rumors or {})[rumorSlot] or nil
    if caseTemplate == nil or rumor == nil then return nil end
    return {
        generation = tonumber(state.generation) or 0,
        templateSlot = templateSlot,
        rumorSlot = rumorSlot,
        caseTemplate = caseTemplate,
        rumor = rumor,
    }
end

-- Content is selected once per investigation generation. Repeated opens,
-- save/load and Lua hot reload resolve the persisted slots without rerolling.
function DarkPassengerCaseContent.Transition(state, event, catalog)
    local nextState = CopyState(state)
    local generation = tonumber(event ~= nil and event.generation)
    if generation == nil or generation <= 0 then
        return nextState, { accepted = false, reason = "invalid_generation" }
    end

    if nextState.generation == generation and
       DarkPassengerCaseContent.Resolve(nextState, catalog) ~= nil then
        return nextState, { accepted = true, reason = "restored" }
    end

    local selection, reason = DarkPassengerCaseContent.Select(
        catalog or {},
        event.context,
        event.roll
    )
    if selection == nil then
        return nextState, { accepted = false, reason = reason }
    end
    nextState.generation = generation
    nextState.templateSlot = selection.templateSlot
    nextState.rumorSlot = selection.rumorSlot
    return nextState, { accepted = true, reason = "selected" }
end

local function CandidateContext(candidate)
    return {
        region = candidate ~= nil and candidate.gameRegion or nil,
        settlement = candidate ~= nil and candidate.settlement or nil,
        archetype = candidate ~= nil and candidate.archetype or nil,
        faction = candidate ~= nil and candidate.faction or nil,
    }
end

function DarkPassengerCaseContent.OnInvestigationOpened(generation, candidate)
    local catalog = Catalog()
    local nextState, result = DarkPassengerCaseContent.Transition(
        ReadState(),
        {
            generation = generation,
            context = CandidateContext(candidate),
        },
        catalog
    )
    if not result.accepted then
        Log(
            "selection unavailable generation=" .. tostring(generation) ..
            " reason=" .. tostring(result.reason)
        )
        return nil
    end
    if not PersistState(nextState) then return nil end
    local selected = DarkPassengerCaseContent.Resolve(nextState, catalog)
    Log(
        "resolved generation=" .. tostring(generation) ..
        " case=" .. tostring(
            selected ~= nil and selected.caseTemplate.id or nil
        ) ..
        " rumor=" .. tostring(selected ~= nil and selected.rumor.id or nil) ..
        " reason=" .. tostring(result.reason)
    )
    return selected
end

function DarkPassengerCaseContent.GetSelected(generation)
    local state = ReadState()
    if generation ~= nil and state.generation ~= tonumber(generation) then
        return nil
    end
    return DarkPassengerCaseContent.Resolve(state, Catalog())
end

function DarkPassengerCaseContent.Restore(investigationState, candidate)
    if investigationState == nil or investigationState.active ~= true then
        return nil
    end
    return DarkPassengerCaseContent.OnInvestigationOpened(
        investigationState.generation,
        candidate
    )
end

function DarkPassengerCaseContent.RunSelfTest()
    local failures = {}
    local function Expect(condition, label)
        if not condition then table.insert(failures, label) end
    end
    local catalog = Catalog()
    local context = { region = "kutnohorsko", settlement = "pritoky" }
    local state, first = DarkPassengerCaseContent.Transition(
        DefaultState(),
        { generation = 4, context = context, roll = 0 },
        catalog
    )
    local selected = DarkPassengerCaseContent.Resolve(state, catalog)
    Expect(first.accepted and first.reason == "selected", "select")
    Expect(
        selected ~= nil and
        selected.caseTemplate.id == "convenient_accident" and
        selected.rumor.id == "pritoky_innkeeper_strong_suspicion",
        "identity"
    )
    local restoredState, restored = DarkPassengerCaseContent.Transition(
        state,
        { generation = 4, context = context, roll = 0.99 },
        catalog
    )
    Expect(
        restored.accepted and restored.reason == "restored" and
        restoredState.templateSlot == state.templateSlot and
        restoredState.rumorSlot == state.rumorSlot,
        "stable restore"
    )
    local missing, unavailable = DarkPassengerCaseContent.Transition(
        DefaultState(),
        {
            generation = 5,
            context = { region = "trosecko", settlement = "trosky" },
            roll = 0,
        },
        catalog
    )
    Expect(
        unavailable.accepted == false and missing.generation == 0,
        "constraint"
    )
    local passed = #failures == 0
    Log(
        "selftest=" .. tostring(passed) ..
        " failures=" .. table.concat(failures, ",")
    )
    return passed
end

pcall(function()
    if System ~= nil and System.AddCCommand ~= nil then
        System.AddCCommand(
            "dp_case_content_selftest",
            "DarkPassengerCaseContent.RunSelfTest()",
            "Dark Passenger: run persistent case-content self-test"
        )
    end
end)

Log("module loaded")

