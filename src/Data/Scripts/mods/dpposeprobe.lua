-- Dark Passenger animation/dialogue research spike.
-- Deliberately independent from the case runtime: select any nearby human,
-- audition a raw animation, or request the tiny FaderDialog through a role
-- override. Remove this module once the retail-safe mechanism is proven.

if DarkPassengerPoseProbe ~= nil and
   DarkPassengerPoseProbe.Unlock ~= nil then
    pcall(function() DarkPassengerPoseProbe.Unlock() end)
end

DarkPassengerPoseProbe = DarkPassengerPoseProbe or {}
DarkPassengerPoseProbe.POSE_LOCK_INTERVAL_MS = 750
DarkPassengerPoseProbe.IDLE_POSE_SETTLE_MS = 1200
DarkPassengerPoseProbe.CONFESSION_STANCE_SETTLE_MS = 250
DarkPassengerPoseProbe.CONFESSION_DIALOG_DELAY_MS = 1500
DarkPassengerPoseProbe.CONFESSION_PROBE_TARGET_NAME = "tzel_vavrinec"
DarkPassengerPoseProbe.CONFESSION_DIALOGUE_HOLDER_NAME =
    "DP_ConfessionDialogueHolder_Trosecko"
DarkPassengerPoseProbe.CONFESSION_LYING_SPOT_NAME =
    "DP_ConfessionLyingSpot_Trosecko"
DarkPassengerPoseProbe.CONFESSION_RIG_ENTITY_PREFIX =
    "DP_ConfessionCameraRig_"
DarkPassengerPoseProbe.CONFESSION_PROBE_BUFF_GUID =
    "d0c1935f-2d7a-4f4e-bb5c-9ce734d99271"
DarkPassengerPoseProbe.CONFESSION_STANCE_BUFF_GUID =
    "5138624d-76d9-42de-ae19-e144031249cc"
DarkPassengerPoseProbe.COCKEREL_GUID = "6a3efa9e-700a-412a-88ee-721d34da98a8"
DarkPassengerPoseProbe.UNCONSCIOUS_BUFF_GUID = "f8d60fe4-e2c1-420a-946a-213e1cd09265"
DarkPassengerPoseProbe._wakeGeneration =
    tonumber(DarkPassengerPoseProbe._wakeGeneration) or 0
DarkPassengerPoseProbe._actionBusy =
    DarkPassengerPoseProbe._actionBusy == true

DarkPassengerPoseProbe.PROFILES = {
    male = {
        classes = { "NPC", "NPC_NAI" },
        role = "DP_CONFESSION_PROBE_MALE",
        animations = {
            "dlg_male_wounded_listen_in",
            "quest_treating_wounded_s",
            "dlg_male_adjuration_loop_s",
        },
    },
    female = {
        classes = { "NPC_Female" },
        role = "RANENY_NA_ZEMI_ZENA",
        animations = {
            "dlg_female_simektereza_talk",
            "dlg_female_simektereza_listen",
            "healing_bed_typhus_female_solo_idle",
            "quest_femme_fatal_kill_loop_light_s",
        },
    },
}

local function Log(message)
    System.LogAlways("[DarkPassengerPoseProbe] " .. tostring(message))
end

local function SplitArgs(argsLine)
    local parts = {}
    if argsLine == nil then return parts end
    for token in tostring(argsLine):gmatch("%S+") do
        table.insert(parts, token)
    end
    return parts
end

local function DistanceSquared(a, b)
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return dx * dx + dy * dy + dz * dz
end

local function CopyVec3(value)
    if value == nil then return nil end
    return { x = value.x or 0, y = value.y or 0, z = value.z or 0 }
end

local function AddScaled(origin, forward, forwardScale, right, rightScale, z)
    return {
        x = (origin.x or 0) + (forward.x or 0) * forwardScale +
            (right.x or 0) * rightScale,
        y = (origin.y or 0) + (forward.y or 0) * forwardScale +
            (right.y or 0) * rightScale,
        z = (origin.z or 0) + z,
    }
end

local function HorizontalDirection(from, to)
    local x = (to.x or 0) - (from.x or 0)
    local y = (to.y or 0) - (from.y or 0)
    local length = math.sqrt(x * x + y * y)
    if length < 0.01 then return { x = 0, y = 1, z = 0 } end
    return { x = x / length, y = y / length, z = 0 }
end

local function LookDirection(from, to)
    local x = (to.x or 0) - (from.x or 0)
    local y = (to.y or 0) - (from.y or 0)
    local z = (to.z or 0) - (from.z or 0)
    local length = math.sqrt(x * x + y * y + z * z)
    if length < 0.01 then return { x = 0, y = 1, z = 0 } end
    return { x = x / length, y = y / length, z = z / length }
end

local function LookAngles(direction)
    return {
        x = math.asin(direction.z),
        y = 0,
        z = math.atan2(-direction.x, direction.y),
    }
end

local function EntityName(entity)
    local name = nil
    pcall(function() name = entity:GetName() end)
    return name
end

local function IsConfessionTarget(entity)
    if DarkPassengerSceneDirector ~= nil and
       DarkPassengerSceneDirector.CanOfferInterrogation ~= nil then
        local allowed = DarkPassengerSceneDirector.CanOfferInterrogation(
            entity,
            g_localActor
        )
        return allowed == true
    end
    return entity ~= nil and
        EntityName(entity) ==
            DarkPassengerPoseProbe.CONFESSION_PROBE_TARGET_NAME
end

local function IsUnconscious(entity)
    if entity == nil or entity.actor == nil or
       entity.actor.IsUnconscious == nil then
        return false
    end
    local ok, unconscious = pcall(function()
        return entity.actor:IsUnconscious()
    end)
    return ok and (
        unconscious == true or (tonumber(unconscious) or 0) == 1
    )
end

local function HasCockerel(actor)
    if actor == nil or actor.inventory == nil or
       actor.inventory.GetCountOfClass == nil then
        return false
    end
    local ok, count = pcall(function()
        return actor.inventory:GetCountOfClass(
            DarkPassengerPoseProbe.COCKEREL_GUID
        )
    end)
    return ok and (tonumber(count) or 0) > 0
end

