DarkPassengerBurial = DarkPassengerBurial or {}

DarkPassengerBurial.SHOVEL_GUID =
    "85409fc6-36ff-4de7-b337-e2889e435f1b"
DarkPassengerBurial.TOTAL_TIME_SECONDS = 7
DarkPassengerBurial.WORLD_TIME_SECONDS = 3600
DarkPassengerBurial.EXHAUST_COST = 10
DarkPassengerBurial.HUNGER_COST = 5
DarkPassengerBurial.AUDIO_TRIGGER = "special_skiptime_digging"
DarkPassengerBurial.SAVE_LOCK = "DarkPassengerBurial"
DarkPassengerBurial.STEP_INTERVAL_MS = 10
DarkPassengerBurial.FADE_OUT_MS = 1000
DarkPassengerBurial.FAILSAFE_MS = 10000

DarkPassengerBurial.DIGGABLE_SURFACES = {
    mat_soil = true,
    mat_mud = true,
    mat_grass = true,
    mat_grassdry = true,
    mat_forest = true,
    mat_gravel = true,
    mat_road = true,
    mat_field = true,
    mat_grass_tall = true,
}

DarkPassengerBurial.generation =
    tonumber(DarkPassengerBurial.generation) or 0
DarkPassengerBurial.active = DarkPassengerBurial.active or nil
DarkPassengerBurial._actionClassHooks =
    DarkPassengerBurial._actionClassHooks or {}

local function Log(message)
    if System ~= nil and System.LogAlways ~= nil then
        System.LogAlways(
            "[DarkPassenger][Burial] " .. tostring(message)
        )
    end
end

local function PlayerEntity()
    if g_localActor ~= nil then return g_localActor end
    if player ~= nil then return player end
    if System ~= nil and System.GetEntityByName ~= nil then
        return System.GetEntityByName("dude")
    end
    return nil
end

local function IsDeadHuman(corpse)
    if corpse == nil or corpse.id == nil then return false end
    if corpse.human == nil or corpse.actor == nil or
       corpse.actor.IsDead == nil then
        return false
    end

    local ok, dead = pcall(function()
        return corpse.actor:IsDead()
    end)
    return ok and dead == true
end

local function ReadSoulState(actor, stateName)
    if actor == nil or actor.soul == nil or
       actor.soul.GetState == nil then
        return nil
    end
    local ok, value = pcall(function()
        return actor.soul:GetState(stateName)
    end)
    if not ok then return nil end
    return tonumber(value)
end

local function WriteSoulState(actor, stateName, value)
    if actor == nil or actor.soul == nil or
       actor.soul.SetState == nil then
        return false
    end
    local ok = pcall(function()
        actor.soul:SetState(stateName, value)
    end)
    return ok
end

local function HasShovel(actor)
    if actor == nil or actor.inventory == nil or
       actor.inventory.GetCountOfClass == nil then
        return false
    end
    local ok, count = pcall(function()
        return actor.inventory:GetCountOfClass(
            DarkPassengerBurial.SHOVEL_GUID
        )
    end)
    return ok and (tonumber(count) or 0) > 0
end

local function StopDiggingAudio(actor)
    if actor == nil or actor.StopAudioTrigger == nil or
       actor.GetDefaultAuxAudioProxyID == nil or
       AudioUtils == nil or AudioUtils.LookupTriggerID == nil then
        return false
    end
    local ok = pcall(function()
        actor:StopAudioTrigger(
            AudioUtils.LookupTriggerID(
                DarkPassengerBurial.AUDIO_TRIGGER
            ),
            actor:GetDefaultAuxAudioProxyID()
        )
    end)
    return ok
end

local function RemoveSaveLock()
    if Game == nil or Game.RemoveSaveLock == nil then return false end
    local ok = pcall(function()
        Game.RemoveSaveLock(DarkPassengerBurial.SAVE_LOCK)
    end)
    return ok
end

local function RestorePresentation()
    if UIAction == nil then return end
    pcall(function()
        UIAction.CallFunction("SkipTime", 1, "RemoveDialog")
    end)
    pcall(function()
        UIAction.HideElement("SkipTime", 1)
    end)
    pcall(function()
        UIAction.HideElement("Overlay", 1)
    end)
    pcall(function()
        UIAction.ShowElement("hud", 0)
    end)
end

