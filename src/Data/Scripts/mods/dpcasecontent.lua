DarkPassengerCaseContent = DarkPassengerCaseContent or {}

DarkPassengerCaseContent.SCHEMA_VERSION = 2

local KEYS = {
    schema = "dp_case_content_schema_version",
    generation = "dp_case_content_generation",
    caseCode = "dp_case_content_case_code",
    openerCode = "dp_case_content_opener_code",
    legacyTemplateSlot = "dp_case_content_template_slot",
    legacyRumorSlot = "dp_case_content_rumor_slot",
}

local LEGACY_V1_SELECTIONS = {
    [1] = {
        [1] = { caseCode = 1001, openerCode = 1101 },
    },
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
    return { generation = 0, caseCode = 0, openerCode = 0 }
end

local function CopyState(state)
    return {
        generation = tonumber(state ~= nil and state.generation) or 0,
        caseCode = tonumber(state ~= nil and state.caseCode) or 0,
        openerCode = tonumber(state ~= nil and state.openerCode) or 0,
    }
end

local function PersistState(state)
    local writes = {
        WriteScalar(KEYS.schema, DarkPassengerCaseContent.SCHEMA_VERSION),
        WriteScalar(KEYS.generation, state.generation),
        WriteScalar(KEYS.caseCode, state.caseCode),
        WriteScalar(KEYS.openerCode, state.openerCode),
    }
    for _, succeeded in ipairs(writes) do
        if not succeeded then return false end
    end
    return true
end

function DarkPassengerCaseContent.MigrateLegacyState(legacy)
    local templateSlot = tonumber(legacy ~= nil and legacy.templateSlot) or 0
    local rumorSlot = tonumber(legacy ~= nil and legacy.rumorSlot) or 0
    local template = LEGACY_V1_SELECTIONS[templateSlot]
    local mapping = template ~= nil and template[rumorSlot] or nil
    if mapping == nil then
        return {
            generation = tonumber(legacy ~= nil and legacy.generation) or 0,
            caseCode = 0,
            openerCode = 0,
        }, { accepted = false, reason = "legacy_unknown" }
    end
    return {
        generation = tonumber(legacy.generation) or 0,
        caseCode = mapping.caseCode,
        openerCode = mapping.openerCode,
    }, { accepted = true, reason = "legacy_v1" }
end

local function ReadState()
    local schema = tonumber(ReadScalar(KEYS.schema))
    if schema == DarkPassengerCaseContent.SCHEMA_VERSION then
        return {
            generation = tonumber(ReadScalar(KEYS.generation)) or 0,
            caseCode = tonumber(ReadScalar(KEYS.caseCode)) or 0,
            openerCode = tonumber(ReadScalar(KEYS.openerCode)) or 0,
        }
    end
    if schema == 1 then
        local migratedState, result =
            DarkPassengerCaseContent.MigrateLegacyState({
                generation = tonumber(ReadScalar(KEYS.generation)) or 0,
                templateSlot =
                    tonumber(ReadScalar(KEYS.legacyTemplateSlot)) or 0,
                rumorSlot = tonumber(ReadScalar(KEYS.legacyRumorSlot)) or 0,
            })
        if result.accepted then
            if not PersistState(migratedState) then
                Log("legacy migration persistence failed")
            else
                Log(
                    "migrated legacy selection generation=" ..
                    tostring(migratedState.generation) ..
                    " caseCode=" .. tostring(migratedState.caseCode) ..
                    " openerCode=" .. tostring(migratedState.openerCode)
                )
            end
        else
            Log("migration rejected reason=" .. tostring(result.reason))
        end
        return migratedState
    end
    return DefaultState()
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

local function CaseByCode(code, catalog)
    if catalog == nil and DarkPassengerCaseCatalogByCode ~= nil then
        local direct = DarkPassengerCaseCatalogByCode[tonumber(code)]
        if direct ~= nil then return direct end
    end
    for _, caseTemplate in ipairs(catalog or Catalog()) do
        if tonumber(caseTemplate.code) == tonumber(code) then
            return caseTemplate
        end
    end
    return nil
end

local function EvidenceByCode(entries, code)
    for _, entry in ipairs(entries or {}) do
        if tonumber(entry.code) == tonumber(code) then return entry end
    end
    return nil
end

local function MatchesConstraints(constraints, context)
    if constraints == nil then return true end
    if context == nil then return false end
    if constraints.region ~= nil and constraints.region ~= context.region then
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
    for _, caseTemplate in ipairs(catalog or {}) do
        if MatchesConstraints(caseTemplate.constraints, context) then
            table.insert(eligibleCases, { value = caseTemplate })
        end
    end
    local selectedCase = WeightedChoice(eligibleCases, roll)
    if selectedCase == nil then return nil, "no_case" end

    local eligibleOpeners = {}
    for _, opener in ipairs(selectedCase.value.rumors or {}) do
        if MatchesConstraints(opener.constraints, context) then
            table.insert(eligibleOpeners, { value = opener })
        end
    end
    local selectedOpener = WeightedChoice(eligibleOpeners, roll)
    if selectedOpener == nil then return nil, "no_opener" end

    return {
        caseCode = tonumber(selectedCase.value.code),
        openerCode = tonumber(selectedOpener.value.code),
        caseTemplate = selectedCase.value,
        rumor = selectedOpener.value,
    }, "selected"
end

function DarkPassengerCaseContent.Resolve(state, catalog)
    local caseCode = tonumber(state ~= nil and state.caseCode) or 0
    local openerCode = tonumber(state ~= nil and state.openerCode) or 0
    local caseTemplate = CaseByCode(caseCode, catalog)
    local opener = caseTemplate ~= nil and
        EvidenceByCode(caseTemplate.rumors, openerCode) or nil
    if caseTemplate == nil or opener == nil then return nil end
    return {
        generation = tonumber(state.generation) or 0,
        caseCode = caseCode,
        openerCode = openerCode,
        caseTemplate = caseTemplate,
        rumor = opener,
    }
end

-- Content is selected once per investigation generation. Repeated opens,
-- save/load and Lua hot reload resolve stable codes without rerolling.
function DarkPassengerCaseContent.Transition(state, event, catalog)
    local nextState = CopyState(state)
    local generation = tonumber(event ~= nil and event.generation)
    if generation == nil or generation <= 0 then
        return nextState, { accepted = false, reason = "invalid_generation" }
    end

    if nextState.generation == generation then
        if DarkPassengerCaseContent.Resolve(nextState, catalog) ~= nil then
            return nextState, { accepted = true, reason = "restored" }
        end
        return nextState, {
            accepted = false,
            reason = "invalid_saved_selection",
        }
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
    nextState.caseCode = selection.caseCode
    nextState.openerCode = selection.openerCode
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
    local snapshot = nil
    if selected ~= nil and DarkPassengerCaseSnapshot ~= nil and
       DarkPassengerCaseSnapshot.Capture ~= nil then
        snapshot = DarkPassengerCaseSnapshot.Capture(
            generation,
            candidate,
            selected
        )
    end
    if snapshot ~= nil and DarkPassengerEvidenceSeeder ~= nil and
       DarkPassengerEvidenceSeeder.Seed ~= nil then
        DarkPassengerEvidenceSeeder.Seed(generation, snapshot)
    end
    if snapshot ~= nil and DarkPassengerLeadPlanner ~= nil and
       DarkPassengerLeadPlanner.Apply ~= nil then
        DarkPassengerLeadPlanner.Apply(generation)
    end
    Log(
        "resolved generation=" .. tostring(generation) ..
        " case=" .. tostring(
            selected ~= nil and selected.caseTemplate.id or nil
        ) ..
        " opener=" .. tostring(selected ~= nil and selected.rumor.id or nil) ..
        " reason=" .. tostring(result.reason)
    )
    return selected
end

function DarkPassengerCaseContent.GetSelected(generation)
    local state = ReadState()
    if generation ~= nil and state.generation ~= tonumber(generation) then
        return nil
    end
    return DarkPassengerCaseContent.Resolve(state, nil)
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
        selected ~= nil and state.caseCode == 1001 and
        state.openerCode == 1101 and
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
        restoredState.caseCode == state.caseCode and
        restoredState.openerCode == state.openerCode,
        "stable restore"
    )
    local migrated, migration = DarkPassengerCaseContent.MigrateLegacyState({
        generation = 4,
        templateSlot = 1,
        rumorSlot = 1,
    })
    Expect(
        migration.accepted and migration.reason == "legacy_v1" and
        migrated.generation == 4 and migrated.caseCode == 1001 and
        migrated.openerCode == 1101,
        "legacy migration"
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