local function ConsumeCockerel(actor)
    if actor == nil or actor.inventory == nil or
       actor.inventory.FindItem == nil or
       actor.inventory.DeleteItem == nil then
        return false
    end
    local found, itemId = pcall(function()
        return actor.inventory:FindItem(
            DarkPassengerPoseProbe.COCKEREL_GUID
        )
    end)
    if not found or itemId == nil or itemId == 0 then return false end
    local deleted, result = pcall(function()
        return actor.inventory:DeleteItem(itemId, 1)
    end)
    return deleted and result ~= false
end

local function RestoreUnconscious(entity)
    if entity == nil or entity.soul == nil or
       entity.soul.AddBuff == nil then
        return false
    end
    local ok = pcall(function()
        entity.soul:AddBuff(
            DarkPassengerPoseProbe.UNCONSCIOUS_BUFF_GUID
        )
    end)
    return ok
end

local function IsUsableHuman(entity)
    if entity == nil or entity.id == nil or
       entity.actor == nil or entity.human == nil then
        return false
    end
    if g_localActor ~= nil and entity.id == g_localActor.id then
        return false
    end
    if entity.actor.IsDead == nil then return false end
    local ok, dead = pcall(function() return entity.actor:IsDead() end)
    return ok and dead == false
end

local function EntitiesForClass(origin, radius, className)
    if System.GetEntitiesInSphereByClass ~= nil then
        local ok, entities = pcall(function()
            return System.GetEntitiesInSphereByClass(
                origin,
                radius,
                className
            )
        end)
        if ok and type(entities) == "table" then return entities end
    end

    local ok, entities = pcall(function()
        return System.GetEntitiesInSphere(origin, radius)
    end)
    if not ok or type(entities) ~= "table" then return {} end

    local filtered = {}
    for _, entity in pairs(entities) do
        if entity ~= nil and entity.class == className then
            table.insert(filtered, entity)
        end
    end
    return filtered
end

local function SelectedEntity()
    local selected = DarkPassengerPoseProbe.selected
    if selected == nil or selected.id == nil then return nil end
    return System.GetEntity(selected.id)
end

local function SelectFromProfile(profileName, origin, radius)
    local profile = DarkPassengerPoseProbe.PROFILES[profileName]
    if profile == nil then return nil, nil end

    local nearest = nil
    local nearestDistance = nil
    for _, className in ipairs(profile.classes) do
        local entities = EntitiesForClass(origin, radius, className)
        for _, entity in pairs(entities) do
            if IsUsableHuman(entity) then
                local ok, position = pcall(function()
                    return entity:GetWorldPos()
                end)
                if ok and position ~= nil then
                    local distance = DistanceSquared(origin, position)
                    if nearestDistance == nil or distance < nearestDistance then
                        nearest = entity
                        nearestDistance = distance
                    end
                end
            end
        end
    end
    return nearest, nearestDistance
end

function DarkPassengerPoseProbe.SelectNearest(argsLine)
    if g_localActor == nil then
        Log("selection failed: player unavailable")
        return nil
    end

    local args = SplitArgs(argsLine)
    local requestedProfile = string.lower(args[1] or "any")
    local radius = tonumber(args[2]) or 8
    if requestedProfile ~= "male" and
       requestedProfile ~= "female" and
       requestedProfile ~= "any" then
        radius = tonumber(args[1]) or radius
        requestedProfile = "any"
    end

    local ok, origin = pcall(function()
        return g_localActor:GetWorldPos()
    end)
    if not ok or origin == nil then
        Log("selection failed: player position unavailable")
        return nil
    end

    local profiles = requestedProfile == "any" and
        { "male", "female" } or { requestedProfile }
    local nearest = nil
    local nearestDistance = nil
    local nearestProfile = nil
    for _, profileName in ipairs(profiles) do
        local entity, distance = SelectFromProfile(
            profileName,
            origin,
            radius
        )
        if entity ~= nil and
           (nearestDistance == nil or distance < nearestDistance) then
            nearest = entity
            nearestDistance = distance
            nearestProfile = profileName
        end
    end

    if nearest == nil then
        Log(
            "selection failed: no " .. requestedProfile ..
            " human within " .. tostring(radius) .. "m"
        )
        return nil
    end

    DarkPassengerPoseProbe.selected = {
        id = nearest.id,
        name = EntityName(nearest),
        profile = nearestProfile,
        animationIndex = 0,
    }
    Log(
        "selected profile=" .. nearestProfile ..
        " name=" .. tostring(EntityName(nearest)) ..
        " id=" .. tostring(nearest.id) ..
        " distance=" .. tostring(math.sqrt(nearestDistance))
    )
    return nearest
end

function DarkPassengerPoseProbe.SelectNamed(argsLine)
    local args = SplitArgs(argsLine)
    local entityName = args[1]
    local profileName = string.lower(args[2] or "female")
    local profile = DarkPassengerPoseProbe.PROFILES[profileName]
    if entityName == nil or entityName == "" or profile == nil or
       System == nil or System.GetEntityByName == nil then
        Log("usage: dp_pose_select_name <entity_name> [male|female]")
        return nil
    end

    local entity = System.GetEntityByName(entityName)
    if entity == nil or entity.id == nil then
        Log("named selection failed: " .. tostring(entityName))
        return nil
    end

    DarkPassengerPoseProbe.selected = {
        id = entity.id,
        name = EntityName(entity),
        profile = profileName,
        animationIndex = 0,
    }
    Log(
        "selected named profile=" .. profileName ..
        " name=" .. tostring(EntityName(entity)) ..
        " id=" .. tostring(entity.id)
    )
    return entity
end

local function ResolveAnimation(argsLine)
    local selected = DarkPassengerPoseProbe.selected
    if selected == nil then return nil end
    local profile = DarkPassengerPoseProbe.PROFILES[selected.profile]
    if profile == nil then return nil end

    local args = SplitArgs(argsLine)
    local requested = args[1]
    if requested ~= nil and requested ~= "" then
        local requestedIndex = tonumber(requested)
        if requestedIndex ~= nil then
            requestedIndex = math.floor(requestedIndex)
            if profile.animations[requestedIndex] ~= nil then
                selected.animationIndex = requestedIndex
                return profile.animations[requestedIndex]
            end
        end
        return requested
    end

    local index = tonumber(selected.animationIndex) or 0
    if index < 1 then index = 1 end
    selected.animationIndex = index
    return profile.animations[index]
