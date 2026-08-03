DarkPassengerEvidence = DarkPassengerEvidence or {}

DarkPassengerEvidence.SCHEMA_VERSION = 2
DarkPassengerEvidence.DEBUG_ACTION_ENABLED = false
DarkPassengerEvidence.FIRST_LEAD_BUFF_GUID =
    "6e532a34-ce2b-47ae-9427-c67a4a1b94b1"
DarkPassengerEvidence.RUMOR_AVAILABLE_BUFF_GUID =
    "8043886b-d0bc-4a3b-9c89-07c8f60bf7d8"

local KEYS = {
    schema = "dp_evidence_schema_version",
    legacyAwardedGeneration = "dp_evidence_awarded_generation",
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
        legacyAwardedGeneration = 0,
        signalGeneration = 0,
    }
end

local function CopyState(state)
    return {
        legacyAwardedGeneration = tonumber(
            state ~= nil and state.legacyAwardedGeneration
        ) or 0,
        signalGeneration = tonumber(
            state ~= nil and state.signalGeneration
        ) or 0,
    }
end

local function ReadState()
    local schema = tonumber(ReadScalar(KEYS.schema))
    if schema == DarkPassengerEvidence.SCHEMA_VERSION then
        return {
            legacyAwardedGeneration = 0,
            signalGeneration =
                tonumber(ReadScalar(KEYS.signalDispatched)) or 0,
        }
    end
    if schema == 1 then
        local legacyAwardedGeneration = tonumber(
            ReadScalar(KEYS.legacyAwardedGeneration)
        ) or 0
        return {
            legacyAwardedGeneration = legacyAwardedGeneration,
            signalGeneration =
                tonumber(ReadScalar(KEYS.signalDispatched)) == 1 and
                legacyAwardedGeneration or 0,
        }
    end
    return DefaultState()
end