function DarkPassengerBurial.HasQuestItem(corpse)
    if DarkPassengerQuestItemCatalog == nil then
        return nil, "quest_catalog_unavailable"
    end
    if corpse == nil or corpse.inventory == nil or
       corpse.inventory.GetInventoryTable == nil or
       ItemManager == nil or ItemManager.GetItem == nil then
        return nil, "quest_item_metadata_unavailable"
    end

    local okInventory, inventoryOrError = pcall(function()
        return corpse.inventory:GetInventoryTable()
    end)
    if not okInventory or type(inventoryOrError) ~= "table" then
        return nil, "quest_item_metadata_unavailable"
    end

    for _, itemWuid in pairs(inventoryOrError) do
        local okItem, itemOrError = pcall(function()
            return ItemManager.GetItem(itemWuid)
        end)
        if not okItem or type(itemOrError) ~= "table" or
           itemOrError.class == nil then
            return nil, "quest_item_metadata_unavailable"
        end

        local classId = string.lower(tostring(itemOrError.class))
        if DarkPassengerQuestItemCatalog[classId] == true then
            return true, classId
        end
    end

    return false, nil
end

function DarkPassengerBurial.IsDiggableGround(corpse)
    if corpse == nil or corpse.GetWorldPos == nil or
       Physics == nil or Physics.RayWorldIntersection == nil or
       System == nil or System.GetSurfaceTypeNameById == nil then
        return false, nil
    end

    local okPosition, positionOrError = pcall(function()
        return corpse:GetWorldPos()
    end)
    if not okPosition or positionOrError == nil then
        return false, nil
    end

    local actor = PlayerEntity()
    local rayStart = {
        x = positionOrError.x,
        y = positionOrError.y,
        z = positionOrError.z + 1,
    }
    local rayDirection = { x = 0, y = 0, z = -4 }
    local hits = {}
    local okRay, hitCountOrError = pcall(function()
        return Physics.RayWorldIntersection(
            rayStart,
            rayDirection,
            10,
            ent_all,
            corpse.id,
            actor ~= nil and actor.id or nil,
            hits
        )
    end)
    if not okRay or (tonumber(hitCountOrError) or 0) < 1 or
       hits[1] == nil or hits[1].surface == nil then
        return false, nil
    end

    if hits[1].normal ~= nil and
       tonumber(hits[1].normal.z) ~= nil and
       tonumber(hits[1].normal.z) < 0.45 then
        return false, nil
    end

    local okSurface, surfaceNameOrError = pcall(function()
        return System.GetSurfaceTypeNameById(hits[1].surface)
    end)
    if not okSurface or surfaceNameOrError == nil then
        return false, nil
    end

    local surfaceName = string.lower(tostring(surfaceNameOrError))
    return DarkPassengerBurial.DIGGABLE_SURFACES[surfaceName] == true,
        surfaceName
end

function DarkPassengerBurial.CanBury(corpse, user)
    if not IsDeadHuman(corpse) then
        return false, "@dp_burial_bad_ground"
    end
    if DarkPassengerBurial.active ~= nil then
        return false, "@dp_burial_busy"
    end

    local actor = user or PlayerEntity()
    if not HasShovel(actor) then
        return false, "@dp_burial_no_shovel"
    end

    local hasQuestItem = DarkPassengerBurial.HasQuestItem(corpse)
    if hasQuestItem == nil or hasQuestItem == true then
        return false, "@dp_burial_quest_item"
    end

    local diggable = DarkPassengerBurial.IsDiggableGround(corpse)
    if not diggable then
        return false, "@dp_burial_bad_ground"
    end

    return true, ""
end

function DarkPassengerBurial.AddBuryAction(
    corpse,
    user,
    firstFast,
    output
)
    if type(output) ~= "table" or not IsDeadHuman(corpse) then
        return false
    end

    local enabled, reason =
        DarkPassengerBurial.CanBury(corpse, user)
    return AddInteractorAction(
        output,
        firstFast,
        Action()
            :hint("@dp_burial_action")
            :action("butcher")
            :hintType(AHT_HOLD)
            :uiOrder(3)
            :func(DarkPassengerBurial.OnBuryBody)
            :interaction(inr_loot)
            :enabled(enabled)
            :reason(reason)
    )
end

local actionClassNames = { "NPC", "NPC_Female", "NPC_NAI" }

local function RestoreLegacyBasicActionHook()
    local hook = DarkPassengerBurial._getActionsHook
    if type(hook) ~= "table" or
       type(hook.wrapper) ~= "function" or
       type(hook.original) ~= "function" or
       BasicAIActions == nil or
       BasicAIActions.GetActions ~= hook.wrapper then
        return false
    end

    BasicAIActions.GetActions = hook.original
    DarkPassengerBurial._getActionsHook = nil
    Log("legacy BasicAIActions hook removed")
    return true
end

