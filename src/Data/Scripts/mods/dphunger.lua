DarkPassengerHunger = DarkPassengerHunger or {}

DarkPassengerHunger.SCHEMA_VERSION = 1
DarkPassengerHunger.SCHEMA_KEY = "dp_hunger_schema_version"
DarkPassengerHunger.LAST_SATISFACTION_KEY =
    "dp_last_satisfaction_world_time"
DarkPassengerHunger.SECONDS_PER_DAY = 86400
DarkPassengerHunger.HUNGER_PER_DAY = 10
DarkPassengerHunger.MAX_HUNGER = 100
DarkPassengerHunger.RELIEF_HUNGER = 50
DarkPassengerHunger.FIRST_INSTALL_DAYS = 5
DarkPassengerHunger.EVALUATION_INTERVAL_MS = 10000
DarkPassengerHunger.SATISFACTION_GATE_GUID =
    "b5c59e05-cc10-4bf8-b82e-d82b913c841f"
DarkPassengerHunger.BUFF_BY_TIER = {
    [0] = "16de3823-48bf-4f86-8498-ce45819a48f0",
    [10] = "4bce1db0-3d61-480e-9879-1b5c226b2de0",
    [20] = "f153ce4e-3892-4939-8c0e-f4c897f49ac9",
    [30] = "ac595695-4441-4ea4-b046-069bd9f056ec",
    [40] = "cc76ea13-2cc6-421f-b233-af00f7d7b770",
    [60] = "cd3a7c4c-96a0-4338-9a97-26382aebe5e9",
    [70] = "453ad2d2-288c-40cf-b6ed-043c67d817d9",
    [80] = "2c399907-d7dc-4fe2-a7fa-07d0ffb5e092",
    [90] = "75f904c6-a73f-439b-91a3-a55d6d40e3ba",
    [100] = "03fc0db7-fc98-4562-924d-ddd2c6879262",
}
DarkPassengerHunger.evaluationGeneration =
    (DarkPassengerHunger.evaluationGeneration or 0) + 1

local function Log(message)
    System.LogAlways("[DarkPassengerHunger] " .. tostring(message))
end

local function ReadGlobal(key)
    if Variables == nil or Variables.GetGlobal == nil then return nil end
    local ok, valueOrError = pcall(function()
        return Variables.GetGlobal(key)
    end)
    if not ok then
        Log("read failed key=" .. tostring(key) ..
            " error=" .. tostring(valueOrError))
        return nil
    end
    return tonumber(valueOrError)
end

local function WriteGlobal(key, value)
    if Variables == nil or Variables.SetGlobal == nil then return false end
    local ok, resultOrError = pcall(function()
        return Variables.SetGlobal(key, value)
    end)
    if not ok then
        Log("write failed key=" .. tostring(key) ..
            " error=" .. tostring(resultOrError))
    end
    return ok
end

local function WorldTime()
    if Calendar == nil or Calendar.GetWorldTime == nil then return nil end
    local ok, valueOrError = pcall(function()
        return Calendar.GetWorldTime()
    end)
    if not ok then
        Log("world time unavailable: " .. tostring(valueOrError))
        return nil
    end
    return tonumber(valueOrError)
end

local function PlayerSoul()
    local player = g_localActor or System.GetEntityByName("dude")
    if player == nil then return nil end
    return player.soul
end

local function HasBuff(soul, buffGuid)
    if soul == nil or soul.HasBuffDebug == nil or buffGuid == nil then
        return false
    end
    local ok, presentOrError = pcall(function()
        return soul:HasBuffDebug(buffGuid)
    end)
    return ok and (presentOrError == true or presentOrError == 1)
end

local function ReadClock(label, reader)
    local ok, valueOrError = pcall(reader)
    if not ok then
        Log(label .. "=ERROR:" .. tostring(valueOrError))
        return nil
    end
    Log(label .. "=" .. tostring(valueOrError))
    return valueOrError
end

