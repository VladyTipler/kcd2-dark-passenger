DarkPassengerWitnessDetector =
    DarkPassengerWitnessDetector or {}

DarkPassengerWitnessDetector.SCAN_INTERVAL_MS = 500
DarkPassengerWitnessDetector.EVIDENCE_REPORT_INTENT = 1
DarkPassengerWitnessDetector.EVIDENCE_REPORT_HANDOFF = 2

DarkPassengerWitnessDetector.active =
    DarkPassengerWitnessDetector.active == true
DarkPassengerWitnessDetector.generationToken =
    tonumber(DarkPassengerWitnessDetector.generationToken) or 0
DarkPassengerWitnessDetector.timerSerial =
    tonumber(DarkPassengerWitnessDetector.timerSerial) or 0
DarkPassengerWitnessDetector.states =
    DarkPassengerWitnessDetector.states or {}
DarkPassengerWitnessDetector.attributedDeaths =
    DarkPassengerWitnessDetector.attributedDeaths or {}

local function Log(message)
    if System ~= nil and System.LogAlways ~= nil then
        System.LogAlways(
            "[DarkPassenger][WitnessDetector] " .. tostring(message)
        )
    end
end

local function HasMethod(owner, methodName)
    return owner ~= nil and type(owner[methodName]) == "function"
end

local function IsActiveAftermath()
    if DarkPassengerAftermath == nil then return false end
    local phase = DarkPassengerAftermath.phase
    return (
        phase == DarkPassengerAftermath.PHASE_SILENCE_CHECK or
        phase == DarkPassengerAftermath.PHASE_CLEANUP
    ) and
        DarkPassengerAftermath.generation ==
        DarkPassengerWitnessDetector.generationToken
end

local function CurrentTime()
    if Calendar ~= nil and Calendar.GetWorldTime ~= nil then
        local ok, value = pcall(function()
            return Calendar.GetWorldTime()
        end)
        if ok and tonumber(value) ~= nil then
            return tonumber(value)
        end
    end
    if not HasMethod(System, "GetCurrTime") then return 0 end
    local ok, value = pcall(function()
        return System.GetCurrTime()
    end)
    if not ok then return 0 end
    return tonumber(value) or 0
end

local function EntityPosition(entity)
    if entity == nil or not HasMethod(entity, "GetWorldPos") then
        return nil
    end
    local ok, position = pcall(function()
        return entity:GetWorldPos()
    end)
    if ok then return position end
    return nil
end

local function DeathOrigin()
    if g_localActor == nil or
       not HasMethod(g_localActor, "GetWorldPos") then
        return nil
    end
    local ok, origin = pcall(function()
        return g_localActor:GetWorldPos()
    end)
    if not ok or origin == nil then return nil end
    origin.x = tonumber(DarkPassengerAftermath.deathX) or origin.x
    origin.y = tonumber(DarkPassengerAftermath.deathY) or origin.y
    origin.z = tonumber(DarkPassengerAftermath.deathZ) or origin.z
    return origin
end

local function EntityDead(entity)
    if entity == nil or entity.actor == nil or
       not HasMethod(entity.actor, "IsDead") then
        return false
    end
    local ok, dead = pcall(function()
        return entity.actor:IsDead()
    end)
    return ok and dead == true
end

local function ReportIntent(entity)
    if entity == nil or entity.soul == nil or
       not HasMethod(entity.soul, "HasScriptContext") then
        return false
    end
    local ok, active = pcall(function()
        return entity.soul:HasScriptContext("crime_interruptReport")
    end)
    return ok and active == true
end

local function Reporting(entity)
    if entity == nil or entity.soul == nil or
       not HasMethod(entity.soul, "HasScriptContext") then
        return false
    end
    local ok, active = pcall(function()
        return entity.soul:HasScriptContext("crime_interruptReport_reporting")
    end)
    return ok and active == true
end