end

function DarkPassengerPoseProbe.Play(argsLine)
    local entity = SelectedEntity()
    if entity == nil then
        Log("play failed: select an NPC first")
        return false
    end
    local requested = tostring(argsLine or ""):match("^%s*(.-)%s*$")
    if string.lower(requested) == "knockout" then
        if g_localActor == nil or g_localActor.actor == nil or
           g_localActor.actor.RequestKnockOut == nil then
            Log("knockout failed: player binding unavailable")
            return false
        end
        local ok, result = pcall(function()
            return g_localActor.actor:RequestKnockOut(entity.id)
        end)
        Log(
            "RequestKnockOut target=" .. tostring(EntityName(entity)) ..
            " ok=" .. tostring(ok) ..
            " result=" .. tostring(result)
        )
        return ok
    end
    local animation = ResolveAnimation(argsLine)
    if animation == nil then
        Log("play failed: animation unavailable")
        return false
    end

    local ok, result = pcall(function()
        return entity:StartAnimation(0, animation)
    end)
    Log(
        "StartAnimation name=" .. tostring(animation) ..
        " accepted=" .. tostring(ok) ..
        " result=" .. tostring(result)
    )
    return ok
end

function DarkPassengerPoseProbe.DebugPlay(argsLine)
    local entity = SelectedEntity()
    if entity == nil then
        Log("debug play failed: select an NPC first")
        return false
    end
    local animation = ResolveAnimation(argsLine)
    local name = EntityName(entity)
    if animation == nil or name == nil or
       name:find("[^%w_%-]") ~= nil then
        Log("debug play failed: unsafe name or missing animation")
        return false
    end
    System.ExecuteCommand(
        "wh_am_DebugPlayAnimation " .. name .. " " .. animation
    )
    Log("dev debug animation requested name=" .. animation)
    return true
end

function DarkPassengerPoseProbe.Cycle()
    local selected = DarkPassengerPoseProbe.selected
    if selected == nil then
        Log("cycle failed: select an NPC first")
        return false
    end
    local profile = DarkPassengerPoseProbe.PROFILES[selected.profile]
    local index = (tonumber(selected.animationIndex) or 0) + 1
    if index > #profile.animations then index = 1 end
    selected.animationIndex = index
    return DarkPassengerPoseProbe.Play(tostring(index))
end

function DarkPassengerPoseProbe.PoseLockTick(generation)
    local lock = DarkPassengerPoseProbe.poseLock
    if lock == nil or lock.active ~= true or
       lock.generation ~= generation then
        return false
    end

    local entity = System.GetEntity(lock.entityId)
    if entity == nil then
        DarkPassengerPoseProbe.poseLock = nil
        Log("pose lock stopped: entity unavailable")
        return false
    end

    if lock.position ~= nil and entity.SetWorldPos ~= nil then
        pcall(function() entity:SetWorldPos(lock.position) end)
    end
    if lock.angles ~= nil and entity.SetWorldAngles ~= nil then
        pcall(function() entity:SetWorldAngles(lock.angles) end)
    end

    lock.timerId = Script.SetTimer(lock.intervalMs, function()
        DarkPassengerPoseProbe.PoseLockTick(generation)
    end)
    return true
end

function DarkPassengerPoseProbe.Unlock()
    local lock = DarkPassengerPoseProbe.poseLock
    local entity = nil
    if lock ~= nil then
        lock.active = false
        DarkPassengerPoseProbe.poseLockGeneration =
            (tonumber(DarkPassengerPoseProbe.poseLockGeneration) or 0) + 1
        if lock.timerId ~= nil and Script ~= nil and
           Script.KillTimer ~= nil then
            pcall(function() Script.KillTimer(lock.timerId) end)
        end
        entity = System.GetEntity(lock.entityId)
    else
        entity = SelectedEntity()
    end

    if entity ~= nil then
        if lock ~= nil and type(lock.animationTags) == "table" and AI ~= nil and
           AI.ClearAnimationTag ~= nil then
            for _, tag in ipairs(lock.animationTags) do
                pcall(function()
                    AI.ClearAnimationTag(entity.id, tag)
                end)
            end
        end
        if (lock == nil or lock.rawAnimation == true) and
           entity.StopAnimation ~= nil then
            pcall(function() entity:StopAnimation(0, 0) end)
        end
        if entity.actor ~= nil then
            if entity.actor.SetMovementControlledByAnimation ~= nil then
                pcall(function()
                    entity.actor:SetMovementControlledByAnimation(true)
                end)
            end
            if entity.actor.SetDialogAnimationState ~= nil then
                pcall(function()
                    entity.actor:SetDialogAnimationState(false)
                end)
            end
        end
        if (lock == nil or lock.behaviorTreeDisabled == true) and AI ~= nil and
           AI.SetBehaviorTreeEvaluationEnabled ~= nil then
            pcall(function()
                AI.SetBehaviorTreeEvaluationEnabled(entity.id, true)
            end)
        end
        if entity.SetDefaultIdleAnimations ~= nil then
            pcall(function() entity:SetDefaultIdleAnimations(0) end)
        end
    end

    DarkPassengerPoseProbe.poseLock = nil
    if lock == nil then
        Log("restored selected control without active lock")
    else
        Log("pose lock released")
    end
    return true
end

