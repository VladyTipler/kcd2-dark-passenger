DarkPassengerEvidence = DarkPassengerEvidence or {}

DarkPassengerEvidence.SCHEMA_VERSION = 1
DarkPassengerEvidence.SOURCE_ENTITY_NAME = "kpri_innkeeper"
DarkPassengerEvidence.SOURCE_REGION = "kutnohorsko"
DarkPassengerEvidence.SOURCE_SETTLEMENT = "pritoky"
DarkPassengerEvidence.CONFIDENCE_REWARD = 30
DarkPassengerEvidence.FIRST_LEAD_BUFF_GUID =
    "6e532a34-ce2b-47ae-9427-c67a4a1b94b1"

DarkPassengerEvidence.RUMORS = {
    pritoky = {
        {
            id = "innkeeper_rumor",
            text = "Хозяин корчмы понизил голос: «Поговаривают, один из местных слишком часто возвращается домой с чужой кровью на рукавах. И каждый раз находит объяснение».",
        },
    },
}

local KEYS = {
    schema = "dp_evidence_schema_version",
    awardedGeneration = "dp_evidence_awarded_generation",
    signalDispatched = "dp_evidence_signal_dispatched",
}

local function Log(message)
    if System ~= nil and System.LogAlways ~= nil then
        System.LogAlways(
            "[DarkPassenger][Evidence] " .. tostring(message)
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
        awardedGeneration = 0,
        signalDispatched = false,
    }
end

local function CopyState(state)
    return {
        awardedGeneration =
            state ~= nil and tonumber(state.awardedGeneration) or 0,
        signalDispatched =
            state ~= nil and state.signalDispatched == true or false,
    }
end

local function ReadState()
    if tonumber(ReadScalar(KEYS.schema)) ~=
       DarkPassengerEvidence.SCHEMA_VERSION then
        return DefaultState()
    end
    return {
        awardedGeneration =
            tonumber(ReadScalar(KEYS.awardedGeneration)) or 0,
        signalDispatched =
            tonumber(ReadScalar(KEYS.signalDispatched)) == 1,
    }
end