function DarkPassengerHunger.Calculate(now, lastSatisfaction)
    local current = tonumber(now)
    local previous = tonumber(lastSatisfaction)
    if current == nil or previous == nil then return nil end

    local elapsed = math.max(0, current - previous)
    local completeDays = math.floor(
        elapsed / DarkPassengerHunger.SECONDS_PER_DAY
    )
    return math.min(
        DarkPassengerHunger.MAX_HUNGER,
        completeDays * DarkPassengerHunger.HUNGER_PER_DAY
    )
end

function DarkPassengerHunger.EnsureInitialized()
    local now = WorldTime()
    if now == nil then return nil end

    local schema = ReadGlobal(DarkPassengerHunger.SCHEMA_KEY)
    local lastSatisfaction =
        ReadGlobal(DarkPassengerHunger.LAST_SATISFACTION_KEY)
    if schema == DarkPassengerHunger.SCHEMA_VERSION and
       lastSatisfaction ~= nil then
        return lastSatisfaction
    end

    lastSatisfaction =
        now -
        DarkPassengerHunger.FIRST_INSTALL_DAYS *
        DarkPassengerHunger.SECONDS_PER_DAY
    WriteGlobal(
        DarkPassengerHunger.SCHEMA_KEY,
        DarkPassengerHunger.SCHEMA_VERSION
    )
    WriteGlobal(
        DarkPassengerHunger.LAST_SATISFACTION_KEY,
        lastSatisfaction
    )
    Log(
        "initialized hunger=" ..
        tostring(
            DarkPassengerHunger.Calculate(now, lastSatisfaction)
        ) ..
        " lastSatisfactionWorldTime=" .. tostring(lastSatisfaction)
    )
    return lastSatisfaction
end

function DarkPassengerHunger.ResetNow(graceDays)
    local now = WorldTime()
    if now == nil then return false end
    local clampedGraceDays = math.max(0, tonumber(graceDays) or 0)
    local effectiveAnchor =
        now +
        clampedGraceDays *
        DarkPassengerHunger.SECONDS_PER_DAY
    WriteGlobal(
        DarkPassengerHunger.SCHEMA_KEY,
        DarkPassengerHunger.SCHEMA_VERSION
    )
    local written = WriteGlobal(
        DarkPassengerHunger.LAST_SATISFACTION_KEY,
        effectiveAnchor
    )
    if written then
        Log(
            "satisfaction timestamp reset=" .. tostring(now) ..
            " graceDays=" .. tostring(clampedGraceDays) ..
            " effectiveAnchor=" .. tostring(effectiveAnchor)
        )
    end
    return written
end

function DarkPassengerHunger.Get()
    local now = WorldTime()
    if now == nil then return nil end
    local lastSatisfaction = DarkPassengerHunger.EnsureInitialized()
    if lastSatisfaction == nil then return nil end
    return DarkPassengerHunger.Calculate(now, lastSatisfaction)
end

function DarkPassengerHunger.TierFor(hunger)
    local value = tonumber(hunger)
    if value == nil then return nil end
    value = math.max(0, math.min(DarkPassengerHunger.MAX_HUNGER, value))
    local tier = math.floor(value / 10) * 10
    if tier == 50 then return nil end
    return tier
end

function DarkPassengerHunger.InvalidateAppliedState()
    DarkPassengerHunger.currentTier = nil
    DarkPassengerHunger.satisfactionGateExpected = nil
end

