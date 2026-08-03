DarkPassengerCaseSnapshot = DarkPassengerCaseSnapshot or {}

DarkPassengerCaseSnapshot.SCHEMA_VERSION = 1

local KEYS = {
    schema = "dp_case_snapshot_schema_version",
    generation = "dp_case_snapshot_generation",
    caseCode = "dp_case_snapshot_case_code",
    openerCode = "dp_case_snapshot_opener_code",
    targetSlot = "dp_case_snapshot_target_slot",
}

local function Log(message)
    if System ~= nil and System.LogAlways ~= nil then
        System.LogAlways(
            "[DarkPassenger][CaseSnapshot] " .. tostring(message)
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
        caseCode = 0,
        openerCode = 0,
        targetSlot = 0,
    }
end

local function CopyState(state)
    return {
        generation = tonumber(state ~= nil and state.generation) or 0,
        caseCode = tonumber(state ~= nil and state.caseCode) or 0,
        openerCode = tonumber(state ~= nil and state.openerCode) or 0,
        targetSlot = tonumber(state ~= nil and state.targetSlot) or 0,
    }
end

local function ReadState()
    if tonumber(ReadScalar(KEYS.schema)) ~=
       DarkPassengerCaseSnapshot.SCHEMA_VERSION then
        return DefaultState()
    end
    return {
        generation = tonumber(ReadScalar(KEYS.generation)) or 0,
        caseCode = tonumber(ReadScalar(KEYS.caseCode)) or 0,
        openerCode = tonumber(ReadScalar(KEYS.openerCode)) or 0,
        targetSlot = tonumber(ReadScalar(KEYS.targetSlot)) or 0,
    }
end

local function PersistState(state)
    local writes = {
        WriteScalar(
            KEYS.schema,
            DarkPassengerCaseSnapshot.SCHEMA_VERSION
        ),
        WriteScalar(KEYS.generation, state.generation),
        WriteScalar(KEYS.caseCode, state.caseCode),
        WriteScalar(KEYS.openerCode, state.openerCode),
        WriteScalar(KEYS.targetSlot, state.targetSlot),
    }
    for _, succeeded in ipairs(writes) do
        if not succeeded then return false end
    end
    return true
end

local function FindCandidate(targetSlot)
    local expected = tonumber(targetSlot)
    if expected == nil or expected <= 0 or
       DarkPassengerGeneratedCandidates == nil then
        return nil
    end
    for _, candidate in ipairs(DarkPassengerGeneratedCandidates) do
        if tonumber(candidate.slot) == expected then return candidate end
    end
    return nil
end

local function SameIdentity(left, right)
    return tonumber(left.generation) == tonumber(right.generation) and
        tonumber(left.caseCode) == tonumber(right.caseCode) and
        tonumber(left.openerCode) == tonumber(right.openerCode) and
        tonumber(left.targetSlot) == tonumber(right.targetSlot)
end

-- The persisted snapshot contains numeric references only. Runtime world
-- bindings are always resolved from generated catalogs, so GUIDs and strings
-- never become a second save-data source of truth.
function DarkPassengerCaseSnapshot.Transition(state, event)
    local nextState = CopyState(state)
    local requested = CopyState(event)
    if requested.generation <= 0 or requested.caseCode <= 0 or
       requested.openerCode <= 0 or requested.targetSlot <= 0 then
        return nextState, { accepted = false, reason = "invalid_snapshot" }
    end
    if requested.generation < nextState.generation then
        return nextState, { accepted = false, reason = "stale_generation" }
    end
    if requested.generation == nextState.generation then
        if SameIdentity(nextState, requested) then
            return nextState, { accepted = true, reason = "restored" }
        end
        return nextState, { accepted = false, reason = "snapshot_conflict" }
    end
    return requested, { accepted = true, reason = "captured" }
end