local function PersistState(state)
    local results = {
        WriteScalar(KEYS.schema, DarkPassengerEvidence.SCHEMA_VERSION),
        WriteScalar(KEYS.awardedGeneration, state.awardedGeneration),
        WriteScalar(
            KEYS.signalDispatched,
            state.signalDispatched and 1 or 0
        ),
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

local function HasBuff(entity, buffGuid)
    if entity == nil or entity.soul == nil or
       entity.soul.HasBuffDebug == nil then
        return false
    end
    local ok, result = pcall(function()
        return entity.soul:HasBuffDebug(buffGuid)
    end)
    return ok and (result == true or result == 1)
end

local function RemoveSignalBuff()
    local actor = PlayerEntity()
    if actor == nil or actor.soul == nil or
       actor.soul.RemoveAllBuffsByGuid == nil then
        return false
    end
    local ok = pcall(function()
        actor.soul:RemoveAllBuffsByGuid(
            DarkPassengerEvidence.FIRST_LEAD_BUFF_GUID
        )
    end)
    return ok
end

local function IsAlive(entity)
    if entity == nil or entity.id == nil or
       entity.actor == nil or entity.actor.IsDead == nil then
        return false
    end
    local ok, dead = pcall(function()
        return entity.actor:IsDead()
    end)
    return ok and dead ~= true
end

local function MatchesSource(entity)
    if entity == nil or entity.id == nil or
       System == nil or System.GetEntityByName == nil then
        return false
    end
    local expected = System.GetEntityByName(
        DarkPassengerEvidence.SOURCE_ENTITY_NAME
    )
    return expected ~= nil and expected.id ~= nil and
        expected.id == entity.id
end

local function IsLocalPlayer(user)
    local actor = PlayerEntity()
    return actor ~= nil and actor.id ~= nil and
        user ~= nil and user.id == actor.id
end

function DarkPassengerEvidence.Transition(state, event)
    local nextState = CopyState(state)
    local result = { accepted = false, reason = "unknown_event" }
    local eventType = event ~= nil and event.type or nil
    local generation = tonumber(event ~= nil and event.generation)

    if generation == nil or generation <= 0 then
        result.reason = "invalid_generation"
        return nextState, result
    end

    if eventType == "open" then
        nextState.signalDispatched = false
        result.accepted = true
        result.reason = "opened"
        return nextState, result
    end

    if eventType == "award" then
        if nextState.awardedGeneration == generation then
            result.reason = "already_awarded"
            return nextState, result
        end
        nextState.awardedGeneration = generation
        nextState.signalDispatched = false
        result.accepted = true
        result.reason = "awarded"
        return nextState, result
    end

    if eventType == "signal" then
        if nextState.awardedGeneration ~= generation then
            result.reason = "not_awarded"
            return nextState, result
        end
        nextState.signalDispatched = true
        result.accepted = true
        result.reason = "signal_dispatched"
        return nextState, result
    end

    if eventType == "restore" then
        result.accepted = true
        result.reason = "restored"
        return nextState, result
    end

    return nextState, result
end

function DarkPassengerEvidence.IsEligible(context, evidenceState)
    if context == nil or context.active ~= true then
        return false, "inactive"
    end
    local generation = tonumber(context.generation)
    if generation == nil or generation <= 0 then
        return false, "invalid_generation"
    end
    if context.gameRegion ~= DarkPassengerEvidence.SOURCE_REGION or
       context.settlement ~= DarkPassengerEvidence.SOURCE_SETTLEMENT then
        return false, "unsupported_settlement"
    end
    if context.sourceMatches ~= true then
        return false, "wrong_source"
    end
    if context.sourceAlive ~= true then
        return false, "source_dead"
    end
    if evidenceState ~= nil and
       tonumber(evidenceState.awardedGeneration) == generation then
        return false, "already_awarded"
    end
    return true, "eligible"
end

local function InvestigationContext(source)
    if DarkPassengerInvestigation == nil or
       DarkPassengerInvestigation.GetState == nil or
       DarkPassengerInvestigation.GetCandidate == nil then
        return nil
    end
    local investigation = DarkPassengerInvestigation.GetState()
    local candidate = DarkPassengerInvestigation.GetCandidate()
    return {
        active = investigation ~= nil and investigation.active == true,
        generation =
            investigation ~= nil and investigation.generation or 0,
        gameRegion = candidate ~= nil and candidate.gameRegion or nil,
        settlement = candidate ~= nil and candidate.settlement or nil,
        sourceMatches = MatchesSource(source),
        sourceAlive = IsAlive(source),
    }
end

local function ResolveRumor(generation)
    local rumors = DarkPassengerEvidence.RUMORS.pritoky or {}
    if #rumors == 0 then return nil end
    local index = ((tonumber(generation) or 1) - 1) % #rumors + 1
    return rumors[index]
end

local function DispatchJournalSignal(generation)
    local actor = PlayerEntity()
    if actor == nil or actor.soul == nil or actor.soul.AddBuff == nil then
        Log("journal signal deferred: player unavailable")
        return false
    end

    local state = ReadState()
    if state.awardedGeneration ~= generation then return false end
    if state.signalDispatched and
       HasBuff(actor, DarkPassengerEvidence.FIRST_LEAD_BUFF_GUID) then
        return true
    end

    local ok, handle = pcall(function()
        return actor.soul:AddBuff(
            DarkPassengerEvidence.FIRST_LEAD_BUFF_GUID
        )
    end)
    if not ok or handle == nil then
        Log(
            "journal signal failed generation=" .. tostring(generation) ..
            " error=" .. tostring(handle)
        )
        return false
    end

    local nextState, result = DarkPassengerEvidence.Transition(
        state,
        { type = "signal", generation = generation }
    )
    if not result.accepted then return false end
    PersistState(nextState)
    Log("journal signal dispatched generation=" .. tostring(generation))
    return true
end

function DarkPassengerEvidence.OnInvestigationOpened(generation)
    local state = ReadState()
    local nextState, result = DarkPassengerEvidence.Transition(
        state,
        { type = "open", generation = generation }
    )
    if not result.accepted then return false end
    RemoveSignalBuff()
    PersistState(nextState)
    return true
end

function DarkPassengerEvidence.Restore(investigationState)
    local state = ReadState()
    local generation = tonumber(
        investigationState ~= nil and investigationState.generation
    )
    if investigationState == nil or investigationState.active ~= true or
       generation == nil or generation <= 0 then
        return false
    end
    if state.awardedGeneration == generation and
       (not state.signalDispatched or
        not HasBuff(
            PlayerEntity(),
            DarkPassengerEvidence.FIRST_LEAD_BUFF_GUID
        )) then
        return DispatchJournalSignal(generation)
    end
    return true
end

function DarkPassengerEvidence.AddRumorAction(
    source,
    user,
    firstFast,
    output
)
    if type(output) ~= "table" or not MatchesSource(source) then
        return false
    end
    local context = InvestigationContext(source)
    local eligible = DarkPassengerEvidence.IsEligible(
        context,
        ReadState()
    )
    if not eligible then return false end

    return AddInteractorAction(
        output,
        firstFast,
        Action()
            :hint("@dp_evidence_ask_rumors")
            :action("butcher")
            :hintType(AHT_RELEASE)
            :uiOrder(1)
            :func(DarkPassengerEvidence.OnAskRumors)
            :interaction(inr_talk)
            :enabled(true)
    )
end

function DarkPassengerEvidence.OnAskRumors(source, user, slotId)
    if not IsLocalPlayer(user) then return false end
    local state = ReadState()
    local context = InvestigationContext(source)
    local eligible, reason = DarkPassengerEvidence.IsEligible(
        context,
        state
    )
    if not eligible then
        Log("rumor rejected reason=" .. tostring(reason))
        return false
    end

    local generation = tonumber(context.generation)
    local rumor = ResolveRumor(generation)
    if rumor == nil then
        Log("rumor rejected: content unavailable")
        return false
    end
    local evidenceResult = DarkPassengerInvestigation.AddEvidence(
        DarkPassengerEvidence.CONFIDENCE_REWARD,
        "innkeeper_rumor",
        generation
    )
    if evidenceResult == nil or evidenceResult.accepted ~= true then
        Log(
            "rumor rejected by investigation reason=" ..
            tostring(evidenceResult ~= nil and evidenceResult.reason or nil)
        )
        return false
    end

    local nextState, transitionResult = DarkPassengerEvidence.Transition(
        state,
        { type = "award", generation = generation }
    )
    if not transitionResult.accepted then return false end
    PersistState(nextState)
    DispatchJournalSignal(generation)

    if Game ~= nil and Game.ShowNotification ~= nil then
        pcall(function()
            Game.ShowNotification(rumor.text)
        end)
    end
    Log(
        "rumor awarded generation=" .. tostring(generation) ..
        " confidence=" .. tostring(evidenceResult.current)
    )
    return true
end

function DarkPassengerEvidence.Status()
    local state = ReadState()
    local context = InvestigationContext(
        System ~= nil and System.GetEntityByName ~= nil and
        System.GetEntityByName(DarkPassengerEvidence.SOURCE_ENTITY_NAME) or nil
    )
    local eligible, reason = DarkPassengerEvidence.IsEligible(context, state)
    Log(
        "status generation=" ..
        tostring(context ~= nil and context.generation or nil) ..
        " awardedGeneration=" .. tostring(state.awardedGeneration) ..
        " signalDispatched=" .. tostring(state.signalDispatched) ..
        " eligible=" .. tostring(eligible) ..
        " reason=" .. tostring(reason)
    )
    return state
end

function DarkPassengerEvidence.RunSelfTest()
    local failures = {}
    local function Expect(condition, label)
        if not condition then table.insert(failures, label) end
    end

    local state = DefaultState()
    local context = {
        active = true,
        generation = 4,
        gameRegion = "kutnohorsko",
        settlement = "pritoky",
        sourceMatches = true,
        sourceAlive = true,
    }
    local eligible = DarkPassengerEvidence.IsEligible(context, state)
    Expect(eligible == true, "eligible")
    state = DarkPassengerEvidence.Transition(
        state,
        { type = "award", generation = 4 }
    )
    eligible = DarkPassengerEvidence.IsEligible(context, state)
    Expect(eligible == false, "one shot")
    local duplicateState, duplicate = DarkPassengerEvidence.Transition(
        state,
        { type = "award", generation = 4 }
    )
    Expect(
        duplicate.accepted == false and
        duplicateState.awardedGeneration == 4,
        "duplicate rejected"
    )
    local signalState, signal = DarkPassengerEvidence.Transition(
        state,
        { type = "signal", generation = 4 }
    )
    Expect(
        signal.accepted and signalState.signalDispatched,
        "signal after award"
    )
    context.gameRegion = "trosecko"
    context.generation = 5
    eligible = DarkPassengerEvidence.IsEligible(context, state)
    Expect(eligible == false, "wrong region")

    local passed = #failures == 0
    Log(
        "selftest=" .. tostring(passed) ..
        " failures=" .. table.concat(failures, ",")
    )
    return passed
end

if DarkPassengerInteractions ~= nil and
   DarkPassengerInteractions.RegisterProvider ~= nil then
    DarkPassengerInteractions.RegisterProvider(
        "innkeeper_rumor",
        function(source, user, firstFast, output)
            return DarkPassengerEvidence.AddRumorAction(
                source,
                user,
                firstFast,
                output
            )
        end
    )
else
    Log("shared interaction registry unavailable")
end

pcall(function()
    if System ~= nil and System.AddCCommand ~= nil then
        System.AddCCommand(
            "dp_evidence_status",
            "DarkPassengerEvidence.Status()",
            "Dark Passenger: print first-lead evidence state"
        )
        System.AddCCommand(
            "dp_evidence_selftest",
            "DarkPassengerEvidence.RunSelfTest()",
            "Dark Passenger: run first-lead evidence self-test"
        )
    end
end)

if DarkPassengerInvestigation ~= nil and
   DarkPassengerInvestigation.GetState ~= nil then
    DarkPassengerEvidence.Restore(
        DarkPassengerInvestigation.GetState()
    )
end
Log("module loaded")
