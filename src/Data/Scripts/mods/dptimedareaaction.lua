DarkPassengerTimedAreaAction = DarkPassengerTimedAreaAction or {}

DarkPassengerTimedAreaAction.TOTAL_TIME_SECONDS = 3
DarkPassengerTimedAreaAction.STEP_INTERVAL_MS = 10
DarkPassengerTimedAreaAction.FADE_OUT_MS = 1000
DarkPassengerTimedAreaAction.FAILSAFE_MS = 15000
DarkPassengerTimedAreaAction.SAVE_LOCK = "DarkPassengerTimedAreaAction"
DarkPassengerTimedAreaAction.active = nil
DarkPassengerTimedAreaAction._nativeActionPublished = false
DarkPassengerTimedAreaAction._nativeActionSignature = nil
DarkPassengerTimedAreaAction._lastInputAt = 0
DarkPassengerTimedAreaAction._currentUsableEntityId = nil
DarkPassengerTimedAreaAction._vanillaFActionVisible = false
DarkPassengerTimedAreaAction._hookOwner =
    DarkPassengerTimedAreaAction._hookOwner or {
        rawActionOriginal = nil,
        rawActionWrapper = nil,
        hudActionPlayer = nil,
        hudActionOriginal = nil,
        hudActionWrapper = nil,
        usableRules = nil,
        usableOriginal = nil,
        usableWrapper = nil,
    }

local function Log(message)
    System.LogAlways("[TimedAreaAction] " .. tostring(message))
end

local function PlayerEntity()
    return g_localActor
end

local function IsTruthy(value)
    return value == true or (tonumber(value) or 0) == 1
end

local function HasScriptContext(actor, context)
    if actor == nil or actor.soul == nil or
       actor.soul.HasScriptContext == nil or
       context == nil or context == "" then
        return false
    end
    local ok, active = pcall(function()
        return actor.soul:HasScriptContext(context)
    end)
    return ok and IsTruthy(active)
end

local function IsInCombatDanger(actor)
    if actor == nil or actor.soul == nil or
       actor.soul.IsInCombatDanger == nil then
        return false
    end
    local ok, danger = pcall(function()
        return actor.soul:IsInCombatDanger()
    end)
    return ok and IsTruthy(danger)
end

local function IsInDialogue(actor)
    if actor == nil or actor.human == nil or
       actor.human.IsInDialog == nil then
        return false
    end
    local ok, active = pcall(function()
        return actor.human:IsInDialog()
    end)
    return ok and IsTruthy(active)
end

local function Notify(key)
    if key == nil or key == "" or Game == nil or
       Game.ShowNotification == nil then
        return false
    end
    return pcall(function() Game.ShowNotification("@" .. key) end)
end

local function IsNullEntityId(entityId)
    if entityId == nil then return true end
    if NULL_ENTITY ~= nil and entityId == NULL_ENTITY then return true end
    return tonumber(entityId) == 0
end

function DarkPassengerTimedAreaAction.InstallRawActionHook()
    if Player == nil or type(Player.OnAction) ~= "function" then
        return false
    end
    local owner = DarkPassengerTimedAreaAction._hookOwner
    if Player.OnAction == owner.rawActionWrapper then
        return true
    end
    if owner.rawActionWrapper ~= nil and
       owner.rawActionOriginal ~= nil and
       Player.OnAction ~= owner.rawActionWrapper then
        owner.rawActionWrapper = nil
        owner.rawActionOriginal = nil
    end
    local original = Player.OnAction
    local wrapper = function(self, actionName, activation, value)
        if DarkPassengerTimedAreaAction ~= nil and
           DarkPassengerTimedAreaAction.OnRawActionEvent ~= nil then
            local ok, err = pcall(
                DarkPassengerTimedAreaAction.OnRawActionEvent,
                actionName,
                activation,
                value
            )
            if not ok then
                Log("raw action failed: " .. tostring(err))
            end
        end
        return original(self, actionName, activation, value)
    end
    owner.rawActionOriginal = original
    owner.rawActionWrapper = wrapper
    Player.OnAction = wrapper
    return true
end

function DarkPassengerTimedAreaAction.HandleNewUsable(
    original,
    self,
    srcId,
    objId,
    usableId
)
    local isLocalActor = srcId == g_localActorId
    if isLocalActor then
        DarkPassengerTimedAreaAction._currentUsableEntityId =
            IsNullEntityId(objId) and nil or objId
        if DarkPassengerTimedAreaAction._currentUsableEntityId == nil then
            DarkPassengerTimedAreaAction._vanillaFActionVisible = false
        end
    end
    local result = original(self, srcId, objId, usableId)
    if isLocalActor and
       DarkPassengerTimedAreaAction.RefreshPrompt ~= nil then
        DarkPassengerTimedAreaAction.RefreshPrompt()
    end
    return result