local function EntityIdentity(entity)
    if entity == nil or entity.soul == nil or
       not HasMethod(entity.soul, "GetId") or
       DarkPassengerWitness == nil or
       DarkPassengerWitness.IdentityFromWuid == nil then
        return nil, nil
    end
    local ok, soulId = pcall(function()
        return entity.soul:GetId()
    end)
    if not ok or soulId == nil then return nil, nil end
    return DarkPassengerWitness.IdentityFromWuid(soulId)
end

local function IdentityKey(identityHigh, identityLow)
    return tostring(identityHigh) .. ":" .. tostring(identityLow)
end

local function ScheduleNext()
    if not DarkPassengerWitnessDetector.active or
       not HasMethod(Script, "SetTimerForFunction") then
        return false
    end
    local userData = {
        generationToken =
            DarkPassengerWitnessDetector.generationToken,
        timerSerial =
            DarkPassengerWitnessDetector.timerSerial,
    }
    local ok, result = pcall(function()
        return Script.SetTimerForFunction(
            DarkPassengerWitnessDetector.SCAN_INTERVAL_MS,
            "DarkPassengerWitnessDetector.OnTimer",
            userData
        )
    end)
    if not ok then
        Log("timer schedule failed error=" .. tostring(result))
        return false
    end
    return result ~= false
end

function DarkPassengerWitnessDetector.RecordAttributedDeath(
    entity,
    method
)
    if not IsActiveAftermath() then return false end
    local identityHigh, identityLow = EntityIdentity(entity)
    if identityHigh == nil or identityLow == nil then return false end
    local key = IdentityKey(identityHigh, identityLow)
    DarkPassengerWitnessDetector.attributedDeaths[key] = {
        generation = DarkPassengerWitnessDetector.generationToken,
        method = tostring(method or "unknown"),
    }
    Log(
        "attributed death armed identity=" .. key ..
        " method=" .. tostring(method)
    )
    return true
end

function DarkPassengerWitnessDetector.Scan()
    if not IsActiveAftermath() then return false end
    if not HasMethod(System, "GetEntitiesInSphere") then
        Log("scan unavailable: sphere binding missing")
        return false
    end

    local origin = DeathOrigin()
    if origin == nil then
        Log("scan unavailable: death origin missing")
        return false
    end
    local radius =
        tonumber(DarkPassengerAftermath.zoneRadius) or
        DarkPassengerAftermath.DEFAULT_ZONE_RADIUS or 120
    local ok, entities = pcall(function()
        return System.GetEntitiesInSphere(origin, radius)
    end)
    if not ok or type(entities) ~= "table" then
        Log("scan failed error=" .. tostring(entities))
        return false
    end

    local incidentTime = CurrentTime()
    for _, entity in pairs(entities) do
        if entity ~= nil and entity.soul ~= nil and
           (
               g_localActor == nil or
               entity.id ~= g_localActor.id
           ) then
            local identityHigh, identityLow =
                EntityIdentity(entity)
            if identityHigh ~= nil and identityLow ~= nil then
                local key = IdentityKey(identityHigh, identityLow)
                local previous =
                    DarkPassengerWitnessDetector.states[key] or {
                        reportIntent = false,
                        reporting = false,
                        dead = false,
                    }
                local reportIntent = ReportIntent(entity)
                local reporting = Reporting(entity)
                local dead = EntityDead(entity)

                if reportIntent and not previous.reportIntent then
                    DarkPassengerAftermath.RecordWitness(
                        identityHigh,
                        identityLow,
                        DarkPassengerWitnessDetector
                            .EVIDENCE_REPORT_INTENT,
                        false,
                        incidentTime
                    )
                    Log("report intent identity=" .. key)
                end
                if reporting and not previous.reporting then
                    DarkPassengerAftermath.RecordReport(
                        identityHigh,
                        identityLow,
                        "native_report_handoff",
                        incidentTime
                    )
                    Log("report handoff identity=" .. key)
                end

                local record = DarkPassengerWitness.GetRecord(
                    identityHigh,
                    identityLow,
                    DarkPassengerWitnessDetector.generationToken
                )
                if dead and not previous.dead and record ~= nil then
                    local attribution =
                        DarkPassengerWitnessDetector
                            .attributedDeaths[key]
                    local attributed =
                        attribution ~= nil and
                        attribution.generation ==
                            DarkPassengerWitnessDetector
                                .generationToken
                    local deathPosition = EntityPosition(entity)
                    DarkPassengerAftermath.RecordWitnessDeath(
                        identityHigh,
                        identityLow,
                        attributed,
                        incidentTime,
                        deathPosition ~= nil and
                            deathPosition.x or 0,
                        deathPosition ~= nil and
                            deathPosition.y or 0,
                        deathPosition ~= nil and
                            deathPosition.z or 0
                    )
                    Log(
                        "witness death identity=" .. key ..
                        " attributed=" .. tostring(attributed)
                    )
                end

                DarkPassengerWitnessDetector.states[key] = {
                    reportIntent = reportIntent,
                    reporting = reporting,
                    dead = dead,
                }
            end
        end
    end
    return true
