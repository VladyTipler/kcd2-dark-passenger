-- Dark Passenger - Case State Machine
-- Auto-loaded from Data/Scripts/Startup/ by the engine at boot, BEFORE
-- Data/Scripts/mods/<modid>.lua runs. Declares global DarkPassengerCase.
-- Single active case for this vertical slice (multi-case/per-region is a
-- later module) -- keeps the state machine itself honest and testable.

DarkPassengerCase = {}

local STATES = {
    NONE = "NONE",
    OPEN = "OPEN",
    INVESTIGATING = "INVESTIGATING",
    READY = "READY",
    RESOLVED_CORRECT = "RESOLVED_CORRECT",
    RESOLVED_WRONG = "RESOLVED_WRONG",
}
DarkPassengerCase.STATES = STATES

local READY_THRESHOLD = 70

-- current case table, or nil if none open
local current = nil

local function NewCaseTable(targetId, targetName, archetype)
    return {
        target_id = targetId,
        target_name = targetName,
        archetype = archetype or "unknown",
        confidence = 0,
        state = STATES.OPEN,
        decoy_ids = {},
    }
end

-- Opens a new case against a tagged NPC. Overwrites any existing case.
function DarkPassengerCase.Open(targetId, targetName, archetype)
    current = NewCaseTable(targetId, targetName, archetype)
    System.LogAlways("[DarkPassengerCase] OPEN target='" .. tostring(targetName) ..
        "' archetype=" .. tostring(current.archetype) .. " confidence=0 state=" .. current.state)
    return current
end

-- Registers a decoy candidate (false lead) on the current case.
function DarkPassengerCase.AddDecoy(decoyId, decoyName)
    if current == nil then
        System.LogAlways("[DarkPassengerCase] AddDecoy failed: no open case.")
        return
    end
    table.insert(current.decoy_ids, { id = decoyId, name = decoyName })
    System.LogAlways("[DarkPassengerCase] decoy added: '" .. tostring(decoyName) .. "'")
end

-- Adds confidence (found evidence) to the current case.
-- OPEN -> INVESTIGATING on first evidence; INVESTIGATING -> READY at threshold.
function DarkPassengerCase.AddEvidence(amount, label)
    if current == nil then
        System.LogAlways("[DarkPassengerCase] AddEvidence failed: no open case.")
        return
    end
    if current.state == STATES.RESOLVED_CORRECT or current.state == STATES.RESOLVED_WRONG then
        System.LogAlways("[DarkPassengerCase] AddEvidence ignored: case already resolved.")
        return
    end

    current.confidence = current.confidence + (tonumber(amount) or 0)
    if current.confidence > 100 then current.confidence = 100 end
    if current.state == STATES.OPEN then current.state = STATES.INVESTIGATING end

    System.LogAlways("[DarkPassengerCase] evidence '" .. tostring(label) .. "' (+" ..
        tostring(amount) .. ") -> confidence=" .. tostring(current.confidence) ..
        " state=" .. current.state)

    if current.confidence >= READY_THRESHOLD and current.state ~= STATES.READY then
        current.state = STATES.READY
        System.LogAlways("[DarkPassengerCase] *** READY *** confidence=" ..
            tostring(current.confidence) .. " target='" .. tostring(current.target_name) ..
            "' -- marker should now resolve (see Q08).")
    end
end

-- Call on any player kill. Resolves the current case if the victim is the
-- target or a known decoy; unrelated kills leave the case untouched.
function DarkPassengerCase.ReportKill(victimId, victimName, method)
    if current == nil then
        System.LogAlways("[DarkPassengerCase] ReportKill: no open case, ignored.")
        return nil
    end
    if current.state == STATES.RESOLVED_CORRECT or current.state == STATES.RESOLVED_WRONG then
        System.LogAlways("[DarkPassengerCase] ReportKill: case already resolved, ignored.")
        return current.state
    end

    if tostring(victimId) == tostring(current.target_id) then
        current.state = STATES.RESOLVED_CORRECT
        System.LogAlways("[DarkPassengerCase] *** RESOLVED_CORRECT *** '" .. tostring(victimName) ..
            "' via " .. tostring(method) .. " (confidence was " .. tostring(current.confidence) .. ").")
        return STATES.RESOLVED_CORRECT
    end

    for _, decoy in ipairs(current.decoy_ids) do
        if tostring(victimId) == tostring(decoy.id) then
            current.state = STATES.RESOLVED_WRONG
            System.LogAlways("[DarkPassengerCase] *** RESOLVED_WRONG (decoy) *** killed '" ..
                tostring(victimName) .. "' instead of '" .. tostring(current.target_name) .. "'.")
            return STATES.RESOLVED_WRONG
        end
    end

    System.LogAlways("[DarkPassengerCase] kill of '" .. tostring(victimName) ..
        "' unrelated to case (target still '" .. tostring(current.target_name) .. "').")
    return nil
end

function DarkPassengerCase.GetCurrent()
    return current
end

System.LogAlways("[DarkPassengerCase] state machine loaded. states=OPEN/INVESTIGATING/READY/RESOLVED_CORRECT/RESOLVED_WRONG ready_threshold=" .. tostring(READY_THRESHOLD))