end

function DarkPassengerTimedAreaAction.InstallUsableTracker()
    if g_gameRules == nil or
       type(g_gameRules.OnNewUsable) ~= "function" then
        return false
    end
    local owner = DarkPassengerTimedAreaAction._hookOwner
    if owner.usableRules == g_gameRules and
       g_gameRules.OnNewUsable == owner.usableWrapper then
        return true
    end
    local original = g_gameRules.OnNewUsable
    local wrapper = function(self, srcId, objId, usableId)
        if DarkPassengerTimedAreaAction ~= nil and
           DarkPassengerTimedAreaAction.HandleNewUsable ~= nil then
            return DarkPassengerTimedAreaAction.HandleNewUsable(
                original,
                self,
                srcId,
                objId,
                usableId
            )
        end
        return original(self, srcId, objId, usableId)
    end
    owner.usableRules = g_gameRules
    owner.usableOriginal = original
    owner.usableWrapper = wrapper
    g_gameRules.OnNewUsable = wrapper
    return true
end

function DarkPassengerTimedAreaAction.RebuildCurrentVanillaActions()
    local entityId = DarkPassengerTimedAreaAction._currentUsableEntityId
    if entityId == nil or System == nil or System.GetEntity == nil or
       g_gameRules == nil or
       type(g_gameRules.OnUsableMessage) ~= "function" then
        return false
    end
    local entity = System.GetEntity(entityId)
    if entity == nil then return false end
    local ok, err = pcall(function()
        g_gameRules:OnUsableMessage(entity)
    end)
    if not ok then
        Log("vanilla HUD rebuild failed: " .. tostring(err))
    end
    return ok
end

function DarkPassengerTimedAreaAction.AugmentNativeActions(actions)
    actions = type(actions) == "table" and actions or {}
    local action = DarkPassengerTimedAreaAction.GetActiveAction()
    if action == nil or action.prompt_key == nil or
       action.prompt_key == "" then
        DarkPassengerTimedAreaAction._vanillaFActionVisible = false
        DarkPassengerTimedAreaAction._nativeActionPublished = false
        return actions
    end

    local prompt = "@" .. action.prompt_key
    local alreadyPresent = false
    local hasConflict = false
    for _, entry in ipairs(actions) do
        if entry.action == "grab_body" or entry.action == "butcher" then
            if entry.action == "grab_body" and entry.hint == prompt then
                alreadyPresent = true
            else
                hasConflict = true
            end
        end
    end
    DarkPassengerTimedAreaAction._vanillaFActionVisible = hasConflict
    if hasConflict then
        DarkPassengerTimedAreaAction._nativeActionPublished = false
        return actions
    end
    if alreadyPresent then
        DarkPassengerTimedAreaAction._nativeActionPublished = true
        return actions
    end

    local allowed = DarkPassengerTimedAreaAction.CanActivate(action)
    if not allowed or Action == nil or AddInteractorAction == nil then
        DarkPassengerTimedAreaAction._nativeActionPublished = false
        return actions
    end
    AddInteractorAction(
        actions,
        false,
        Action():hint(prompt)
            :action("grab_body")
            :hintType(AHT_RELEASE)
            :uiOrder(0)
            :enabled(true)
    )
    DarkPassengerTimedAreaAction._nativeActionPublished = true
    return actions
end

function DarkPassengerTimedAreaAction.InstallHudActionHook()
    local actor = PlayerEntity()
    if actor == nil or actor.player == nil or
       type(actor.player.AddLuaActions) ~= "function" then
        return false
    end
    local player = actor.player
    local owner = DarkPassengerTimedAreaAction._hookOwner
    if owner.hudActionPlayer == player and
       player.AddLuaActions == owner.hudActionWrapper then
        return true
    end

    local original = player.AddLuaActions
    local wrapper = function(self, actions)
        local resolved = actions
        if DarkPassengerTimedAreaAction ~= nil and
           DarkPassengerTimedAreaAction.AugmentNativeActions ~= nil then
            local ok, value = pcall(
                DarkPassengerTimedAreaAction.AugmentNativeActions,
                actions
            )
            if ok then
                resolved = value
            else
                Log("HUD action merge failed: " .. tostring(value))
            end
        end
        return original(self, resolved)
    end
    owner.hudActionPlayer = player
    owner.hudActionOriginal = original
    owner.hudActionWrapper = wrapper
    player.AddLuaActions = wrapper
    return true