local function Resolve(state)
    if state == nil or state.generation <= 0 then
        return nil, "snapshot_missing"
    end
    if DarkPassengerCaseContent == nil or
       DarkPassengerCaseContent.GetSelected == nil then
        return nil, "case_content_unavailable"
    end
    local selected = DarkPassengerCaseContent.GetSelected(state.generation)
    if selected == nil or
       tonumber(selected.caseCode) ~= tonumber(state.caseCode) or
       tonumber(selected.openerCode) ~= tonumber(state.openerCode) then
        return nil, "snapshot_conflict"
    end
    local candidate = FindCandidate(state.targetSlot)
    if candidate == nil then return nil, "candidate_unavailable" end
    local caseTemplate = selected.caseTemplate
    local constraints = caseTemplate ~= nil and
        caseTemplate.constraints or {}
    if constraints.region ~= nil and
       constraints.region ~= candidate.gameRegion then
        return nil, "candidate_region_mismatch"
    end
    if constraints.settlement ~= nil and
       constraints.settlement ~= candidate.settlement then
        return nil, "candidate_settlement_mismatch"
    end
    return {
        generation = state.generation,
        caseCode = state.caseCode,
        openerCode = state.openerCode,
        targetSlot = state.targetSlot,
        candidate = candidate,
        region = candidate.gameRegion,
        settlement = candidate.settlement,
        selected = selected,
        caseTemplate = caseTemplate,
        opener = selected.rumor,
        bindings = caseTemplate.bindings,
    }, "resolved"
end

function DarkPassengerCaseSnapshot.Capture(generation, candidate, selected)
    generation = tonumber(generation)
    if selected == nil and DarkPassengerCaseContent ~= nil and
       DarkPassengerCaseContent.GetSelected ~= nil then
        selected = DarkPassengerCaseContent.GetSelected(generation)
    end
    if candidate == nil and DarkPassengerInvestigation ~= nil and
       DarkPassengerInvestigation.GetCandidate ~= nil then
        candidate = DarkPassengerInvestigation.GetCandidate()
    end
    local nextState, result = DarkPassengerCaseSnapshot.Transition(
        ReadState(),
        {
            generation = generation,
            caseCode = selected ~= nil and selected.caseCode or 0,
            openerCode = selected ~= nil and selected.openerCode or 0,
            targetSlot = candidate ~= nil and candidate.slot or 0,
        }
    )
    if not result.accepted then
        Log(
            "capture rejected generation=" .. tostring(generation) ..
            " reason=" .. tostring(result.reason)
        )
        return nil, result.reason
    end
    if not PersistState(nextState) then return nil, "persistence_failed" end
    local snapshot, reason = Resolve(nextState)
    Log(
        "capture generation=" .. tostring(generation) ..
        " reason=" .. tostring(result.reason) ..
        " resolved=" .. tostring(reason)
    )
    return snapshot, reason
end

function DarkPassengerCaseSnapshot.Get(generation)
    local state = ReadState()
    if generation ~= nil and
       tonumber(generation) ~= tonumber(state.generation) then
        return nil, "stale_generation"
    end
    return Resolve(state)
end

function DarkPassengerCaseSnapshot.Restore(generation)
    return DarkPassengerCaseSnapshot.Get(generation)
end

function DarkPassengerCaseSnapshot.RunSelfTest()
    local first, firstResult = DarkPassengerCaseSnapshot.Transition(
        DefaultState(),
        { generation = 4, caseCode = 1001, openerCode = 1101, targetSlot = 9 }
    )
    local restored, restoredResult = DarkPassengerCaseSnapshot.Transition(
        first,
        { generation = 4, caseCode = 1001, openerCode = 1101, targetSlot = 9 }
    )
    local _, conflict = DarkPassengerCaseSnapshot.Transition(
        first,
        { generation = 4, caseCode = 1001, openerCode = 1101, targetSlot = 10 }
    )
    local _, stale = DarkPassengerCaseSnapshot.Transition(
        first,
        { generation = 3, caseCode = 1001, openerCode = 1101, targetSlot = 9 }
    )
    local passed = firstResult.accepted and
        firstResult.reason == "captured" and
        restoredResult.accepted and restoredResult.reason == "restored" and
        SameIdentity(first, restored) and
        conflict.reason == "snapshot_conflict" and
        stale.reason == "stale_generation"
    Log("selftest=" .. tostring(passed))
    return passed
end

pcall(function()
    if System ~= nil and System.AddCCommand ~= nil then
        System.AddCCommand(
            "dp_case_snapshot_selftest",
            "DarkPassengerCaseSnapshot.RunSelfTest()",
            "Dark Passenger: run immutable case-snapshot checks"
        )
    end
end)

Log("module loaded")
