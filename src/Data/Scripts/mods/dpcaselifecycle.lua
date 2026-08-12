DarkPassengerCaseLifecycle = DarkPassengerCaseLifecycle or {}

DarkPassengerCaseLifecycle.SCHEMA_VERSION = 1
DarkPassengerCaseLifecycle.ACTIVATION_DELAY_MS = 2000
DarkPassengerCaseLifecycle.MAX_ACTIVATION_ATTEMPTS = 8
DarkPassengerCaseLifecycle.clearedGeneration =
    DarkPassengerCaseLifecycle.clearedGeneration or 0
DarkPassengerCaseLifecycle.preparedGeneration =
    DarkPassengerCaseLifecycle.preparedGeneration or 0
DarkPassengerCaseLifecycle.preparedRevision =
    DarkPassengerCaseLifecycle.preparedRevision or 0
DarkPassengerCaseLifecycle.activatedGeneration =
    DarkPassengerCaseLifecycle.activatedGeneration or 0
DarkPassengerCaseLifecycle.activatedRevision =
    DarkPassengerCaseLifecycle.activatedRevision or 0
DarkPassengerCaseLifecycle.timerSerial =
    DarkPassengerCaseLifecycle.timerSerial or 0

local KEYS = {
    schema = "dp_case_lifecycle_schema_version",
    clearedGeneration = "dp_case_lifecycle_cleared_generation",
    appliedGeneration = "dp_case_lifecycle_applied_generation",
    appliedRevision = "dp_case_lifecycle_applied_revision",
}

