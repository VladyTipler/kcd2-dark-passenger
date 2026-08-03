DarkPassengerLeadPlanner = DarkPassengerLeadPlanner or {}

DarkPassengerLeadPlanner.SCHEMA_VERSION = 1

local KEYS = {
    schema = "dp_lead_presentation_schema_version",
    generation = "dp_lead_presentation_generation",
    stateCode = "dp_lead_presentation_state_code",
    revision = "dp_lead_presentation_revision",
}

local function Log(message)
    if System ~= nil and System.LogAlways ~= nil then
        System.LogAlways(
            "[DarkPassenger][LeadPlanner] " .. tostring(message)
        )
    end
end

local function ReadScalar(key)
    if Variables == nil or Variables.GetGlobal == nil then return nil end
    local ok, value = pcall(function() return Variables.GetGlobal(key) end)
    if not ok then return nil end
    return value
end

local function WriteScalar(key, value)
    if Variables == nil or Variables.SetGlobal == nil then return false end
    local ok = pcall(function() Variables.SetGlobal(key, value) end)
    return ok
end

local function DefaultPresentationState()
    return { generation = 0, stateCode = -1, revision = 0 }
end

local function CopyPresentationState(state)
    return {
        generation = tonumber(state ~= nil and state.generation) or 0,
        stateCode = tonumber(state ~= nil and state.stateCode) or -1,
        revision = tonumber(state ~= nil and state.revision) or 0,
    }
end

local function ReadPresentationState()
    if tonumber(ReadScalar(KEYS.schema)) ~=
       DarkPassengerLeadPlanner.SCHEMA_VERSION then
        return DefaultPresentationState()
    end
    return {
        generation = tonumber(ReadScalar(KEYS.generation)) or 0,
        stateCode = tonumber(ReadScalar(KEYS.stateCode)) or -1,
        revision = tonumber(ReadScalar(KEYS.revision)) or 0,
    }
end

local function PersistPresentationState(state)
    if not WriteScalar(KEYS.stateCode, state.stateCode) or
       not WriteScalar(KEYS.revision, state.revision) or
       not WriteScalar(KEYS.schema, DarkPassengerLeadPlanner.SCHEMA_VERSION) then
        return false
    end
    return WriteScalar(KEYS.generation, state.generation)
end

function DarkPassengerLeadPlanner.Transition(state, event)
    local nextState = CopyPresentationState(state)
    local generation = tonumber(event ~= nil and event.generation)
    local stateCode = tonumber(event ~= nil and event.stateCode)
    if generation == nil or generation <= 0 or stateCode == nil or
       stateCode < 0 then
        return nextState, { accepted = false, reason = "invalid_presentation" }
    end
    if generation < nextState.generation then
        return nextState, { accepted = false, reason = "stale_generation" }
    end
    if generation == nextState.generation and
       stateCode == nextState.stateCode then
        return nextState, {
            accepted = false,
            reason = "presentation_unchanged",
        }
    end
    nextState.generation = generation
    nextState.stateCode = stateCode
    nextState.revision = nextState.revision + 1
    return nextState, { accepted = true, reason = "presentation_changed" }
end

local function StatusByCode(evidenceState)
    local result = {}
    for _, entry in ipairs(
        evidenceState ~= nil and evidenceState.evidence or {}
    ) do
        result[tonumber(entry.code)] = entry.status or "pending"
    end
    return result
end

local function DefinitionById(caseTemplate)
    local result = {}
    for _, evidence in ipairs(
        caseTemplate ~= nil and caseTemplate.evidence or {}
    ) do
        result[evidence.id] = evidence
    end
    return result
end

local function HintsSatisfied(evidence, definitions, statuses)
    local hints = evidence.hints_unlocked_by or {}
    if #hints == 0 then return true end
    for _, hintId in ipairs(hints) do
        local source = definitions[hintId]
        if source == nil or statuses[tonumber(source.code)] ~= "discovered" then
            return false
        end
    end
    return true
end