end

function DarkPassengerWitnessDetector.Start(reason)
    if DarkPassengerAftermath == nil then return false end
    local generation =
        tonumber(DarkPassengerAftermath.generation) or 0
    if generation <= 0 then return false end
    if DarkPassengerWitnessDetector.generationToken ~= generation then
        DarkPassengerWitnessDetector.states = {}
        DarkPassengerWitnessDetector.attributedDeaths = {}
    end
    DarkPassengerWitnessDetector.generationToken = generation
    DarkPassengerWitnessDetector.timerSerial =
        DarkPassengerWitnessDetector.timerSerial + 1
    DarkPassengerWitnessDetector.active = IsActiveAftermath()
    if not DarkPassengerWitnessDetector.active then return false end
    DarkPassengerWitnessDetector.Scan()
    ScheduleNext()
    Log(
        "started generation=" .. tostring(generation) ..
        " serial=" ..
        tostring(DarkPassengerWitnessDetector.timerSerial) ..
        " reason=" .. tostring(reason)
    )
    return true
end

function DarkPassengerWitnessDetector.Stop(reason)
    local wasActive = DarkPassengerWitnessDetector.active
    DarkPassengerWitnessDetector.active = false
    DarkPassengerWitnessDetector.timerSerial =
        DarkPassengerWitnessDetector.timerSerial + 1
    if wasActive then
        Log(
            "stopped generation=" ..
            tostring(DarkPassengerWitnessDetector.generationToken) ..
            " reason=" .. tostring(reason)
        )
    end
    return wasActive
end

function DarkPassengerWitnessDetector.OnTimer(userData, timerId)
    local requestedGeneration =
        userData ~= nil and
        tonumber(userData.generationToken) or nil
    local requestedSerial =
        userData ~= nil and tonumber(userData.timerSerial) or nil
    if requestedGeneration ~=
           DarkPassengerWitnessDetector.generationToken or
       requestedSerial ~=
           DarkPassengerWitnessDetector.timerSerial or
       not DarkPassengerWitnessDetector.active then
        return false
    end
    if not IsActiveAftermath() then
        DarkPassengerWitnessDetector.Stop("aftermath_inactive")
        return false
    end
    DarkPassengerWitnessDetector.Scan()
    return ScheduleNext()
end

function DarkPassengerWitnessDetector.Status()
    local count = 0
    for _ in pairs(DarkPassengerWitnessDetector.states) do
        count = count + 1
    end
    Log(
        "status active=" ..
        tostring(DarkPassengerWitnessDetector.active) ..
        " generation=" ..
        tostring(DarkPassengerWitnessDetector.generationToken) ..
        " serial=" ..
        tostring(DarkPassengerWitnessDetector.timerSerial) ..
        " tracked=" .. tostring(count)
    )
    return {
        active = DarkPassengerWitnessDetector.active,
        generation =
            DarkPassengerWitnessDetector.generationToken,
        timerSerial =
            DarkPassengerWitnessDetector.timerSerial,
        tracked = count,
    }
end
