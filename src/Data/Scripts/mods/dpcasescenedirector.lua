DarkPassengerSceneDirector = DarkPassengerSceneDirector or {}

DarkPassengerSceneDirector.materializedGenerations =
    DarkPassengerSceneDirector.materializedGenerations or {}

local function Log(message)
    if System ~= nil and System.LogAlways ~= nil then
        System.LogAlways(
            "[DarkPassenger][SceneDirector] " .. tostring(message)
        )
    end
end

local function EntityName(entity)
    if entity == nil then return nil end
    local name = nil
    pcall(function() name = entity:GetName() end)
    return name
end

local function ResolveLiveBinding(binding)
    if binding == nil then return nil, true end
    local resolved = {
        definition = binding,
        entityName = binding.entity_name,
        entityGuid = binding.entity_guid,
        soulGuid = binding.soul_guid,
        candidateSlot = tonumber(binding.candidate_slot) or 0,
        entity = nil,
    }
    local requiresLiveActor = binding.kind == "NPC"
    if binding.entity_name ~= nil and binding.entity_name ~= "" and
       System ~= nil and System.GetEntityByName ~= nil then
        resolved.entity = System.GetEntityByName(binding.entity_name)
    end
    return resolved, not requiresLiveActor or resolved.entity ~= nil
end

function DarkPassengerSceneDirector.BuildSceneInstances(
    sceneDefinitions
)
    local instances = {}
    for _, definition in ipairs(sceneDefinitions or {}) do
        local resolvedBindings = {}
        local ready = true
        for role, binding in pairs(definition.resolved_bindings or {}) do
            local resolved, bindingReady = ResolveLiveBinding(binding)
            resolvedBindings[role] = resolved
            ready = ready and bindingReady
        end
        table.insert(instances, {
            id = definition.id,
            kind = definition.kind,
            evidenceCode = tonumber(definition.evidence_code) or 0,
            placement = definition.placement,
            evidenceModule = definition.evidence_module,
            definition = definition,
            resolvedBindings = resolvedBindings,
            compiledAssets = definition.compiled_assets,
            state = ready and "ready" or "streaming_deferred",
        })
    end
    return instances
end

function DarkPassengerSceneDirector.BuildCaseInstance(snapshot)
    if snapshot == nil or tonumber(snapshot.generation) == nil then return nil end
    local sceneDefinitions = snapshot.sceneDefinitions or {}
    local caseInstance = {
        generation = tonumber(snapshot.generation),
        caseCode = tonumber(snapshot.caseCode),
        openerCode = tonumber(snapshot.openerCode),
        variantId = snapshot.variantId,
        variantCode = tonumber(snapshot.variantCode) or 0,
        bindingCode = tonumber(snapshot.bindingCode) or 0,
        targetSlot = tonumber(snapshot.targetSlot) or 0,
        bindings = snapshot.bindings or {},
        sceneDefinitions = sceneDefinitions,
        sceneInstances = DarkPassengerSceneDirector.BuildSceneInstances(
            sceneDefinitions
        ),
        interrogationOffered = snapshot.interrogationOffered == true,
    }
    return caseInstance
end

local function HasDeferredScenes(caseInstance)
    for _, scene in ipairs(caseInstance.sceneInstances or {}) do
        if scene.state == "streaming_deferred" then return true end
    end
    return false
end

local function HasCaseStartEvidence(caseInstance)
    for _, scene in ipairs(caseInstance.sceneInstances or {}) do
        local evidence = scene.definition or {}
        if evidence.placement == "case_start" and
           tonumber(evidence.evidence_code) ~= nil then
            return true
        end
    end
    return false
end

