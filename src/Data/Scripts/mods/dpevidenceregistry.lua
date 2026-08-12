DarkPassengerEvidenceRegistry = DarkPassengerEvidenceRegistry or {}

DarkPassengerEvidenceRegistry.SCHEMA_VERSION = 1

local STATUS = {
    pending = 0,
    placed = 1,
    discovered = 2,
}

local STATUS_BY_CODE = {
    [0] = "pending",
    [1] = "placed",
    [2] = "discovered",
}

local KEYS = {
    schema = "dp_evidence_registry_schema_version",
    generation = "dp_evidence_registry_generation",
    caseCode = "dp_evidence_registry_case_code",
    entryGeneration = "dp_evidence_registry_entry_generation_",
    status = "dp_evidence_registry_status_",
}

local function Log(message)
    if System ~= nil and System.LogAlways ~= nil then
        System.LogAlways(
            "[DarkPassenger][EvidenceRegistry] " .. tostring(message)
        )
    end
end

local function ReadScalar(key)
    if Variables == nil or Variables.GetGlobal == nil then return nil end
    local ok, valueOrError = pcall(function()
        return Variables.GetGlobal(key)
    end)
    if not ok then
        Log(
            "read failed key=" .. tostring(key) ..
            " error=" .. tostring(valueOrError)
        )
        return nil
    end
    return valueOrError
end

local function WriteScalar(key, value)
    if Variables == nil or Variables.SetGlobal == nil then return false end
    local ok, resultOrError = pcall(function()
        return Variables.SetGlobal(key, value)
    end)
    if not ok then
        Log(
            "write failed key=" .. tostring(key) ..
            " error=" .. tostring(resultOrError)
        )
    end
    return ok
end

local function EntryGenerationKey(code)
    return KEYS.entryGeneration .. tostring(code)
end

local function StatusKey(code)
    return KEYS.status .. tostring(code)
end

local function CopyStrings(values)
    local copied = {}
    for _, value in ipairs(values or {}) do
        table.insert(copied, tostring(value))
    end
    return copied
end

local function CopyEvidence(entry)
    return {
        code = tonumber(entry ~= nil and entry.code) or 0,
        confidence = tonumber(entry ~= nil and entry.confidence) or 0,
        status = entry ~= nil and entry.status or "pending",
        claim_id = entry ~= nil and entry.claim_id or nil,
        claim_cap = tonumber(entry ~= nil and entry.claim_cap) or nil,
        reveals = CopyStrings(entry ~= nil and entry.reveals or nil),
    }
end

local function CopyState(state)
    local copied = {
        generation = tonumber(state ~= nil and state.generation) or 0,
        caseCode = tonumber(state ~= nil and state.caseCode) or 0,
        evidence = {},
        confidence = tonumber(state ~= nil and state.confidence) or 0,
    }
    for _, entry in ipairs(state ~= nil and state.evidence or {}) do
        table.insert(copied.evidence, CopyEvidence(entry))
    end
    return copied
end

local function FindEvidence(state, evidenceCode)
    evidenceCode = tonumber(evidenceCode)
    if evidenceCode == nil then return nil end
    for _, entry in ipairs(state ~= nil and state.evidence or {}) do
        if tonumber(entry.code) == evidenceCode then return entry end
    end
    return nil
end

local function CalculateConfidence(state)
    local total = 0
    local claims = {}
    for _, entry in ipairs(state ~= nil and state.evidence or {}) do
        if entry.status == "discovered" then
            local confidence = math.max(0, tonumber(entry.confidence) or 0)
            local claimId = entry.claim_id
            local claimCap = tonumber(entry.claim_cap)
            if claimId ~= nil and claimId ~= "" and
               claimCap ~= nil and claimCap >= 0 then
                local claim = claims[claimId]
                if claim == nil then
                    claim = { total = 0, cap = claimCap }
                    claims[claimId] = claim
                else
                    claim.cap = math.min(claim.cap, claimCap)
                end
                claim.total = claim.total + confidence
            else
                total = total + confidence
            end
        end
    end
    for _, claim in pairs(claims) do
        total = total + math.min(claim.total, claim.cap)
    end
    return math.min(100, total)
end

