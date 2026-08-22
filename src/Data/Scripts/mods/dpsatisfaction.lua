DarkPassengerSatisfaction = DarkPassengerSatisfaction or {}

DarkPassengerSatisfaction.BUFF_GUID =
    "b5c59e05-cc10-4bf8-b82e-d82b913c841f"
DarkPassengerSatisfaction.buffHandle =
    DarkPassengerSatisfaction.buffHandle or nil

local function Log(message)
    System.LogAlways(
        "[DarkPassengerSatisfaction] " .. tostring(message)
    )
end

local function PlayerSoul()
    local player = System.GetEntityByName("dude")
    if player == nil or player.soul == nil then
        Log("player soul unavailable")
        return nil
    end

    return player.soul
end

local function HasBuff(soul)
    local present = false
    local ok, err = pcall(function()
        present = soul:HasBuffDebug(
            DarkPassengerSatisfaction.BUFF_GUID
        )
    end)

    if not ok then
        Log("HasBuffDebug failed: " .. tostring(err))
        return false
    end

    return present
end

function DarkPassengerSatisfaction.Add()
    local soul = PlayerSoul()
    if soul == nil then return false end

    if HasBuff(soul) then
        Log("add skipped: satisfaction already active")
        return true
    end

    DarkPassengerSatisfaction.buffHandle = nil

    local cleanupOk, cleanupErr = pcall(function()
        soul:RemoveAllBuffsByGuid(DarkPassengerSatisfaction.BUFF_GUID)
    end)
    if not cleanupOk then
        Log("pre-add cleanup failed: " .. tostring(cleanupErr))
    end

    local ok, handleOrError = pcall(function()
        return soul:AddBuff(DarkPassengerSatisfaction.BUFF_GUID)
    end)
    if ok and handleOrError ~= nil then
        DarkPassengerSatisfaction.buffHandle = handleOrError
    end

    Log(
        "add ok=" .. tostring(ok) ..
        " handle=" .. tostring(DarkPassengerSatisfaction.buffHandle) ..
        " err=" .. tostring(ok and nil or handleOrError)
    )
    return ok and DarkPassengerSatisfaction.buffHandle ~= nil
end

function DarkPassengerSatisfaction.Remove()
    local soul = PlayerSoul()
    if soul == nil then return false end

    local ok, err = pcall(function()
        soul:RemoveAllBuffsByGuid(DarkPassengerSatisfaction.BUFF_GUID)
    end)
    DarkPassengerSatisfaction.buffHandle = nil

    Log("remove ok=" .. tostring(ok) .. " err=" .. tostring(err))
    return ok
end

function DarkPassengerSatisfaction.Status()
    local soul = PlayerSoul()
    if soul == nil then return false end

    local present = HasBuff(soul)
    Log("present=" .. tostring(present))
    return present
end

pcall(function()
    System.AddCCommand(
        "dp_satisfaction_add",
        "DarkPassengerSatisfaction.Add()",
        "Add Dark Passenger satisfaction"
    )
    System.AddCCommand(
        "dp_satisfaction_remove",
        "DarkPassengerSatisfaction.Remove()",
        "Remove Dark Passenger satisfaction"
    )
    System.AddCCommand(
        "dp_satisfaction_status",
        "DarkPassengerSatisfaction.Status()",
        "Report Dark Passenger satisfaction state"
    )
end)

Log("loaded")