function DarkPassengerSceneDirector.Materialize(generation, snapshot)
    generation = tonumber(generation)
    if generation == nil or generation <= 0 then
        return nil, "invalid_generation"
    end
    if DarkPassengerSceneDirector.materializedGenerations[generation] then
        local restored = snapshot ~= nil and snapshot.caseInstance or nil
        return restored, "already_materialized"
    end
    if snapshot == nil and DarkPassengerCaseSnapshot ~= nil and
       DarkPassengerCaseSnapshot.Restore ~= nil then
        snapshot = DarkPassengerCaseSnapshot.Restore(generation)
    end
    if snapshot == nil then return nil, "snapshot_unavailable" end
    -- Rebuild from immutable definitions on every attempt. A snapshot may have
    -- been captured while one or more bound actors were still streamed out.
    local caseInstance = DarkPassengerSceneDirector.BuildCaseInstance(snapshot)
    if caseInstance == nil then return nil, "case_instance_unavailable" end

    -- Placement and presentation stay behind existing idempotent adapters.
    -- SceneDirector only feeds them compiled definitions and persisted bindings.
    if HasCaseStartEvidence(caseInstance) and
       DarkPassengerEvidenceSeeder ~= nil and
       DarkPassengerEvidenceSeeder.Seed ~= nil then
        DarkPassengerEvidenceSeeder.Seed(generation, snapshot)
    end
    local reason = "streaming_deferred"
    if not HasDeferredScenes(caseInstance) then
        DarkPassengerSceneDirector.materializedGenerations[generation] = true
        reason = "materialized"
    end
    Log(
        "generation=" .. tostring(generation) ..
        " variantId=" .. tostring(caseInstance.variantId) ..
        " scenes=" .. tostring(#caseInstance.sceneInstances) ..
        " reason=" .. reason
    )
    return caseInstance, reason
end

function DarkPassengerSceneDirector.Restore(generation)
    if DarkPassengerCaseSnapshot == nil or
       DarkPassengerCaseSnapshot.Restore == nil then
        return nil, "snapshot_unavailable"
    end
    local snapshot, reason = DarkPassengerCaseSnapshot.Restore(generation)
    if snapshot == nil then return nil, reason end
    return DarkPassengerSceneDirector.Materialize(generation, snapshot)
end

local function CurrentSnapshot()
    if DarkPassengerInvestigation == nil or
       DarkPassengerInvestigation.GetState == nil or
       DarkPassengerCaseSnapshot == nil or
       DarkPassengerCaseSnapshot.Get == nil then
        return nil, nil
    end
    local investigation = DarkPassengerInvestigation.GetState()
    if investigation == nil or investigation.active ~= true or
       investigation.revealed ~= true then
        return nil, investigation
    end
    return DarkPassengerCaseSnapshot.Get(investigation.generation), investigation
end

function DarkPassengerSceneDirector.CanOfferInterrogation(target, user)
    local snapshot = CurrentSnapshot()
    if snapshot == nil or snapshot.interrogationOffered == true or
       target == nil then
        return false, ""
    end
    local expectedName = snapshot.candidate ~= nil and
        snapshot.candidate.entityName or nil
    if expectedName == nil or EntityName(target) ~= expectedName then
        return false, ""
    end
    return true, ""
end

function DarkPassengerSceneDirector.MarkInterrogationOffered(target)
    local snapshot, investigation = CurrentSnapshot()
    if snapshot == nil or investigation == nil then
        return false, "case_unavailable"
    end
    if target ~= nil and snapshot.candidate ~= nil and
       EntityName(target) ~= snapshot.candidate.entityName then
        return false, "target_mismatch"
    end
    if DarkPassengerCaseSnapshot == nil or
       DarkPassengerCaseSnapshot.MarkInterrogationOffered == nil then
        return false, "snapshot_unavailable"
    end
    return DarkPassengerCaseSnapshot.MarkInterrogationOffered(
        investigation.generation
    )
end

function DarkPassengerSceneDirector.RunSelfTest()
    local snapshot = {
        generation = 4,
        caseCode = 1001,
        openerCode = 1101,
        variantId = "case--region--settlement--hash",
        variantCode = 777,
        bindingCode = 888,
        targetSlot = 9,
        bindings = { target = { candidate_slot = 9 } },
        sceneDefinitions = {
            {
                id = "paper-trail/read-letter",
                kind = "search",
                evidence_code = 1102,
                placement = "case_start",
                evidence_module = "document-in-container",
                resolved_bindings = {},
                compiled_assets = { id = "default" },
            },
        },
    }
    local instance = DarkPassengerSceneDirector.BuildCaseInstance(snapshot)
    local passed = instance ~= nil and
        instance.variantId == snapshot.variantId and
        instance.bindingCode == 888 and
        #instance.sceneInstances == 1 and
        instance.sceneInstances[1].evidenceCode == 1102 and
        instance.sceneInstances[1].state == "ready"
    Log("selftest=" .. tostring(passed))
    return passed
end

pcall(function()
    if System ~= nil and System.AddCCommand ~= nil then
        System.AddCCommand(
            "dp_case_scene_selftest",
            "DarkPassengerSceneDirector.RunSelfTest()",
            "Dark Passenger: run compiled case-scene checks"
        )
    end
end)

Log("module loaded")