function DarkPassengerEvidenceRegistry.IsIdentitySatisfied(
    state,
    identityRequirement
)
    if identityRequirement == nil then return true end
    local known = {}
    for _, entry in ipairs(state ~= nil and state.evidence or {}) do
        if entry.status == "discovered" then
            for _, fact in ipairs(entry.reveals or {}) do
                known[tostring(fact)] = true
            end
        end
    end
    local allOf = identityRequirement.allOf
    if allOf ~= nil then
        if #allOf == 0 then return false end
        for _, fact in ipairs(allOf) do
            if known[tostring(fact)] ~= true then return false end
        end
        return true
    end
    local anyOf = identityRequirement.anyOf
    if anyOf ~= nil then
        if #anyOf == 0 then return false end
        for _, fact in ipairs(anyOf) do
            if known[tostring(fact)] == true then return true end
        end
        return false
    end
    return false
end

local function ResolveIdentitySatisfied(state, generation)
    if DarkPassengerCaseContent == nil or
       DarkPassengerCaseContent.GetSelected == nil then
        return false
    end
    local selected = DarkPassengerCaseContent.GetSelected(generation)
    local caseTemplate = selected ~= nil and selected.caseTemplate or nil
    local identityRequirement = caseTemplate ~= nil and
        caseTemplate.identity_requirement or nil
    return DarkPassengerEvidenceRegistry.IsIdentitySatisfied(
        state,
        identityRequirement
    )
end

local function ReadPersistedStatus(generation, evidenceCode)
    if tonumber(ReadScalar(EntryGenerationKey(evidenceCode))) ~= generation then
        return "pending"
    end
    return STATUS_BY_CODE[tonumber(ReadScalar(StatusKey(evidenceCode)))] or
        "pending"
end

local function BuildCaseState(generation, selected)
    local state = {
        generation = tonumber(generation) or 0,
        caseCode = tonumber(
            selected ~= nil and selected.caseTemplate ~= nil and
            selected.caseTemplate.code
        ) or 0,
        evidence = {},
        confidence = 0,
    }
    local headerMatches =
        tonumber(ReadScalar(KEYS.schema)) ==
            DarkPassengerEvidenceRegistry.SCHEMA_VERSION and
        tonumber(ReadScalar(KEYS.generation)) == state.generation and
        tonumber(ReadScalar(KEYS.caseCode)) == state.caseCode
    local evidence = selected ~= nil and selected.caseTemplate ~= nil and
        selected.caseTemplate.evidence or {}
    for _, definition in ipairs(evidence) do
        local entry = CopyEvidence(definition)
        entry.status = headerMatches and ReadPersistedStatus(
            state.generation,
            entry.code
        ) or "pending"
        table.insert(state.evidence, entry)
    end
    state.confidence = CalculateConfidence(state)
    return state
end

local function PersistState(state)
    local succeeded = true
    for _, entry in ipairs(state.evidence or {}) do
        local statusCode = STATUS[entry.status]
        if statusCode == nil or
           not WriteScalar(
               EntryGenerationKey(entry.code),
               state.generation
           ) or
           not WriteScalar(StatusKey(entry.code), statusCode) then
            succeeded = false
        end
    end
    if not succeeded then return false end
    if not WriteScalar(KEYS.caseCode, state.caseCode) then return false end
    if not WriteScalar(
        KEYS.schema,
        DarkPassengerEvidenceRegistry.SCHEMA_VERSION
    ) then
        return false
    end
    -- Generation is the commit marker and is written only after all entries.
    return WriteScalar(KEYS.generation, state.generation)
end