function DarkPassengerPoseProbe.Lock(argsLine)
    local entity = SelectedEntity()
    if entity == nil then
        Log("pose lock failed: select an NPC first")
        return false
    end
    if Script == nil or Script.SetTimer == nil then
        Log("pose lock failed: timer binding unavailable")
        return false
    end

    local animation = ResolveAnimation(argsLine)
    if animation == nil then
        Log("pose lock failed: animation unavailable")
        return false
    end
    local args = SplitArgs(argsLine)
    local intervalMs = tonumber(args[2]) or
        DarkPassengerPoseProbe.POSE_LOCK_INTERVAL_MS
    intervalMs = math.max(250, math.floor(intervalMs))

    DarkPassengerPoseProbe.Unlock()
    local behaviorTreeDisabled = false
    if AI ~= nil and AI.SetBehaviorTreeEvaluationEnabled ~= nil then
        behaviorTreeDisabled = pcall(function()
            AI.SetBehaviorTreeEvaluationEnabled(entity.id, false)
        end)
    end
    if AI ~= nil and AI.AbortAction ~= nil then
        pcall(function() AI.AbortAction(entity.id) end)
    end
    if AI ~= nil and AI.RequestToStopMovement ~= nil then
        pcall(function() AI.RequestToStopMovement(entity.id) end)
    end
    if entity.actor ~= nil then
        if entity.actor.SetDialogAnimationState ~= nil then
            pcall(function()
                entity.actor:SetDialogAnimationState(false)
            end)
        end
        if entity.actor.SetMovementControlledByAnimation ~= nil then
            pcall(function()
                entity.actor:SetMovementControlledByAnimation(false)
            end)
        end
    end

    local lockPosition = nil
    local lockAngles = nil
    pcall(function() lockPosition = CopyVec3(entity:GetWorldPos()) end)
    pcall(function() lockAngles = CopyVec3(entity:GetWorldAngles()) end)

    local animationOk, animationResult = pcall(function()
        return entity:StartAnimation(0, animation, 0, 0.15, 1.0, true)
    end)
    if not animationOk then
        if behaviorTreeDisabled and AI ~= nil and
           AI.SetBehaviorTreeEvaluationEnabled ~= nil then
            pcall(function()
                AI.SetBehaviorTreeEvaluationEnabled(entity.id, true)
            end)
        end
        Log("pose lock animation failed: " .. tostring(animationResult))
        return false
    end
    local generation =
        (tonumber(DarkPassengerPoseProbe.poseLockGeneration) or 0) + 1
    DarkPassengerPoseProbe.poseLockGeneration = generation
    DarkPassengerPoseProbe.poseLock = {
        active = true,
        generation = generation,
        entityId = entity.id,
        entityName = EntityName(entity),
        animation = animation,
        intervalMs = intervalMs,
        position = lockPosition,
        angles = lockAngles,
        behaviorTreeDisabled = behaviorTreeDisabled,
        rawAnimation = true,
    }

    Log(
        "pose lock started entity=" .. tostring(EntityName(entity)) ..
        " animation=" .. tostring(animation) ..
        " intervalMs=" .. tostring(intervalMs) ..
        " aiFrozen=" .. tostring(behaviorTreeDisabled) ..
        " rootMotion=false"
    )
    DarkPassengerPoseProbe.PoseLockTick(generation)
    return true
end

function DarkPassengerPoseProbe.IdlePose(argsLine)
    local entity = SelectedEntity()
    if entity == nil then
        Log("idle pose failed: select an NPC first")
        return false
    end
    if AI == nil or AI.SetAnimationTag == nil then
        Log("idle pose failed: animation tag binding unavailable")
        return false
    end

    local tags = SplitArgs(argsLine)
    if #tags == 0 then
        tags = { "sittingGround", "sittingGroundVar1" }
    end

    DarkPassengerPoseProbe.Unlock()
    if AI.SetBehaviorTreeEvaluationEnabled ~= nil then
        pcall(function()
            AI.SetBehaviorTreeEvaluationEnabled(entity.id, true)
        end)
    end
    local aborted = false
    if AI.AbortAction ~= nil then
        aborted = pcall(function() AI.AbortAction(entity.id) end)
    end
    if AI.RequestToStopMovement ~= nil then
        pcall(function() AI.RequestToStopMovement(entity.id) end)
    end
    if entity.SetDefaultIdleAnimations ~= nil then
        pcall(function() entity:SetDefaultIdleAnimations(0) end)
    end

    local appliedTags = {}
    for _, tag in ipairs(tags) do
        local ok = pcall(function()
            AI.SetAnimationTag(entity.id, tag)
        end)
        if ok then table.insert(appliedTags, tag) end
    end

    local queued = false
    if entity.actor ~= nil and
       entity.actor.QueueAnimationState ~= nil then
        queued = pcall(function()
            entity.actor:QueueAnimationState("idle")
        end)
    end

    local generation =
        (tonumber(DarkPassengerPoseProbe.poseLockGeneration) or 0) + 1
    DarkPassengerPoseProbe.poseLockGeneration = generation
    DarkPassengerPoseProbe.poseLock = {
        active = true,
        generation = generation,
        entityId = entity.id,
        entityName = EntityName(entity),
        intervalMs = DarkPassengerPoseProbe.POSE_LOCK_INTERVAL_MS,
        animationTags = appliedTags,
        behaviorTreeDisabled = false,
        rawAnimation = false,
    }

    Log(
        "idle pose staging entity=" .. tostring(EntityName(entity)) ..
        " tags=" .. table.concat(appliedTags, "+") ..
        " aborted=" .. tostring(aborted) ..
        " queued=" .. tostring(queued) ..
        " settleMs=" .. tostring(
            DarkPassengerPoseProbe.IDLE_POSE_SETTLE_MS
        )
    )
    DarkPassengerPoseProbe.poseLock.timerId = Script.SetTimer(
        DarkPassengerPoseProbe.IDLE_POSE_SETTLE_MS,
        function()
            local lock = DarkPassengerPoseProbe.poseLock
            if lock == nil or lock.active ~= true or
               lock.generation ~= generation then
                return
            end
            local liveEntity = System.GetEntity(lock.entityId)
            if liveEntity == nil then
                DarkPassengerPoseProbe.Unlock()
                return
            end
            if AI.RequestToStopMovement ~= nil then
                pcall(function()
                    AI.RequestToStopMovement(liveEntity.id)
                end)
            end
            if AI.SetBehaviorTreeEvaluationEnabled ~= nil then
                lock.behaviorTreeDisabled = pcall(function()
                    AI.SetBehaviorTreeEvaluationEnabled(
                        liveEntity.id,
                        false
                    )
                end)
            end
            pcall(function() lock.position = liveEntity:GetWorldPos() end)
            pcall(function() lock.angles = liveEntity:GetWorldAngles() end)
            local animationState = nil
            if liveEntity.actor ~= nil and
               liveEntity.actor.GetCurrentAnimationState ~= nil then
                pcall(function()
                    animationState =
                        liveEntity.actor:GetCurrentAnimationState()
                end)
            end
            Log(
                "idle pose locked entity=" ..
                tostring(EntityName(liveEntity)) ..
                " state=" .. tostring(animationState) ..
                " aiFrozen=" ..
                tostring(lock.behaviorTreeDisabled)
            )
            DarkPassengerPoseProbe.PoseLockTick(generation)
        end
    )
    return true