local function Log(message)
    if System ~= nil and System.LogAlways ~= nil then
        System.LogAlways(
            "[DarkPassenger][CaseLifecycle] " .. tostring(message)
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
    local ok = pcall(function() Variables.SetGlobal(key, value) end)
    return ok
end

local function CurrentRevision()
    return tonumber(DarkPassengerCaseVariantCatalogRevision) or 1
end

local function PersistAppliedRevision(generation, revision)
    return WriteScalar(KEYS.schema, DarkPassengerCaseLifecycle.SCHEMA_VERSION) and
        WriteScalar(KEYS.appliedGeneration, generation) and
        WriteScalar(KEYS.appliedRevision, revision)
end

local function ReadAppliedRevision()
    if tonumber(ReadScalar(KEYS.schema)) ~=
       DarkPassengerCaseLifecycle.SCHEMA_VERSION then
        return 0, 0
    end
    return tonumber(ReadScalar(KEYS.appliedGeneration)) or 0,
        tonumber(ReadScalar(KEYS.appliedRevision)) or 0
end

local function PlayerEntity()
    if g_localActor ~= nil then return g_localActor end
    if player ~= nil then return player end
    if System ~= nil and System.GetEntityByName ~= nil then
        return System.GetEntityByName("dude")
    end
    return nil
end

local function ValidateManifest(manifest)
    return type(manifest) == "table" and
        tonumber(manifest.schema_version) ==
            DarkPassengerCaseLifecycle.SCHEMA_VERSION and
        type(manifest.items) == "table" and
        type(manifest.signal_buff_guids) == "table"
end

function DarkPassengerCaseLifecycle.ResolveManifest(generation)
    generation = tonumber(generation)
    if generation == nil or generation <= 0 or
       DarkPassengerCaseContent == nil or
       DarkPassengerCaseContent.GetSelected == nil then
        return nil, "case_unavailable"
    end
    local selected = DarkPassengerCaseContent.GetSelected(generation)
    local manifest = selected ~= nil and selected.variant ~= nil and
        selected.variant.cleanup_manifest or nil
    if not ValidateManifest(manifest) then
        return nil, "cleanup_manifest_unavailable"
    end
    return manifest, "resolved"
end

local function DisableAvailability(generation, manifest)
    for _, role in ipairs(manifest.availability_roles or {}) do
        if role == "innkeeper" and DarkPassengerEvidence ~= nil and
           DarkPassengerEvidence.ApplyAvailability ~= nil then
            pcall(function()
                DarkPassengerEvidence.ApplyAvailability(generation, false)
            end)
        elseif role == "witness" and DarkPassengerWitnessLead ~= nil and
               DarkPassengerWitnessLead.ApplyAvailability ~= nil then
            pcall(function()
                DarkPassengerWitnessLead.ApplyAvailability(generation, false)
            end)
        elseif role == "overheard" and
               DarkPassengerOverheardEvidence ~= nil and
               DarkPassengerOverheardEvidence.ApplyAvailability ~= nil then
            pcall(function()
                DarkPassengerOverheardEvidence.ApplyAvailability(
                    generation,
                    false
                )
            end)
        end
    end
end

local function RemoveSignalBuffs(manifest, preservedBuffGuid)
    local actor = PlayerEntity()
    local soul = actor ~= nil and actor.soul or nil
    if soul == nil or soul.RemoveAllBuffsByGuid == nil then return false end
    local succeeded = true
    for _, buffGuid in ipairs(manifest.signal_buff_guids or {}) do
        if preservedBuffGuid == nil or
           tostring(buffGuid) ~= tostring(preservedBuffGuid) then
            local ok = pcall(function()
                soul:RemoveAllBuffsByGuid(buffGuid)
            end)
            succeeded = succeeded and ok
        end
    end
    return succeeded
end

local function DeleteItem(inventory, itemGuid)
    if inventory == nil or inventory.DeleteItemOfClass == nil then
        return false
    end
    local ok = pcall(function()
        inventory.DeleteItemOfClass(itemGuid, -1)
    end)
    return ok
end

local function RemoveCaseItems(manifest)
    local actor = PlayerEntity()
    if actor == nil or actor.inventory == nil then return false end
    local succeeded = true
    for _, item in ipairs(manifest.items or {}) do
        local retention = tostring(item.retention or "")
        if retention == "case" then
            if DarkPassengerQuestItemPlacement ~= nil and
               DarkPassengerQuestItemPlacement.Cancel ~= nil then
                pcall(function()
                    DarkPassengerQuestItemPlacement.Cancel(item.item_guid)
                end)
            end
            succeeded = DeleteItem(actor.inventory, item.item_guid) and
                succeeded
            local destination = nil
            if item.destination_entity_name ~= nil and
               item.destination_entity_name ~= "" and
               System ~= nil and System.GetEntityByName ~= nil then
                destination = System.GetEntityByName(
                    item.destination_entity_name
                )
            end
            if destination ~= nil and destination.inventory ~= nil then
                succeeded = DeleteItem(
                    destination.inventory,
                    item.item_guid
                ) and succeeded
            end
        end
    end
    return succeeded
end

local function ClearPresentation(generation, manifest, preservedBuffGuid)
    DisableAvailability(generation, manifest)
    return RemoveSignalBuffs(manifest, preservedBuffGuid)
end

local function PersistClearedGeneration(generation)
    if not WriteScalar(KEYS.schema, DarkPassengerCaseLifecycle.SCHEMA_VERSION) or
       not WriteScalar(KEYS.clearedGeneration, generation) then
        return false
    end
    DarkPassengerCaseLifecycle.clearedGeneration = generation
    return true
end

local function ReadClearedGeneration()
    if tonumber(ReadScalar(KEYS.schema)) ~=
       DarkPassengerCaseLifecycle.SCHEMA_VERSION then
        return tonumber(DarkPassengerCaseLifecycle.clearedGeneration) or 0
    end
    return tonumber(ReadScalar(KEYS.clearedGeneration)) or 0
end

function DarkPassengerCaseLifecycle.ClearCaseArtifacts(generation, reason)
    generation = tonumber(generation)
    if generation == nil or generation <= 0 then
        return false, "invalid_generation"
    end
    if ReadClearedGeneration() == generation then
        return true, "already_cleared"
    end
    local manifest, manifestReason =
        DarkPassengerCaseLifecycle.ResolveManifest(generation)
    if manifest == nil then return false, manifestReason end

    local presentationCleared = ClearPresentation(generation, manifest)
    local itemsCleared = RemoveCaseItems(manifest)
    if DarkPassengerSceneDirector ~= nil and
       DarkPassengerSceneDirector.materializedGenerations ~= nil then
        DarkPassengerSceneDirector.materializedGenerations[generation] = nil
    end
    if not presentationCleared or not itemsCleared then
        Log(
            "cleanup deferred generation=" .. tostring(generation) ..
            " presentation=" .. tostring(presentationCleared) ..
            " items=" .. tostring(itemsCleared)
        )
        return false, "cleanup_deferred"
    end
    if not PersistClearedGeneration(generation) then
        return false, "persistence_failed"
    end
    Log(
        "cleared generation=" .. tostring(generation) ..
        " reason=" .. tostring(reason or "unspecified")
    )
    return true, "cleared"
end

local function ScheduleActivation(generation, serial, attempt)
    if Script == nil or Script.SetTimerForFunction == nil then
        return false, "timer_unavailable"
    end
    local ok = pcall(function()
        Script.SetTimerForFunction(
            DarkPassengerCaseLifecycle.ACTIVATION_DELAY_MS,
            "DarkPassengerCaseLifecycle.ActivatePreparedGeneration",
            {
                generation = generation,
                serial = serial,
                attempt = attempt or 1,
            }
        )
    end)
    return ok, ok and "scheduled" or "schedule_failed"
end

function DarkPassengerCaseLifecycle.BeginRestoreCycle(reason)
    DarkPassengerCaseLifecycle.timerSerial =
        DarkPassengerCaseLifecycle.timerSerial + 1
    DarkPassengerCaseLifecycle.preparedGeneration = 0
    DarkPassengerCaseLifecycle.preparedRevision = 0
    DarkPassengerCaseLifecycle.activatedGeneration = 0
    DarkPassengerCaseLifecycle.activatedRevision = 0
    local appliedGeneration, appliedRevision = ReadAppliedRevision()
    Log(
        "restore cycle reason=" .. tostring(reason or "unspecified") ..
        " serial=" .. tostring(DarkPassengerCaseLifecycle.timerSerial) ..
        " applied=" .. tostring(appliedGeneration) ..
        "/" .. tostring(appliedRevision) ..
        " currentRevision=" .. tostring(CurrentRevision())
    )
    return true
end

function DarkPassengerCaseLifecycle.PrepareCaseGeneration(generation)
    generation = tonumber(generation)
    if generation == nil or generation <= 0 then
        return false, "invalid_generation"
    end
    local revision = CurrentRevision()
    if DarkPassengerCaseLifecycle.activatedGeneration == generation and
       DarkPassengerCaseLifecycle.activatedRevision == revision then
        return true, "already_activated"
    end
    if DarkPassengerCaseLifecycle.preparedGeneration == generation and
       DarkPassengerCaseLifecycle.preparedRevision == revision then
        local scheduled, reason = ScheduleActivation(generation, DarkPassengerCaseLifecycle.timerSerial, 1)
        return scheduled, scheduled and "already_prepared" or reason
    end
    local manifest, manifestReason =
        DarkPassengerCaseLifecycle.ResolveManifest(generation)
    if manifest == nil then return false, manifestReason end
    local selected = DarkPassengerCaseContent.GetSelected(generation)
    local activationBuffGuid =
        selected ~= nil and selected.variant ~= nil and
        selected.variant.case_activation_buff_guid or nil
    if not ClearPresentation(generation, manifest, activationBuffGuid) then
        return false, "presentation_cleanup_deferred"
    end
    DarkPassengerCaseLifecycle.preparedGeneration = generation
    DarkPassengerCaseLifecycle.preparedRevision = revision
    DarkPassengerCaseLifecycle.timerSerial =
        DarkPassengerCaseLifecycle.timerSerial + 1
    local scheduled, reason = ScheduleActivation(
        generation,
        DarkPassengerCaseLifecycle.timerSerial,
        1
    )
    if not scheduled then
        DarkPassengerCaseLifecycle.preparedGeneration = 0
        DarkPassengerCaseLifecycle.preparedRevision = 0
    end
    Log(
        "prepared generation=" .. tostring(generation) ..
        " scheduled=" .. tostring(scheduled)
    )
    return scheduled, reason
end

function DarkPassengerCaseLifecycle.ActivatePreparedGeneration(payload)
    local generation = tonumber(
        type(payload) == "table" and payload.generation or payload
    )
    local serial = tonumber(type(payload) == "table" and payload.serial) or 0
    local attempt = tonumber(type(payload) == "table" and payload.attempt) or 1
    local revision = tonumber(
        type(payload) == "table" and payload.revision
    ) or DarkPassengerCaseLifecycle.preparedRevision
    if generation == nil or
       generation ~= DarkPassengerCaseLifecycle.preparedGeneration or
       serial ~= DarkPassengerCaseLifecycle.timerSerial or
       revision ~= DarkPassengerCaseLifecycle.preparedRevision or
       revision ~= CurrentRevision() then
        return false
    end
    local investigation =
        DarkPassengerInvestigation ~= nil and
        DarkPassengerInvestigation.GetState ~= nil and
        DarkPassengerInvestigation.GetState() or nil
    if investigation == nil or investigation.active ~= true or
       tonumber(investigation.generation) ~= generation then
        return false
    end
    local plan, reason = nil, "planner_unavailable"
    if DarkPassengerLeadPlanner ~= nil and
       DarkPassengerLeadPlanner.Apply ~= nil then
        plan, reason = DarkPassengerLeadPlanner.Apply(generation)
    end
    if plan == nil then
        if attempt < DarkPassengerCaseLifecycle.MAX_ACTIVATION_ATTEMPTS then
            ScheduleActivation(generation, serial, attempt + 1)
        end
        Log(
            "activation deferred generation=" .. tostring(generation) ..
            " attempt=" .. tostring(attempt) ..
            " reason=" .. tostring(reason)
        )
        return false
    end
    DarkPassengerCaseLifecycle.activatedGeneration = generation
    DarkPassengerCaseLifecycle.activatedRevision = revision
    DarkPassengerCaseLifecycle.preparedGeneration = 0
    DarkPassengerCaseLifecycle.preparedRevision = 0
    if not PersistAppliedRevision(generation, revision) then
        Log(
            "applied revision persistence failed generation=" ..
            tostring(generation) .. " revision=" .. tostring(revision)
        )
    end
    Log(
        "activated generation=" .. tostring(generation) ..
        " attempt=" .. tostring(attempt)
    )
    return true
end

function DarkPassengerCaseLifecycle.Reconcile(investigationState)
    local state = investigationState
    if state == nil and DarkPassengerInvestigation ~= nil and
       DarkPassengerInvestigation.GetState ~= nil then
        state = DarkPassengerInvestigation.GetState()
    end
    if state == nil or state.active ~= true then return false end
    return DarkPassengerCaseLifecycle.PrepareCaseGeneration(
        state.generation
    )
end

function DarkPassengerCaseLifecycle.Status()
    local appliedGeneration, appliedRevision = ReadAppliedRevision()
    Log(
        "status clearedGeneration=" .. tostring(ReadClearedGeneration()) ..
        " preparedGeneration=" ..
            tostring(DarkPassengerCaseLifecycle.preparedGeneration) ..
        " activatedGeneration=" ..
            tostring(DarkPassengerCaseLifecycle.activatedGeneration) ..
        " revision=" .. tostring(CurrentRevision()) ..
        " applied=" .. tostring(appliedGeneration) ..
            "/" .. tostring(appliedRevision)
    )
end

function DarkPassengerCaseLifecycle.RunSelfTest()
    local manifest = {
        schema_version = 1,
        signal_buff_guids = {},
        items = {
            { item_guid = "case", retention = "case" },
            { item_guid = "trophy", retention = "permanent" },
        },
    }
    local removable = 0
    for _, item in ipairs(manifest.items) do
        local retention = item.retention
        if retention == "case" then removable = removable + 1 end
    end
    local passed = ValidateManifest(manifest) and removable == 1 and
        not ValidateManifest({ schema_version = 99, items = {},
            signal_buff_guids = {} })
    Log("selftest=" .. tostring(passed))
    return passed
end

pcall(function()
    if System ~= nil and System.AddCCommand ~= nil then
        System.AddCCommand(
            "dp_case_lifecycle_status",
            "DarkPassengerCaseLifecycle.Status()",
            "Dark Passenger: print generated case lifecycle state"
        )
        System.AddCCommand(
            "dp_case_lifecycle_selftest",
            "DarkPassengerCaseLifecycle.RunSelfTest()",
            "Dark Passenger: run generated case lifecycle self-test"
        )
    end
end)

Log("module loaded")