function DarkPassengerEvidenceRegistry.Transition(state, event)
    local nextState = CopyState(state)
    local result = {
        accepted = false,
        reason = "unknown_event",
        previous = CalculateConfidence(nextState),
        current = CalculateConfidence(nextState),
        delta = 0,
    }
    local eventGeneration = tonumber(event ~= nil and event.generation)
    if eventGeneration == nil or
       eventGeneration ~= nextState.generation then
        result.reason = "stale_generation"
        return nextState, result
    end

    local eventType = event ~= nil and event.type or nil
    if eventType == "restore" then
        nextState.confidence = CalculateConfidence(nextState)
        result.accepted = true
        result.reason = "restored"
        result.current = nextState.confidence
        return nextState, result
    end

    local entry = FindEvidence(nextState, event ~= nil and event.evidenceCode)
    if entry == nil then
        result.reason = "unknown_evidence"
        return nextState, result
    end

    if eventType == "place" then
        if entry.status == "discovered" then
            result.reason = "already_discovered"
            return nextState, result
        end
        if entry.status == "placed" then
            result.reason = "already_placed"
            return nextState, result
        end
        entry.status = "placed"
        result.accepted = true
        result.reason = "placed"
        return nextState, result
    end

    if eventType == "discover" then
        if entry.status == "discovered" then
            result.reason = "already_discovered"
            return nextState, result
        end
        entry.status = "discovered"
        nextState.confidence = CalculateConfidence(nextState)
        result.accepted = true
        result.reason = "discovered"
        result.current = nextState.confidence
        result.delta = result.current - result.previous
        return nextState, result
    end

    return nextState, result
end


function DarkPassengerEvidenceRegistry.GetCaseState(generation)
    generation = tonumber(generation)
    if generation == nil or generation <= 0 then
        return nil, "invalid_generation"
    end
    if DarkPassengerCaseContent == nil or
       DarkPassengerCaseContent.GetSelected == nil then
        return nil, "case_content_unavailable"
    end
    local selected = DarkPassengerCaseContent.GetSelected(generation)
    if selected == nil then return nil, "case_not_selected" end
    return BuildCaseState(generation, selected), "resolved"
end

function DarkPassengerEvidenceRegistry.MarkPlaced(generation, evidenceCode)
    local current, reason =
        DarkPassengerEvidenceRegistry.GetCaseState(generation)
    if current == nil then
        return { accepted = false, reason = reason }
    end
    local nextState, result = DarkPassengerEvidenceRegistry.Transition(
        current,
        {
            type = "place",
            generation = generation,
            evidenceCode = evidenceCode,
        }
    )
    if not result.accepted then return result end
    if not PersistState(nextState) then
        result.accepted = false
        result.reason = "persistence_failed"
    end
    return result
end

function DarkPassengerEvidenceRegistry.Discover(
    generation,
    evidenceCode,
    context
)
    local current, reason =
        DarkPassengerEvidenceRegistry.GetCaseState(generation)
    if current == nil then
        return { accepted = false, reason = reason }
    end
    local nextState, result = DarkPassengerEvidenceRegistry.Transition(
        current,
        {
            type = "discover",
            generation = generation,
            evidenceCode = evidenceCode,
            context = context,
        }
    )
    if not result.accepted then return result end
    if not PersistState(nextState) then
        result.accepted = false
        result.reason = "persistence_failed"
        return result
    end
    if DarkPassengerInvestigation ~= nil and
       DarkPassengerInvestigation.ReconcileEvidence ~= nil then
        result.identitySatisfied = ResolveIdentitySatisfied(
            nextState,
            generation
        )
        result.reconciliation =
            DarkPassengerInvestigation.ReconcileEvidence(
                nextState.confidence,
                generation,
                result.identitySatisfied
            )
    end
    Log(
        "discovered generation=" .. tostring(generation) ..
        " evidence=" .. tostring(evidenceCode) ..
        " confidence=" .. tostring(nextState.confidence)
    )
    return result
end

function DarkPassengerEvidenceRegistry.Restore(generation)
    local current, reason =
        DarkPassengerEvidenceRegistry.GetCaseState(generation)
    if current == nil then
        return { accepted = false, reason = reason }
    end
    local nextState, result = DarkPassengerEvidenceRegistry.Transition(
        current,
        { type = "restore", generation = generation }
    )
    if not result.accepted then return result end
    if DarkPassengerInvestigation ~= nil and
       DarkPassengerInvestigation.ReconcileEvidence ~= nil then
        result.identitySatisfied = ResolveIdentitySatisfied(
            nextState,
            generation
        )
        result.reconciliation =
            DarkPassengerInvestigation.ReconcileEvidence(
                nextState.confidence,
                generation,
                result.identitySatisfied
            )
    end
    return result
end

