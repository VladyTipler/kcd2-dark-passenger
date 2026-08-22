DarkPassengerEvidenceReaction = DarkPassengerEvidenceReaction or {}

DarkPassengerEvidenceReaction.SCHEMA_VERSION = 2
DarkPassengerEvidenceReaction.SAFE_METAROLE = nil

local function Log(message)
    if System ~= nil and System.LogAlways ~= nil then
        System.LogAlways(
            "[DarkPassenger][EvidenceReaction] " .. tostring(message)
        )
    end
end

local function SafeEvidenceId(evidenceId)
    if evidenceId == nil then return nil end
    local safe = tostring(evidenceId):gsub("[^%w_]", "_")
    if safe == "" then return nil end
    return safe
end

local function StateKey(evidenceId, suffix)
    local safe = SafeEvidenceId(evidenceId)
    if safe == nil then return nil end
    return "dp_evidence_reaction_" .. safe .. "_" .. suffix
end

local function ReadScalar(key)
    if key == nil or Variables == nil or Variables.GetGlobal == nil then
        return nil
    end
    local ok, value = pcall(function() return Variables.GetGlobal(key) end)
    if not ok then
        Log("read failed key=" .. tostring(key) .. " error=" .. tostring(value))
        return nil
    end
    return value
end

local function WriteScalar(key, value)
    if key == nil or Variables == nil or Variables.SetGlobal == nil then
        return false
    end
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

local function ReadState(evidenceId)
    return {
        schema = tonumber(ReadScalar(StateKey(evidenceId, "schema"))) or 0,
        dispatchedGeneration = tonumber(
            ReadScalar(StateKey(evidenceId, "dispatched_generation"))
        ) or 0,
    }
end

local function PersistDispatch(evidenceId, generation)
    return WriteScalar(
        StateKey(evidenceId, "schema"),
        DarkPassengerEvidenceReaction.SCHEMA_VERSION
    ) and WriteScalar(
        StateKey(evidenceId, "dispatched_generation"),
        generation
    )
end

function DarkPassengerEvidenceReaction.Dispatch(evidenceId, generation)
    generation = tonumber(generation)
    if SafeEvidenceId(evidenceId) == nil or
       generation == nil or generation <= 0 then
        return { accepted = false, reason = "invalid_request" }
    end

    local state = ReadState(evidenceId)
    if state.dispatchedGeneration == generation then
        return { accepted = false, reason = "already_dispatched" }
    end

    local metarole = DarkPassengerEvidenceReaction.SAFE_METAROLE
    if metarole == nil or tostring(metarole) == "" then
        return { accepted = false, reason = "no_safe_reaction" }
    end

    if DialogUtils == nil or
       DialogUtils.RequestPlayerMonologByMetarole == nil then
        return { accepted = false, reason = "monologue_unavailable" }
    end

    local ok, errorMessage = pcall(function()
        DialogUtils.RequestPlayerMonologByMetarole(
            metarole
        )
    end)
    if not ok then
        Log("monologue request failed error=" .. tostring(errorMessage))
        return { accepted = false, reason = "monologue_failed" }
    end

    if not PersistDispatch(evidenceId, generation) then
        return { accepted = false, reason = "dispatch_persist_failed" }
    end

    Log(
        "dispatched evidenceId=" .. tostring(evidenceId) ..
        " generation=" .. tostring(generation) ..
        " metarole=" .. tostring(metarole)
    )
    return {
        accepted = true,
        reason = "dispatched",
        reaction = "vanilla_metarole",
        metarole = metarole,
    }
end

function DarkPassengerEvidenceReaction.Restore(evidenceId, generation)
    return DarkPassengerEvidenceReaction.Dispatch(evidenceId, generation)
end

function DarkPassengerEvidenceReaction.Reset(evidenceId)
    if SafeEvidenceId(evidenceId) == nil then return false end
    return WriteScalar(
        StateKey(evidenceId, "schema"),
        DarkPassengerEvidenceReaction.SCHEMA_VERSION
    ) and WriteScalar(
        StateKey(evidenceId, "dispatched_generation"),
        0
    )
end

function DarkPassengerEvidenceReaction.RunSelfTest()
    local passed =
        StateKey("vojtech-belongings", "schema") ==
        "dp_evidence_reaction_vojtech_belongings_schema" and
        SafeEvidenceId(nil) == nil
    Log("selftest=" .. tostring(passed))
    return passed
end

pcall(function()
    if System ~= nil and System.AddCCommand ~= nil then
        System.AddCCommand(
            "dp_evidence_reaction_selftest",
            "DarkPassengerEvidenceReaction.RunSelfTest()",
            "Dark Passenger: run evidence reaction self-test"
        )
    end
end)

Log("module loaded")