local function InstallClassActionHook(className, classTable)
    if type(classTable) ~= "table" or
       type(classTable.GetActions) ~= "function" then
        return false
    end

    local hooks = DarkPassengerBurial._actionClassHooks
    local hook = hooks[className]
    if type(hook) ~= "table" then
        hook = {}
        hooks[className] = hook
    end

    if hook.wrapper ~= nil and
       classTable.GetActions == hook.wrapper then
        return true
    end

    hook.original = classTable.GetActions
    local wrapper = function(self, user, firstFast)
        local output = hook.original(self, user, firstFast)
        if type(output) ~= "table" then output = {} end
        DarkPassengerBurial.AddBuryAction(self, user, firstFast, output)
        return output
    end
    hook.wrapper = wrapper
    classTable.GetActions = wrapper
    Log(className .. ".GetActions hook installed")
    return true
end

function DarkPassengerBurial.InstallActionHook()
    RestoreLegacyBasicActionHook()

    local installed = 0
    for _, className in ipairs(actionClassNames) do
        local classTable = _G ~= nil and _G[className] or nil
        if InstallClassActionHook(className, classTable) then
            installed = installed + 1
        else
            Log(className .. ".GetActions hook unavailable")
        end
    end

    return installed > 0
end

local function BeginPresentation(corpse, actor)
    local exhaust = ReadSoulState(actor, "exhaust")
    local hunger = ReadSoulState(actor, "hunger")
    local health = ReadSoulState(actor, "health")
    if exhaust == nil or hunger == nil or health == nil then
        Log("burial blocked: player stats unavailable")
        return false
    end
    if Calendar == nil or Calendar.GetWorldTime == nil or
       Calendar.SetWorldTime == nil or UIAction == nil or
       Game == nil or Game.AddSaveLock == nil or
       Script == nil or Script.SetTimerForFunction == nil or
       System == nil or System.GetCurrAsyncTime == nil then
        Log("burial blocked: SkipTime runtime unavailable")
        return false
    end

    DarkPassengerBurial.generation =
        DarkPassengerBurial.generation + 1
    local generation = DarkPassengerBurial.generation
    local startWorldTime = Calendar.GetWorldTime()
    DarkPassengerBurial.active = {
        generation = generation,
        corpseId = corpse.id,
        actorId = actor.id,
        started = false,
        closing = false,
        startWorldTime = startWorldTime,
        startClockHour = (startWorldTime / 3600) % 24,
        startHealth = health,
        startExhaust = exhaust,
        startHunger = hunger,
        targetHealth = health,
        targetExhaust = math.max(
            0,
            exhaust - DarkPassengerBurial.EXHAUST_COST
        ),
        targetHunger = math.max(
            0,
            hunger - DarkPassengerBurial.HUNGER_COST
        ),
    }

    local timerOk = pcall(function()
        Script.SetTimerForFunction(
            DarkPassengerBurial.FAILSAFE_MS,
            "DarkPassengerBurial.OnFailsafe",
            { generation = generation }
        )
    end)
    if not timerOk then
        DarkPassengerBurial.active = nil
        Log("burial blocked: failsafe timer unavailable")
        return false
    end

    Calendar.SetWorldTime(
        startWorldTime + DarkPassengerBurial.WORLD_TIME_SECONDS
    )
    local stepOk, stepError = pcall(function()
        DarkPassengerBurial.OnSkipTimeStep({
            generation = generation,
        })
    end)
    if not stepOk then
        Log("SkipTime start failed error=" .. tostring(stepError))
    end
    return stepOk
end

function DarkPassengerBurial.OnBuryBody(corpse, user, slotId)
    local allowed, reason =
        DarkPassengerBurial.CanBury(corpse, user)
    if not allowed then
        Log("burial rejected reason=" .. tostring(reason))
        return false
    end

    local actor = user or PlayerEntity()
    Log(
        "burial started corpse=" .. tostring(corpse.id) ..
        " slot=" .. tostring(slotId)
    )
    return BeginPresentation(corpse, actor)
end

local function RemoveActiveCorpse(active)
    if active == nil then return false end
    if active.corpseRemoved == true then return true end

    local corpseId = active.corpseId
    local corpse = nil
    if System ~= nil and System.GetEntity ~= nil then
        corpse = System.GetEntity(corpseId)
    end

    active.corpseRemovalAttempted = true
    if IsDeadHuman(corpse) and System.RemoveEntity ~= nil then
        active.corpseRemoved = pcall(function()
            System.RemoveEntity(corpse.id)
        end)
    else
        active.corpseRemoved = false
    end

    if active.corpseRemoved == true and
       active.burialRecorded ~= true and
       DarkPassengerAftermath ~= nil and
       DarkPassengerAftermath.RecordBurial ~= nil then
        DarkPassengerAftermath.RecordBurial(corpseId)
        active.burialRecorded = true
    end

    return active.corpseRemoved == true
end