function DarkPassengerEvidenceRegistry.RunSelfTest()
    local failures = {}
    local function Expect(condition, label)
        if not condition then table.insert(failures, label) end
    end
    local function NewState()
        return {
            generation = 7,
            caseCode = 2001,
            evidence = {
                { code = 2101, confidence = 20, status = "pending" },
                { code = 2102, confidence = 30, status = "pending" },
                { code = 2103, confidence = 20, status = "pending" },
            },
            confidence = 0,
        }
    end
    local function RunOrder(order, state)
        state = state or NewState()
        local result = nil
        for _, evidenceCode in ipairs(order) do
            state, result = DarkPassengerEvidenceRegistry.Transition(
                state,
                {
                    type = "discover",
                    generation = 7,
                    evidenceCode = evidenceCode,
                }
            )
            Expect(result.accepted, "order discovery " .. evidenceCode)
        end
        return state, result
    end

    local placedState, placedResult =
        DarkPassengerEvidenceRegistry.Transition(
            NewState(),
            { type = "place", generation = 7, evidenceCode = 2102 }
        )
    Expect(
        placedResult.accepted and
        FindEvidence(placedState, 2102).status == "placed",
        "pending placed discovered"
    )
    local discoveredState, discoveredResult =
        DarkPassengerEvidenceRegistry.Transition(
            placedState,
            { type = "discover", generation = 7, evidenceCode = 2102 }
        )
    Expect(
        discoveredResult.accepted and
        FindEvidence(discoveredState, 2102).status == "discovered",
        "placed discovered"
    )
    local duplicateState, duplicateResult =
        DarkPassengerEvidenceRegistry.Transition(
            discoveredState,
            { type = "discover", generation = 7, evidenceCode = 2102 }
        )
    Expect(
        not duplicateResult.accepted and
        duplicateResult.reason == "already_discovered" and
        duplicateState.confidence == discoveredState.confidence,
        "duplicate discovery"
    )
    local _, staleResult = DarkPassengerEvidenceRegistry.Transition(
        NewState(),
        { type = "discover", generation = 6, evidenceCode = 2101 }
    )
    Expect(
        not staleResult.accepted and staleResult.reason == "stale_generation",
        "stale generation"
    )

    local forward = RunOrder({ 2101, 2102, 2103 })
    local reverse = RunOrder({ 2103, 2101, 2102 })
    Expect(forward.confidence == 70, "order rumor-ledger-witness")
    Expect(reverse.confidence == 70, "order witness-rumor-ledger")
    Expect(
        forward.confidence == reverse.confidence,
        "same discovered set"
    )

    local capped = NewState()
    capped.evidence[1].claim_id = "same_claim"
    capped.evidence[1].claim_cap = 25
    capped.evidence[2].claim_id = "same_claim"
    capped.evidence[2].claim_cap = 25
    capped = RunOrder({ 2101, 2102, 2103 }, capped)
    Expect(capped.confidence == 45, "claim cap")

    local identityState = NewState()
    identityState.evidence[1].status = "discovered"
    identityState.evidence[1].reveals = { "rumor", "lover_named" }
    identityState.evidence[2].status = "discovered"
    identityState.evidence[2].reveals = { "forest_returner_named" }
    Expect(
        not DarkPassengerEvidenceRegistry.IsIdentitySatisfied(
            identityState,
            { allOf = { "lover_named", "letter_found" } }
        ),
        "identity allOf waits for every fact"
    )
    Expect(
        DarkPassengerEvidenceRegistry.IsIdentitySatisfied(
            identityState,
            { anyOf = { "lover_named", "letter_found" } }
        ) and
        DarkPassengerEvidenceRegistry.IsIdentitySatisfied(
            identityState,
            { anyOf = { "letter_found", "forest_returner_named" } }
        ),
        "identity anyOf accepts either fact"
    )
    Expect(
        not DarkPassengerEvidenceRegistry.IsIdentitySatisfied(
            identityState,
            { unknown = { "lover_named" } }
        ),
        "identity rejects unknown mode"
    )

    local passed = #failures == 0
    Log(
        "selftest " .. (passed and "PASS" or "FAIL") ..
        " failures=" .. table.concat(failures, ",")
    )
    return passed
end

pcall(function()
    if System ~= nil and System.AddCCommand ~= nil then
        System.AddCCommand(
            "dp_evidence_registry_selftest",
            "DarkPassengerEvidenceRegistry.RunSelfTest()",
            "Dark Passenger: run evidence-registry transition checks"
        )
    end
end)

Log("module loaded")
