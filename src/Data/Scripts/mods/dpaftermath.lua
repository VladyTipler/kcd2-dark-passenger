DarkPassengerAftermath = DarkPassengerAftermath or {}

DarkPassengerAftermath.PHASE_HUNTING = "HUNTING"
DarkPassengerAftermath.PHASE_SILENCE_CHECK = "SILENCE_CHECK"
DarkPassengerAftermath.PHASE_CLEANUP = "CLEANUP"
DarkPassengerAftermath.PHASE_RESOLVED = "RESOLVED"

DarkPassengerAftermath.SILENCE_DURATION_MS = 90000
DarkPassengerAftermath.DEFAULT_ZONE_RADIUS = 120

DarkPassengerAftermath.phase =
    DarkPassengerAftermath.phase or DarkPassengerAftermath.PHASE_HUNTING
DarkPassengerAftermath.generation =
    tonumber(DarkPassengerAftermath.generation) or 0
DarkPassengerAftermath.timerActive =
    DarkPassengerAftermath.timerActive == true
DarkPassengerAftermath.exposed =
    DarkPassengerAftermath.exposed == true
DarkPassengerAftermath.collateralCount =
    tonumber(DarkPassengerAftermath.collateralCount) or 0
DarkPassengerAftermath.witnessRemovedCount =
    tonumber(DarkPassengerAftermath.witnessRemovedCount) or 0

local function Log(message)
    if System ~= nil and System.LogAlways ~= nil then
        System.LogAlways(
            "[DarkPassenger][Aftermath] " .. tostring(message)
        )
    end
end

local function NumberOr(value, fallback)
    local parsed = tonumber(value)
    if parsed == nil then return fallback end
    return parsed
end

local function PlayerPosition()
    if g_localActor == nil or g_localActor.GetWorldPos == nil then
        return nil
    end

    local ok, position = pcall(function()
        return g_localActor:GetWorldPos()
    end)
    if not ok then return nil end
    return position
end

local function ScheduleSilenceTimer()
    if Script == nil or Script.SetTimerForFunction == nil then
        Log("silence timer unavailable")
        return false
    end

    local generationToken = {
        generation = DarkPassengerAftermath.generation,
    }
    local ok, timerOrError = pcall(function()
        return Script.SetTimerForFunction(
            DarkPassengerAftermath.SILENCE_DURATION_MS,
            "DarkPassengerAftermath.OnSilenceTimer",
            generationToken
        )
    end)
    if not ok then
        Log("silence timer scheduling failed: " .. tostring(timerOrError))
        return false
    end

    DarkPassengerAftermath.timerActive = true
    return true
end

function DarkPassengerAftermath.Begin(
    region,
    settlement,
    targetSlot,
    deathX,
    deathY,
    deathZ,
    requestedZoneRadius
)
    DarkPassengerAftermath.generation =
        DarkPassengerAftermath.generation + 1
    DarkPassengerAftermath.phase =
        DarkPassengerAftermath.PHASE_SILENCE_CHECK
    DarkPassengerAftermath.region = region
    DarkPassengerAftermath.settlement = settlement
    DarkPassengerAftermath.targetSlot = targetSlot
    DarkPassengerAftermath.deathX = NumberOr(deathX, 0)
    DarkPassengerAftermath.deathY = NumberOr(deathY, 0)
    DarkPassengerAftermath.deathZ = NumberOr(deathZ, 0)
    DarkPassengerAftermath.zoneRadius = math.max(
        1,
        NumberOr(
            requestedZoneRadius,
            DarkPassengerAftermath.DEFAULT_ZONE_RADIUS
        )
    )
    DarkPassengerAftermath.timerActive = false
    DarkPassengerAftermath.exposed = false
    DarkPassengerAftermath.collateralCount = 0
    DarkPassengerAftermath.witnessRemovedCount = 0
    DarkPassengerAftermath.result = nil
    DarkPassengerAftermath.suspicionReason = nil

    ScheduleSilenceTimer()
    Log(
        "begin generation=" .. tostring(DarkPassengerAftermath.generation) ..
        " region=" .. tostring(region) ..
        " settlement=" .. tostring(settlement) ..
        " target=" .. tostring(targetSlot) ..
        " zone_radius=" .. tostring(DarkPassengerAftermath.zoneRadius)
    )
    return true
end

function DarkPassengerAftermath.RecordSuspicion(reason)
    if DarkPassengerAftermath.phase ==
       DarkPassengerAftermath.PHASE_RESOLVED then
        return false
    end
    if DarkPassengerAftermath.phase ==
       DarkPassengerAftermath.PHASE_HUNTING then
        return false
    end

    DarkPassengerAftermath.exposed = true
    DarkPassengerAftermath.suspicionReason = reason or "unspecified"
    DarkPassengerAftermath.timerActive = false
    DarkPassengerAftermath.phase =
        DarkPassengerAftermath.PHASE_CLEANUP
    Log(
        "suspicion generation=" ..
        tostring(DarkPassengerAftermath.generation) ..
        " reason=" .. tostring(DarkPassengerAftermath.suspicionReason)
    )
    return true
end

