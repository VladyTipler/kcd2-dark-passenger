DarkPassengerAftermath = DarkPassengerAftermath or {}

DarkPassengerAftermath.PHASE_HUNTING = "HUNTING"
DarkPassengerAftermath.PHASE_SILENCE_CHECK = "SILENCE_CHECK"
DarkPassengerAftermath.PHASE_CLEANUP = "CLEANUP"
DarkPassengerAftermath.PHASE_RESOLVED = "RESOLVED"

DarkPassengerAftermath.SILENCE_DURATION_MS = 90000
DarkPassengerAftermath.DEFAULT_ZONE_RADIUS = 120
DarkPassengerAftermath.PERSISTENCE_HEARTBEAT_MS = 1000
DarkPassengerAftermath.HEARTBEAT_STALE_MS = 2500
DarkPassengerAftermath.RESTORE_DELAY_MS = 1500
DarkPassengerAftermath.SCHEMA_VERSION = 1

DarkPassengerAftermath.KEYS = {
    schema = "dp_aftermath_schema_version",
    phase = "dp_aftermath_phase",
    regionCode = "dp_aftermath_region_code",
    settlementCode = "dp_aftermath_settlement_code",
    targetSlot = "dp_aftermath_target_slot",
    deathX = "dp_aftermath_death_x",
    deathY = "dp_aftermath_death_y",
    deathZ = "dp_aftermath_death_z",
    zoneRadius = "dp_aftermath_zone_radius",
    silenceRemainingMs = "dp_aftermath_silence_remaining_ms",
    generation = "dp_aftermath_generation",
    exposed = "dp_aftermath_exposed",
    collateralCount = "dp_aftermath_collateral_count",
    witnessRemovedCount = "dp_aftermath_witness_removed_count",
    resolvedGeneration = "dp_aftermath_resolved_generation",
    resultCode = "dp_aftermath_result_code",
}

DarkPassengerAftermath.PHASE_TO_CODE = {
    [DarkPassengerAftermath.PHASE_HUNTING] = 0,
    [DarkPassengerAftermath.PHASE_SILENCE_CHECK] = 1,
    [DarkPassengerAftermath.PHASE_CLEANUP] = 2,
    [DarkPassengerAftermath.PHASE_RESOLVED] = 3,
}
DarkPassengerAftermath.CODE_TO_PHASE = {
    [0] = DarkPassengerAftermath.PHASE_HUNTING,
    [1] = DarkPassengerAftermath.PHASE_SILENCE_CHECK,
    [2] = DarkPassengerAftermath.PHASE_CLEANUP,
    [3] = DarkPassengerAftermath.PHASE_RESOLVED,
}
DarkPassengerAftermath.RESULT_TO_CODE = {
    clean = 1,
    controlled = 2,
    noisy = 3,
    external = 4,
}
DarkPassengerAftermath.CODE_TO_RESULT = {
    [1] = "clean",
    [2] = "controlled",
    [3] = "noisy",
    [4] = "external",
}

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
DarkPassengerAftermath.silenceRemainingMs =
    tonumber(DarkPassengerAftermath.silenceRemainingMs) or 0
DarkPassengerAftermath.resolvedGeneration =
    tonumber(DarkPassengerAftermath.resolvedGeneration) or 0
DarkPassengerAftermath.timerSerial =
    tonumber(DarkPassengerAftermath.timerSerial) or 0
DarkPassengerAftermath.restoreSerial =
    tonumber(DarkPassengerAftermath.restoreSerial) or 0
DarkPassengerAftermath.loadRecoveryPending =
    DarkPassengerAftermath.loadRecoveryPending == true
DarkPassengerAftermath.actionRestoreRequested =
    DarkPassengerAftermath.actionRestoreRequested == true

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

