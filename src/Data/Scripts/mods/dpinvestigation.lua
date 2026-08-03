DarkPassengerInvestigation = DarkPassengerInvestigation or {}

DarkPassengerInvestigation.SCHEMA_VERSION = 1
DarkPassengerInvestigation.REVEAL_THRESHOLD = 70
DarkPassengerInvestigation.REVEAL_BUFF_GUID =
    "1aff569d-80ee-4250-b28e-0f08d0524aa4"
DarkPassengerInvestigation.TARGET_BUFF_GUID =
    "a6046bb4-57c1-4a95-b743-880aba11f5ba"
DarkPassengerInvestigation.ACTIVE_TARGET_SLOT_KEY = "dp_active_target_slot"
DarkPassengerInvestigation.SLICE_SETTLEMENT_OVERRIDES = {
    kutnohorsko = "pritoky",
}

local KEYS = {
    schema = "dp_investigation_schema_version",
    active = "dp_investigation_active",
    generation = "dp_investigation_active_generation",
    confidence = "dp_investigation_confidence",
    revealed = "dp_investigation_revealed",
    revealDispatched = "dp_investigation_reveal_dispatched",
}

local function InvestigationLog(message)
    System.LogAlways("[DarkPassengerInvestigation] " .. tostring(message))
end

local function CopyState(state)
    return {
        active = state ~= nil and state.active == true or false,
        generation = state ~= nil and tonumber(state.generation) or 0,
        confidence = state ~= nil and tonumber(state.confidence) or 0,
        revealed = state ~= nil and state.revealed == true or false,
        revealDispatched =
            state ~= nil and state.revealDispatched == true or false,
    }
end

local function DefaultState()
    return CopyState(nil)
end