function DarkPassengerBurial.OnSkipTimeStep(userData, timerId)
    local active = DarkPassengerBurial.active
    local requestedGeneration =
        userData ~= nil and tonumber(userData.generation) or nil
    if active == nil or
       requestedGeneration ~= active.generation or
       active.closing == true then
        return false
    end

    local actor = PlayerEntity()
    if actor == nil then
        DarkPassengerBurial.OnFailsafe(userData, timerId)
        return false
    end

    if not active.started then
        active.started = true
        active.startRealTime = System.GetCurrAsyncTime()

        UIAction.HideElement("hud", 0)
        UIAction.ShowElement("Overlay", 1)
        UIAction.CallFunction(
            "Overlay",
            1,
            "AddOverlay",
            5,
            0,
            true
        )
        UIAction.CallFunction("Overlay", 1, "SetAlpha", 5, 255)
        UIAction.ShowElement("SkipTime", 1)
        UIAction.CallFunction(
            "SkipTime",
            1,
            "AddDialog",
            7,
            "@dp_burial_skiptime"
        )
        Game.AddSaveLock(
            DarkPassengerBurial.SAVE_LOCK,
            "@ui_cant_save_minigame"
        )
        if AudioUtils ~= nil and
           AudioUtils.PlayAudioTrigger ~= nil then
            AudioUtils.PlayAudioTrigger(
                actor,
                DarkPassengerBurial.AUDIO_TRIGGER
            )
        end
    end

    local elapsed =
        System.GetCurrAsyncTime() - active.startRealTime
    local progress =
        elapsed / DarkPassengerBurial.TOTAL_TIME_SECONDS
    if progress > 1 then progress = 1 end
    if progress < 0 then progress = 0 end

    local health = active.startHealth +
        (active.targetHealth - active.startHealth) * progress
    local exhaust = active.startExhaust +
        (active.targetExhaust - active.startExhaust) * progress
    local hunger = active.startHunger +
        (active.targetHunger - active.startHunger) * progress
    local elapsedHours = progress

    UIAction.CallFunction(
        "SkipTime",
        1,
        "SetStats",
        health,
        exhaust,
        hunger
    )
    UIAction.CallFunction(
        "SkipTime",
        1,
        "SetInterval",
        1 - elapsedHours
    )
    UIAction.CallFunction(
        "SkipTime",
        1,
        "SetTime",
        active.startClockHour + elapsedHours
    )

    if progress < 1 then
        Script.SetTimerForFunction(
            DarkPassengerBurial.STEP_INTERVAL_MS,
            "DarkPassengerBurial.OnSkipTimeStep",
            { generation = active.generation }
        )
        return true
    end

    active.completed = true
    active.closing = true
    WriteSoulState(actor, "health", active.targetHealth)
    WriteSoulState(actor, "exhaust", active.targetExhaust)
    WriteSoulState(actor, "hunger", active.targetHunger)
    RemoveSaveLock()
    RemoveActiveCorpse(active)
    UIAction.CallFunction("SkipTime", 1, "FadeOutDialog")
    UIAction.CallFunction("Overlay", 1, "RemoveOverlay", 5)
    StopDiggingAudio(actor)
    Script.SetTimerForFunction(
        DarkPassengerBurial.FADE_OUT_MS,
        "DarkPassengerBurial.Finish",
        { generation = active.generation }
    )
    return true
end

function DarkPassengerBurial.Finish(userData, timerId)
    local active = DarkPassengerBurial.active
    local requestedGeneration =
        userData ~= nil and tonumber(userData.generation) or nil
    if active == nil or requestedGeneration ~= active.generation or
       active.completed ~= true then
        return false
    end

    RemoveSaveLock()
    StopDiggingAudio(PlayerEntity())
    RemoveActiveCorpse(active)
    RestorePresentation()

    Log(
        "burial finished corpse=" .. tostring(active.corpseId) ..
        " removed=" .. tostring(active.corpseRemoved)
    )
    local removed = active.corpseRemoved == true
    DarkPassengerBurial.active = nil
    return removed
end

function DarkPassengerBurial.OnFailsafe(userData, timerId)
    local active = DarkPassengerBurial.active
    local requestedGeneration =
        userData ~= nil and tonumber(userData.generation) or nil
    if active == nil or requestedGeneration ~= active.generation then
        return false
    end

    Log("failsafe cleanup generation=" .. tostring(active.generation))
    if active.completed == true then
        return DarkPassengerBurial.Finish(userData, timerId)
    end

    RemoveSaveLock()
    StopDiggingAudio(PlayerEntity())
    RestorePresentation()
    DarkPassengerBurial.active = nil
    return true
end

DarkPassengerBurial.InstallActionHook()
Log("module loaded")