function DarkPassengerHunger.ApplyTier(soul, tier)
    if soul == nil then return false end
    local desiredGuid = DarkPassengerHunger.BUFF_BY_TIER[tier]
    local shouldHaveSatisfactionGate = tier ~= nil and tier < 50
    local changed = DarkPassengerHunger.currentTier ~= tier

    if shouldHaveSatisfactionGate and
       DarkPassengerHunger.satisfactionGateExpected ~= true then
        local gateOk, gateHandleOrError = pcall(function()
            return soul:AddBuff(
                DarkPassengerHunger.SATISFACTION_GATE_GUID
            )
        end)
        if not gateOk or gateHandleOrError == nil then
            Log("satisfaction gate add failed error=" ..
                tostring(gateHandleOrError))
            return false
        end
    end

    if desiredGuid ~= nil and not HasBuff(soul, desiredGuid) then
        local ok, handleOrError = pcall(function()
            return soul:AddBuff(desiredGuid)
        end)
        if not ok or handleOrError == nil then
            Log(
                "tier add failed tier=" .. tostring(tier) ..
                " error=" .. tostring(handleOrError)
            )
            return false
        end
        changed = true
    end

    for _, buffGuid in pairs(DarkPassengerHunger.BUFF_BY_TIER) do
        if buffGuid ~= desiredGuid then
            pcall(function()
                soul:RemoveAllBuffsByGuid(buffGuid)
            end)
        end
    end

    if not shouldHaveSatisfactionGate and
       DarkPassengerHunger.satisfactionGateExpected ~= false then
        pcall(function()
            soul:RemoveAllBuffsByGuid(
                DarkPassengerHunger.SATISFACTION_GATE_GUID
            )
        end)
    end

    DarkPassengerHunger.satisfactionGateExpected =
        shouldHaveSatisfactionGate
    DarkPassengerHunger.currentTier = tier
    if changed then
        Log(
            "tier applied=" .. tostring(tier) ..
            " buff=" .. tostring(desiredGuid)
        )
    end
    return true
end

function DarkPassengerHunger.ResetAfterHunt(graceDays, result)
    local clampedGraceDays = math.max(0, tonumber(graceDays) or 0)
    local investigationState =
        DarkPassengerInvestigation ~= nil and
        DarkPassengerInvestigation.GetState ~= nil and
        DarkPassengerInvestigation.GetState() or nil
    local lifecycleGeneration = tonumber(
        investigationState ~= nil and investigationState.generation
    )
    if not DarkPassengerHunger.ResetNow(graceDays) then return false end
    if lifecycleGeneration ~= nil and lifecycleGeneration > 0 and
       DarkPassengerCaseLifecycle ~= nil and
       DarkPassengerCaseLifecycle.ClearCaseArtifacts ~= nil then
        DarkPassengerCaseLifecycle.ClearCaseArtifacts(
            lifecycleGeneration,
            "hunt_resolved"
        )
    end
    -- The native quest death branch has already added the hidden gate. Do not
    -- probe it: HasBuffDebug throws for this Cpp:Constant custom buff.
    DarkPassengerHunger.lastGraceDays = clampedGraceDays
    DarkPassengerHunger.lastResult = result
    DarkPassengerHunger.satisfactionGateExpected = true
    DarkPassengerHunger.currentTier = nil
    local hunger = DarkPassengerHunger.Evaluate()
    if hunger ~= nil then
        Log(
            "resolved hunt applied hunger=" .. tostring(hunger) ..
            " graceDays=" .. tostring(clampedGraceDays) ..
            " result=" .. tostring(result)
        )
    end
    return hunger ~= nil
end

function DarkPassengerHunger.ReliefTransition(hunger)
    local value = tonumber(hunger)
    if value == nil then
        return {
            accepted = false,
            reason = "invalid_hunger",
        }
    end

    value = math.max(
        0,
        math.min(DarkPassengerHunger.MAX_HUNGER, value)
    )
    if value <= DarkPassengerHunger.RELIEF_HUNGER then
        return {
            accepted = false,
            reason = "not_hungry",
            previous = value,
            current = value,
        }
    end

    return {
        accepted = true,
        reason = "relieved",
        previous = value,
        current = 50,
    }
end