function DarkPassengerAftermath.RecordWitnessRemoved(witnessId)
    if DarkPassengerAftermath.phase ~=
           DarkPassengerAftermath.PHASE_SILENCE_CHECK and
       DarkPassengerAftermath.phase ~=
           DarkPassengerAftermath.PHASE_CLEANUP then
        return false
    end

    DarkPassengerAftermath.witnessRemovedCount =
        DarkPassengerAftermath.witnessRemovedCount + 1
    DarkPassengerAftermath.collateralCount =
        DarkPassengerAftermath.collateralCount + 1
    Log(
        "witness removed generation=" ..
        tostring(DarkPassengerAftermath.generation) ..
        " witness=" .. tostring(witnessId) ..
        " collateral=" ..
        tostring(DarkPassengerAftermath.collateralCount)
    )
    return true
end

function DarkPassengerAftermath.Resolve(result)
    if DarkPassengerAftermath.phase ==
       DarkPassengerAftermath.PHASE_RESOLVED then
        Log(
            "resolve ignored generation=" ..
            tostring(DarkPassengerAftermath.generation) ..
            " existing_result=" .. tostring(DarkPassengerAftermath.result)
        )
        return false
    end

    DarkPassengerAftermath.phase =
        DarkPassengerAftermath.PHASE_RESOLVED
    DarkPassengerAftermath.timerActive = false
    DarkPassengerAftermath.result = result or "clean"
    Log(
        "resolved generation=" ..
        tostring(DarkPassengerAftermath.generation) ..
        " result=" .. tostring(DarkPassengerAftermath.result) ..
        " exposed=" .. tostring(DarkPassengerAftermath.exposed) ..
        " collateral=" ..
        tostring(DarkPassengerAftermath.collateralCount)
    )
    return true
end

function DarkPassengerAftermath.OnSilenceTimer(userData, timerId)
    local requestedGeneration =
        userData ~= nil and tonumber(userData.generation) or nil
    if requestedGeneration ~= DarkPassengerAftermath.generation then
        Log(
            "stale timer ignored requested=" ..
            tostring(requestedGeneration) ..
            " current=" .. tostring(DarkPassengerAftermath.generation)
        )
        return false
    end
    if not DarkPassengerAftermath.timerActive then
        return false
    end
    if DarkPassengerAftermath.phase ~=
       DarkPassengerAftermath.PHASE_SILENCE_CHECK then
        return false
    end

    return DarkPassengerAftermath.Resolve("clean")
end

function DarkPassengerAftermath.OnPlayerPosition(x, y, z)
    if DarkPassengerAftermath.phase ~=
           DarkPassengerAftermath.PHASE_SILENCE_CHECK and
       DarkPassengerAftermath.phase ~=
           DarkPassengerAftermath.PHASE_CLEANUP then
        return false
    end

    local dx = NumberOr(x, 0) - DarkPassengerAftermath.deathX
    local dy = NumberOr(y, 0) - DarkPassengerAftermath.deathY
    local dz = NumberOr(z, 0) - DarkPassengerAftermath.deathZ
    local distanceFromDeath = math.sqrt(dx * dx + dy * dy + dz * dz)
    local zoneRadius = DarkPassengerAftermath.zoneRadius

    if distanceFromDeath >= zoneRadius then
        if DarkPassengerAftermath.phase ==
           DarkPassengerAftermath.PHASE_CLEANUP then
            return DarkPassengerAftermath.Resolve("noisy")
        end
        return DarkPassengerAftermath.Resolve("clean")
    end
    return false
end

function DarkPassengerAftermath.Status()
    local status = {
        phase = DarkPassengerAftermath.phase,
        generation = DarkPassengerAftermath.generation,
        timerActive = DarkPassengerAftermath.timerActive,
        exposed = DarkPassengerAftermath.exposed,
        collateralCount = DarkPassengerAftermath.collateralCount,
        witnessRemovedCount =
            DarkPassengerAftermath.witnessRemovedCount,
        region = DarkPassengerAftermath.region,
        settlement = DarkPassengerAftermath.settlement,
        targetSlot = DarkPassengerAftermath.targetSlot,
        zoneRadius = DarkPassengerAftermath.zoneRadius,
        result = DarkPassengerAftermath.result,
    }
    Log(
        "status phase=" .. tostring(status.phase) ..
        " generation=" .. tostring(status.generation) ..
        " timer_active=" .. tostring(status.timerActive) ..
        " exposed=" .. tostring(status.exposed) ..
        " collateral=" .. tostring(status.collateralCount) ..
        " result=" .. tostring(status.result)
    )
    return status
end

function DarkPassengerAftermath.DebugBegin(argsLine)
    local requestedRadius = tonumber(
        string.match(tostring(argsLine or ""), "^%s*([^%s]+)")
    )
    local position = PlayerPosition()
    if position == nil then
        Log("debug begin unavailable: player position=nil")
        return false
    end

    return DarkPassengerAftermath.Begin(
        "debug",
        "debug",
        "debug",
        position.x,
        position.y,
        position.z,
        requestedRadius
    )
end

function DarkPassengerAftermath.DebugExit(argsLine)
    if DarkPassengerAftermath.deathX == nil then
        Log("debug exit ignored: no active death position")
        return false
    end
    local extraDistance = tonumber(
        string.match(tostring(argsLine or ""), "^%s*([^%s]+)")
    ) or 1
    return DarkPassengerAftermath.OnPlayerPosition(
        DarkPassengerAftermath.deathX +
            DarkPassengerAftermath.zoneRadius +
            math.max(1, extraDistance),
        DarkPassengerAftermath.deathY,
        DarkPassengerAftermath.deathZ
    )
end

