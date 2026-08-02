DarkPassengerCaseEvidence = DarkPassengerCaseEvidence or {}

local function Log(message)
    if System ~= nil and System.LogAlways ~= nil then
        System.LogAlways(
            "[DarkPassenger][CaseEvidence] " .. tostring(message)
        )
    end
end

local function FindEvidence(caseTemplate, role)
    for _, evidence in ipairs(
        caseTemplate ~= nil and caseTemplate.evidence or {}
    ) do
        if evidence.role == role then return evidence end
    end
    return nil
end

local function MatchesCandidate(caseTemplate, candidate)
    if caseTemplate == nil or candidate == nil then return false end
    local constraints = caseTemplate.constraints or {}
    if constraints.region ~= nil and
       candidate.gameRegion ~= constraints.region then
        return false
    end
    if constraints.settlement ~= nil and
       candidate.settlement ~= constraints.settlement then
        return false
    end
    return true
end

function DarkPassengerCaseEvidence.Resolve(
    generation,
    role,
    selected,
    candidate
)
    generation = tonumber(generation)
    if generation == nil or generation <= 0 then
        return nil, "invalid_generation"
    end
    if role == nil or role == "" then return nil, "invalid_role" end
    if selected == nil then
        if DarkPassengerCaseContent == nil or
           DarkPassengerCaseContent.GetSelected == nil then
            return nil, "case_content_unavailable"
        end
        selected = DarkPassengerCaseContent.GetSelected(generation)
    end
    if selected == nil or tonumber(selected.generation) ~= generation then
        return nil, "case_not_selected"
    end

    local caseTemplate = selected.caseTemplate
    if candidate ~= nil and not MatchesCandidate(caseTemplate, candidate) then
        return nil, "candidate_mismatch"
    end
    local evidence = FindEvidence(caseTemplate, role)
    if evidence == nil then return nil, "evidence_not_found" end
    local binding = caseTemplate ~= nil and
        caseTemplate.bindings ~= nil and
        caseTemplate.bindings[role] or nil
    if binding == nil then return nil, "binding_not_found" end
    return {
        generation = generation,
        selected = selected,
        caseTemplate = caseTemplate,
        evidence = evidence,
        binding = binding,
        candidate = candidate,
    }, "resolved"
end

function DarkPassengerCaseEvidence.ResolveActive(role)
    if DarkPassengerInvestigation == nil or
       DarkPassengerInvestigation.GetState == nil or
       DarkPassengerInvestigation.GetCandidate == nil then
        return nil, "investigation_unavailable"
    end
    local investigation = DarkPassengerInvestigation.GetState()
    local candidate = DarkPassengerInvestigation.GetCandidate()
    if investigation == nil or investigation.active ~= true then
        return nil, "investigation_inactive"
    end
    return DarkPassengerCaseEvidence.Resolve(
        investigation.generation,
        role,
        nil,
        candidate
    )
end

function DarkPassengerCaseEvidence.RunSelfTest()
    local caseTemplate = {
        constraints = { region = "r", settlement = "s" },
        evidence = {
            { id = "lead", role = "innkeeper", confidence = 20 },
        },
        bindings = {
            innkeeper = { entityName = "test_innkeeper" },
        },
    }
    local selected = {
        generation = 7,
        caseTemplate = caseTemplate,
    }
    local resolved, reason = DarkPassengerCaseEvidence.Resolve(
        7,
        "innkeeper",
        selected,
        { gameRegion = "r", settlement = "s" }
    )
    local mismatch, mismatchReason = DarkPassengerCaseEvidence.Resolve(
        7,
        "innkeeper",
        selected,
        { gameRegion = "r", settlement = "other" }
    )
    local passed = resolved ~= nil and reason == "resolved" and
        resolved.evidence.id == "lead" and
        resolved.binding.entityName == "test_innkeeper" and
        mismatch == nil and mismatchReason == "candidate_mismatch"
    Log("selftest=" .. tostring(passed))
    return passed
end

pcall(function()
    if System ~= nil and System.AddCCommand ~= nil then
        System.AddCCommand(
            "dp_case_evidence_selftest",
            "DarkPassengerCaseEvidence.RunSelfTest()",
            "Dark Passenger: run case-evidence resolver self-test"
        )
    end
end)

Log("module loaded")