function DarkPassengerHunger.RelieveFromOrdinaryKill()
    local transition = DarkPassengerHunger.ReliefTransition(
        DarkPassengerHunger.Get()
    )
    if not transition.accepted then
        return transition
    end

    local now = WorldTime()
    if now == nil then
        transition.accepted = false
        transition.reason = "world_time_unavailable"
        return transition
    end

    local lastSatisfaction =
        now -
        (DarkPassengerHunger.RELIEF_HUNGER /
            DarkPassengerHunger.HUNGER_PER_DAY) *
        DarkPassengerHunger.SECONDS_PER_DAY
    if not WriteGlobal(
        DarkPassengerHunger.LAST_SATISFACTION_KEY,
        lastSatisfaction
    ) then
        transition.accepted = false
        transition.reason = "timestamp_write_failed"
        return transition
    end
    if not WriteGlobal(
        DarkPassengerHunger.SCHEMA_KEY,
        DarkPassengerHunger.SCHEMA_VERSION
    ) then
        transition.accepted = false
        transition.reason = "schema_write_failed"
        return transition
    end

    -- Force the neutral tier through ApplyTier even if this module was
    -- hot-reloaded and no longer remembers the currently visible debuff.
    DarkPassengerHunger.currentTier = false
    local evaluated = DarkPassengerHunger.Evaluate()
    if evaluated == nil then
        transition.accepted = false
        transition.reason = "evaluation_failed"
        return transition
    end

    transition.current = evaluated
    Log(
        "ordinary kill relief previous=" ..
        tostring(transition.previous) ..
        " current=" .. tostring(transition.current)
    )
    return transition
end

function DarkPassengerHunger.RunReliefSelfTest()
    local function assertTransition(input, accepted, current)
        local transition = DarkPassengerHunger.ReliefTransition(input)
        if transition.accepted ~= accepted or
           transition.current ~= current then
            error(
                "relief transition failed input=" .. tostring(input) ..
                " accepted=" .. tostring(transition.accepted) ..
                " current=" .. tostring(transition.current)
            )
        end
    end

    assertTransition(40, false, 40)
    assertTransition(50, false, 50)
    assertTransition(60, true, 50)
    assertTransition(100, true, 50)
    Log("ordinary kill relief self-test passed")
    return true
end

function DarkPassengerHunger.Status()
    local now = WorldTime()
    local lastSatisfaction = DarkPassengerHunger.EnsureInitialized()
    local hunger = DarkPassengerHunger.Calculate(now, lastSatisfaction)
    local tier = DarkPassengerHunger.TierFor(hunger)
    local graceRemainingDays = nil
    if now ~= nil and lastSatisfaction ~= nil then
        graceRemainingDays = math.max(
            0,
            (lastSatisfaction - now) /
                DarkPassengerHunger.SECONDS_PER_DAY
        )
    end
    local effectiveAnchor = lastSatisfaction
    Log(
        "status hunger=" .. tostring(hunger) ..
        " tier=" .. tostring(tier) ..
        " now=" .. tostring(now) ..
        " lastSatisfactionWorldTime=" .. tostring(lastSatisfaction) ..
        " graceRemainingDays=" .. tostring(graceRemainingDays) ..
        " lastResult=" .. tostring(DarkPassengerHunger.lastResult) ..
        " effectiveAnchor=" .. tostring(effectiveAnchor)
    )
    return hunger
end

function DarkPassengerHunger.Set(argsLine)
    local requested = tonumber(
        string.match(tostring(argsLine or ""), "^%s*([^%s]+)")
    )
    if requested == nil then
        Log("set failed: expected hunger 0..100")
        return false
    end

    requested = math.max(
        0,
        math.min(DarkPassengerHunger.MAX_HUNGER, requested)
    )
    local now = WorldTime()
    if now == nil then return false end
    local lastSatisfaction =
        now -
        (requested / DarkPassengerHunger.HUNGER_PER_DAY) *
        DarkPassengerHunger.SECONDS_PER_DAY
    WriteGlobal(
        DarkPassengerHunger.SCHEMA_KEY,
        DarkPassengerHunger.SCHEMA_VERSION
    )
    if not WriteGlobal(
        DarkPassengerHunger.LAST_SATISFACTION_KEY,
        lastSatisfaction
    ) then
        return false
    end
    DarkPassengerHunger.InvalidateAppliedState()
    return DarkPassengerHunger.Evaluate() ~= nil
