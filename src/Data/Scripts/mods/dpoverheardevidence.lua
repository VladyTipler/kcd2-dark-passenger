DarkPassengerOverheardEvidence = DarkPassengerOverheardEvidence or {}

DarkPassengerOverheardEvidence.SCHEMA_VERSION = 2

local KEYS = {
    schema = "dp_overheard_schema_version",
    generation = "dp_overheard_generation",
    pairIndex = "dp_overheard_pair_index",
    available = "dp_overheard_available",
}

local function SafeSceneId(sceneId)
    local value = tostring(sceneId or "legacy")
    return value:gsub("[^%w_]", "_")
end

local function StateKeys(sceneId)
    if sceneId == nil or sceneId == "" or sceneId == "legacy" then
        return KEYS
    end
    local prefix = "dp_overheard_" .. SafeSceneId(sceneId) .. "_"
    return {
        schema = prefix .. "schema_version",
        generation = prefix .. "generation",
        pairIndex = prefix .. "pair_index",
        available = prefix .. "available",
    }
end

local function Log(message)
    if System ~= nil and System.LogAlways ~= nil then
        System.LogAlways(
            "[DarkPassenger][OverheardEvidence] " .. tostring(message)
        )
    end
end

local function ReadScalar(key)
    if Variables == nil or Variables.GetGlobal == nil then return nil end
    local ok, value = pcall(function() return Variables.GetGlobal(key) end)
    if not ok then return nil end
    return value
end

local function WriteScalar(key, value)
    if Variables == nil or Variables.SetGlobal == nil then return false end
    return pcall(function() Variables.SetGlobal(key, value) end)
end

local function DefaultState()
    return { generation = 0, pairIndex = 0, available = false }
end

local function CopyState(state)
    return {
        generation = tonumber(state ~= nil and state.generation) or 0,
        pairIndex = tonumber(state ~= nil and state.pairIndex) or 0,
        available = state ~= nil and state.available == true,
    }
end

local function ReadState(sceneId)
    local keys = StateKeys(sceneId)
    if tonumber(ReadScalar(keys.schema)) ~=
       DarkPassengerOverheardEvidence.SCHEMA_VERSION then
        return DefaultState()
    end
    return {
        generation = tonumber(ReadScalar(keys.generation)) or 0,
        pairIndex = tonumber(ReadScalar(keys.pairIndex)) or 0,
        available = tonumber(ReadScalar(keys.available)) == 1,
    }
end

local function PersistState(state, sceneId)
    local keys = StateKeys(sceneId)
    return WriteScalar(keys.pairIndex, state.pairIndex) and
        WriteScalar(keys.available, state.available and 1 or 0) and
        WriteScalar(keys.schema, DarkPassengerOverheardEvidence.SCHEMA_VERSION) and
        WriteScalar(keys.generation, state.generation)
end

function DarkPassengerOverheardEvidence.Transition(state, event)
    local nextState = CopyState(state)
    local generation = tonumber(event ~= nil and event.generation)
    if generation == nil or generation <= 0 then
        return nextState, { accepted = false, reason = "invalid_generation" }
    end
    if generation < nextState.generation then
        return nextState, { accepted = false, reason = "stale_generation" }
    end
    local eventType = event ~= nil and event.type or nil
    if eventType == "select" then
        local pairIndex = tonumber(event.pairIndex)
        if pairIndex == nil or pairIndex <= 0 then
            return nextState, { accepted = false, reason = "invalid_pair" }
        end
        nextState.generation = generation
        nextState.pairIndex = pairIndex
        nextState.available = event.available == true
        return nextState, { accepted = true, reason = "selected" }
    end
    if generation ~= nextState.generation then
        return nextState, { accepted = false, reason = "stale_generation" }
    end
    if eventType == "close" then
        nextState.available = false
        return nextState, { accepted = true, reason = "closed" }
    end
    if eventType == "restore" then
        return nextState, { accepted = true, reason = "restored" }
    end
    return nextState, { accepted = false, reason = "unknown_event" }
end

local function PairContainsTarget(pair, targetEntityName)
    if targetEntityName == nil then return false end
    for _, speaker in ipairs(pair ~= nil and pair.speakers or {}) do
        if speaker.entityName == targetEntityName then return true end
    end
    return false
end