local function ReadGlobal(key)
    if Variables == nil or Variables.GetGlobal == nil then return nil end
    local ok, valueOrError = pcall(function()
        return Variables.GetGlobal(key)
    end)
    if not ok then
        Log(
            "persistence read failed key=" .. tostring(key) ..
            " error=" .. tostring(valueOrError)
        )
        return nil
    end
    return tonumber(valueOrError)
end

local function WriteGlobal(key, value)
    if Variables == nil or Variables.SetGlobal == nil then return false end
    local ok, resultOrError = pcall(function()
        return Variables.SetGlobal(key, tonumber(value) or 0)
    end)
    if not ok then
        Log(
            "persistence write failed key=" .. tostring(key) ..
            " error=" .. tostring(resultOrError)
        )
    end
    return ok
end

local function StableCode(value)
    local text = tostring(value or "")
    local code = 5381
    for index = 1, #text do
        code = (code * 33 + string.byte(text, index)) % 2147483647
    end
    return code
end

local function MonotonicTimeMs()
    if System == nil or System.GetCurrTime == nil then return nil end
    local ok, valueOrError = pcall(function()
        return System.GetCurrTime()
    end)
    if not ok then return nil end
    local seconds = tonumber(valueOrError)
    if seconds == nil then return nil end
    return seconds * 1000
end

local function RestoreCandidateMetadata(targetSlot)
    local expectedSlot = tonumber(targetSlot)
    if expectedSlot == nil or DarkPassengerGeneratedCandidates == nil then
        return nil, nil
    end
    for _, candidate in ipairs(DarkPassengerGeneratedCandidates) do
        if tonumber(candidate.slot) == expectedSlot then
            return candidate.gameRegion, candidate.settlement
        end
    end
    return nil, nil
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

local function SchedulePersistenceHeartbeat(generation, timerSerial)
    if Script == nil or Script.SetTimerForFunction == nil then
        return false
    end
    local ok = pcall(function()
        return Script.SetTimerForFunction(
            DarkPassengerAftermath.PERSISTENCE_HEARTBEAT_MS,
            "DarkPassengerAftermath.OnPersistenceHeartbeat",
            {
                generation = generation,
                timerSerial = timerSerial,
            }
        )
    end)
    return ok
end

local function ScheduleSilenceTimer(requestedDelayMs)
    if Script == nil or Script.SetTimerForFunction == nil then
        Log("silence timer unavailable")
        return false
    end

    local delayMs = math.max(
        1,
        NumberOr(
            requestedDelayMs,
            DarkPassengerAftermath.SILENCE_DURATION_MS
        )
    )
    DarkPassengerAftermath.timerSerial =
        DarkPassengerAftermath.timerSerial + 1
    local generationToken = {
        generation = DarkPassengerAftermath.generation,
        timerSerial = DarkPassengerAftermath.timerSerial,
    }
    local ok, timerOrError = pcall(function()
        return Script.SetTimerForFunction(
            delayMs,
            "DarkPassengerAftermath.OnSilenceTimer",
            generationToken
        )
    end)
    if not ok then
        Log("silence timer scheduling failed: " .. tostring(timerOrError))
        return false
    end

    DarkPassengerAftermath.timerActive = true
    DarkPassengerAftermath.lastHeartbeatTimeMs = MonotonicTimeMs()
    SchedulePersistenceHeartbeat(
        DarkPassengerAftermath.generation,
        DarkPassengerAftermath.timerSerial
    )
    return true
end

function DarkPassengerAftermath.ScheduleRestore(reason)
    DarkPassengerAftermath.restoreSerial =
        DarkPassengerAftermath.restoreSerial + 1
    DarkPassengerAftermath.loadRecoveryPending = true
    DarkPassengerAftermath.actionRestoreRequested = false

    if Script == nil or Script.SetTimerForFunction == nil then
        Log("deferred restore unavailable reason=" .. tostring(reason))
        return false
    end

    local restoreSerial = DarkPassengerAftermath.restoreSerial
    local ok, timerOrError = pcall(function()
        return Script.SetTimerForFunction(
            DarkPassengerAftermath.RESTORE_DELAY_MS,
            "DarkPassengerAftermath.OnDeferredRestore",
            {
                reason = reason,
                restoreSerial = restoreSerial,
            }
        )
    end)
    if not ok then
        Log(
            "deferred restore scheduling failed reason=" ..
            tostring(reason) .. " error=" .. tostring(timerOrError)
        )
        return false
    end

    Log(
        "restore scheduled reason=" .. tostring(reason) ..
        " serial=" .. tostring(restoreSerial)
    )
    return true