end

function DarkPassengerHunger.Evaluate()
    local hunger = DarkPassengerHunger.Get()
    local soul = PlayerSoul()
    if hunger == nil or soul == nil then return nil end

    local tier = DarkPassengerHunger.TierFor(hunger)
    if not DarkPassengerHunger.ApplyTier(soul, tier) then
        return nil
    end
    return hunger
end

local function ScheduleEvaluation()
    if Script == nil or Script.SetTimerForFunction == nil then return false end
    local generation = DarkPassengerHunger.evaluationGeneration
    local ok, timerOrError = pcall(function()
        return Script.SetTimerForFunction(
            DarkPassengerHunger.EVALUATION_INTERVAL_MS,
            "DarkPassengerHunger.OnEvaluationTimer",
            { generation = generation }
        )
    end)
    if not ok then
        Log("timer scheduling failed: " .. tostring(timerOrError))
        return false
    end
    return true
end

function DarkPassengerHunger.OnEvaluationTimer(userData, timerId)
    local requestedGeneration =
        userData ~= nil and tonumber(userData.generation) or nil
    if requestedGeneration ~= DarkPassengerHunger.evaluationGeneration then
        return
    end
    if DarkPassengerHunger.evaluationAliveLoggedGeneration ~=
       requestedGeneration then
        DarkPassengerHunger.evaluationAliveLoggedGeneration =
            requestedGeneration
        Log("evaluation timer alive generation=" .. tostring(requestedGeneration))
    end
    DarkPassengerHunger.Evaluate()
    ScheduleEvaluation()
end

function DarkPassengerHunger.StartEvaluation(reason)
    if reason ~= "first_player_action" then
        DarkPassengerHunger.playerActionRestartRequested = false
    end
    DarkPassengerHunger.evaluationGeneration =
        DarkPassengerHunger.evaluationGeneration + 1
    DarkPassengerHunger.evaluationAliveLoggedGeneration = nil
    Log(
        "evaluation started reason=" .. tostring(reason) ..
        " generation=" ..
        tostring(DarkPassengerHunger.evaluationGeneration)
    )
    DarkPassengerHunger.Evaluate()
    return ScheduleEvaluation()
end

function DarkPassengerHunger.EnsureEvaluationFromPlayerAction(...)
    if DarkPassengerHunger.evaluationAliveLoggedGeneration ==
       DarkPassengerHunger.evaluationGeneration then
        return false
    end
    if DarkPassengerHunger.playerActionRestartRequested then
        return false
    end

    DarkPassengerHunger.playerActionRestartRequested = true
    local started =
        DarkPassengerHunger.StartEvaluation("first_player_action")
    if not started then
        DarkPassengerHunger.playerActionRestartRequested = false
    end
    return started
end

function DarkPassengerHunger.Probe()
    ReadClock(
        "devMode",
        function() return System.IsDevModeEnable() end
    )
    ReadClock(
        "worldTime",
        function() return Calendar.GetWorldTime() end
    )
    ReadClock(
        "gameTime",
        function() return Calendar.GetGameTime() end
    )
    ReadClock(
        "worldDay",
        function() return Calendar.GetWorldDay() end
    )
    ReadClock(
        "worldHourOfDay",
        function() return Calendar.GetWorldHourOfDay() end
    )
    return DarkPassengerHunger.Status() ~= nil
end

function DarkPassengerHunger.ProbeSet(argsLine)
    local requested = tonumber(
        string.match(tostring(argsLine or ""), "^%s*([^%s]+)")
    )
    if requested == nil then requested = WorldTime() end
    if requested == nil then return false end

    WriteGlobal(
        DarkPassengerHunger.SCHEMA_KEY,
        DarkPassengerHunger.SCHEMA_VERSION
    )
    WriteGlobal(
        DarkPassengerHunger.LAST_SATISFACTION_KEY,
        requested
    )
    Log("probe timestamp set=" .. tostring(requested))
    return DarkPassengerHunger.Probe()