end

function DarkPassengerPoseProbe.SetInput(argsLine)
    local entity = SelectedEntity()
    local args = SplitArgs(argsLine)
    if entity == nil or entity.actor == nil or
       entity.actor.SetAnimationInput == nil then
        Log("animation input failed: binding or selection unavailable")
        return false
    end
    if args[1] == nil or args[2] == nil then
        Log("usage: dp_pose_input <input> <value>")
        return false
    end
    local ok, result = pcall(function()
        return entity.actor:SetAnimationInput(args[1], args[2])
    end)
    Log(
        "SetAnimationInput " .. args[1] .. "=" .. args[2] ..
        " accepted=" .. tostring(ok) ..
        " result=" .. tostring(result)
    )
    return ok
end

function DarkPassengerPoseProbe.Dialog(argsLine)
    local entity = SelectedEntity()
    if entity == nil then
        entity = DarkPassengerPoseProbe.SelectNearest(argsLine)
    end
    local selected = DarkPassengerPoseProbe.selected
    if entity == nil or selected == nil or
       g_localActor == nil or g_localActor.actor == nil or
       g_localActor.actor.RequestDialog == nil then
        Log("dialog failed: actor, player, or binding unavailable")
        return false
    end

    local profile = DarkPassengerPoseProbe.PROFILES[selected.profile]
    local requestedRole = tostring(argsLine or ""):match("^%s*(.-)%s*$")
    if requestedRole == "" then
        requestedRole = profile.role
    end
    local ok, accepted = pcall(function()
        return g_localActor.actor:RequestDialog(
            entity.id,
            requestedRole,
            true,
            false
        )
    end)
    Log(
        "RequestDialog role=" .. requestedRole ..
        " accepted=" .. tostring(ok and accepted) ..
        " callOk=" .. tostring(ok)
    )
    return ok and accepted ~= false
end

local function RemovePlayerBuff(buffGuid)
    if g_localActor == nil or g_localActor.soul == nil or
       g_localActor.soul.RemoveAllBuffsByGuid == nil then
        return false
    end
    return pcall(function()
        g_localActor.soul:RemoveAllBuffsByGuid(buffGuid)
    end)
end

local function RemoveConfessionProbeBuff()
    return RemovePlayerBuff(
        DarkPassengerPoseProbe.CONFESSION_PROBE_BUFF_GUID
    )
end

local function RemoveConfessionStanceBuff()
    return RemovePlayerBuff(
        DarkPassengerPoseProbe.CONFESSION_STANCE_BUFF_GUID
    )
end

function DarkPassengerPoseProbe.PositionConfessionLyingSpot(target)
    if target == nil or System == nil or
       System.GetEntityByName == nil then
        Log("lying spot failed: runtime binding unavailable")
        return false
    end
    local spot = System.GetEntityByName(
        DarkPassengerPoseProbe.CONFESSION_LYING_SPOT_NAME
    )
    if spot == nil or spot.SetWorldPos == nil then
        Log(
            "lying spot failed: entity unavailable name=" ..
            DarkPassengerPoseProbe.CONFESSION_LYING_SPOT_NAME
        )
        return false
    end

    local targetPosition = nil
    local targetAngles = nil
    pcall(function() targetPosition = target:GetWorldPos() end)
    pcall(function() targetAngles = target:GetWorldAngles() end)
    if targetPosition == nil then
        Log("lying spot failed: target position unavailable")
        return false
    end
    local moved = pcall(function()
        spot:SetWorldPos(CopyVec3(targetPosition))
        if targetAngles ~= nil and spot.SetWorldAngles ~= nil then
            spot:SetWorldAngles({
                x = 0,
                y = 0,
                z = targetAngles.z or 0,
            })
        end
    end)
    if not moved then
        Log("lying spot failed: transform rejected")
        return false
    end
    Log(
        "lying-harmed smart object positioned target=" ..
        tostring(EntityName(target))
    )
    return true
end

function DarkPassengerPoseProbe.DestroyConfessionCameraRig()
    -- Camera entities and their cameraOverride links are authored into the
    -- level registry. Runtime cleanup must never remove that static rig.
    DarkPassengerPoseProbe._confessionCameraRig = nil
end