function DarkPassengerOverheardEvidence.NormalizePairs(pairs)
    if type(pairs) ~= "table" then return {} end
    if pairs.speakers ~= nil then return { pairs } end
    return pairs
end

function DarkPassengerOverheardEvidence.NormalizeScenes(scenes)
    if type(scenes) ~= "table" then return {} end
    if scenes.id ~= nil then return { scenes } end
    return scenes
end

local function ScenePairs(scene)
    if scene == nil then return {} end
    return DarkPassengerOverheardEvidence.NormalizePairs(scene.pairs)
end

function DarkPassengerOverheardEvidence.SelectPair(
    pairs,
    targetEntityName,
    isPairAvailable
)
    local collisionSeen = false
    for index, pair in ipairs(pairs or {}) do
        if PairContainsTarget(pair, targetEntityName) then
            collisionSeen = true
        elseif isPairAvailable == nil or isPairAvailable(pair, index) then
            return pair, index, "selected"
        end
    end
    if collisionSeen then return nil, 0, "target_collision" end
    return nil, 0, "no_available_pair"
end

local function EntityByName(entityName)
    if System == nil or System.GetEntityByName == nil or
       entityName == nil then
        return nil
    end
    return System.GetEntityByName(entityName)
end

local function IsAlive(entity)
    if entity == nil or entity.actor == nil or
       entity.actor.IsDead == nil then
        return false
    end
    local ok, dead = pcall(function() return entity.actor:IsDead() end)
    return ok and dead ~= true and dead ~= 1
end

