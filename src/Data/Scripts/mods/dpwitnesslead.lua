DarkPassengerWitnessLead = DarkPassengerWitnessLead or {}

DarkPassengerWitnessLead.SCHEMA_VERSION = 1
DarkPassengerWitnessLead.AVAILABLE_BUFF_GUID = "a823ebb8-f3e3-4437-b885-9fafea591858"

local KEYS = {
    schema = "dp_witness_lead_schema_version",
    availableGeneration = "dp_witness_lead_available_generation",
    awardedGeneration = "dp_witness_lead_awarded_generation",
}

local function Log(message)
    if System ~= nil and System.LogAlways ~= nil then
        System.LogAlways(
            "[DarkPassenger][WitnessLead] " .. tostring(message)
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
    return { availableGeneration = 0, awardedGeneration = 0 }
end

local function CopyState(state)
    return {
        availableGeneration =
            tonumber(state ~= nil and state.availableGeneration) or 0,
        awardedGeneration =
            tonumber(state ~= nil and state.awardedGeneration) or 0,
    }
end

local function ReadState()
    if tonumber(ReadScalar(KEYS.schema)) ~=
       DarkPassengerWitnessLead.SCHEMA_VERSION then
        return DefaultState()
    end
    return {
        availableGeneration =
            tonumber(ReadScalar(KEYS.availableGeneration)) or 0,
        awardedGeneration =
            tonumber(ReadScalar(KEYS.awardedGeneration)) or 0,
    }
end

local function PersistState(state)
    local results = {
        WriteScalar(KEYS.schema, DarkPassengerWitnessLead.SCHEMA_VERSION),
        WriteScalar(KEYS.availableGeneration, state.availableGeneration),
        WriteScalar(KEYS.awardedGeneration, state.awardedGeneration),
    }
    for _, succeeded in ipairs(results) do
        if not succeeded then return false end
    end
    return true
end

local function PlayerEntity()
    if g_localActor ~= nil then return g_localActor end
    if player ~= nil then return player end
    if System ~= nil and System.GetEntityByName ~= nil then
        return System.GetEntityByName("dude")
    end
    return nil
end

local function HasAvailabilityBuff()
    local actor = PlayerEntity()
    if actor == nil or actor.soul == nil or
       actor.soul.HasBuffDebug == nil then
        return false
    end
    local ok, result = pcall(function()
        return actor.soul:HasBuffDebug(
            DarkPassengerWitnessLead.AVAILABLE_BUFF_GUID
        )
    end)
    return ok and (result == true or result == 1)
end

local function AddAvailabilityBuff()
    local actor = PlayerEntity()
    if actor == nil or actor.soul == nil or actor.soul.AddBuff == nil then
        return false
    end
    if HasAvailabilityBuff() then return true end
    local ok, handle = pcall(function()
        return actor.soul:AddBuff(
            DarkPassengerWitnessLead.AVAILABLE_BUFF_GUID
        )
    end)
    return ok and handle ~= nil
end

local function RemoveAvailabilityBuff()
    local actor = PlayerEntity()
    if actor == nil or actor.soul == nil or
       actor.soul.RemoveAllBuffsByGuid == nil then
        return false
    end
    local ok = pcall(function()
        actor.soul:RemoveAllBuffsByGuid(
            DarkPassengerWitnessLead.AVAILABLE_BUFF_GUID
        )
    end)
    return ok
end

local function InvestigationContext()
    if DarkPassengerInvestigation == nil or
       DarkPassengerInvestigation.GetState == nil or
       DarkPassengerInvestigation.GetCandidate == nil then
        return nil, nil
    end
    return DarkPassengerInvestigation.GetState(),
        DarkPassengerInvestigation.GetCandidate()
end

local function ResolveWitness()
    if DarkPassengerCaseEvidence == nil or
       DarkPassengerCaseEvidence.ResolveActive == nil then
        return nil
    end
    return DarkPassengerCaseEvidence.ResolveActive("witness")
end

local function MatchesActiveCanary(generation)
    local investigation, candidate = InvestigationContext()
    local resolved = ResolveWitness()
    return investigation ~= nil and investigation.active == true and
        tonumber(investigation.generation) == tonumber(generation) and
        candidate ~= nil and resolved ~= nil and
        tonumber(resolved.generation) == tonumber(generation)
end

function DarkPassengerWitnessLead.Transition(state, event)
    local nextState = CopyState(state)
    local eventType = event ~= nil and event.type or nil
    local generation = tonumber(event ~= nil and event.generation)
    if generation == nil or generation <= 0 then
        return nextState, { accepted = false, reason = "invalid_generation" }
    end

    if eventType == "open" then
        if nextState.awardedGeneration == generation then
            return nextState, { accepted = false, reason = "already_awarded" }
        end
        nextState.availableGeneration = generation
        return nextState, { accepted = true, reason = "opened" }
    end

    if eventType == "award" then
        if nextState.awardedGeneration == generation then
            return nextState, { accepted = false, reason = "already_awarded" }
        end
        if nextState.availableGeneration ~= generation then
            return nextState, { accepted = false, reason = "not_available" }
        end
        nextState.availableGeneration = 0
        nextState.awardedGeneration = generation
        return nextState, { accepted = true, reason = "awarded" }
    end

    if eventType == "restore" then
        return nextState, { accepted = true, reason = "restored" }
    end

    return nextState, { accepted = false, reason = "unknown_event" }
end

function DarkPassengerWitnessLead.Start(generation)
    generation = tonumber(generation)
    if generation == nil or not MatchesActiveCanary(generation) then
        Log("start rejected generation=" .. tostring(generation))
        return false
    end
    local state = ReadState()
    if state.awardedGeneration == generation then
        RemoveAvailabilityBuff()
        return true
    end
    local nextState, result = DarkPassengerWitnessLead.Transition(
        state,
        { type = "open", generation = generation }
    )
    if not result.accepted or not PersistState(nextState) then return false end
    if not AddAvailabilityBuff() then
        Log("availability deferred generation=" .. tostring(generation))
        return false
    end
    Log("available generation=" .. tostring(generation))
    return true
end

function DarkPassengerWitnessLead.Restore(generation)
    generation = tonumber(generation)
    if generation == nil or not MatchesActiveCanary(generation) then
        RemoveAvailabilityBuff()
        return false
    end
    local state = ReadState()
    if state.awardedGeneration == generation then
        RemoveAvailabilityBuff()
        return true
    end
    if state.availableGeneration ~= generation then
        return DarkPassengerWitnessLead.Start(generation)
    end
    return AddAvailabilityBuff()
end

function DarkPassengerWitnessLead.OnDialogueCompleted(gameRegion)
    local resolved = ResolveWitness()
    if resolved == nil or resolved.caseTemplate == nil or
       resolved.caseTemplate.constraints == nil or
       gameRegion ~= resolved.caseTemplate.constraints.region then
        return false
    end
    local investigation = DarkPassengerInvestigation ~= nil and
        DarkPassengerInvestigation.GetState ~= nil and
        DarkPassengerInvestigation.GetState() or nil
    local generation = tonumber(
        investigation ~= nil and investigation.generation
    )
    if generation == nil or not MatchesActiveCanary(generation) then
        Log("dialogue rejected: active canary mismatch")
        return false
    end

    local state = ReadState()
    if state.awardedGeneration == generation then
        RemoveAvailabilityBuff()
        return true
    end
    if state.availableGeneration ~= generation then
        Log("dialogue rejected: witness lead unavailable")
        return false
    end

    local evidenceResult = DarkPassengerInvestigation.AddEvidence(
        resolved.evidence.confidence,
        resolved.evidence.id,
        generation
    )
    if evidenceResult == nil or evidenceResult.accepted ~= true then
        Log(
            "dialogue evidence rejected reason=" ..
            tostring(evidenceResult ~= nil and evidenceResult.reason or nil)
        )
        return false
    end

    local nextState, transition = DarkPassengerWitnessLead.Transition(
        state,
        { type = "award", generation = generation }
    )
    if not transition.accepted or not PersistState(nextState) then return false end
    RemoveAvailabilityBuff()
    Log(
        "awarded generation=" .. tostring(generation) ..
        " confidence=" .. tostring(evidenceResult.current)
    )
    return true
end

function DarkPassengerWitnessLead.Status()
    local state = ReadState()
    Log(
        "status availableGeneration=" ..
        tostring(state.availableGeneration) ..
        " awardedGeneration=" .. tostring(state.awardedGeneration) ..
        " hasBuff=" .. tostring(HasAvailabilityBuff())
    )
    return state
end

function DarkPassengerWitnessLead.RunSelfTest()
    local failures = {}
    local function Expect(condition, label)
        if not condition then table.insert(failures, label) end
    end
    local state = DefaultState()
    local opened
    state, opened = DarkPassengerWitnessLead.Transition(
        state,
        { type = "open", generation = 8 }
    )
    Expect(opened.accepted and state.availableGeneration == 8, "open")
    local awarded
    state, awarded = DarkPassengerWitnessLead.Transition(
        state,
        { type = "award", generation = 8 }
    )
    Expect(
        awarded.accepted and state.availableGeneration == 0 and
        state.awardedGeneration == 8,
        "award"
    )
    local duplicateState, duplicate = DarkPassengerWitnessLead.Transition(
        state,
        { type = "award", generation = 8 }
    )
    Expect(
        not duplicate.accepted and duplicate.reason == "already_awarded" and
        duplicateState.awardedGeneration == 8,
        "duplicate"
    )
    local staleState, stale = DarkPassengerWitnessLead.Transition(
        DefaultState(),
        { type = "award", generation = 7 }
    )
    Expect(
        not stale.accepted and stale.reason == "not_available" and
        staleState.awardedGeneration == 0,
        "requires availability"
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
            "dp_witness_lead_status",
            "DarkPassengerWitnessLead.Status()",
            "Dark Passenger: print tavern-witness lead state"
        )
        System.AddCCommand(
            "dp_witness_lead_selftest",
            "DarkPassengerWitnessLead.RunSelfTest()",
            "Dark Passenger: run tavern-witness lead self-test"
        )
    end
end)

Log("module loaded")