end

function DarkPassengerHunger.ProbeClear()
    WriteGlobal(DarkPassengerHunger.SCHEMA_KEY, 0)
    WriteGlobal(DarkPassengerHunger.LAST_SATISFACTION_KEY, 0)
    Log("probe timestamp cleared")
    return true
end

local function ProbeStore(label, setter, getter)
    local setOk, setResult = pcall(setter)
    local getOk, valueOrError = pcall(getter)
    Log(
        "store=" .. label ..
        " setOk=" .. tostring(setOk) ..
        " setResult=" .. tostring(setResult) ..
        " getOk=" .. tostring(getOk) ..
        " value=" .. tostring(valueOrError)
    )
end

function DarkPassengerHunger.StoreProbe()
    local key = "dp_hunger_probe_value"
    local value = 424242

    ProbeStore(
        "Variables",
        function() return Variables.SetGlobal(key, value) end,
        function() return Variables.GetGlobal(key) end
    )
    ProbeStore(
        "GameToken",
        function() return GameToken.SetToken(key, value) end,
        function() return GameToken.GetToken(key) end
    )

    local player = g_localActor or System.GetEntityByName("dude")
    local soulId =
        player ~= nil and player.soul ~= nil and
        player.soul:GetId() or nil
    if soulId == nil then
        Log("store=XGen skipped: player soul id unavailable")
        return false
    end

    ProbeStore(
        "XGenBrain",
        function()
            return XGenAIModule.SetBrainVariable(soulId, key, value)
        end,
        function()
            return XGenAIModule.GetBrainVariable(soulId, key)
        end
    )
    return true
end

function DarkPassengerHunger.StoreRead()
    local key = "dp_hunger_probe_value"
    local variablesOk, variablesValue = pcall(function()
        return Variables.GetGlobal(key)
    end)
    local tokenOk, tokenValue = pcall(function()
        return GameToken.GetToken(key)
    end)
    Log(
        "store read Variables ok=" .. tostring(variablesOk) ..
        " value=" .. tostring(variablesValue)
    )
    Log(
        "store read GameToken ok=" .. tostring(tokenOk) ..
        " value=" .. tostring(tokenValue)
    )
    return variablesOk and tokenOk
end

local okCommands, commandError = pcall(function()
    System.AddCCommand(
        "dp_hunger_status",
        "DarkPassengerHunger.Status()",
        "Show Dark Passenger hidden hunger"
    )
    System.AddCCommand(
        "dp_hunger_set",
        "DarkPassengerHunger.Set(%line)",
        "Set Dark Passenger hidden hunger from 0 to 100"
    )
    System.AddCCommand(
        "dp_hunger_probe",
        "DarkPassengerHunger.Probe()",
        "Inspect Dark Passenger persisted hunger clock"
    )
    System.AddCCommand(
        "dp_hunger_probe_set",
        "DarkPassengerHunger.ProbeSet(%line)",
        "Persist current or supplied Dark Passenger world timestamp"
    )
    System.AddCCommand(
        "dp_hunger_probe_clear",
        "DarkPassengerHunger.ProbeClear()",
        "Clear persisted Dark Passenger world timestamp"
    )
    System.AddCCommand(
        "dp_hunger_store_probe",
        "DarkPassengerHunger.StoreProbe()",
        "Compare native Dark Passenger numeric storage candidates"
    )
    System.AddCCommand(
        "dp_hunger_store_read",
        "DarkPassengerHunger.StoreRead()",
        "Read native Dark Passenger storage candidates without writing"
    )
end)

if not okCommands then
    Log("console command registration failed: " .. tostring(commandError))
end

DarkPassengerHunger.StartEvaluation("module_load")
Log("persistent hunger clock loaded")
