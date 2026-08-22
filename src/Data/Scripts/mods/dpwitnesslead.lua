DarkPassengerWitnessLead = DarkPassengerWitnessLead or {}

DarkPassengerWitnessLead.SCHEMA_VERSION = 2
DarkPassengerWitnessLead.AVAILABLE_BUFF_GUID = "a823ebb8-f3e3-4437-b885-9fafea591858"

local KEYS = {
    schema = "dp_witness_lead_schema_version",
    availableGeneration = "dp_witness_lead_available_generation",
    legacyAwardedGeneration = "dp_witness_lead_awarded_generation",
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
    return { availableGeneration = 0, legacyAwardedGeneration = 0 }
end

local function CopyState(state)
    return {
        availableGeneration =
            tonumber(state ~= nil and state.availableGeneration) or 0,
        legacyAwardedGeneration = tonumber(
            state ~= nil and state.legacyAwardedGeneration
        ) or 0,
    }
end

local function ReadState()
    local schema = tonumber(ReadScalar(KEYS.schema))
    if schema == DarkPassengerWitnessLead.SCHEMA_VERSION then
        return {
            availableGeneration =
                tonumber(ReadScalar(KEYS.availableGeneration)) or 0,
            legacyAwardedGeneration = 0,
        }
    end
    if schema == 1 then
        return {
            availableGeneration =
                tonumber(ReadScalar(KEYS.availableGeneration)) or 0,
            legacyAwardedGeneration = tonumber(
                ReadScalar(KEYS.legacyAwardedGeneration)
            ) or 0,
        }
    end
    return DefaultState()
end

local function PersistState(state)
    local results = {
        WriteScalar(KEYS.schema, DarkPassengerWitnessLead.SCHEMA_VERSION),
        WriteScalar(KEYS.availableGeneration, state.availableGeneration),
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

local function IsDiscovered(generation, resolved)
    if resolved == nil or resolved.evidence == nil or
       DarkPassengerEvidenceRegistry == nil or
       DarkPassengerEvidenceRegistry.GetCaseState == nil then
        return false
    end
    local registryState =
        DarkPassengerEvidenceRegistry.GetCaseState(generation)
    for _, entry in ipairs(
        registryState ~= nil and registryState.evidence or {}
    ) do
        if tonumber(entry.code) == tonumber(resolved.evidence.code) then
            return entry.status == "discovered"
        end
    end
    return false
end

local function MigrateLegacyDiscovery(generation, state, resolved)
    if tonumber(state.legacyAwardedGeneration) ~= tonumber(generation) then
        return true
    end
    if DarkPassengerEvidenceRegistry == nil or
       DarkPassengerEvidenceRegistry.Discover == nil then
        return false
    end
    local result = DarkPassengerEvidenceRegistry.Discover(
        generation,
        resolved.evidence.code,
        { source = "legacy_witness_award" }
    )
    if result == nil or (
        result.accepted ~= true and result.reason ~= "already_discovered"
    ) then
        return false
    end
    state.legacyAwardedGeneration = 0
    state.availableGeneration = 0
    return PersistState(state)
end

function DarkPassengerWitnessLead.Transition(state, event)
    local nextState = CopyState(state)
    local eventType = event ~= nil and event.type or nil
    local generation = tonumber(event ~= nil and event.generation)
    if generation == nil or generation <= 0 then
        return nextState, { accepted = false, reason = "invalid_generation" }
    end

    if eventType == "open" then
        nextState.availableGeneration = generation
        return nextState, { accepted = true, reason = "opened" }
    end

    if eventType == "close" then
        nextState.availableGeneration = 0
        return nextState, { accepted = true, reason = "closed" }
    end

    if eventType == "restore" then
        return nextState, { accepted = true, reason = "restored" }
    end

    return nextState, { accepted = false, reason = "unknown_event" }
end

function DarkPassengerWitnessLead.Start(generation)
    return DarkPassengerWitnessLead.ApplyAvailability(generation, true)
end

function DarkPassengerWitnessLead.ApplyAvailability(generation, available)
    generation = tonumber(generation)
    if generation == nil or not MatchesActiveCanary(generation) then
        RemoveAvailabilityBuff()
        return false
    end
    local state = ReadState()
    local resolved = ResolveWitness()
    if not MigrateLegacyDiscovery(generation, state, resolved) then
        return false
    end
    state = ReadState()
    if IsDiscovered(generation, resolved) then available = false end
    local nextState, result = DarkPassengerWitnessLead.Transition(
        state,
        { type = available and "open" or "close", generation = generation }
    )
    if not result.accepted or not PersistState(nextState) then return false end
    if not available then
        RemoveAvailabilityBuff()
        return true
    end
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
    local resolved = ResolveWitness()
    if not MigrateLegacyDiscovery(generation, state, resolved) then
        return false
    end
    if DarkPassengerLeadPlanner ~= nil and
       DarkPassengerLeadPlanner.Apply ~= nil then
        return DarkPassengerLeadPlanner.Apply(generation) ~= nil
    end
    return DarkPassengerWitnessLead.ApplyAvailability(generation, false)
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
    if not MigrateLegacyDiscovery(generation, state, resolved) then
        return false
    end
    state = ReadState()
    if IsDiscovered(generation, resolved) then
        RemoveAvailabilityBuff()
        return true
    end
    if state.availableGeneration ~= generation then
        Log("dialogue rejected: witness lead unavailable")
        return false
    end

    local evidenceResult = DarkPassengerEvidenceRegistry.Discover(
        generation,
        resolved.evidence.code,
        { source = "witness_dialogue" }
    )
    if evidenceResult == nil or evidenceResult.accepted ~= true then
        Log(
            "dialogue evidence rejected reason=" ..
            tostring(evidenceResult ~= nil and evidenceResult.reason or nil)
        )
        return false
    end

    DarkPassengerWitnessLead.ApplyAvailability(generation, false)
    Log(
        "awarded generation=" .. tostring(generation) ..
        " confidence=" .. tostring(evidenceResult.current) ..
        " configured=" .. tostring(resolved.evidence.confidence)
    )
    return true
end

function DarkPassengerWitnessLead.Status()
    local state = ReadState()
    Log(
        "status availableGeneration=" ..
        tostring(state.availableGeneration) ..
        " legacyAwardedGeneration=" ..
        tostring(state.legacyAwardedGeneration) ..
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
    local closed
    state, closed = DarkPassengerWitnessLead.Transition(
        state,
        { type = "close", generation = 8 }
    )
    Expect(
        closed.accepted and state.availableGeneration == 0,
        "close"
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