end

local function MetricKey(prefix, settlement)
    return prefix .. tostring(StableCode(settlement))
end

function DarkPassengerAftermath.Persist()
    local keys = DarkPassengerAftermath.KEYS
    local writes = {
        { keys.schema, DarkPassengerAftermath.SCHEMA_VERSION },
        {
            keys.phase,
            DarkPassengerAftermath.PHASE_TO_CODE[
                DarkPassengerAftermath.phase
            ] or 0,
        },
        { keys.regionCode, StableCode(DarkPassengerAftermath.region) },
        {
            keys.settlementCode,
            StableCode(DarkPassengerAftermath.settlement),
        },
        { keys.targetSlot, NumberOr(DarkPassengerAftermath.targetSlot, 0) },
        { keys.deathX, NumberOr(DarkPassengerAftermath.deathX, 0) },
        { keys.deathY, NumberOr(DarkPassengerAftermath.deathY, 0) },
        { keys.deathZ, NumberOr(DarkPassengerAftermath.deathZ, 0) },
        {
            keys.zoneRadius,
            NumberOr(
                DarkPassengerAftermath.zoneRadius,
                DarkPassengerAftermath.DEFAULT_ZONE_RADIUS
            ),
        },
        {
            keys.silenceRemainingMs,
            NumberOr(DarkPassengerAftermath.silenceRemainingMs, 0),
        },
        { keys.generation, DarkPassengerAftermath.generation },
        { keys.exposed, DarkPassengerAftermath.exposed and 1 or 0 },
        {
            keys.collateralCount,
            DarkPassengerAftermath.collateralCount,
        },
        {
            keys.witnessRemovedCount,
            DarkPassengerAftermath.witnessRemovedCount,
        },
        {
            keys.resolvedGeneration,
            DarkPassengerAftermath.resolvedGeneration,
        },
        {
            keys.resultCode,
            DarkPassengerAftermath.RESULT_TO_CODE[
                DarkPassengerAftermath.result
            ] or 0,
        },
    }

    local allWritten = true
    for _, entry in ipairs(writes) do
        if not WriteGlobal(entry[1], entry[2]) then
            allWritten = false
        end
    end
    return allWritten
end