-- Pure projection: discovered facts are authoritative, while the returned
-- directions are only native presentation requests. A physical clue can be
-- discovered without its direction when discoverable_without_hint is true.
function DarkPassengerLeadPlanner.Evaluate(caseTemplate, evidenceState)
    local plan = {
        directions = {},
        by_role = {},
        stateCode = 0,
        confidence = tonumber(
            evidenceState ~= nil and evidenceState.confidence
        ) or 0,
    }
    local statuses = StatusByCode(evidenceState)
    local definitions = DefinitionById(caseTemplate)
    for _, evidence in ipairs(
        caseTemplate ~= nil and caseTemplate.evidence or {}
    ) do
        local status = statuses[tonumber(evidence.code)] or "pending"
        if status ~= "discovered" and
           HintsSatisfied(evidence, definitions, statuses) then
            table.insert(plan.directions, evidence.id)
            if evidence.role ~= nil then
                plan.by_role[evidence.role] = true
            end
            plan.stateCode = plan.stateCode +
                (tonumber(evidence.direction_code) or 0)
        end
    end
    return plan
end

local function PlayerEntity()
    if g_localActor ~= nil then return g_localActor end
    if player ~= nil then return player end
    if System ~= nil and System.GetEntityByName ~= nil then
        return System.GetEntityByName("dude")
    end
    return nil
end

local function HasBuff(soul, buffGuid)
    if soul == nil or soul.HasBuffDebug == nil then return false end
    local ok, result = pcall(function() return soul:HasBuffDebug(buffGuid) end)
    return ok and (result == true or result == 1)
end

local function FindJournalState(caseTemplate, stateCode)
    for _, state in ipairs(
        caseTemplate ~= nil and caseTemplate.journal_states or {}
    ) do
        if tonumber(state.code) == tonumber(stateCode) then return state end
    end
    return nil
end

function DarkPassengerLeadPlanner.Publish(generation, caseTemplate, plan)
    local state = FindJournalState(
        caseTemplate,
        plan ~= nil and plan.stateCode or nil
    )
    if state == nil or state.buff_guid == nil then
        return nil, "journal_state_unavailable"
    end
    local actor = PlayerEntity()
    local soul = actor ~= nil and actor.soul or nil
    if soul == nil or soul.AddBuff == nil or
       soul.RemoveAllBuffsByGuid == nil then
        return nil, "player_unavailable"
    end
    local nextState, result = DarkPassengerLeadPlanner.Transition(
        ReadPresentationState(),
        { generation = generation, stateCode = plan.stateCode }
    )
    if result.accepted and not PersistPresentationState(nextState) then
        return nil, "persistence_failed"
    end
    for _, candidateState in ipairs(caseTemplate.journal_states or {}) do
        if candidateState.buff_guid ~= state.buff_guid then
            pcall(function()
                soul:RemoveAllBuffsByGuid(candidateState.buff_guid)
            end)
        end
    end
    if not HasBuff(soul, state.buff_guid) then
        local ok, handle = pcall(function()
            return soul:AddBuff(state.buff_guid)
        end)
        if not ok or handle == nil then return nil, "signal_failed" end
    end
    plan.presentationRevision = nextState.revision
    plan.presentationReason = result.reason
    return plan, result.reason
end

function DarkPassengerLeadPlanner.HasDirection(plan, directionId)
    for _, current in ipairs(plan ~= nil and plan.directions or {}) do
        if current == directionId then return true end
    end
    return false
end

function DarkPassengerLeadPlanner.Apply(generation)
    generation = tonumber(generation)
    if generation == nil or generation <= 0 or
       DarkPassengerCaseContent == nil or
       DarkPassengerCaseContent.GetSelected == nil or
       DarkPassengerEvidenceRegistry == nil or
       DarkPassengerEvidenceRegistry.GetCaseState == nil then
        return nil, "planner_unavailable"
    end
    local selected = DarkPassengerCaseContent.GetSelected(generation)
    local evidenceState, reason =
        DarkPassengerEvidenceRegistry.GetCaseState(generation)
    if selected == nil or evidenceState == nil then
        return nil, reason or "case_unavailable"
    end
    local plan = DarkPassengerLeadPlanner.Evaluate(
        selected.caseTemplate,
        evidenceState
    )
    local published, publishReason = DarkPassengerLeadPlanner.Publish(
        generation,
        selected.caseTemplate,
        plan
    )
    if published == nil then
        Log("presentation deferred reason=" .. tostring(publishReason))
    end
    if DarkPassengerEvidence ~= nil and
       DarkPassengerEvidence.ApplyAvailability ~= nil then
        DarkPassengerEvidence.ApplyAvailability(
            generation,
            plan.by_role.innkeeper == true
        )
    end
    if DarkPassengerWitnessLead ~= nil and
       DarkPassengerWitnessLead.ApplyAvailability ~= nil then
        DarkPassengerWitnessLead.ApplyAvailability(
            generation,
            plan.by_role.witness == true
        )
    end
    Log(
        "applied generation=" .. tostring(generation) ..
        " directions=" .. table.concat(plan.directions, ",") ..
        " confidence=" .. tostring(plan.confidence)
    )
    return plan, "applied"