local function ResolvePairEntities(pair)
    local entities = {}
    for _, speaker in ipairs(pair ~= nil and pair.speakers or {}) do
        local entity = EntityByName(speaker.entityName)
        if not IsAlive(entity) then return nil end
        entities[#entities + 1] = entity
    end
    if #entities ~= 2 then return nil end
    return entities
end

local function ResolvePairEntitiesDetailed(pair)
    local entities = {}
    for _, speaker in ipairs(pair ~= nil and pair.speakers or {}) do
        local entity = EntityByName(speaker.entityName)
        if entity == nil then return nil, "speaker_missing" end
        if not IsAlive(entity) then return nil, "speaker_dead" end
        entities[#entities + 1] = entity
    end
    if #entities ~= 2 then return nil, "speaker_missing" end
    return entities, "ready"
end

local function EntityName(entity)
    if entity == nil then return nil end
    if entity.GetName ~= nil then
        local ok, name = pcall(function() return entity:GetName() end)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return entity.name
end

local function RemovePairSignal(pair, buffGuid)
    local first = pair ~= nil and pair.speakers ~= nil and
        pair.speakers[1] or nil
    local entity = first ~= nil and EntityByName(first.entityName) or nil
    if entity == nil or entity.soul == nil or
       entity.soul.RemoveAllBuffsByGuid == nil then
        return false
    end
    return pcall(function()
        entity.soul:RemoveAllBuffsByGuid(buffGuid)
    end)
end

local function RemoveAllSignals(overheard)
    for _, pair in ipairs(ScenePairs(overheard)) do
        RemovePairSignal(pair, overheard.buff_guid)
    end
end

local function AddPairSignal(pair, buffGuid)
    local entities = ResolvePairEntities(pair)
    local entity = entities ~= nil and entities[1] or nil
    if entity == nil or entity.soul == nil or
       entity.soul.AddBuff == nil then
        return false
    end
    if entity.soul.HasBuffDebug ~= nil then
        local ok, present = pcall(function()
            return entity.soul:HasBuffDebug(buffGuid)
        end)
        if ok and (present == true or present == 1) then return true end
    end
    local ok, handle = pcall(function()
        return entity.soul:AddBuff(buffGuid)
    end)
    return ok and handle ~= nil
end

local function IsDiscovered(generation, evidenceCode)
    if DarkPassengerEvidenceRegistry == nil or
       DarkPassengerEvidenceRegistry.GetCaseState == nil then
        return false
    end
    local registryState =
        DarkPassengerEvidenceRegistry.GetCaseState(generation)
    for _, entry in ipairs(
        registryState ~= nil and registryState.evidence or {}
    ) do
        if tonumber(entry.code) == tonumber(evidenceCode) then
            return entry.status == "discovered"
        end
    end
    return false
end

local function ActiveSnapshot(generation)
    if DarkPassengerInvestigation == nil or
       DarkPassengerInvestigation.GetState == nil or
       DarkPassengerCaseSnapshot == nil or
       DarkPassengerCaseSnapshot.Get == nil then
        return nil, "runtime_unavailable"
    end
    local investigation = DarkPassengerInvestigation.GetState()
    if investigation == nil or investigation.active ~= true or
       tonumber(investigation.generation) ~= tonumber(generation) then
        return nil, "stale_generation"
    end
    return DarkPassengerCaseSnapshot.Get(generation)
end

local function TargetEntityName(snapshot)
    return snapshot ~= nil and snapshot.candidate ~= nil and
        snapshot.candidate.entityName or nil
end

local function OverheardScenes(caseTemplate)
    if caseTemplate == nil then return {} end
    local scenes = DarkPassengerOverheardEvidence.NormalizeScenes(
        caseTemplate.overheard_scenes
    )
    if #scenes > 0 then return scenes end
    return DarkPassengerOverheardEvidence.NormalizeScenes(
        caseTemplate.overheard
    )
end

local function SceneId(scene)
    return scene ~= nil and scene.id or "legacy"
end

local function FindSceneById(caseTemplate, sceneId)
    local expected = tostring(sceneId or "")
    for _, scene in ipairs(OverheardScenes(caseTemplate)) do
        if expected == "" or tostring(SceneId(scene)) == expected then
            return scene
        end
    end
    return nil
end

local function ApplySceneAvailability(generation, scene, available, snapshot)
    local sceneId = SceneId(scene)
    if available ~= true or
       IsDiscovered(generation, scene.evidence_code) then
        RemoveAllSignals(scene)
        local current = ReadState(sceneId)
        if current.generation == generation then
            local closed = DarkPassengerOverheardEvidence.Transition(
                current,
                { type = "close", generation = generation }
            )
            PersistState(closed, sceneId)
        end
        return true, "closed"
    end

    local current = ReadState(sceneId)
    local pair = nil
    local pairIndex = 0
    local reason = nil
    if current.generation == generation and current.pairIndex > 0 then
        local persisted = ScenePairs(scene)[current.pairIndex]
        if persisted ~= nil and
           not PairContainsTarget(persisted, TargetEntityName(snapshot)) and
           ResolvePairEntities(persisted) ~= nil then
            pair = persisted
            pairIndex = current.pairIndex
        end
    end
    if pair == nil then
        pair, pairIndex, reason =
            DarkPassengerOverheardEvidence.SelectPair(
                ScenePairs(scene),
                TargetEntityName(snapshot),
                function(candidatePair)
                    return ResolvePairEntities(candidatePair) ~= nil
                end
            )
    end
    RemoveAllSignals(scene)
    if pair == nil then
        Log(
            "scene unavailable id=" .. tostring(sceneId) ..
            " reason=" .. tostring(reason)
        )
        return false, reason
    end
    local nextState, result = DarkPassengerOverheardEvidence.Transition(
        current,
        {
            type = "select",
            generation = generation,
            pairIndex = pairIndex,
            available = true,
        }
    )
    if not result.accepted or not PersistState(nextState, sceneId) then
        return false, result.reason or "persistence_failed"
    end
    if not AddPairSignal(pair, scene.buff_guid) then
        return false, "signal_failed"
    end
    Log(
        "available generation=" .. tostring(generation) ..
        " scene=" .. tostring(sceneId) ..
        " pair=" .. tostring(pair.id)
    )
    return true, "available"
end

function DarkPassengerOverheardEvidence.ApplyAvailability(
    generation,
    available
)
    generation = tonumber(generation)
    local snapshot, reason = ActiveSnapshot(generation)
    local caseTemplate = snapshot ~= nil and snapshot.caseTemplate or nil
    local scenes = OverheardScenes(caseTemplate)
    if #scenes == 0 then
        return false, reason or "overheard_unavailable"
    end
    local applied = false
    local lastReason = "closed"
    for _, scene in ipairs(OverheardScenes(caseTemplate)) do
        if scene.activation_mode == "proximity" then
            local ok, sceneReason = ApplySceneAvailability(
                generation,
                scene,
                available,
                snapshot
            )
            applied = applied or ok
            lastReason = sceneReason or lastReason
        elseif available ~= true then
            ApplySceneAvailability(generation, scene, false, snapshot)
            applied = true
        end
    end
    return applied, lastReason
end

function DarkPassengerOverheardEvidence.Restore(generation)
    generation = tonumber(generation)
    local snapshot, reason = ActiveSnapshot(generation)
    if snapshot == nil then return false, reason end
    return DarkPassengerOverheardEvidence.ApplyAvailability(generation, true)
end

local function WorldPosition(entity)
    if entity == nil or entity.GetWorldPos == nil then return nil end
    local ok, position = pcall(function() return entity:GetWorldPos() end)
    if not ok then return nil end
    return position
end

local function Distance(left, right)
    if left == nil or right == nil then return nil end
    local dx = (tonumber(left.x) or 0) - (tonumber(right.x) or 0)
    local dy = (tonumber(left.y) or 0) - (tonumber(right.y) or 0)
    local dz = (tonumber(left.z) or 0) - (tonumber(right.z) or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function PlayerEntity()
    if g_localActor ~= nil then return g_localActor end
    if player ~= nil then return player end
    return EntityByName("dude")
end

local function IsLocalPlayer(user)
    local actor = PlayerEntity()
    return actor ~= nil and actor.id ~= nil and
        user ~= nil and tostring(user.id) == tostring(actor.id)
end

local function IsInCombatDanger(actor)
    if actor == nil or actor.soul == nil or
       actor.soul.IsInCombatDanger == nil then
        return false
    end
    local ok, danger = pcall(function()
        return actor.soul:IsInCombatDanger()
    end)
    return ok and (
        danger == true or (tonumber(danger) or 0) == 1
    )
end

local function IsInDialogue(entity)
    if entity == nil or entity.human == nil or
       entity.human.IsInDialog == nil then
        return false
    end
    local ok, active = pcall(function()
        return entity.human:IsInDialog()
    end)
    return ok and (
        active == true or (tonumber(active) or 0) == 1
    )
end

local function AnyDialogueActive(entities)
    if IsInDialogue(PlayerEntity()) then return true end
    for _, entity in ipairs(entities or {}) do
        if IsInDialogue(entity) then return true end
    end
    return false
end

local function PairContainsEntityName(pair, entityName)
    if entityName == nil then return false end
    for _, speaker in ipairs(pair ~= nil and pair.speakers or {}) do
        if speaker.entityName == entityName then return true end
    end
    return false
end

local function IsWithinHearingDistance(pair, hearingDistance)
    local playerPosition = WorldPosition(PlayerEntity())
    local entities = ResolvePairEntities(pair)
    if playerPosition == nil or entities == nil then return false end
    for _, entity in ipairs(entities) do
        local distance = Distance(playerPosition, WorldPosition(entity))
        if distance ~= nil and distance <= hearingDistance then return true end
    end
    return false
end

function DarkPassengerOverheardEvidence.GetContextRequests(gameRegion)
    local investigation = DarkPassengerInvestigation ~= nil and
        DarkPassengerInvestigation.GetState ~= nil and
        DarkPassengerInvestigation.GetState() or nil
    local generation = tonumber(
        investigation ~= nil and investigation.generation
    )
    local snapshot = ActiveSnapshot(generation)
    local caseTemplate = snapshot ~= nil and snapshot.caseTemplate or nil
    if caseTemplate == nil or caseTemplate.constraints == nil or
       gameRegion ~= caseTemplate.constraints.region then
        return {}
    end

    local requests = {}
    for _, scene in ipairs(OverheardScenes(caseTemplate)) do
        if scene.context ~= nil and
           not IsDiscovered(generation, scene.evidence_code) then
            requests[#requests + 1] = {
                sceneId = SceneId(scene),
                context = scene.context,
                generation = generation,
                activationMode = scene.activation_mode,
            }
        end
    end
    return requests
end

function DarkPassengerOverheardEvidence.GetInteractiveSceneForEntity(entity)
    local investigation = DarkPassengerInvestigation ~= nil and
        DarkPassengerInvestigation.GetState ~= nil and
        DarkPassengerInvestigation.GetState() or nil
    local generation = tonumber(
        investigation ~= nil and investigation.generation
    )
    local snapshot, reason = ActiveSnapshot(generation)
    if snapshot == nil then return nil, reason end
    local entityName = EntityName(entity)
    if entityName == nil then return nil, "speaker_missing" end

    local caseTemplate = snapshot.caseTemplate
    for _, scene in ipairs(OverheardScenes(caseTemplate)) do
        if scene.activation_mode == "interaction" then
            for pairIndex, pair in ipairs(ScenePairs(scene)) do
                if PairContainsEntityName(pair, entityName) then
                    return {
                        generation = generation,
                        snapshot = snapshot,
                        scene = scene,
                        pair = pair,
                        pairIndex = pairIndex,
                    }, "ready"
                end
            end
        end
    end
    return nil, "scene_unavailable"
end

function DarkPassengerOverheardEvidence.CanStartInteraction(entity, user)
    if not IsLocalPlayer(user) then
        return false, "not_local_player"
    end
    local context, reason =
        DarkPassengerOverheardEvidence.GetInteractiveSceneForEntity(entity)
    if context == nil then return false, reason end

    local generation = context.generation
    local scene = context.scene
    local pair = context.pair
    if IsDiscovered(generation, scene.evidence_code) then
        return false, "already_discovered"
    end
    if PairContainsTarget(pair, TargetEntityName(context.snapshot)) then
        return false, "target_collision"
    end
    local entities, entityReason = ResolvePairEntitiesDetailed(pair)
    if entities == nil then return false, entityReason end
    if IsInCombatDanger(user or PlayerEntity()) then
        return false, "player_in_combat"
    end
    if AnyDialogueActive(entities) then
        return false, "dialogue_active"
    end
    if not IsWithinHearingDistance(pair, scene.hearing_distance) then
        return false, "out_of_range"
    end
    context.entities = entities
    return true, "ready", context
end

function DarkPassengerOverheardEvidence.StartInteraction(
    entity,
    user,
    slotId
)
    local allowed, reason, context =
        DarkPassengerOverheardEvidence.CanStartInteraction(entity, user)
    if not allowed then
        Log("interaction rejected reason=" .. tostring(reason))
        return false
    end

    local generation = context.generation
    local scene = context.scene
    local pair = context.pair
    local sceneId = SceneId(scene)
    RemoveAllSignals(scene)
    local selected, result = DarkPassengerOverheardEvidence.Transition(
        ReadState(sceneId),
        {
            type = "select",
            generation = generation,
            pairIndex = context.pairIndex,
            available = true,
        }
    )
    if not result.accepted or not PersistState(selected, sceneId) then
        return false, result.reason or "persistence_failed"
    end
    if not AddPairSignal(pair, scene.buff_guid) then
        local closed = DarkPassengerOverheardEvidence.Transition(
            selected,
            { type = "close", generation = generation }
        )
        PersistState(closed, sceneId)
        return false, "signal_failed"
    end
    Log(
        "interaction started generation=" .. tostring(generation) ..
        " scene=" .. tostring(sceneId) ..
        " pair=" .. tostring(pair.id) ..
        " slot=" .. tostring(slotId)
    )
    return true
end

function DarkPassengerOverheardEvidence.AddListenAction(
    entity,
    user,
    firstFast,
    output
)
    if type(output) ~= "table" then return false end
    local allowed =
        DarkPassengerOverheardEvidence.CanStartInteraction(entity, user)
    if not allowed then return false end
    return AddInteractorAction(
        output,
        firstFast,
        Action()
            :hint("@dp_overheard_listen_action")
            :action("butcher")
            :hintType(AHT_RELEASE)
            :uiOrder(2)
            :func(DarkPassengerOverheardEvidence.StartInteraction)
            :interaction(inr_talk)
            :enabled(true)
    )
end

function DarkPassengerOverheardEvidence.OnClueSpoken(gameRegion, sceneId)
    local investigation = DarkPassengerInvestigation ~= nil and
        DarkPassengerInvestigation.GetState ~= nil and
        DarkPassengerInvestigation.GetState() or nil
    local generation = tonumber(
        investigation ~= nil and investigation.generation
    )
    local snapshot, reason = ActiveSnapshot(generation)
    local caseTemplate = snapshot ~= nil and snapshot.caseTemplate or nil
    local scene = FindSceneById(caseTemplate, sceneId)
    if scene == nil or caseTemplate.constraints == nil or
       gameRegion ~= caseTemplate.constraints.region then
        return false, reason or "overheard_unavailable"
    end
    if IsDiscovered(generation, scene.evidence_code) then
        RemoveAllSignals(scene)
        return false, "already_discovered"
    end
    local resolvedSceneId = SceneId(scene)
    local state = ReadState(resolvedSceneId)
    if state.generation ~= generation or state.available ~= true then
        return false, "stale_generation"
    end
    local pair = ScenePairs(scene)[state.pairIndex]
    if pair == nil or PairContainsTarget(pair, TargetEntityName(snapshot)) then
        return false, "target_collision"
    end
    if not IsWithinHearingDistance(pair, scene.hearing_distance) then
        return false, "out_of_range"
    end
    if DarkPassengerEvidenceRegistry == nil or
       DarkPassengerEvidenceRegistry.Discover == nil then
        return false, "registry_unavailable"
    end
    local evidenceResult = DarkPassengerEvidenceRegistry.Discover(
        generation,
        scene.evidence_code,
        {
            source = "overheard_dialogue",
            sceneId = resolvedSceneId,
            pairId = pair.id,
        }
    )
    if evidenceResult == nil or evidenceResult.accepted ~= true then
        return false,
            evidenceResult ~= nil and evidenceResult.reason or
            "discovery_failed"
    end
    RemoveAllSignals(scene)
    local closed = DarkPassengerOverheardEvidence.Transition(
        state,
        { type = "close", generation = generation }
    )
    PersistState(closed, resolvedSceneId)
    if DarkPassengerLeadPlanner ~= nil and
       DarkPassengerLeadPlanner.Apply ~= nil then
        DarkPassengerLeadPlanner.Apply(generation)
    end
    Log(
        "discovered generation=" .. tostring(generation) ..
        " scene=" .. tostring(resolvedSceneId) ..
        " pair=" .. tostring(pair.id) ..
        " confidence=" .. tostring(evidenceResult.current)
    )
    return true, "discovered"
end

function DarkPassengerOverheardEvidence.RunSelfTest()
    local failures = {}
    local function Expect(condition, label)
        if not condition then failures[#failures + 1] = label end
    end
    local pairs = {
        {
            id = "primary",
            speakers = {
                { entityName = "primary_a" },
                { entityName = "primary_b" },
            },
        },
        {
            id = "fallback",
            speakers = {
                { entityName = "fallback_a" },
                { entityName = "fallback_b" },
            },
        },
    }
    local pair, index = DarkPassengerOverheardEvidence.SelectPair(
        pairs,
        "target",
        function() return true end
    )
    Expect(pair == pairs[1] and index == 1, "primary")
    pair, index = DarkPassengerOverheardEvidence.SelectPair(
        pairs,
        "primary_a",
        function() return true end
    )
    Expect(pair == pairs[2] and index == 2, "target_collision_fallback")
    pair, index = DarkPassengerOverheardEvidence.SelectPair(
        pairs,
        "target",
        function() return false end
    )
    Expect(pair == nil and index == 0, "unavailable")
    local state = DefaultState()
    state = DarkPassengerOverheardEvidence.Transition(
        state,
        { type = "select", generation = 8, pairIndex = 1, available = true }
    )
    local _, stale = DarkPassengerOverheardEvidence.Transition(
        state,
        { type = "close", generation = 7 }
    )
    Expect(stale.reason == "stale_generation", "stale_generation")
    local passed = #failures == 0
    Log(
        "self-test " .. (passed and "PASS" or "FAIL") ..
        " failures=" .. table.concat(failures, ",")
    )
    return passed, failures
end

if DarkPassengerInteractions ~= nil and
   DarkPassengerInteractions.RegisterProvider ~= nil then
    DarkPassengerInteractions.RegisterProvider(
        "interactive_overheard",
        function(entity, user, firstFast, output)
            return DarkPassengerOverheardEvidence.AddListenAction(
                entity,
                user,
                firstFast,
                output
            )
        end
    )
end

if System ~= nil and System.AddCCommand ~= nil then
    System.AddCCommand(
        "dp_test_overheard_selftest",
        "DarkPassengerOverheardEvidence.RunSelfTest()",
        "Runs deterministic overheard evidence tests"
    )
end