end

local function RestorePresentation()
    if UIAction ~= nil then
        pcall(function()
            UIAction.CallFunction("SkipTime", 1, "RemoveDialog")
        end)
        pcall(function() UIAction.HideElement("SkipTime", 1) end)
        pcall(function() UIAction.HideElement("Overlay", 1) end)
        pcall(function() UIAction.ShowElement("hud", 0) end)
    end
    if Game ~= nil and Game.RemoveSaveLock ~= nil then
        pcall(function()
            Game.RemoveSaveLock(DarkPassengerTimedAreaAction.SAVE_LOCK)
        end)
    end
end

local function EvidenceDiscovered(generation, evidenceCode)
    if DarkPassengerEvidenceRegistry == nil or
       DarkPassengerEvidenceRegistry.GetCaseState == nil then
        return false
    end
    local state = DarkPassengerEvidenceRegistry.GetCaseState(generation)
    for _, evidence in ipairs(state ~= nil and state.evidence or {}) do
        if tonumber(evidence.code) == tonumber(evidenceCode) then
            return evidence.status == "discovered"
        end
    end
    return false
end

function DarkPassengerTimedAreaAction.IsWithinWorkingHours(
    hour,
    availableFromHour,
    availableUntilHour
)
    hour = tonumber(hour)
    availableFromHour = tonumber(availableFromHour)
    availableUntilHour = tonumber(availableUntilHour)
    if hour == nil or availableFromHour == nil or
       availableUntilHour == nil then
        return false
    end
    return hour >= availableFromHour and hour < availableUntilHour
end