function DarkPassengerAftermath.Restore(reason)
    local keys = DarkPassengerAftermath.KEYS
    if ReadGlobal(keys.schema) ~= DarkPassengerAftermath.SCHEMA_VERSION then
        Log("restore skipped reason=" .. tostring(reason) .. " state=missing")
        return false
    end

    local phaseCode = ReadGlobal(keys.phase)
    local restoredPhase =
        DarkPassengerAftermath.CODE_TO_PHASE[phaseCode]
    if restoredPhase == nil then
        Log("restore rejected invalid phase=" .. tostring(phaseCode))
        return false
    end

    DarkPassengerAftermath.timerActive = false
    DarkPassengerAftermath.timerSerial =
        DarkPassengerAftermath.timerSerial + 1
    DarkPassengerAftermath.phase = restoredPhase
    DarkPassengerAftermath.regionCode =
        NumberOr(ReadGlobal(keys.regionCode), 0)
    DarkPassengerAftermath.settlementCode =
        NumberOr(ReadGlobal(keys.settlementCode), 0)
    DarkPassengerAftermath.targetSlot =
        NumberOr(ReadGlobal(keys.targetSlot), 0)
    DarkPassengerAftermath.deathX =
        NumberOr(ReadGlobal(keys.deathX), 0)
    DarkPassengerAftermath.deathY =
        NumberOr(ReadGlobal(keys.deathY), 0)
    DarkPassengerAftermath.deathZ =
        NumberOr(ReadGlobal(keys.deathZ), 0)
    DarkPassengerAftermath.zoneRadius = math.max(
        1,
        NumberOr(
            ReadGlobal(keys.zoneRadius),
            DarkPassengerAftermath.DEFAULT_ZONE_RADIUS
        )
    )
    DarkPassengerAftermath.silenceRemainingMs = math.max(
        0,
        NumberOr(ReadGlobal(keys.silenceRemainingMs), 0)
    )
    DarkPassengerAftermath.generation =
        NumberOr(ReadGlobal(keys.generation), 0)
    DarkPassengerAftermath.exposed =
        NumberOr(ReadGlobal(keys.exposed), 0) == 1
    DarkPassengerAftermath.collateralCount =
        NumberOr(ReadGlobal(keys.collateralCount), 0)
    DarkPassengerAftermath.witnessRemovedCount =
        NumberOr(ReadGlobal(keys.witnessRemovedCount), 0)
    DarkPassengerAftermath.resolvedGeneration =
        NumberOr(ReadGlobal(keys.resolvedGeneration), 0)
    DarkPassengerAftermath.result =
        DarkPassengerAftermath.CODE_TO_RESULT[
            NumberOr(ReadGlobal(keys.resultCode), 0)
        ]

    local restoredRegion, restoredSettlement =
        RestoreCandidateMetadata(DarkPassengerAftermath.targetSlot)
    DarkPassengerAftermath.region = restoredRegion
    DarkPassengerAftermath.settlement = restoredSettlement

    if restoredPhase ==
       DarkPassengerAftermath.PHASE_SILENCE_CHECK then
        if DarkPassengerAftermath.silenceRemainingMs <= 0 then
            DarkPassengerAftermath.Resolve("clean")
        else
            ScheduleSilenceTimer(
                DarkPassengerAftermath.silenceRemainingMs
            )
        end
    end

    Log(
        "restored reason=" .. tostring(reason) ..
        " phase=" .. tostring(DarkPassengerAftermath.phase) ..
        " generation=" .. tostring(DarkPassengerAftermath.generation) ..
        " remaining_ms=" ..
        tostring(DarkPassengerAftermath.silenceRemainingMs)
    )
    return true
end

function DarkPassengerAftermath.OnDeferredRestore(userData, timerId)
    local requestedSerial =
        userData ~= nil and tonumber(userData.restoreSerial) or nil
    if requestedSerial ~= DarkPassengerAftermath.restoreSerial then
        return false
    end

    local restored = DarkPassengerAftermath.Restore(
        userData ~= nil and userData.reason or "deferred"
    )
    if not restored or
       DarkPassengerAftermath.phase ~=
           DarkPassengerAftermath.PHASE_SILENCE_CHECK then
        DarkPassengerAftermath.loadRecoveryPending = false
    end
    return restored
end

function DarkPassengerAftermath.EnsureRestoreFromPlayerAction(...)
    local heartbeatStale = false
    if DarkPassengerAftermath.phase ==
           DarkPassengerAftermath.PHASE_SILENCE_CHECK and
       DarkPassengerAftermath.timerActive then
        local nowMs = MonotonicTimeMs()
        heartbeatStale =
            nowMs == nil or
            DarkPassengerAftermath.lastHeartbeatTimeMs == nil or
            nowMs < DarkPassengerAftermath.lastHeartbeatTimeMs or
            nowMs - DarkPassengerAftermath.lastHeartbeatTimeMs >=
                DarkPassengerAftermath.HEARTBEAT_STALE_MS
    end

    if not DarkPassengerAftermath.loadRecoveryPending and
       not heartbeatStale then
        return false
    end
    if DarkPassengerAftermath.actionRestoreRequested and
       not heartbeatStale then
        return false
    end

    DarkPassengerAftermath.actionRestoreRequested = true
    Log(
        "action restore requested pending=" ..
        tostring(DarkPassengerAftermath.loadRecoveryPending) ..
        " heartbeat_stale=" .. tostring(heartbeatStale)
    )
    local restored =
        DarkPassengerAftermath.Restore("first_player_action")
    if not restored or
       DarkPassengerAftermath.phase ~=
           DarkPassengerAftermath.PHASE_SILENCE_CHECK then
        DarkPassengerAftermath.loadRecoveryPending = false
    end
    return restored
