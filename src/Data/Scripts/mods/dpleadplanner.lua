DarkPassengerLeadPlanner = DarkPassengerLeadPlanner or {}

local function Log(message)
    if System ~= nil and System.LogAlways ~= nil then
        System.LogAlways(
            "[DarkPassenger][LeadPlanner] " .. tostring(message)
        )
    end
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
        end
    end
    return plan
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