function DarkPassengerTimedAreaAction.GetActiveAction()
    if DarkPassengerInvestigation == nil or
       DarkPassengerInvestigation.GetState == nil or
       DarkPassengerCaseContent == nil or
       DarkPassengerCaseContent.GetSelected == nil then
        return nil, "case_unavailable"
    end
    local investigation = DarkPassengerInvestigation.GetState()
    if investigation == nil or investigation.active ~= true then
        return nil, "case_inactive"
    end
    local generation = tonumber(investigation.generation)
    local selected = DarkPassengerCaseContent.GetSelected(generation)
    if selected == nil or selected.caseTemplate == nil then
        return nil, "case_unavailable"
    end
    local actions = selected.caseTemplate.timed_area_actions
    if (type(actions) ~= "table" or #actions == 0) and
       selected.variant ~= nil then
        actions = selected.variant.timed_area_actions
    end
    for _, action in ipairs(actions or {}) do
        if not EvidenceDiscovered(generation, action.evidence_code) and
           HasScriptContext(PlayerEntity(), action.area_context) then
            local resolved = action
            resolved.generation = generation
            return resolved, "active"
        end
    end
    return nil, "outside_area"
end

function DarkPassengerTimedAreaAction.CanActivate(action)
    if action == nil then return false, "action_unavailable" end
    if DarkPassengerTimedAreaAction.active ~= nil then
        return false, "already_running"
    end
    local actor = PlayerEntity()
    if not HasScriptContext(actor, action.area_context) then
        return false, "outside_area"
    end
    if EvidenceDiscovered(action.generation, action.evidence_code) then
        return false, "already_discovered"
    end
    if IsInCombatDanger(actor) then return false, "player_in_combat" end
    if IsInDialogue(actor) then return false, "dialogue_active" end
    if DarkPassengerTimedAreaAction._vanillaFActionVisible == true then
        return false, "vanilla_f_action_available"
    end
    if Calendar == nil or Calendar.GetWorldTime == nil then
        return false, "calendar_unavailable"
    end
    local hour = (Calendar.GetWorldTime() / 3600) % 24
    if not DarkPassengerTimedAreaAction.IsWithinWorkingHours(
        hour,
        action.available_from_hour,
        action.available_until_hour
    ) then
        return false, "outside_working_hours"
    end
    return true, "ready"
end

function DarkPassengerTimedAreaAction.Start(action)
    local allowed, reason =
        DarkPassengerTimedAreaAction.CanActivate(action)
    if not allowed then
        if reason == "outside_working_hours" then
            Notify(action ~= nil and action.unavailable_key or nil)
        end
        return false, reason
    end
    if Calendar.SetWorldTime == nil or UIAction == nil or
       Script == nil or Script.SetTimerForFunction == nil or
       System == nil or System.GetCurrAsyncTime == nil then
        return false, "skip_time_unavailable"
    end
    local startWorldTime = Calendar.GetWorldTime()
    local durationHours = tonumber(action.duration_hours) or 2
    DarkPassengerTimedAreaAction.active = {
        generation = tonumber(action.generation),
        evidence_code = tonumber(action.evidence_code),
        progress_key = action.progress_key,
        duration_hours = durationHours,
        start_world_time = startWorldTime,
        start_clock_hour = (startWorldTime / 3600) % 24,
        started = false,
        completed = false,
        closing = false,
    }
    local advanced = pcall(function()
        Calendar.SetWorldTime(
            startWorldTime + durationHours * 60 * 60
        )
    end)
    if not advanced then
        DarkPassengerTimedAreaAction.active = nil
        return false, "skip_time_failed"
    end
    Script.SetTimerForFunction(
        DarkPassengerTimedAreaAction.FAILSAFE_MS,
        "DarkPassengerTimedAreaAction.OnFailsafe",
        { generation = action.generation }
    )
    local started, result = pcall(
        DarkPassengerTimedAreaAction.OnSkipTimeStep,
        {
            generation = action.generation,
        }
    )
    if not started then
        DarkPassengerTimedAreaAction.OnFailsafe({
            generation = action.generation,
        })
        return false, "skip_time_failed"
    end
    return result, "started"
end

function DarkPassengerTimedAreaAction.OnActionEvent(
    actionName,
    activation,
    value
)
    if actionName ~= "grab_body" and
       actionName ~= "butcher" then
        return false
    end
    if activation ~= "release" then
        return false
    end
    local now = System ~= nil and System.GetCurrAsyncTime ~= nil and
        System.GetCurrAsyncTime() or 0
    if now - DarkPassengerTimedAreaAction._lastInputAt < 0.25 then
        return false
    end
    DarkPassengerTimedAreaAction._lastInputAt = now
    local action = DarkPassengerTimedAreaAction.GetActiveAction()
    if action == nil then return false end
    if not HasScriptContext(PlayerEntity(), action.area_context) then
        return false
    end
    return DarkPassengerTimedAreaAction.Start(action)
end

function DarkPassengerTimedAreaAction.OnRawActionEvent(
    actionName,
    activation,
    value
)
    return DarkPassengerTimedAreaAction.OnActionEvent(
        actionName,
        activation,
        value
    )
end

function DarkPassengerTimedAreaAction.OnSkipTimeStep(userData, timerId)
    local active = DarkPassengerTimedAreaAction.active
    local generation = userData ~= nil and
        tonumber(userData.generation) or nil
    if active == nil or generation ~= active.generation or
       active.closing == true then
        return false
    end
    if not active.started then
        active.started = true
        active.start_real_time = System.GetCurrAsyncTime()
        UIAction.HideElement("hud", 0)
        UIAction.ShowElement("Overlay", 1)
        UIAction.CallFunction("Overlay", 1, "AddOverlay", 5, 0, true)
        UIAction.CallFunction("Overlay", 1, "SetAlpha", 5, 255)
        UIAction.ShowElement("SkipTime", 1)
        UIAction.CallFunction(
            "SkipTime", 1, "AddDialog", 7, "@" .. active.progress_key
        )
        if Game ~= nil and Game.AddSaveLock ~= nil then
            Game.AddSaveLock(
                DarkPassengerTimedAreaAction.SAVE_LOCK,
                "@ui_cant_save_minigame"
            )
        end
    end
    local elapsed = System.GetCurrAsyncTime() - active.start_real_time
    local progress = math.max(0, math.min(
        1,
        elapsed / DarkPassengerTimedAreaAction.TOTAL_TIME_SECONDS
    ))
    local elapsedHours = active.duration_hours * progress
    UIAction.CallFunction(
        "SkipTime", 1, "SetInterval",
        active.duration_hours - elapsedHours
    )
    UIAction.CallFunction(
        "SkipTime", 1, "SetTime",
        active.start_clock_hour + elapsedHours
    )
    if progress < 1 then
        Script.SetTimerForFunction(
            DarkPassengerTimedAreaAction.STEP_INTERVAL_MS,
            "DarkPassengerTimedAreaAction.OnSkipTimeStep",
            { generation = active.generation }
        )
        return true
    end
    active.completed = true
    active.closing = true
    UIAction.CallFunction("SkipTime", 1, "FadeOutDialog")
    UIAction.CallFunction("Overlay", 1, "RemoveOverlay", 5)
    Script.SetTimerForFunction(
        DarkPassengerTimedAreaAction.FADE_OUT_MS,
        "DarkPassengerTimedAreaAction.Finish",
        { generation = active.generation }
    )
    return true
end

function DarkPassengerTimedAreaAction.Finish(userData, timerId)
    local active = DarkPassengerTimedAreaAction.active
    local generation = userData ~= nil and
        tonumber(userData.generation) or nil
    if active == nil or generation ~= active.generation or
       active.completed ~= true then
        return false
    end
    RestorePresentation()
    local result = DarkPassengerEvidenceRegistry.Discover(
        active.generation,
        active.evidence_code,
        { source = "timed_area_action" }
    )
    DarkPassengerTimedAreaAction.active = nil
    Log(
        "finished generation=" .. tostring(generation) ..
        " evidence=" .. tostring(active.evidence_code) ..
        " accepted=" .. tostring(result ~= nil and result.accepted)
    )
    return result ~= nil and result.accepted == true
end

function DarkPassengerTimedAreaAction.OnFailsafe(userData, timerId)
    local active = DarkPassengerTimedAreaAction.active
    local generation = userData ~= nil and
        tonumber(userData.generation) or nil
    if active == nil or generation ~= active.generation then
        return false
    end
    Log("failsafe generation=" .. tostring(generation))
    active.completed = true
    active.closing = true
    return DarkPassengerTimedAreaAction.Finish(userData, timerId)
end

function DarkPassengerTimedAreaAction.ClearNativeAction()
    if DarkPassengerTimedAreaAction._nativeActionPublished ~= true then
        return false
    end
    local ok = false
    if DarkPassengerTimedAreaAction._currentUsableEntityId ~= nil then
        ok = DarkPassengerTimedAreaAction.RebuildCurrentVanillaActions()
    end
    DarkPassengerTimedAreaAction._nativeActionPublished = false
    DarkPassengerTimedAreaAction._nativeActionSignature = nil
    return ok
end

function DarkPassengerTimedAreaAction.PublishNativeAction(action)
    local actor = PlayerEntity()
    if action == nil or action.prompt_key == nil or
       action.prompt_key == "" or actor == nil or
       actor.player == nil or actor.player.AddLuaActions == nil or
       Action == nil or AddInteractorAction == nil then
        return false
    end
    if DarkPassengerTimedAreaAction._currentUsableEntityId ~= nil and
       DarkPassengerTimedAreaAction.RebuildCurrentVanillaActions() then
        return DarkPassengerTimedAreaAction._nativeActionPublished == true
    end
    local signature = tostring(action.generation) .. ":" ..
        tostring(action.evidence_code) .. ":" ..
        tostring(action.area_context)
    local actions = {}
    local nativeAction = Action():hint("@" .. action.prompt_key)
        :action("grab_body")
        :hintType(AHT_RELEASE)
        :uiOrder(0)
        :enabled(true)
    AddInteractorAction(actions, false, nativeAction)
    local ok = pcall(function()
        actor.player:AddLuaActions(actions)
    end)
    if ok then
        DarkPassengerTimedAreaAction._nativeActionPublished = true
        DarkPassengerTimedAreaAction._nativeActionSignature = signature
    end
    return ok
end

function DarkPassengerTimedAreaAction.RefreshPrompt()
    local action = DarkPassengerTimedAreaAction.GetActiveAction()
    local allowed = false
    if action ~= nil then
        allowed = DarkPassengerTimedAreaAction.CanActivate(action)
    end
    if allowed then
        return DarkPassengerTimedAreaAction.PublishNativeAction(action)
    end
    DarkPassengerTimedAreaAction.ClearNativeAction()
    return false
end

function DarkPassengerTimedAreaAction.OnReload()
    RestorePresentation()
    DarkPassengerTimedAreaAction.active = nil
    DarkPassengerTimedAreaAction._nativeActionPublished = false
    DarkPassengerTimedAreaAction._nativeActionSignature = nil
    DarkPassengerTimedAreaAction._vanillaFActionVisible = false
    DarkPassengerTimedAreaAction.InstallUsableTracker()
    DarkPassengerTimedAreaAction.InstallRawActionHook()
    DarkPassengerTimedAreaAction.InstallHudActionHook()
    return DarkPassengerTimedAreaAction.RefreshPrompt()
end

DarkPassengerTimedAreaAction.InstallUsableTracker()
DarkPassengerTimedAreaAction.InstallRawActionHook()
DarkPassengerTimedAreaAction.InstallHudActionHook()