end

function DarkPassengerAftermath.AdjustSettlementMetrics(
    settlement,
    attentionDelta,
    bloodTrailDelta
)
    local attentionKey =
        MetricKey("dp_aftermath_attention_v1_", settlement)
    local bloodTrailKey =
        MetricKey("dp_aftermath_blood_trail_v1_", settlement)
    local attention = math.max(
        0,
        NumberOr(ReadGlobal(attentionKey), 0) +
            NumberOr(attentionDelta, 0)
    )
    local bloodTrail = math.max(
        0,
        NumberOr(ReadGlobal(bloodTrailKey), 0) +
            NumberOr(bloodTrailDelta, 0)
    )
    WriteGlobal(attentionKey, attention)
    WriteGlobal(bloodTrailKey, bloodTrail)
    return attention, bloodTrail
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
    DarkPassengerAftermath.silenceRemainingMs =
        DarkPassengerAftermath.SILENCE_DURATION_MS
    DarkPassengerAftermath.exposed = false
    DarkPassengerAftermath.collateralCount = 0
    DarkPassengerAftermath.witnessRemovedCount = 0
    DarkPassengerAftermath.resolvedGeneration = 0
    DarkPassengerAftermath.result = nil
    DarkPassengerAftermath.suspicionReason = nil

    ScheduleSilenceTimer(DarkPassengerAftermath.silenceRemainingMs)
    DarkPassengerAftermath.Persist()
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
    DarkPassengerAftermath.timerSerial =
        DarkPassengerAftermath.timerSerial + 1
    DarkPassengerAftermath.phase =
        DarkPassengerAftermath.PHASE_CLEANUP
    DarkPassengerAftermath.Persist()
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

    if DarkPassengerAftermath.phase ==
       DarkPassengerAftermath.PHASE_SILENCE_CHECK then
        DarkPassengerAftermath.RecordSuspicion("witness_removed")
    end

    DarkPassengerAftermath.witnessRemovedCount =
        DarkPassengerAftermath.witnessRemovedCount + 1
    DarkPassengerAftermath.collateralCount =
        DarkPassengerAftermath.collateralCount + 1
    DarkPassengerAftermath.Persist()
    Log(
        "witness removed generation=" ..
        tostring(DarkPassengerAftermath.generation) ..
        " witness=" .. tostring(witnessId) ..
        " collateral=" ..
        tostring(DarkPassengerAftermath.collateralCount)
    )
    return true
end