end

function DarkPassengerLeadPlanner.RunSelfTest()
    local caseTemplate = {
        evidence = {
            {
                id = "rumor",
                code = 1,
                role = "innkeeper",
                hints_unlocked_by = {},
            },
            {
                id = "ledger",
                code = 2,
                role = "document",
                discoverable_without_hint = true,
                hints_unlocked_by = { "rumor" },
            },
            {
                id = "witness",
                code = 3,
                role = "witness",
                hints_unlocked_by = { "rumor" },
            },
        },
    }
    local function State(rumor, ledger, witness)
        local evidence = {
            { code = 1, confidence = 20, status = rumor },
            { code = 2, confidence = 30, status = ledger },
            { code = 3, confidence = 20, status = witness },
        }
        local confidence = 0
        for _, entry in ipairs(evidence) do
            if entry.status == "discovered" then
                confidence = confidence + entry.confidence
            end
        end
        return { evidence = evidence, confidence = confidence }
    end
    local rumorLedgerWitness = DarkPassengerLeadPlanner.Evaluate(
        caseTemplate,
        State("discovered", "discovered", "pending")
    )
    local rumorWitnessLedger = DarkPassengerLeadPlanner.Evaluate(
        caseTemplate,
        State("discovered", "pending", "discovered")
    )
    local ledgerRumorWitness = DarkPassengerLeadPlanner.Evaluate(
        caseTemplate,
        State("pending", "discovered", "pending")
    )
    local completed = DarkPassengerLeadPlanner.Evaluate(
        caseTemplate,
        State("discovered", "discovered", "discovered")
    )
    local sameConfidence =
        State("discovered", "discovered", "discovered").confidence == 70
    local parallelAfterRumor = DarkPassengerLeadPlanner.Evaluate(
        caseTemplate,
        State("discovered", "placed", "pending")
    )
    local passed =
        DarkPassengerLeadPlanner.HasDirection(
            parallelAfterRumor,
            "ledger"
        ) and
        DarkPassengerLeadPlanner.HasDirection(
            parallelAfterRumor,
            "witness"
        ) and
        DarkPassengerLeadPlanner.HasDirection(
            rumorLedgerWitness,
            "witness"
        ) and
        not DarkPassengerLeadPlanner.HasDirection(
            rumorLedgerWitness,
            "ledger"
        ) and
        DarkPassengerLeadPlanner.HasDirection(
            rumorWitnessLedger,
            "ledger"
        ) and
        DarkPassengerLeadPlanner.HasDirection(
            ledgerRumorWitness,
            "rumor"
        ) and
        not DarkPassengerLeadPlanner.HasDirection(
            ledgerRumorWitness,
            "witness"
        ) and
        #completed.directions == 0 and sameConfidence
    local presentation, changed = DarkPassengerLeadPlanner.Transition(
        DefaultPresentationState(),
        { generation = 7, stateCode = 3 }
    )
    local unchangedState, unchanged = DarkPassengerLeadPlanner.Transition(
        presentation,
        { generation = 7, stateCode = 3 }
    )
    local nextPresentation, nextChanged =
        DarkPassengerLeadPlanner.Transition(
            unchangedState,
            { generation = 7, stateCode = 1 }
        )
    passed = passed and changed.accepted and
        presentation.revision == 1 and
        not unchanged.accepted and
        unchanged.reason == "presentation_unchanged" and
        nextChanged.accepted and nextPresentation.revision == 2
    Log(
        "selftest=" .. tostring(passed) ..
        " rumor-ledger-witness=" ..
        table.concat(rumorLedgerWitness.directions, ",") ..
        " rumor-witness-ledger=" ..
        table.concat(rumorWitnessLedger.directions, ",") ..
        " ledger-rumor-witness=" ..
        table.concat(ledgerRumorWitness.directions, ",") ..
        " parallel after rumor=" ..
        table.concat(parallelAfterRumor.directions, ",") ..
        " same confidence=" .. tostring(sameConfidence)
    )
    return passed
end

pcall(function()
    if System ~= nil and System.AddCCommand ~= nil then
        System.AddCCommand(
            "dp_lead_planner_selftest",
            "DarkPassengerLeadPlanner.RunSelfTest()",
            "Dark Passenger: run nonlinear lead-planner checks"
        )
    end
end)

Log("module loaded")