local function PersistState(state)
    local results = {
        WriteScalar(KEYS.schema, DarkPassengerEvidence.SCHEMA_VERSION),
        WriteScalar(
            KEYS.signalDispatched,
            state.signalGeneration
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

local function RemoveBuff(buffGuid)
    local actor = PlayerEntity()
    if actor == nil or actor.soul == nil or
       actor.soul.RemoveAllBuffsByGuid == nil then
        return false
    end
    local ok = pcall(function()
        actor.soul:RemoveAllBuffsByGuid(buffGuid)
    end)
    return ok
end

local function AddBuff(buffGuid)
    local actor = PlayerEntity()
    if actor == nil or actor.soul == nil or actor.soul.AddBuff == nil then
        return false
    end
    if HasBuff(actor, buffGuid) then return true end
    local ok, handle = pcall(function()
        return actor.soul:AddBuff(buffGuid)
    end)
    return ok and handle ~= nil
end

local function SetRumorAvailability(available)
    if available then
        return AddBuff(DarkPassengerEvidence.RUMOR_AVAILABLE_BUFF_GUID)
    end
    return RemoveBuff(DarkPassengerEvidence.RUMOR_AVAILABLE_BUFF_GUID)
end

function DarkPassengerEvidence.ApplyAvailability(generation, available)
    generation = tonumber(generation)
    if generation == nil or generation <= 0 then return false end
    return SetRumorAvailability(available == true)
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
       System == nil or System.GetEntityByName == nil or
       DarkPassengerCaseEvidence == nil or
       DarkPassengerCaseEvidence.ResolveActive == nil then
        return false
    end
    local resolved = DarkPassengerCaseEvidence.ResolveActive("innkeeper")
    if resolved == nil or resolved.binding == nil or
       resolved.binding.entityName == nil then
        return false
    end
    local expected = System.GetEntityByName(
        resolved.binding.entityName
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
        if nextState.signalGeneration ~= generation then
            nextState.signalGeneration = 0
        end
        result.accepted = true
        result.reason = "opened"
        return nextState, result
    end

    if eventType == "signal" then
        nextState.signalGeneration = generation
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
    if context.caseResolved ~= true then
        return false, "content_unavailable"
    end
    if context.gameRegion ~= context.expectedRegion or
       context.settlement ~= context.expectedSettlement then
        return false, "unsupported_settlement"
    end
    if context.sourceMatches ~= true then
        return false, "wrong_source"
    end
    if context.sourceAlive ~= true then
        return false, "source_dead"
    end
    if context.evidenceDiscovered == true then
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
    local resolved =
        DarkPassengerCaseEvidence ~= nil and
        DarkPassengerCaseEvidence.ResolveActive ~= nil and
        DarkPassengerCaseEvidence.ResolveActive("innkeeper") or nil
    local constraints = resolved ~= nil and
        resolved.caseTemplate ~= nil and
        resolved.caseTemplate.constraints or nil
    local evidenceDiscovered = false
    if resolved ~= nil and resolved.evidence ~= nil and
       DarkPassengerEvidenceRegistry ~= nil and
       DarkPassengerEvidenceRegistry.GetCaseState ~= nil then
        local registryState = DarkPassengerEvidenceRegistry.GetCaseState(
            investigation ~= nil and investigation.generation or 0
        )
        for _, entry in ipairs(
            registryState ~= nil and registryState.evidence or {}
        ) do
            if tonumber(entry.code) == tonumber(resolved.evidence.code) and
               entry.status == "discovered" then
                evidenceDiscovered = true
            end
        end
    end
    return {
        active = investigation ~= nil and investigation.active == true,
        generation =
            investigation ~= nil and investigation.generation or 0,
        gameRegion = candidate ~= nil and candidate.gameRegion or nil,
        settlement = candidate ~= nil and candidate.settlement or nil,
        caseResolved = resolved ~= nil,
        expectedRegion = constraints ~= nil and constraints.region or nil,
        expectedSettlement =
            constraints ~= nil and constraints.settlement or nil,
        sourceMatches = MatchesSource(source),
        sourceAlive = IsAlive(source),
        evidenceDiscovered = evidenceDiscovered,
    }
end

local function ResolveRumor(generation)
    if DarkPassengerCaseContent == nil or
       DarkPassengerCaseContent.GetSelected == nil then
        return nil
    end
    local selected = DarkPassengerCaseContent.GetSelected(generation)
    return selected ~= nil and selected.rumor or nil
end

local function IsRumorDiscovered(generation, rumor)
    rumor = rumor or ResolveRumor(generation)
    if rumor == nil or DarkPassengerEvidenceRegistry == nil or
       DarkPassengerEvidenceRegistry.GetCaseState == nil then
        return false
    end
    local registryState =
        DarkPassengerEvidenceRegistry.GetCaseState(generation)
    for _, entry in ipairs(
        registryState ~= nil and registryState.evidence or {}
    ) do
        if tonumber(entry.code) == tonumber(rumor.code) then
            return entry.status == "discovered"
        end
    end
    return false
end

local function MigrateLegacyDiscovery(generation, state)
    if tonumber(state.legacyAwardedGeneration) ~= tonumber(generation) then
        return true
    end
    local rumor = ResolveRumor(generation)
    if rumor == nil or DarkPassengerEvidenceRegistry == nil or
       DarkPassengerEvidenceRegistry.Discover == nil then
        return false
    end
    local result = DarkPassengerEvidenceRegistry.Discover(
        generation,
        rumor.code,
        { source = "legacy_rumor_award" }
    )
    if result == nil or (
        result.accepted ~= true and result.reason ~= "already_discovered"
    ) then
        return false
    end
    state.legacyAwardedGeneration = 0
    return PersistState(state)
end

local function DispatchJournalSignal(generation)
    local actor = PlayerEntity()
    if actor == nil or actor.soul == nil or actor.soul.AddBuff == nil then
        Log("journal signal deferred: player unavailable")
        return false
    end

    local state = ReadState()
    if not IsRumorDiscovered(generation) then return false end
    if state.signalGeneration == generation and
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
    local selected = nil
    if DarkPassengerCaseContent ~= nil and
       DarkPassengerCaseContent.OnInvestigationOpened ~= nil then
        local candidate =
            DarkPassengerInvestigation ~= nil and
            DarkPassengerInvestigation.GetCandidate ~= nil and
            DarkPassengerInvestigation.GetCandidate() or nil
        selected = DarkPassengerCaseContent.OnInvestigationOpened(
            generation,
            candidate
        )
    end
    local state = ReadState()
    local nextState, result = DarkPassengerEvidence.Transition(
        state,
        { type = "open", generation = generation }
    )
    if not result.accepted then return false end
    RemoveBuff(DarkPassengerEvidence.FIRST_LEAD_BUFF_GUID)
    PersistState(nextState)
    if DarkPassengerLeadPlanner ~= nil and
       DarkPassengerLeadPlanner.Apply ~= nil then
        DarkPassengerLeadPlanner.Apply(generation)
    end
    return true
end

function DarkPassengerEvidence.Restore(investigationState)
    local selected = nil
    if DarkPassengerCaseContent ~= nil and
       DarkPassengerCaseContent.Restore ~= nil then
        local candidate =
            DarkPassengerInvestigation ~= nil and
            DarkPassengerInvestigation.GetCandidate ~= nil and
            DarkPassengerInvestigation.GetCandidate() or nil
        selected = DarkPassengerCaseContent.Restore(
            investigationState,
            candidate
        )
    end
    local state = ReadState()
    local generation = tonumber(
        investigationState ~= nil and investigationState.generation
    )
    if investigationState == nil or investigationState.active ~= true or
       generation == nil or generation <= 0 then
        SetRumorAvailability(false)
        return false
    end
    if not MigrateLegacyDiscovery(generation, state) then return false end
    state = ReadState()
    if DarkPassengerLeadPlanner ~= nil and
       DarkPassengerLeadPlanner.Apply ~= nil then
        DarkPassengerLeadPlanner.Apply(generation)
    else
        SetRumorAvailability(
            selected ~= nil and not IsRumorDiscovered(generation)
        )
    end
    if IsRumorDiscovered(generation) then
        if state.signalGeneration ~= generation or
           not HasBuff(
               PlayerEntity(),
               DarkPassengerEvidence.FIRST_LEAD_BUFF_GUID
           ) then
            return DispatchJournalSignal(generation)
        end
    end
    return true
end

function DarkPassengerEvidence.AddRumorAction(
    source,
    user,
    firstFast,
    output
)
    if not DarkPassengerEvidence.DEBUG_ACTION_ENABLED or
       type(output) ~= "table" or not MatchesSource(source) then
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

local function AwardSelectedRumor(generation, showNotification)
    local state = ReadState()
    local selectedRumor = ResolveRumor(generation)
    if selectedRumor == nil then
        Log("rumor rejected: content unavailable")
        return false
    end
    local evidenceResult = DarkPassengerEvidenceRegistry.Discover(
        generation,
        selectedRumor.code,
        { source = "innkeeper_rumor" }
    )
    if evidenceResult == nil or (
        evidenceResult.accepted ~= true and
        evidenceResult.reason ~= "already_discovered"
    ) then
        Log(
            "rumor rejected by investigation reason=" ..
            tostring(evidenceResult ~= nil and evidenceResult.reason or nil)
        )
        return false
    end

    SetRumorAvailability(false)
    if DarkPassengerLeadPlanner ~= nil and
       DarkPassengerLeadPlanner.Apply ~= nil then
        DarkPassengerLeadPlanner.Apply(generation)
    end
    DispatchJournalSignal(generation)

    if showNotification and Game ~= nil and Game.ShowNotification ~= nil then
        pcall(function()
            Game.ShowNotification(selectedRumor.notification)
        end)
    end
    Log(
        "rumor awarded generation=" .. tostring(generation) ..
        " confidence=" .. tostring(evidenceResult.current)
    )
    return true
end

function DarkPassengerEvidence.OnRumorCompleted(gameRegion)
    if DarkPassengerInvestigation == nil or
       DarkPassengerInvestigation.GetState == nil or
       DarkPassengerInvestigation.GetCandidate == nil then
        return false
    end
    local investigation = DarkPassengerInvestigation.GetState()
    local candidate = DarkPassengerInvestigation.GetCandidate()
    if investigation == nil or investigation.active ~= true or
       candidate == nil or candidate.gameRegion ~= gameRegion then
        Log("native rumor rejected: active case mismatch")
        return false
    end
    return AwardSelectedRumor(
        tonumber(investigation.generation),
        false
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
    return AwardSelectedRumor(tonumber(context.generation), true)
end

function DarkPassengerEvidence.Status()
    local state = ReadState()
    local resolved =
        DarkPassengerCaseEvidence ~= nil and
        DarkPassengerCaseEvidence.ResolveActive ~= nil and
        DarkPassengerCaseEvidence.ResolveActive("innkeeper") or nil
    local sourceName = resolved ~= nil and resolved.binding ~= nil and
        resolved.binding.entityName or nil
    local context = InvestigationContext(
        System ~= nil and System.GetEntityByName ~= nil and
        sourceName ~= nil and System.GetEntityByName(sourceName) or nil
    )
    local eligible, reason = DarkPassengerEvidence.IsEligible(context, state)
    Log(
        "status generation=" ..
        tostring(context ~= nil and context.generation or nil) ..
        " legacyAwardedGeneration=" ..
        tostring(state.legacyAwardedGeneration) ..
        " signalGeneration=" .. tostring(state.signalGeneration) ..
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
        caseResolved = true,
        expectedRegion = "kutnohorsko",
        expectedSettlement = "pritoky",
        sourceMatches = true,
        sourceAlive = true,
    }
    local eligible = DarkPassengerEvidence.IsEligible(context, state)
    Expect(eligible == true, "eligible")
    context.evidenceDiscovered = true
    eligible = DarkPassengerEvidence.IsEligible(context, state)
    Expect(eligible == false, "one shot")
    local signalState, signal = DarkPassengerEvidence.Transition(
        state,
        { type = "signal", generation = 4 }
    )
    Expect(
        signal.accepted and signalState.signalGeneration == 4,
        "signal generation"
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