function DarkPassengerAftermath.ApplyHungerOutcome(result)
    if result == "external" then
        return true
    end
    if DarkPassengerHunger == nil or
       DarkPassengerHunger.ResetAfterHunt == nil then
        Log("hunger outcome unavailable result=" .. tostring(result))
        return false
    end
    if result == "clean" then
        return DarkPassengerHunger.ResetAfterHunt(2, result)
    elseif result == "controlled" then
        return DarkPassengerHunger.ResetAfterHunt(1, result)
    elseif result == "noisy" then
        return DarkPassengerHunger.ResetAfterHunt(0, result)
    end
    Log("unknown hunger outcome result=" .. tostring(result))
    return false
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
    DarkPassengerAftermath.timerSerial =
        DarkPassengerAftermath.timerSerial + 1
    DarkPassengerAftermath.result = result or "clean"
    DarkPassengerAftermath.resolvedGeneration =
        DarkPassengerAftermath.generation
    DarkPassengerAftermath.silenceRemainingMs = 0
    DarkPassengerAftermath.Persist()
    DarkPassengerAftermath.ApplyHungerOutcome(
        DarkPassengerAftermath.result
    )
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
    local requestedTimerSerial =
        userData ~= nil and tonumber(userData.timerSerial) or nil
    if requestedGeneration ~= DarkPassengerAftermath.generation or
       requestedTimerSerial ~= DarkPassengerAftermath.timerSerial then
        Log(
            "stale timer ignored requested=" ..
            tostring(requestedGeneration) ..
            ":" .. tostring(requestedTimerSerial) ..
            " current=" .. tostring(DarkPassengerAftermath.generation) ..
            ":" .. tostring(DarkPassengerAftermath.timerSerial)
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

function DarkPassengerAftermath.OnPersistenceHeartbeat(userData, timerId)
    local requestedGeneration =
        userData ~= nil and tonumber(userData.generation) or nil
    local requestedTimerSerial =
        userData ~= nil and tonumber(userData.timerSerial) or nil
    if requestedGeneration ~= DarkPassengerAftermath.generation or
       requestedTimerSerial ~= DarkPassengerAftermath.timerSerial or
       not DarkPassengerAftermath.timerActive or
       DarkPassengerAftermath.phase ~=
           DarkPassengerAftermath.PHASE_SILENCE_CHECK then
        return false
    end

    DarkPassengerAftermath.loadRecoveryPending = false
    DarkPassengerAftermath.actionRestoreRequested = false

    local nowMs = MonotonicTimeMs()
    local elapsedMs = DarkPassengerAftermath.PERSISTENCE_HEARTBEAT_MS
    if nowMs ~= nil and DarkPassengerAftermath.lastHeartbeatTimeMs ~= nil then
        elapsedMs = math.max(
            1,
            nowMs - DarkPassengerAftermath.lastHeartbeatTimeMs
        )
    end
    DarkPassengerAftermath.lastHeartbeatTimeMs = nowMs
    DarkPassengerAftermath.silenceRemainingMs = math.max(
        0,
        DarkPassengerAftermath.silenceRemainingMs - elapsedMs
    )
    WriteGlobal(
        DarkPassengerAftermath.KEYS.silenceRemainingMs,
        DarkPassengerAftermath.silenceRemainingMs
    )

    if DarkPassengerAftermath.silenceRemainingMs <= 0 then
        return DarkPassengerAftermath.Resolve("clean")
    end

    return SchedulePersistenceHeartbeat(
        DarkPassengerAftermath.generation,
        DarkPassengerAftermath.timerSerial
    )
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
        timerSerial = DarkPassengerAftermath.timerSerial,
        silenceRemainingMs =
            DarkPassengerAftermath.silenceRemainingMs,
        exposed = DarkPassengerAftermath.exposed,
        collateralCount = DarkPassengerAftermath.collateralCount,
        witnessRemovedCount =
            DarkPassengerAftermath.witnessRemovedCount,
        region = DarkPassengerAftermath.region,
        settlement = DarkPassengerAftermath.settlement,
        targetSlot = DarkPassengerAftermath.targetSlot,
        zoneRadius = DarkPassengerAftermath.zoneRadius,
        result = DarkPassengerAftermath.result,
        resolvedGeneration =
            DarkPassengerAftermath.resolvedGeneration,
    }
    Log(
        "status phase=" .. tostring(status.phase) ..
        " generation=" .. tostring(status.generation) ..
        " timer_active=" .. tostring(status.timerActive) ..
        " timer_serial=" .. tostring(status.timerSerial) ..
        " remaining_ms=" .. tostring(status.silenceRemainingMs) ..
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