local function ReadScalar(key)
    if Variables == nil or Variables.GetGlobal == nil then return nil end
    local ok, valueOrError = pcall(function()
        return Variables.GetGlobal(key)
    end)
    if not ok then
        InvestigationLog(
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
        InvestigationLog(
            "write failed key=" .. tostring(key) ..
            " error=" .. tostring(resultOrError)
        )
    end
    return ok
end

local function ReadState()
    local schema = tonumber(ReadScalar(KEYS.schema))
    if schema ~= DarkPassengerInvestigation.SCHEMA_VERSION then
        return DefaultState()
    end
    return {
        active = tonumber(ReadScalar(KEYS.active)) == 1,
        generation = tonumber(ReadScalar(KEYS.generation)) or 0,
        confidence = tonumber(ReadScalar(KEYS.confidence)) or 0,
        revealed = tonumber(ReadScalar(KEYS.revealed)) == 1,
        revealDispatched =
            tonumber(ReadScalar(KEYS.revealDispatched)) == 1,
    }
end

local function PersistState(state)
    local results = {
        WriteScalar(
            KEYS.schema,
            DarkPassengerInvestigation.SCHEMA_VERSION
        ),
        WriteScalar(KEYS.active, state.active and 1 or 0),
        WriteScalar(KEYS.generation, state.generation),
        WriteScalar(KEYS.confidence, state.confidence),
        WriteScalar(KEYS.revealed, state.revealed and 1 or 0),
        WriteScalar(
            KEYS.revealDispatched,
            state.revealDispatched and 1 or 0
        ),
    }
    for _, succeeded in ipairs(results) do
        if not succeeded then return false end
    end
    return true
end

local function FindCandidateByActiveSlot()
    local slot = tonumber(
        ReadScalar(DarkPassengerInvestigation.ACTIVE_TARGET_SLOT_KEY)
    )
    if slot == nil or slot <= 0 or
       DarkPassengerGeneratedCandidates == nil then
        return nil
    end
    for _, candidate in ipairs(DarkPassengerGeneratedCandidates) do
        if tonumber(candidate.slot) == slot then return candidate end
    end
    return nil
end

local function ResolveEntity(candidate, entity)
    if entity ~= nil then return entity end
    if candidate == nil or candidate.entityName == nil or
       System == nil or System.GetEntityByName == nil then
        return nil
    end
    return System.GetEntityByName(candidate.entityName)
end

local function HasBuff(entity, buffGuid)
    if entity == nil or entity.soul == nil or
       entity.soul.HasBuffDebug == nil then
        return false
    end
    local ok, hasBuffOrError = pcall(function()
        return entity.soul:HasBuffDebug(buffGuid)
    end)
    return ok and (hasBuffOrError == true or hasBuffOrError == 1)
end

local function RemoveRevealBuff(entity)
    if entity == nil or entity.soul == nil or
       entity.soul.RemoveAllBuffsByGuid == nil then
        return false
    end
    local ok = pcall(function()
        entity.soul:RemoveAllBuffsByGuid(
            DarkPassengerInvestigation.REVEAL_BUFF_GUID
        )
    end)
    return ok
end

function DarkPassengerInvestigation.GetSettlementOverride(gameRegion)
    return DarkPassengerInvestigation.SLICE_SETTLEMENT_OVERRIDES[gameRegion]
end

function DarkPassengerInvestigation.GetState()
    return ReadState()
end

function DarkPassengerInvestigation.GetCandidate()
    return DarkPassengerInvestigation.candidate or
        FindCandidateByActiveSlot()
end

function DarkPassengerInvestigation.Transition(state, event)
    local nextState = CopyState(state)
    local result = {
        accepted = false,
        delta = 0,
        revealRequested = false,
        reason = "unknown_event",
    }
    local eventType = event ~= nil and event.type or nil

    if eventType == "open" then
        local generation = tonumber(event.generation)
        if generation == nil or generation <= nextState.generation then
            result.reason = "stale_generation"
            return nextState, result
        end
        nextState.active = true
        nextState.generation = generation
        nextState.confidence = 0
        nextState.revealed = false
        nextState.revealDispatched = false
        result.accepted = true
        result.reason = "opened"
        return nextState, result
    end

    if eventType == "restore" then
        result.accepted = true
        result.reason = "restored"
        return nextState, result
    end

    if eventType == "clear" then
        nextState.active = false
        nextState.confidence = 0
        nextState.revealed = false
        nextState.revealDispatched = false
        result.accepted = true
        result.reason = "cleared"
        return nextState, result
    end

    local eventGeneration = tonumber(event ~= nil and event.generation)
    if not nextState.active then
        result.reason = "inactive"
        return nextState, result
    end
    if eventGeneration ~= nil and eventGeneration ~= nextState.generation then
        result.reason = "stale_generation"
        return nextState, result
    end

    if eventType == "evidence" then
        local amount = tonumber(event.amount)
        if amount == nil or amount <= 0 then
            result.reason = "invalid_evidence"
            return nextState, result
        end
        local previous = nextState.confidence
        nextState.confidence = math.min(100, previous + amount)
        result.accepted = true
        result.delta = nextState.confidence - previous
        result.reason = "evidence_added"
        if not nextState.revealed and
           nextState.confidence >=
               DarkPassengerInvestigation.REVEAL_THRESHOLD then
            nextState.revealed = true
            result.revealRequested = true
        end
        return nextState, result
    end

    if eventType == "reconcile" then
        local total = tonumber(event.total)
        if total == nil or total < 0 then
            result.reason = "invalid_evidence_total"
            return nextState, result
        end
        total = math.min(100, total)
        if total < nextState.confidence then
            result.reason = "non_monotonic_confidence"
            return nextState, result
        end
        if total == nextState.confidence then
            result.accepted = true
            result.reason = "evidence_unchanged"
            return nextState, result
        end
        local previous = nextState.confidence
        nextState.confidence = total
        result.accepted = true
        result.delta = nextState.confidence - previous
        result.reason = "evidence_reconciled"
        if not nextState.revealed and
           nextState.confidence >=
               DarkPassengerInvestigation.REVEAL_THRESHOLD then
            nextState.revealed = true
            result.revealRequested = true
        end
        return nextState, result
    end

    if eventType == "target_death" then
        nextState.active = false
        result.accepted = true
        result.reason = "target_dead"
        return nextState, result
    end

    return nextState, result
end

local function DispatchReveal(nextState, entity)
    if not nextState.active or not nextState.revealed then return false end
    entity = ResolveEntity(
        DarkPassengerInvestigation.candidate,
        entity
    )
    if entity == nil or entity.soul == nil then
        InvestigationLog("reveal dispatch deferred: target entity unavailable")
        return false
    end
    if nextState.revealDispatched and
       HasBuff(entity, DarkPassengerInvestigation.REVEAL_BUFF_GUID) then
        return true
    end

    PersistState(nextState)
    local accepted, buffHandleOrError = pcall(function()
        return entity.soul:AddBuff(DarkPassengerInvestigation.REVEAL_BUFF_GUID)
    end)
    if not accepted or buffHandleOrError == nil then
        InvestigationLog(
            "reveal dispatch failed generation=" ..
            tostring(nextState.generation) ..
            " error=" .. tostring(buffHandleOrError)
        )
        return false
    end

    DarkPassengerInvestigation.revealBuffHandle = buffHandleOrError
    nextState.revealDispatched = true
    PersistState(nextState)
    DarkPassengerInvestigation.state = nextState
    InvestigationLog(
        "target revealed generation=" .. tostring(nextState.generation) ..
        " confidence=" .. tostring(nextState.confidence)
    )
    return true
end

function DarkPassengerInvestigation.Open(candidate, entity)
    if candidate == nil then
        InvestigationLog("open rejected: candidate unavailable")
        return false
    end
    if DarkPassengerInvestigation.entity ~= nil then
        RemoveRevealBuff(DarkPassengerInvestigation.entity)
    end
    local current = ReadState()
    local nextState, result = DarkPassengerInvestigation.Transition(
        current,
        {
            type = "open",
            generation = current.generation + 1,
        }
    )
    if not result.accepted then return false end

    DarkPassengerInvestigation.candidate = candidate
    DarkPassengerInvestigation.entity = ResolveEntity(candidate, entity)
    DarkPassengerInvestigation.state = nextState
    PersistState(nextState)
    if DarkPassengerEvidence ~= nil and
       DarkPassengerEvidence.OnInvestigationOpened ~= nil then
        DarkPassengerEvidence.OnInvestigationOpened(nextState.generation)
    end
    InvestigationLog(
        "opened generation=" .. tostring(nextState.generation) ..
        " region=" .. tostring(candidate.gameRegion) ..
        " settlement=" .. tostring(candidate.settlement) ..
        " slot=" .. tostring(candidate.slot)
    )
    return true
end

function DarkPassengerInvestigation.Restore(candidate, entity)
    local current = ReadState()
    local nextState, result = DarkPassengerInvestigation.Transition(
        current,
        { type = "restore" }
    )
    if not result.accepted or not nextState.active then return false end

    candidate = candidate or FindCandidateByActiveSlot()
    if candidate == nil then
        InvestigationLog("restore deferred: active target slot unavailable")
        return false
    end
    entity = ResolveEntity(candidate, entity)
    DarkPassengerInvestigation.candidate = candidate
    DarkPassengerInvestigation.entity = entity
    DarkPassengerInvestigation.state = nextState
    if nextState.revealed then DispatchReveal(nextState, entity) end
    if DarkPassengerEvidence ~= nil and
       DarkPassengerEvidence.Restore ~= nil then
        DarkPassengerEvidence.Restore(nextState)
    end
    if DarkPassengerEvidenceRegistry ~= nil and
       DarkPassengerEvidenceRegistry.Restore ~= nil then
        DarkPassengerEvidenceRegistry.Restore(nextState.generation)
    end
    return true
end

function DarkPassengerInvestigation.AddEvidence(amount, label, generation)
    local current = ReadState()
    local nextState, result = DarkPassengerInvestigation.Transition(
        current,
        {
            type = "evidence",
            amount = amount,
            generation = generation,
        }
    )
    result.previous = current.confidence
    result.current = nextState.confidence
    result.generation = nextState.generation
    result.revealed = nextState.revealed
    if not result.accepted then
        InvestigationLog(
            "evidence rejected label=" .. tostring(label) ..
            " reason=" .. tostring(result.reason)
        )
        return result
    end

    DarkPassengerInvestigation.state = nextState
    PersistState(nextState)
    if result.revealRequested or
       (nextState.revealed and not nextState.revealDispatched) then
        result.revealDispatched = DispatchReveal(
            nextState,
            DarkPassengerInvestigation.entity
        )
    else
        result.revealDispatched = nextState.revealDispatched
    end
    InvestigationLog(
        "evidence label=" .. tostring(label) ..
        " old=" .. tostring(result.previous) ..
        " accepted=" .. tostring(result.delta) ..
        " new=" .. tostring(result.current) ..
        " generation=" .. tostring(result.generation) ..
        " reveal=" .. tostring(result.revealRequested)
    )
    return result
end

function DarkPassengerInvestigation.ReconcileEvidence(total, generation)
    local current = ReadState()
    local nextState, result = DarkPassengerInvestigation.Transition(
        current,
        {
            type = "reconcile",
            total = total,
            generation = generation,
        }
    )
    result.previous = current.confidence
    result.current = nextState.confidence
    result.generation = nextState.generation
    result.revealed = nextState.revealed
    if not result.accepted then
        InvestigationLog(
            "reconciliation rejected reason=" .. tostring(result.reason) ..
            " total=" .. tostring(total) ..
            " generation=" .. tostring(generation)
        )
        return result
    end

    DarkPassengerInvestigation.state = nextState
    if result.reason ~= "evidence_unchanged" then
        PersistState(nextState)
    end
    if result.revealRequested or
       (nextState.revealed and not nextState.revealDispatched) then
        result.revealDispatched = DispatchReveal(
            nextState,
            DarkPassengerInvestigation.entity
        )
    else
        result.revealDispatched = nextState.revealDispatched
    end
    InvestigationLog(
        "evidence reconciled old=" .. tostring(result.previous) ..
        " new=" .. tostring(result.current) ..
        " generation=" .. tostring(result.generation) ..
        " reveal=" .. tostring(result.revealRequested)
    )
    return result
end

function DarkPassengerInvestigation.OnTargetDeath(generation)
    local current = ReadState()
    local nextState, result = DarkPassengerInvestigation.Transition(
        current,
        {
            type = "target_death",
            generation = generation,
        }
    )
    if not result.accepted then return false end
    DarkPassengerInvestigation.state = nextState
    PersistState(nextState)
    return true
end

function DarkPassengerInvestigation.DebugSetConfidence(confidence, generation)
    local current = ReadState()
    confidence = tonumber(confidence)
    generation = tonumber(generation)
    if current.active ~= true or confidence == nil or confidence < 0 or
       confidence >= DarkPassengerInvestigation.REVEAL_THRESHOLD or
       generation == nil or generation ~= current.generation then
        InvestigationLog(
            "debug confidence rejected value=" .. tostring(confidence) ..
            " generation=" .. tostring(generation)
        )
        return false
    end
    if current.revealed or current.revealDispatched then
        RemoveRevealBuff(ResolveEntity(
            DarkPassengerInvestigation.candidate,
            DarkPassengerInvestigation.entity
        ))
    end
    current.confidence = confidence
    current.revealed = false
    current.revealDispatched = false
    DarkPassengerInvestigation.state = current
    if not PersistState(current) then return false end
    InvestigationLog(
        "debug confidence set value=" .. tostring(confidence) ..
        " generation=" .. tostring(generation)
    )
    return true
end

function DarkPassengerInvestigation.Clear(entity)
    local current = ReadState()
    local nextState, result = DarkPassengerInvestigation.Transition(
        current,
        {
            type = "clear",
            generation = current.generation,
        }
    )
    entity = ResolveEntity(
        DarkPassengerInvestigation.candidate,
        entity or DarkPassengerInvestigation.entity
    )
    RemoveRevealBuff(entity)
    DarkPassengerInvestigation.candidate = nil
    DarkPassengerInvestigation.entity = nil
    DarkPassengerInvestigation.revealBuffHandle = nil
    DarkPassengerInvestigation.state = nextState
    PersistState(nextState)
    return result.accepted
end

function DarkPassengerInvestigation.Status()
    local state = ReadState()
    local candidate =
        DarkPassengerInvestigation.candidate or FindCandidateByActiveSlot()
    local entity = ResolveEntity(
        candidate,
        DarkPassengerInvestigation.entity
    )
    InvestigationLog(
        "status active=" .. tostring(state.active) ..
        " generation=" .. tostring(state.generation) ..
        " region=" ..
            tostring(candidate ~= nil and candidate.gameRegion or nil) ..
        " settlement=" ..
            tostring(candidate ~= nil and candidate.settlement or nil) ..
        " slot=" .. tostring(candidate ~= nil and candidate.slot or nil) ..
        " confidence=" .. tostring(state.confidence) ..
        " revealed=" .. tostring(state.revealed) ..
        " dispatched=" .. tostring(state.revealDispatched) ..
        " targetBuff=" ..
            tostring(HasBuff(
                entity,
                DarkPassengerInvestigation.TARGET_BUFF_GUID
            )) ..
        " revealBuff=" ..
            tostring(HasBuff(
                entity,
                DarkPassengerInvestigation.REVEAL_BUFF_GUID
            ))
    )
    return state
end

function DarkPassengerInvestigation.RunSelfTest()
    local failures = {}
    local function Expect(condition, label)
        if not condition then table.insert(failures, label) end
    end

    local state = DefaultState()
    local result = nil
    state, result = DarkPassengerInvestigation.Transition(
        state,
        { type = "open", generation = 1 }
    )
    Expect(
        result.accepted and state.active and state.confidence == 0 and
        not state.revealed,
        "open"
    )
    local beforeInvalid = state
    state, result = DarkPassengerInvestigation.Transition(
        state,
        { type = "evidence", amount = 0, generation = 1 }
    )
    Expect(
        not result.accepted and
        state.confidence == beforeInvalid.confidence,
        "invalid evidence"
    )
    state, result = DarkPassengerInvestigation.Transition(
        state,
        { type = "evidence", amount = 69, generation = 1 }
    )
    Expect(
        result.accepted and state.confidence == 69 and
        not state.revealed and not result.revealRequested,
        "sixty nine"
    )
    state, result = DarkPassengerInvestigation.Transition(
        state,
        { type = "evidence", amount = 1, generation = 1 }
    )
    Expect(
        state.confidence == 70 and state.revealed and
        result.revealRequested,
        "reveal threshold"
    )
    local restored, restoredResult =
        DarkPassengerInvestigation.Transition(state, { type = "restore" })
    Expect(
        restoredResult.accepted and
        restored.generation == state.generation and
        restored.confidence == state.confidence,
        "restore"
    )
    state, result = DarkPassengerInvestigation.Transition(
        state,
        { type = "evidence", amount = 90, generation = 1 }
    )
    Expect(
        state.confidence == 100 and not result.revealRequested,
        "clamp and one shot"
    )
    state, result = DarkPassengerInvestigation.Transition(
        state,
        { type = "open", generation = 2 }
    )
    Expect(
        result.accepted and state.generation == 2 and
        state.confidence == 0 and not state.revealed,
        "new generation"
    )
    local reconcileState, reconcileResult =
        DarkPassengerInvestigation.Transition(
            state,
            { type = "reconcile", total = 50, generation = 2 }
        )
    Expect(
        reconcileResult.accepted and reconcileState.confidence == 50 and
        reconcileResult.delta == 50,
        "reconcile exact total"
    )
    reconcileState, reconcileResult =
        DarkPassengerInvestigation.Transition(
            reconcileState,
            { type = "reconcile", total = 50, generation = 2 }
        )
    Expect(
        reconcileResult.accepted and
        reconcileResult.reason == "evidence_unchanged" and
        reconcileResult.delta == 0,
        "reconcile idempotent"
    )
    reconcileState, reconcileResult =
        DarkPassengerInvestigation.Transition(
            reconcileState,
            { type = "reconcile", total = 40, generation = 2 }
        )
    Expect(
        not reconcileResult.accepted and
        reconcileResult.reason == "non_monotonic_confidence" and
        reconcileState.confidence == 50,
        "reconcile rejects regression"
    )
    reconcileState, reconcileResult =
        DarkPassengerInvestigation.Transition(
            reconcileState,
            { type = "reconcile", total = 70, generation = 2 }
        )
    Expect(
        reconcileResult.accepted and reconcileState.revealed and
        reconcileResult.revealRequested,
        "reconcile reveal once"
    )
    state, result = DarkPassengerInvestigation.Transition(
        state,
        { type = "evidence", amount = 10, generation = 1 }
    )
    Expect(
        not result.accepted and state.confidence == 0,
        "stale callback"
    )
    state, result = DarkPassengerInvestigation.Transition(
        state,
        { type = "clear", generation = 2 }
    )
    Expect(
        result.accepted and not state.active and state.confidence == 0 and
        not state.revealed,
        "clear"
    )

    local passed = #failures == 0
    InvestigationLog(
        "selftest " .. (passed and "PASS" or "FAIL") ..
        " failures=" .. table.concat(failures, ",")
    )
    return passed
end

pcall(function()
    if System ~= nil and System.AddCCommand ~= nil then
        System.AddCCommand("dp_investigation_status",
            "DarkPassengerInvestigation.Status()",
            "Dark Passenger: print persistent investigation state")
        System.AddCCommand("dp_investigation_selftest",
            "DarkPassengerInvestigation.RunSelfTest()",
            "Dark Passenger: run pure investigation transition checks")
    end
end)

InvestigationLog("module loaded")