function DarkPassengerPoseProbe.CreateConfessionCameraRig(target)
    if target == nil or g_localActor == nil or System == nil or
       System.GetEntityByName == nil then
        Log("camera rig failed: runtime binding unavailable")
        return false
    end

    DarkPassengerPoseProbe.DestroyConfessionCameraRig()
    local holder = System.GetEntityByName(
        DarkPassengerPoseProbe.CONFESSION_DIALOGUE_HOLDER_NAME
    )
    if holder == nil or holder.SetWorldPos == nil then
        Log(
            "camera rig failed: DialogueHolder unavailable name=" ..
            DarkPassengerPoseProbe.CONFESSION_DIALOGUE_HOLDER_NAME
        )
        return false
    end

    local targetPosition = nil
    local playerPosition = nil
    pcall(function() targetPosition = target:GetWorldPos() end)
    pcall(function() playerPosition = g_localActor:GetWorldPos() end)
    if targetPosition == nil or playerPosition == nil then
        Log("camera rig failed: participant position unavailable")
        return false
    end

    targetPosition = CopyVec3(targetPosition)
    playerPosition = CopyVec3(playerPosition)
    local towardPlayer = HorizontalDirection(targetPosition, playerPosition)
    local right = {
        x = -towardPlayer.y,
        y = towardPlayer.x,
        z = 0,
    }
    local targetFocus = AddScaled(
        targetPosition, towardPlayer, 0, right, 0, 0.55
    )
    local playerFocus = AddScaled(
        playerPosition, towardPlayer, 0, right, 0, 1.55
    )
    local entityIds = {}

    pcall(function() holder:SetWorldPos(targetPosition) end)
    local cameraSpecs = {
        {
            entityName = DarkPassengerPoseProbe.CONFESSION_RIG_ENTITY_PREFIX ..
                "targetCloseup",
            position = AddScaled(
                targetPosition, towardPlayer, 1.05, right, 0.45, 1.05
            ),
            focus = targetFocus,
        },
        {
            entityName = DarkPassengerPoseProbe.CONFESSION_RIG_ENTITY_PREFIX ..
                "targetCloseShot",
            position = AddScaled(
                targetPosition, towardPlayer, 1.45, right, 0.65, 1.30
            ),
            focus = targetFocus,
        },
        {
            entityName = DarkPassengerPoseProbe.CONFESSION_RIG_ENTITY_PREFIX ..
                "targetMedium",
            position = AddScaled(
                targetPosition, towardPlayer, 1.95, right, 0.85, 1.55
            ),
            focus = targetFocus,
        },
        {
            entityName = DarkPassengerPoseProbe.CONFESSION_RIG_ENTITY_PREFIX ..
                "playerCloseup",
            position = AddScaled(
                playerPosition, towardPlayer, -0.80, right, -0.35, 1.45
            ),
            focus = playerFocus,
        },
        {
            entityName = DarkPassengerPoseProbe.CONFESSION_RIG_ENTITY_PREFIX ..
                "playerCloseShot",
            position = AddScaled(
                playerPosition, towardPlayer, -1.10, right, -0.55, 1.35
            ),
            focus = playerFocus,
        },
        {
            entityName = DarkPassengerPoseProbe.CONFESSION_RIG_ENTITY_PREFIX ..
                "playerMedium",
            position = AddScaled(
                playerPosition, towardPlayer, -1.45, right, -0.75, 1.20
            ),
            focus = playerFocus,
        },
    }

    for _, cameraSpec in ipairs(cameraSpecs) do
        local camera = System.GetEntityByName(cameraSpec.entityName)
        if camera == nil or camera.id == nil then
            DarkPassengerPoseProbe.DestroyConfessionCameraRig()
            Log(
                "camera rig failed: authored camera unavailable name=" ..
                tostring(cameraSpec.entityName)
            )
            return false
        end
        table.insert(entityIds, camera.id)
        pcall(function()
            camera:SetWorldPos(CopyVec3(cameraSpec.position))
            camera:SetWorldAngles(
                LookAngles(
                    LookDirection(cameraSpec.position, cameraSpec.focus)
                )
            )
        end)
    end

    DarkPassengerPoseProbe._confessionCameraRig = {
        holderId = holder.id,
        entityIds = entityIds,
        targetId = target.id,
    }
    Log(
        "vanilla lying-harmed camera rig ready target=" ..
        tostring(EntityName(target)) .. " cameras=" ..
        tostring(#cameraSpecs)
    )
    return true
end

function DarkPassengerPoseProbe.StartConfession(argsLine)
    if g_localActor == nil or g_localActor.soul == nil or
       g_localActor.soul.AddBuff == nil or Script == nil or
       Script.SetTimer == nil then
        Log("confession failed: player or buff binding unavailable")
        return false
    end

    local requestedName = tostring(argsLine or ""):match("^%s*(.-)%s*$")
    if requestedName == "" then
        requestedName = DarkPassengerPoseProbe.CONFESSION_PROBE_TARGET_NAME
    end
    local entity = DarkPassengerPoseProbe.SelectNamed(
        requestedName .. " male"
    )
    local selected = DarkPassengerPoseProbe.selected
    local profile = DarkPassengerPoseProbe.PROFILES.male
    if entity == nil or selected == nil or entity.soul == nil or
       entity.soul.AddMetaRoleByName == nil then
        Log("confession failed: target or role binding unavailable")
        return false
    end

    DarkPassengerPoseProbe.ClearDialogs()
    if not DarkPassengerPoseProbe.PositionConfessionLyingSpot(entity) then
        Log("confession failed: lying-harmed smart object unavailable")
        return false
    end
    if not DarkPassengerPoseProbe.CreateConfessionCameraRig(entity) then
        Log("confession failed: lying-harmed camera rig unavailable")
        return false
    end
    local roleOk, roleResult = pcall(function()
        return entity.soul:AddMetaRoleByName(profile.role)
    end)
    if not roleOk then
        DarkPassengerPoseProbe.DestroyConfessionCameraRig()
        Log("confession role failed: " .. tostring(roleResult))
        return false
    end
    selected.roleApplied = true

    local stanceOk, stanceResult = pcall(function()
        return g_localActor.soul:AddBuff(
            DarkPassengerPoseProbe.CONFESSION_STANCE_BUFF_GUID
        )
    end)
    if not stanceOk then
        pcall(function()
            entity.soul:RemoveMetaRoleByName(profile.role)
        end)
        selected.roleApplied = false
        DarkPassengerPoseProbe.DestroyConfessionCameraRig()
        Log("confession stance trigger failed: " .. tostring(stanceResult))
        return false
    end

    DarkPassengerPoseProbe._wakeGeneration =
        DarkPassengerPoseProbe._wakeGeneration + 1
    local generation = DarkPassengerPoseProbe._wakeGeneration
    DarkPassengerPoseProbe._actionBusy = true
    DarkPassengerPoseProbe.pendingWake = {
        generation = generation,
        targetId = entity.id,
    }
    Script.SetTimer(
        DarkPassengerPoseProbe.CONFESSION_STANCE_SETTLE_MS,
        function()
            local pending = DarkPassengerPoseProbe.pendingWake
            if pending == nil or pending.generation ~= generation then
                return
            end
            local liveTarget = System.GetEntity(pending.targetId)
            if liveTarget == nil or liveTarget.soul == nil or
               liveTarget.soul.RemoveAllBuffsByGuid == nil then
                DarkPassengerPoseProbe.ClearDialogs()
                Log("confession wake failed: target unavailable")
                return
            end
            local woke, wakeError = pcall(function()
                liveTarget.soul:RemoveAllBuffsByGuid(
                    DarkPassengerPoseProbe.UNCONSCIOUS_BUFF_GUID
                )
            end)
            if not woke then
                DarkPassengerPoseProbe.ClearDialogs()
                RestoreUnconscious(liveTarget)
                Log("confession wake failed: " .. tostring(wakeError))
                return
            end

            Script.SetTimer(
                DarkPassengerPoseProbe.CONFESSION_DIALOG_DELAY_MS,
                function()
                    local ready = DarkPassengerPoseProbe.pendingWake
                    if ready == nil or ready.generation ~= generation then
                        return
                    end
                    local dialogOk, dialogResult = pcall(function()
                        return g_localActor.soul:AddBuff(
                            DarkPassengerPoseProbe.CONFESSION_PROBE_BUFF_GUID
                        )
                    end)
                    if not dialogOk then
                        DarkPassengerPoseProbe.ClearDialogs()
                        RestoreUnconscious(liveTarget)
                        Log(
                            "confession dialog trigger failed: " ..
                            tostring(dialogResult)
                        )
                        return
                    end
                    DarkPassengerPoseProbe.pendingWake = nil
                    Log(
                        "confession lying-harmed dialog armed target=" ..
                        tostring(EntityName(liveTarget)) ..
                        " alias=dp_pose_confession_probe"
                    )
                end
            )
        end
    )

    Log(
        "confession lying-harmed stance armed target=" ..
        tostring(EntityName(entity)) ..
        " settleMs=" ..
        tostring(DarkPassengerPoseProbe.CONFESSION_STANCE_SETTLE_MS)
    )
    return true
end

function DarkPassengerPoseProbe.CanWakeForConfession(target, user)
    local actor = user or g_localActor
    local approved = IsConfessionTarget(target)
    if DarkPassengerSceneDirector ~= nil and
       DarkPassengerSceneDirector.CanOfferInterrogation ~= nil then
        approved = DarkPassengerSceneDirector.CanOfferInterrogation(
            target,
            actor
        )
    end
    if not approved or not IsUsableHuman(target) or
       not IsUnconscious(target) then
        return false, ""
    end
    if DarkPassengerPoseProbe._actionBusy then
        return false, ""
    end
    if not HasCockerel(actor) then
        return false, "@dp_confession_requires_cockerel"
    end
    return true, ""
end

function DarkPassengerPoseProbe.AddWakeAction(
    target,
    user,
    firstFast,
    output
)
    if type(output) ~= "table" or
       not IsConfessionTarget(target) or
       not IsUnconscious(target) or
       DarkPassengerPoseProbe._actionBusy then
        return false
    end
    local enabled, reason =
        DarkPassengerPoseProbe.CanWakeForConfession(target, user)
    return AddInteractorAction(
        output,
        firstFast,
        Action()
            :hint("@dp_confession_wake_action")
            :action("butcher")
            :hintType(AHT_HOLD)
            :uiOrder(2)
            :func(DarkPassengerPoseProbe.OnWakeForConfession)
            :interaction(inr_talk)
            :enabled(enabled)
            :reason(reason)
    )
end

function DarkPassengerPoseProbe.OnWakeForConfession(target, user, slotId)
    local allowed, reason =
        DarkPassengerPoseProbe.CanWakeForConfession(target, user)
    if not allowed then
        Log("wake confession rejected reason=" .. tostring(reason))
        return false
    end
    if target.soul == nil then
        Log("wake confession rejected: runtime binding unavailable")
        return false
    end
    local actor = user or g_localActor
    local started = DarkPassengerPoseProbe.StartConfession(
        EntityName(target)
    )
    if not started or not ConsumeCockerel(actor) then
        DarkPassengerPoseProbe.ClearDialogs()
        RestoreUnconscious(target)
        Log("wake confession rolled back before dialog")
        return false
    end
    if DarkPassengerSceneDirector ~= nil and
       DarkPassengerSceneDirector.MarkInterrogationOffered ~= nil then
        local marked = DarkPassengerSceneDirector.MarkInterrogationOffered(
            target
        )
        if not marked then
            DarkPassengerPoseProbe.ClearDialogs()
            RestoreUnconscious(target)
            Log("wake confession rolled back: case snapshot rejected")
            return false
        end
    end
    DarkPassengerPoseProbe._actionBusy = true
    Log(
        "wake confession armed target=" ..
        tostring(EntityName(target)) ..
        " slot=" .. tostring(slotId) ..
        " cockerelConsumed=true"
    )
    return true
end

function DarkPassengerPoseProbe.ClearDialogs()
    local pending = DarkPassengerPoseProbe.pendingWake
    DarkPassengerPoseProbe._wakeGeneration =
        DarkPassengerPoseProbe._wakeGeneration + 1
    DarkPassengerPoseProbe.pendingWake = nil
    if pending ~= nil and pending.targetId ~= nil and
       System ~= nil and System.GetEntity ~= nil then
        RestoreUnconscious(System.GetEntity(pending.targetId))
    end
    local entity = SelectedEntity()
    if g_localActor ~= nil and g_localActor.human ~= nil and
       g_localActor.human.InterruptDialogs ~= nil then
        pcall(function() g_localActor.human:InterruptDialogs() end)
    end
    if entity ~= nil and entity.human ~= nil and
       entity.human.InterruptDialogs ~= nil then
        pcall(function() entity.human:InterruptDialogs() end)
    end
    local selected = DarkPassengerPoseProbe.selected
    if entity ~= nil and selected ~= nil and selected.roleApplied == true and
       entity.soul ~= nil and
       entity.soul.RemoveMetaRoleByName ~= nil then
        local profile = DarkPassengerPoseProbe.PROFILES[selected.profile]
        if profile ~= nil then
            pcall(function()
                entity.soul:RemoveMetaRoleByName(profile.role)
            end)
        end
        selected.roleApplied = false
    end
    RemoveConfessionProbeBuff()
    RemoveConfessionStanceBuff()
    DarkPassengerPoseProbe.DestroyConfessionCameraRig()
    DarkPassengerPoseProbe._actionBusy = false
    Log("interrupted player and selected NPC dialogs")
    return true
end

function DarkPassengerPoseProbe.ForceDialog()
    local entity = SelectedEntity()
    if entity == nil or g_localActor == nil then
        Log("force dialog failed: selection or player unavailable")
        return false
    end

    local binding = nil
    if DialogModule ~= nil and DialogModule.ForceDialog ~= nil then
        binding = DialogModule.ForceDialog
    elseif Dialog ~= nil and Dialog.ForceDialog ~= nil then
        binding = Dialog.ForceDialog
    elseif DialogSystem ~= nil and DialogSystem.ForceDialog ~= nil then
        binding = DialogSystem.ForceDialog
    end
    if binding == nil then
        Log("force dialog failed: ForceDialog binding unavailable")
        return false
    end

    local ok, result = pcall(function()
        return binding(entity.id, g_localActor.id)
    end)
    Log(
        "ForceDialog speaker=" .. tostring(EntityName(entity)) ..
        " ok=" .. tostring(ok) ..
        " result=" .. tostring(result)
    )
    return ok
end

function DarkPassengerPoseProbe.AnalyzeRequest()
    local binding = nil
    if DialogModule ~= nil and DialogModule.AnalyzeRequest ~= nil then
        binding = DialogModule.AnalyzeRequest
    elseif Dialog ~= nil and Dialog.AnalyzeRequest ~= nil then
        binding = Dialog.AnalyzeRequest
    elseif DialogSystem ~= nil and DialogSystem.AnalyzeRequest ~= nil then
        binding = DialogSystem.AnalyzeRequest
    end
    if binding == nil then
        Log("analyze request failed: AnalyzeRequest binding unavailable")
        return false
    end

    local ok, result = pcall(function() return binding() end)
    Log(
        "AnalyzeRequest ok=" .. tostring(ok) ..
        " result=" .. tostring(result)
    )
    return ok
end

function DarkPassengerPoseProbe.Status()
    local selected = DarkPassengerPoseProbe.selected
    local entity = SelectedEntity()
    if selected == nil or entity == nil then
        Log("status: no live selection")
        return false
    end
    local profile = DarkPassengerPoseProbe.PROFILES[selected.profile]
    local hasMetaRole = nil
    local unconscious = nil
    if entity.actor ~= nil and entity.actor.IsUnconscious ~= nil then
        local ok, result = pcall(function()
            return entity.actor:IsUnconscious()
        end)
        if ok then unconscious = result end
    end
    if entity.soul ~= nil and profile ~= nil and
       entity.soul.HasMetaRoleByName ~= nil then
        local ok, result = pcall(function()
            return entity.soul:HasMetaRoleByName(profile.role)
        end)
        if ok then hasMetaRole = result end
    end
    Log(
        "status profile=" .. tostring(selected.profile) ..
        " name=" .. tostring(EntityName(entity)) ..
        " id=" .. tostring(entity.id) ..
        " animationIndex=" .. tostring(selected.animationIndex) ..
        " hasMetaRole=" .. tostring(hasMetaRole) ..
        " unconscious=" .. tostring(unconscious)
    )
    return true
end

if DarkPassengerInteractions ~= nil and
   DarkPassengerInteractions.RegisterProvider ~= nil then
    DarkPassengerInteractions.RegisterProvider(
        "confession_wake",
        function(target, user, firstFast, output)
            return DarkPassengerPoseProbe.AddWakeAction(
                target,
                user,
                firstFast,
                output
            )
        end
    )
end

local okCommands, commandError = pcall(function()
    System.AddCCommand(
        "dp_pose_select",
        "DarkPassengerPoseProbe.SelectNearest(%line)",
        "Select nearest human: dp_pose_select [male|female|any] [radius]"
    )
    System.AddCCommand(
        "dp_pose_select_name",
        "DarkPassengerPoseProbe.SelectNamed(%line)",
        "Select human by entity name: dp_pose_select_name <entity_name> [male|female]"
    )
    System.AddCCommand(
        "dp_pose_play",
        "DarkPassengerPoseProbe.Play(%line)",
        "Retail binding probe: dp_pose_play [index|raw_animation]"
    )
    System.AddCCommand(
        "dp_pose_cycle",
        "DarkPassengerPoseProbe.Cycle()",
        "Play the next raw animation through Entity.StartAnimation"
    )
    System.AddCCommand(
        "dp_pose_lock",
        "DarkPassengerPoseProbe.Lock(%line)",
        "Keep selected NPC in an animation: dp_pose_lock [index|animation] [interval_ms]"
    )
    System.AddCCommand(
        "dp_pose_unlock",
        "DarkPassengerPoseProbe.Unlock()",
        "Release selected NPC from the pose lock"
    )
    System.AddCCommand(
        "dp_pose_idle",
        "DarkPassengerPoseProbe.IdlePose(%line)",
        "Keep selected NPC in an idle tag state"
    )
    System.AddCCommand(
        "dp_pose_debug",
        "DarkPassengerPoseProbe.DebugPlay(%line)",
        "Dev-only wh_am_DebugPlayAnimation audition"
    )
    System.AddCCommand(
        "dp_pose_input",
        "DarkPassengerPoseProbe.SetInput(%line)",
        "Retail binding probe: dp_pose_input <input> <value>"
    )
    System.AddCCommand(
        "dp_pose_dialog",
        "DarkPassengerPoseProbe.Dialog(%line)",
        "Request the selected NPC pose-probe FaderDialog"
    )
    System.AddCCommand(
        "dp_pose_confession",
        "DarkPassengerPoseProbe.StartConfession(%line)",
        "Start the scheduler-owned Lavrentiy confession probe"
    )
    System.AddCCommand(
        "dp_pose_clear_dialogs",
        "DarkPassengerPoseProbe.ClearDialogs()",
        "Interrupt pending dialogs for player and selected NPC"
    )
    System.AddCCommand(
        "dp_pose_force",
        "DarkPassengerPoseProbe.ForceDialog()",
        "Force the selected NPC/player dialog after role request"
    )
    System.AddCCommand(
        "dp_pose_analyze",
        "DarkPassengerPoseProbe.AnalyzeRequest()",
        "Analyze the pending role-preserving dialog request"
    )
    System.AddCCommand(
        "dp_pose_status",
        "DarkPassengerPoseProbe.Status()",
        "Print pose-probe selection"
    )
end)

if okCommands then
    Log("loaded; run dp_pose_confession for the scheduler-owned probe")
else
    Log("command registration failed: " .. tostring(commandError))
end
