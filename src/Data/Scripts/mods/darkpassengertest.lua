-- Dark Passenger Test mod - vertical slice v8
-- v8 adds dp_test_marker: experimental probe of GameRules.SetObjectiveEntity
-- to see if it produces any visible marker in KCD2 SP (unverified CryEngine 2012 doc).
-- v4 proved match/miss against a raw targetId works end-to-end in-game.
-- v5 swapped the raw targetId check for the DarkPassengerCase state machine.
-- v6 fixed the %line multi-arg parsing... except SplitArgs was never actually
-- defined anywhere, so every command call errored with
-- "attempt to call global 'SplitArgs' (a nil value)". v7 adds the missing
-- helper (local, declared before first use) and nothing else changes.

DarkPassengerTest = DarkPassengerTest or {}

-- KCD2 runs only Scripts/mods/<mod_id>.lua as the mod init script.
-- Load the satisfaction bridge explicitly so its console commands and
-- correct-kill reward are available in retail builds.
Script.ReloadScript("Scripts/mods/dpsatisfaction.lua")
Script.ReloadScript("Scripts/mods/dphunger.lua")
Script.ReloadScript("Scripts/mods/dpwitness.lua")
Script.ReloadScript("Scripts/mods/dpaftermath.lua")
Script.ReloadScript("Scripts/mods/dpwitnessdetector.lua")
Script.ReloadScript("Scripts/mods/generated/dp_candidate_catalog.lua")
Script.ReloadScript("Scripts/mods/generated/dp_investigation_area_catalog.lua")
Script.ReloadScript("Scripts/mods/dpinvestigation.lua")
Script.ReloadScript("Scripts/mods/generated/dp_quest_item_catalog.lua")
Script.ReloadScript("Scripts/mods/dpinteractions.lua")
Script.ReloadScript("Scripts/mods/generated/dp_case_catalog.lua")
Script.ReloadScript("Scripts/mods/dpcasecontent.lua")
Script.ReloadScript("Scripts/mods/dpcaseevidence.lua")
Script.ReloadScript("Scripts/mods/dpevidenceregistry.lua")
Script.ReloadScript("Scripts/mods/dpevidencereaction.lua")
Script.ReloadScript("Scripts/mods/dpwitnesslead.lua")
Script.ReloadScript("Scripts/mods/dpbelongings.lua")
Script.ReloadScript("Scripts/mods/dpevidence.lua")
Script.ReloadScript("Scripts/mods/dpburial.lua")

-- %line hands the console command handler the ENTIRE remainder of the line
-- as one string (e.g. "40 rumor"), not separate Lua arguments. Split it
-- ourselves on whitespace.
local function SplitArgs(argsLine)
    local parts = {}
    if argsLine == nil then return parts end
    for token in tostring(argsLine):gmatch("%S+") do
        table.insert(parts, token)
    end
    return parts
end

local function CaseReady()
    if DarkPassengerCase == nil then
        System.LogAlways("[DarkPassenger] DarkPassengerCase not found -- did Startup/case_state.lua load?")
        return false
    end
    return true
end

-- Runtime victim selection bridge.
-- The quest graph cannot assign a runtime Soul to a static alias. Lua therefore
-- marks one loaded regional NPC with a hidden AI buff tag; the graph resolves
-- that tag back to an I_Soul* from its compact regional SoulAsset pool.
DarkPassengerTarget = DarkPassengerTarget or {}
DarkPassengerTarget.TARGET_BUFF_GUID = "a6046bb4-57c1-4a95-b743-880aba11f5ba"
DarkPassengerTarget.ACTIVE_TARGET_SLOT_KEY = "dp_active_target_slot"
DarkPassengerTarget.QUEST_SELECTION_SCHEMA_KEY =
    "dp_quest_selection_schema"
DarkPassengerTarget.QUEST_SELECTION_SCHEMA_VERSION = 1
DarkPassengerTarget.MAX_SELECTION_ATTEMPTS = 3
DarkPassengerTarget.cases = DarkPassengerTarget.cases or {}
DarkPassengerTarget.questSelectionMigrationScheduled =
    DarkPassengerTarget.questSelectionMigrationScheduled or false

local function TargetLog(message)
    System.LogAlways("[DarkPassengerTarget] " .. tostring(message))
end

local function InternalEntityName(ent)
    local name = nil
    pcall(function() name = ent:GetName() end)
    return name
end

local function IsLivingCandidate(ent)
    if ent == nil or ent.id == nil or ent.soul == nil or ent.actor == nil then
        return false
    end
    if g_localActor == nil or ent.id == g_localActor.id then
        return false
    end
    if ent.actor.IsDead == nil then
        return false
    end

    local okDead, dead = pcall(function() return ent.actor:IsDead() end)
    return okDead and dead == false
end

local function IsPolicyCandidate(candidate, gameRegion, settlement)
    if candidate == nil then return false end
    if candidate.gameRegion ~= gameRegion then return false end
    if candidate.settlement ~= settlement then return false end
    if candidate.killableVerified ~= true then return false end
    if candidate.storyCritical == true then return false end
    if candidate.questCritical == true then return false end
    if candidate.immortal == true then return false end
    if candidate.dead == true then return false end
    return true
end

local function WeightedCandidate(eligible)
    local totalWeight = 0
    for _, entry in ipairs(eligible) do
        local weight = tonumber(entry.candidate.weight) or 0
        if weight > 0 then
            totalWeight = totalWeight + weight
        end
    end
    if totalWeight <= 0 then return nil end

    local roll = (random(1, 1000000) / 1000000) * totalWeight
    local cursor = 0
    for _, entry in ipairs(eligible) do
        local weight = tonumber(entry.candidate.weight) or 0
        if weight > 0 then
            cursor = cursor + weight
            if roll <= cursor then return entry end
        end
    end
    return eligible[#eligible]
end

local function HasStaticCandidate(gameRegion, settlement)
    if DarkPassengerGeneratedCandidates == nil then return false end
    for _, candidate in ipairs(DarkPassengerGeneratedCandidates) do
        if IsPolicyCandidate(candidate, gameRegion, settlement) then
            return true
        end
    end
    return false
end

local function FindCandidateBySlot(slot)
    local expectedSlot = tonumber(slot)
    if expectedSlot == nil or DarkPassengerGeneratedCandidates == nil then
        return nil
    end
    for _, candidate in ipairs(DarkPassengerGeneratedCandidates) do
        if tonumber(candidate.slot) == expectedSlot then
            return candidate
        end
    end
    return nil
end

local function ReadPersistedTargetSlot()
    if Variables == nil or Variables.GetGlobal == nil then return nil end
    local ok, slotOrError = pcall(function()
        return Variables.GetGlobal(
            DarkPassengerTarget.ACTIVE_TARGET_SLOT_KEY
        )
    end)
    local slot = ok and tonumber(slotOrError) or nil
    if slot == nil or slot <= 0 then return nil end
    return slot
end

local function RememberTarget(candidate)
    if candidate == nil or Variables == nil or Variables.SetGlobal == nil then
        return false
    end
    local ok, errorOrResult = pcall(function()
        return Variables.SetGlobal(
            DarkPassengerTarget.ACTIVE_TARGET_SLOT_KEY,
            tonumber(candidate.slot)
        )
    end)
    if not ok then
        TargetLog("target persistence failed: " .. tostring(errorOrResult))
    end
    return ok
end

local function ForgetPersistedTarget()
    if Variables == nil or Variables.SetGlobal == nil then return false end
    local ok, errorOrResult = pcall(function()
        return Variables.SetGlobal(
            DarkPassengerTarget.ACTIVE_TARGET_SLOT_KEY,
            0
        )
    end)
    if not ok then
        TargetLog("target persistence clear failed: " .. tostring(errorOrResult))
    end
    return ok
end

local function ReadQuestSelectionSchema()
    if Variables == nil or Variables.GetGlobal == nil then return 0 end
    local ok, versionOrError = pcall(function()
        return Variables.GetGlobal(
            DarkPassengerTarget.QUEST_SELECTION_SCHEMA_KEY
        )
    end)
    return ok and (tonumber(versionOrError) or 0) or 0
end

local function MarkQuestSelectionSchemaCurrent()
    if Variables == nil or Variables.SetGlobal == nil then return false end
    local ok, errorOrResult = pcall(function()
        return Variables.SetGlobal(
            DarkPassengerTarget.QUEST_SELECTION_SCHEMA_KEY,
            DarkPassengerTarget.QUEST_SELECTION_SCHEMA_VERSION
        )
    end)
    if not ok then
        TargetLog(
            "quest selection migration persistence failed: " ..
            tostring(errorOrResult)
        )
    end
    return ok
end

local function NeedsQuestSelectionMigration(candidate)
    return candidate ~= nil and
        candidate.gameRegion == "kutnohorsko" and
        candidate.settlement == "pritoky" and
        ReadQuestSelectionSchema() <
            DarkPassengerTarget.QUEST_SELECTION_SCHEMA_VERSION
end

local function HasTargetBuff(entity)
    if entity == nil or entity.soul == nil or
       entity.soul.HasBuffDebug == nil then
        return false
    end
    local ok, hasBuffOrError = pcall(function()
        return entity.soul:HasBuffDebug(
            DarkPassengerTarget.TARGET_BUFF_GUID
        )
    end)
    return ok and (hasBuffOrError == true or hasBuffOrError == 1)
end

function DarkPassengerTarget.ReapplyTargetBuffForQuestMigration(
    userData,
    timerId
)
    DarkPassengerTarget.questSelectionMigrationScheduled = false
    local expectedSlot =
        userData ~= nil and tonumber(userData.slot) or nil
    local candidate = FindCandidateBySlot(expectedSlot)
    local currentCandidate = DarkPassengerTarget.targetCandidate
    if candidate == nil or currentCandidate == nil or
       tonumber(currentCandidate.slot) ~= expectedSlot or
       not NeedsQuestSelectionMigration(candidate) then
        return false
    end

    local entity = System.GetEntityByName(candidate.entityName)
    if entity == nil or entity.soul == nil or
       entity.soul.AddBuff == nil then
        TargetLog(
            "quest selection migration deferred slot=" ..
            tostring(expectedSlot)
        )
        return false
    end

    local ok, handleOrError = pcall(function()
        return entity.soul:AddBuff(DarkPassengerTarget.TARGET_BUFF_GUID)
    end)
    if not ok or handleOrError == nil then
        TargetLog(
            "quest selection migration reapply failed slot=" ..
            tostring(expectedSlot) .. " error=" ..
            tostring(handleOrError)
        )
        return false
    end

    DarkPassengerTarget.targetBuffHandle = handleOrError
    if not MarkQuestSelectionSchemaCurrent() then return false end
    if DarkPassengerAreaBridge ~= nil and
       DarkPassengerAreaBridge.StartPolling ~= nil then
        DarkPassengerAreaBridge.StartPolling(
            "quest_selection_migration",
            candidate.gameRegion,
            candidate.settlement
        )
    end
    TargetLog(
        "quest selection migration complete slot=" ..
        tostring(expectedSlot)
    )
    return true
end

local function ScheduleQuestSelectionMigration(candidate, entity)
    if not NeedsQuestSelectionMigration(candidate) or
       DarkPassengerTarget.questSelectionMigrationScheduled then
        return false
    end
    if entity == nil or entity.soul == nil or
       entity.soul.RemoveAllBuffsByGuid == nil or
       Script == nil or Script.SetTimerForFunction == nil then
        return false
    end

    local removed, removeError = pcall(function()
        entity.soul:RemoveAllBuffsByGuid(
            DarkPassengerTarget.TARGET_BUFF_GUID
        )
    end)
    if not removed then
        TargetLog(
            "quest selection migration remove failed slot=" ..
            tostring(candidate.slot) .. " error=" ..
            tostring(removeError)
        )
        return false
    end

    DarkPassengerTarget.questSelectionMigrationScheduled = true
    local scheduled, timerOrError = pcall(function()
        return Script.SetTimerForFunction(
            1000,
            "DarkPassengerTarget.ReapplyTargetBuffForQuestMigration",
            { slot = tonumber(candidate.slot) }
        )
    end)
    if not scheduled then
        DarkPassengerTarget.questSelectionMigrationScheduled = false
        pcall(function()
            entity.soul:AddBuff(DarkPassengerTarget.TARGET_BUFF_GUID)
        end)
        TargetLog(
            "quest selection migration scheduling failed slot=" ..
            tostring(candidate.slot) .. " error=" ..
            tostring(timerOrError)
        )
        return false
    end

    TargetLog(
        "quest selection migration scheduled slot=" ..
        tostring(candidate.slot)
    )
    return true
end

local function IsRecoveredTargetBound(candidate, entity)
    if candidate == nil or entity == nil then return false end
    local currentCandidate = DarkPassengerTarget.targetCandidate
    local currentCase =
        DarkPassengerTarget.cases[candidate.gameRegion]
    local investigationCandidate =
        DarkPassengerInvestigation ~= nil and
        DarkPassengerInvestigation.candidate or nil
    return currentCandidate ~= nil and
        tonumber(currentCandidate.slot) == tonumber(candidate.slot) and
        DarkPassengerTarget.targetEntityId == entity.id and
        DarkPassengerTarget.activeRegion == candidate.gameRegion and
        currentCase ~= nil and
        currentCase.settlement == candidate.settlement and
        currentCase.status == "ACTIVE" and
        investigationCandidate ~= nil and
        tonumber(investigationCandidate.slot) == tonumber(candidate.slot) and
        DarkPassengerInvestigation.entity == entity
end

local function BindRecoveredTarget(candidate, entity)
    DarkPassengerTarget.targetCandidate = candidate
    DarkPassengerTarget.targetEntityId = entity ~= nil and entity.id or nil
    DarkPassengerTarget.targetName =
        entity ~= nil and (InternalEntityName(entity) or "?") or nil
    DarkPassengerTarget.targetBuffHandle = nil
    DarkPassengerTarget.activeRegion = candidate.gameRegion
    DarkPassengerTarget.cases[candidate.gameRegion] = {
        settlement = candidate.settlement,
        target = candidate,
        status = "ACTIVE",
    }
    RememberTarget(candidate)
    DarkPassengerInvestigation.Restore(candidate, entity)
    ScheduleQuestSelectionMigration(candidate, entity)
    if DarkPassengerAreaBridge ~= nil and
       DarkPassengerAreaBridge.StartPolling ~= nil then
        DarkPassengerAreaBridge.StartPolling(
            "target_restore",
            candidate.gameRegion,
            candidate.settlement
        )
    end
    return true
end

function DarkPassengerTarget.RestoreExisting(gameRegion)
    local runtimeCandidate = DarkPassengerTarget.targetCandidate
    if runtimeCandidate ~= nil and
       runtimeCandidate.gameRegion == gameRegion then
        local runtimeEntity =
            System.GetEntityByName(runtimeCandidate.entityName)
        if HasTargetBuff(runtimeEntity) then
            if IsRecoveredTargetBound(runtimeCandidate, runtimeEntity) then
                ScheduleQuestSelectionMigration(
                    runtimeCandidate,
                    runtimeEntity
                )
                return true
            end
            BindRecoveredTarget(runtimeCandidate, runtimeEntity)
            return true
        end
    end

    if DarkPassengerGeneratedCandidates ~= nil then
        for _, candidate in ipairs(DarkPassengerGeneratedCandidates) do
            if candidate.gameRegion == gameRegion then
                local entity = System.GetEntityByName(candidate.entityName)
                if HasTargetBuff(entity) then
                    if runtimeCandidate ~= nil and
                       tonumber(runtimeCandidate.slot) ==
                           tonumber(candidate.slot) then
                        BindRecoveredTarget(runtimeCandidate, entity)
                        return true
                    end
                    BindRecoveredTarget(candidate, entity)
                    if CaseReady() and entity ~= nil then
                        DarkPassengerCase.Open(
                            entity.id,
                            InternalEntityName(entity) or "?",
                            candidate.settlement
                        )
                    end
                    TargetLog(
                        "recovered tagged quest target region=" ..
                        tostring(gameRegion) ..
                        " slot=" .. tostring(candidate.slot)
                    )
                    return true
                end
            end
        end
    end

    if runtimeCandidate ~= nil and runtimeCandidate.gameRegion == gameRegion then
        BindRecoveredTarget(
            runtimeCandidate,
            System.GetEntityByName(runtimeCandidate.entityName)
        )
        return true
    end

    local persistedCandidate =
        FindCandidateBySlot(ReadPersistedTargetSlot())
    if persistedCandidate ~= nil and
       persistedCandidate.gameRegion == gameRegion then
        local persistedEntity =
            System.GetEntityByName(persistedCandidate.entityName)
        BindRecoveredTarget(persistedCandidate, persistedEntity)
        TargetLog(
            "preserved persisted quest target region=" ..
            tostring(gameRegion) ..
            " slot=" .. tostring(persistedCandidate.slot) ..
            " loaded=" .. tostring(persistedEntity ~= nil)
        )
        return true
    end

    return false
end

local function OrderedSettlements(gameRegion, playerPosition)
    local ordered = {}
    if DarkPassengerGeneratedSettlements == nil or playerPosition == nil then
        return ordered
    end

    for _, settlement in ipairs(DarkPassengerGeneratedSettlements) do
        if settlement.gameRegion == gameRegion and
           HasStaticCandidate(gameRegion, settlement.id) then
            local dx = playerPosition.x - settlement.x
            local dy = playerPosition.y - settlement.y
            local distanceSquared = dx * dx + dy * dy
            table.insert(ordered, {
                settlement = settlement,
                distanceSquared = distanceSquared,
            })
        end
    end

    table.sort(ordered, function(left, right)
        if left.distanceSquared == right.distanceSquared then
            return left.settlement.id < right.settlement.id
        end
        return left.distanceSquared < right.distanceSquared
    end)
    return ordered
end

function DarkPassengerTarget.Clear()
    local previousId = DarkPassengerTarget.targetEntityId
    local previous = previousId ~= nil and System.GetEntity(previousId) or nil
    DarkPassengerInvestigation.Clear(previous)
    if previous ~= nil and previous.soul ~= nil then
        pcall(function()
            previous.soul:RemoveAllBuffsByGuid(
                DarkPassengerTarget.TARGET_BUFF_GUID
            )
        end)
    end
    DarkPassengerTarget.targetEntityId = nil
    DarkPassengerTarget.targetName = nil
    DarkPassengerTarget.targetCandidate = nil
    DarkPassengerTarget.targetBuffHandle = nil
    ForgetPersistedTarget()
    return true
end

function DarkPassengerTarget.ResetCase(gameRegion)
    local targetBelongsToRegion =
        DarkPassengerTarget.targetCandidate ~= nil and
        DarkPassengerTarget.targetCandidate.gameRegion == gameRegion
    DarkPassengerTarget.cases[gameRegion] = nil
    if DarkPassengerTarget.activeRegion == gameRegion then
        DarkPassengerTarget.activeRegion = nil
    end
    if targetBelongsToRegion then
        return DarkPassengerTarget.Clear()
    end
    return true
end

function DarkPassengerTarget.Select(gameRegion, settlement)
    if g_localActor == nil then
        TargetLog("select failed: g_localActor is nil")
        return false
    end

    DarkPassengerTarget.Clear()

    if DarkPassengerGeneratedCandidates == nil then
        TargetLog("select failed: generated candidate catalogue is unavailable")
        return false
    end

    local eligible = {}
    for _, candidate in ipairs(DarkPassengerGeneratedCandidates) do
        if IsPolicyCandidate(candidate, gameRegion, settlement) then
            local ent = System.GetEntityByName(candidate.entityName)
            if IsLivingCandidate(ent) then
                table.insert(eligible, {
                    candidate = candidate,
                    entity = ent,
                })
            end
        end
    end

    if #eligible == 0 then
        TargetLog(
            "select failed: no eligible living candidate region=" ..
            tostring(gameRegion) .. " settlement=" .. tostring(settlement)
        )
        return false
    end

    local attempts = 0
    local selectedEntry = nil
    local selectedBuffHandle = nil
    while attempts < DarkPassengerTarget.MAX_SELECTION_ATTEMPTS and
          #eligible > 0 do
        attempts = attempts + 1
        local candidateEntry = WeightedCandidate(eligible)
        if candidateEntry == nil then break end

        local tagged, buffHandleOrError = pcall(function()
            return candidateEntry.entity.soul:AddBuff(
                DarkPassengerTarget.TARGET_BUFF_GUID
            )
        end)
        if tagged and buffHandleOrError ~= nil then
            selectedEntry = candidateEntry
            selectedBuffHandle = buffHandleOrError
            break
        end

        TargetLog(
            "tag attempt=" .. tostring(attempts) ..
            " failed candidate=" ..
            tostring(candidateEntry.candidate.entityName) ..
            " error=" .. tostring(buffHandleOrError)
        )
        for index, entry in ipairs(eligible) do
            if entry == candidateEntry then
                table.remove(eligible, index)
                break
            end
        end
    end

    if selectedEntry == nil then
        TargetLog(
            "select failed after attempts=" .. tostring(attempts) ..
            " region=" .. tostring(gameRegion) ..
            " settlement=" .. tostring(settlement)
        )
        return false
    end

    local selected = selectedEntry.entity
    local selectedCandidate = selectedEntry.candidate
    local displayName = InternalEntityName(selected) or "?"
    pcall(function()
        local localizedName = EntityUtils.GetName(selected)
        if localizedName ~= nil then displayName = localizedName end
    end)

    DarkPassengerTarget.targetEntityId = selected.id
    DarkPassengerTarget.targetName = displayName
    DarkPassengerTarget.targetCandidate = selectedCandidate
    DarkPassengerTarget.targetBuffHandle = selectedBuffHandle
    DarkPassengerTarget.activeRegion = gameRegion
    DarkPassengerTarget.cases[gameRegion] = {
        settlement = settlement,
        target = selectedCandidate,
        status = "ACTIVE",
    }
    RememberTarget(selectedCandidate)
    MarkQuestSelectionSchemaCurrent()
    DarkPassengerInvestigation.Open(selectedCandidate, selected)
    if CaseReady() then
        DarkPassengerCase.Open(selected.id, displayName, settlement)
    end
    if DarkPassengerAreaBridge ~= nil and
       DarkPassengerAreaBridge.StartPolling ~= nil then
        DarkPassengerAreaBridge.StartPolling(
            "target_select",
            gameRegion,
            settlement
        )
    end

    TargetLog(
        "selected gameRegion=" .. tostring(gameRegion) ..
        " settlement=" .. tostring(settlement) ..
        " eligible=" .. tostring(#eligible) ..
        " slot=" .. tostring(selectedCandidate.slot) ..
        " alias=" .. tostring(selectedCandidate.alias) ..
        " target=" .. tostring(displayName) ..
        " id=" .. tostring(selected.id)
    )
    return true
end

function DarkPassengerTarget.SelectNearest(gameRegion)
    if g_localActor == nil or g_localActor.GetWorldPos == nil then
        TargetLog("nearest selection failed: player position unavailable")
        return false
    end

    if DarkPassengerTarget.RestoreExisting(gameRegion) then return true end

    local settlementOverride =
        DarkPassengerInvestigation.GetSettlementOverride(gameRegion)
    if settlementOverride ~= nil then
        DarkPassengerTarget.activeRegion = gameRegion
        DarkPassengerTarget.cases[gameRegion] = {
            settlement = settlementOverride,
            target = nil,
            status = "SELECTING",
        }
        TargetLog(
            "investigation settlement override region=" ..
            tostring(gameRegion) ..
            " settlement=" .. tostring(settlementOverride)
        )
        return DarkPassengerTarget.Select(gameRegion, settlementOverride)
    end

    local existingCase = DarkPassengerTarget.cases[gameRegion]
    if existingCase ~= nil and
       existingCase.settlement ~= nil and
       (existingCase.status == "SELECTING" or existingCase.status == "ACTIVE") then
        return DarkPassengerTarget.Select(gameRegion, existingCase.settlement)
    end

    if DarkPassengerTarget.activeRegion ~= nil and
       DarkPassengerTarget.activeRegion ~= gameRegion then
        local activeCase =
            DarkPassengerTarget.cases[DarkPassengerTarget.activeRegion]
        local activeEntity =
            DarkPassengerTarget.targetEntityId ~= nil and
            System.GetEntity(DarkPassengerTarget.targetEntityId) or nil
        if activeCase ~= nil and
           activeCase.status == "ACTIVE" and
           IsLivingCandidate(activeEntity) then
            TargetLog(
                "nearest selection deferred: active case region=" ..
                tostring(DarkPassengerTarget.activeRegion)
            )
            return false
        end
    end

    local playerPosition = g_localActor:GetWorldPos()
    local ordered = OrderedSettlements(gameRegion, playerPosition)
    if #ordered == 0 then
        TargetLog(
            "nearest selection failed: no safe settlement region=" ..
            tostring(gameRegion)
        )
        return false
    end

    local chosen = ordered[1]
    DarkPassengerTarget.activeRegion = gameRegion
    DarkPassengerTarget.cases[gameRegion] = {
        settlement = chosen.settlement.id,
        target = nil,
        status = "SELECTING",
    }
    TargetLog(
        "nearest settlement region=" .. tostring(gameRegion) ..
        " settlement=" .. tostring(chosen.settlement.id) ..
        " distanceSquared=" .. tostring(chosen.distanceSquared)
    )
    return DarkPassengerTarget.Select(gameRegion, chosen.settlement.id)
end

function DarkPassengerTarget.Revalidate(gameRegion, settlement, slot)
    local expectedSlot = tonumber(slot)
    local candidate = DarkPassengerTarget.targetCandidate
    if candidate == nil or tonumber(candidate.slot) ~= expectedSlot then
        return false
    end

    local currentEntity = DarkPassengerTarget.targetEntityId ~= nil and
        System.GetEntity(DarkPassengerTarget.targetEntityId) or nil
    if IsPolicyCandidate(candidate, gameRegion, settlement) and
       IsLivingCandidate(currentEntity) then
        return true
    end

    TargetLog(
        "revalidation failed slot=" .. tostring(expectedSlot) ..
        "; clearing target and requesting bounded replacement"
    )
    DarkPassengerTarget.Clear()
    return DarkPassengerTarget.Select(gameRegion, settlement)
end

function DarkPassengerTarget.OnTargetDeath(gameRegion, settlement, slot)
    local currentCase = CaseReady() and DarkPassengerCase.GetCurrent() or nil
    local expectedSlot = tonumber(slot)
    local candidate = FindCandidateBySlot(expectedSlot)
    if candidate == nil then
        TargetLog("unknown target death slot=" .. tostring(expectedSlot))
        return false
    end
    if DarkPassengerTarget.targetCandidate == nil or
       tonumber(DarkPassengerTarget.targetCandidate.slot) ~= expectedSlot then
        TargetLog(
            "rebinding target death from stale slot=" ..
            tostring(
                DarkPassengerTarget.targetCandidate ~= nil and
                DarkPassengerTarget.targetCandidate.slot or "nil"
            ) ..
            " to graph slot=" .. tostring(expectedSlot)
        )
        BindRecoveredTarget(
            candidate,
            System.GetEntityByName(candidate.entityName)
        )
        currentCase = CaseReady() and DarkPassengerCase.GetCurrent() or nil
    end
    local targetEntity =
        System.GetEntityByName(candidate.entityName)
    if targetEntity == nil and candidate ~= nil then
        targetEntity =
            DarkPassengerTarget.targetEntityId ~= nil and
            System.GetEntity(DarkPassengerTarget.targetEntityId) or nil
    end
    local deathPosition = nil
    if targetEntity ~= nil and targetEntity.GetWorldPos ~= nil then
        local ok, positionOrError = pcall(function()
            return targetEntity:GetWorldPos()
        end)
        if ok then deathPosition = positionOrError end
    end
    if deathPosition == nil and g_localActor ~= nil and
       g_localActor.GetWorldPos ~= nil then
        local ok, positionOrError = pcall(function()
            return g_localActor:GetWorldPos()
        end)
        if ok then deathPosition = positionOrError end
    end
    DarkPassengerInvestigation.OnTargetDeath()
    if deathPosition == nil or DarkPassengerAftermath == nil or
       DarkPassengerAftermath.Begin == nil then
        TargetLog("target death aftermath unavailable slot=" .. tostring(expectedSlot))
        return false
    end

    local attributedToHenry =
        currentCase ~= nil and currentCase.state == "RESOLVED_CORRECT"
    TargetLog(
        "target death starts aftermath slot=" .. tostring(expectedSlot) ..
        " attributedToHenry=" .. tostring(attributedToHenry)
    )
    local started = DarkPassengerAftermath.Begin(
        gameRegion,
        settlement,
        expectedSlot,
        deathPosition.x,
        deathPosition.y,
        deathPosition.z,
        DarkPassengerAftermath.DEFAULT_ZONE_RADIUS
    )
    DarkPassengerTarget.Clear()
    return started
end

function DarkPassengerTarget.SelectPritoky()
    return DarkPassengerTarget.SelectNearest("kutnohorsko")
end

function DarkPassengerTarget.SelectCommand(argsLine)
    local parts = SplitArgs(argsLine)
    local gameRegion = parts[1] or "kutnohorsko"
    local settlement = parts[2] or
        DarkPassengerInvestigation.GetSettlementOverride(gameRegion)
    return DarkPassengerTarget.Select(gameRegion, settlement)
end

function DarkPassengerTarget.ValidateCommand(argsLine)
    local parts = SplitArgs(argsLine)
    local gameRegion = parts[1] or "kutnohorsko"
    local settlement = parts[2] or
        DarkPassengerInvestigation.GetSettlementOverride(gameRegion)
    return DarkPassengerTarget.Revalidate(
        gameRegion,
        settlement,
        parts[3]
    )
end

function DarkPassengerTarget.DeathCommand(argsLine)
    local parts = SplitArgs(argsLine)
    local gameRegion = parts[1] or "kutnohorsko"
    local settlement = parts[2] or
        DarkPassengerInvestigation.GetSettlementOverride(gameRegion)
    return DarkPassengerTarget.OnTargetDeath(
        gameRegion,
        settlement,
        parts[3]
    )
end

function DarkPassengerTarget.QuestStatus()
    local ok, activeOrError = pcall(function()
        return QuestSystem.IsQuestActive("dark_within_k")
    end)
    TargetLog(
        "quest status name=dark_within_k ok=" .. tostring(ok) ..
        " active=" .. tostring(ok and activeOrError or nil) ..
        " error=" .. tostring(ok and nil or activeOrError)
    )
    return ok and activeOrError == true
end

DarkPassengerTarget.QUEST_BY_REGION = {
    kutnohorsko = "dark_within_k",
    trosecko = "dark_within_t",
}

function DarkPassengerTarget.IsRegionQuestActive(gameRegion)
    local questName = DarkPassengerTarget.QUEST_BY_REGION[gameRegion]
    if questName == nil or QuestSystem == nil or
       QuestSystem.IsQuestActive == nil then
        return false
    end
    local ok, activeOrError = pcall(function()
        return QuestSystem.IsQuestActive(questName)
    end)
    return ok and activeOrError == true
end

function DarkPassengerTarget.DumpActiveObjectives()
    local questApi = QuestSystem or Quest
    if questApi == nil or questApi.GetActiveObjectives == nil then
        TargetLog(
            "active objectives unavailable QuestSystem=" ..
            tostring(type(QuestSystem)) ..
            " Quest=" .. tostring(type(Quest))
        )
        return false
    end
    for _, questName in ipairs({ "dark_within_k", "dark_within_t" }) do
        local ok, objectivesOrError = pcall(function()
            return questApi.GetActiveObjectives(questName)
        end)
        if not ok then
            TargetLog(
                "active objectives name=" .. tostring(questName) ..
                " error=" .. tostring(objectivesOrError)
            )
        elseif type(objectivesOrError) ~= "table" then
            TargetLog(
                "active objectives name=" .. tostring(questName) ..
                " value=" .. tostring(objectivesOrError)
            )
        else
            local values = {}
            for key, value in pairs(objectivesOrError) do
                table.insert(
                    values,
                    tostring(key) .. "=" .. tostring(value)
                )
            end
            table.sort(values)
            TargetLog(
                "active objectives name=" .. tostring(questName) ..
                " values=" .. table.concat(values, ",")
            )
        end
    end
    return true
end

DarkPassengerAreaBridge = DarkPassengerAreaBridge or {}
DarkPassengerAreaBridge.POLL_INTERVAL_MS = 500
DarkPassengerAreaBridge.MAX_ATTEMPTS = 120
DarkPassengerAreaBridge.pollGeneration =
    DarkPassengerAreaBridge.pollGeneration or 0

local function AreaLog(message)
    if System ~= nil and System.LogAlways ~= nil then
        System.LogAlways("[DarkPassengerArea] " .. tostring(message))
    end
end

local function HasNamedLink(source, target, expectedName)
    local okCount, linkCount = pcall(function()
        return source:CountLinks()
    end)
    if not okCount or type(linkCount) ~= "number" then
        return false
    end
    for index = 0, linkCount - 1 do
        local okLink, linkTarget, linkName = pcall(function()
            return source:GetLink(index)
        end)
        if okLink and linkTarget ~= nil and linkName == expectedName and
           linkTarget.id == target.id then
            return true
        end
    end
    return false
end

function DarkPassengerAreaBridge.EnsureNamedLink(
    source,
    target,
    linkName,
    label
)
    if source == nil or source.id == nil or target == nil or
       target.id == nil or source.CountLinks == nil or
       source.GetLink == nil or source.CreateLink == nil or
       linkName == nil or linkName == "" then
        AreaLog(tostring(label) .. " link API unavailable")
        return false
    end
    if HasNamedLink(source, target, linkName) then
        return true
    end
    local okCreate, createError = pcall(function()
        source:CreateLink(linkName, target.id)
    end)
    if not okCreate then
        AreaLog(tostring(label) .. " CreateLink failed error=" .. tostring(createError))
        return false
    end
    if HasNamedLink(source, target, linkName) then
        AreaLog("linked " .. tostring(label))
        return true
    end
    AreaLog(tostring(label) .. " CreateLink returned without verification")
    return false
end

function DarkPassengerAreaBridge.EnsureModuleLink(source, target, label)
    return DarkPassengerAreaBridge.EnsureNamedLink(
        source,
        target,
        "module",
        label
    )
end

function DarkPassengerAreaBridge.EnsureSettlementLinked(gameRegion, settlement)
    if System == nil or System.GetEntityByName == nil then
        return false
    end
    if DarkPassengerInvestigationAreaCatalog == nil or
       DarkPassengerInvestigationAreaCatalog.schemaVersion ~= 1 or
       DarkPassengerInvestigationAreaCatalog.regions == nil then
        AreaLog("generated area catalog unavailable")
        return false
    end

    local region =
        DarkPassengerInvestigationAreaCatalog.regions[gameRegion]
    if region == nil or region.settlements == nil then
        AreaLog("unknown region=" .. tostring(gameRegion))
        return false
    end
    local settlementEntry = region.settlements[settlement]
    if settlementEntry == nil or settlementEntry.alias == nil or
       type(settlementEntry.areas) ~= "table" or
       #settlementEntry.areas == 0 then
        AreaLog(
            "unknown settlement=" .. tostring(gameRegion) .. "/" ..
            tostring(settlement)
        )
        return false
    end

    local levelHolder = System.GetEntityByName(region.levelHolderName)
    local holder = System.GetEntityByName(region.questHolderName)
    if levelHolder == nil or levelHolder.id == nil or
       holder == nil or holder.id == nil then
        return false
    end

    local moduleLinked = DarkPassengerAreaBridge.EnsureModuleLink(
        levelHolder,
        holder,
        tostring(gameRegion) .. " LevelHolder to Quest holder"
    )
    if not moduleLinked then
        return false
    end

    local aliases = { settlementEntry.alias }
    for _, legacyAlias in ipairs(settlementEntry.legacyAliases or {}) do
        table.insert(aliases, legacyAlias)
    end
    for _, alias in ipairs(aliases) do
        local linkName = "asset['" .. alias .. "']"
        for _, area in ipairs(settlementEntry.areas) do
            local target = System.GetEntityByName(area.name)
            if target == nil or target.id == nil then
                return false
            end
            local areaLinked = DarkPassengerAreaBridge.EnsureNamedLink(
                holder,
                target,
                linkName,
                "Quest holder to area " .. tostring(area.name) ..
                    " alias=" .. tostring(alias)
            )
            if not areaLinked then
                return false
            end
        end
    end

    return true
end

local function ResolveActiveAreaCase()
    local persistedCandidate = FindCandidateBySlot(ReadPersistedTargetSlot())
    if persistedCandidate ~= nil then
        return persistedCandidate.gameRegion, persistedCandidate.settlement
    end

    local runtimeCandidate =
        DarkPassengerTarget ~= nil and
        DarkPassengerTarget.targetCandidate or nil
    if runtimeCandidate ~= nil then
        return runtimeCandidate.gameRegion, runtimeCandidate.settlement
    end

    local activeRegion =
        DarkPassengerTarget ~= nil and
        DarkPassengerTarget.activeRegion or nil
    local activeCase =
        activeRegion ~= nil and
        DarkPassengerTarget.cases[activeRegion] or nil
    if activeCase ~= nil and activeCase.settlement ~= nil and
       (activeCase.status == "SELECTING" or activeCase.status == "ACTIVE") then
        return activeRegion, activeCase.settlement
    end
    return nil, nil
end

local function ScheduleAreaLinkPoll(
    generation,
    attempt,
    gameRegion,
    settlement
)
    if Script == nil or Script.SetTimerForFunction == nil then
        AreaLog("poll unavailable: Script.SetTimerForFunction is nil")
        return false
    end
    local ok, timerOrError = pcall(function()
        return Script.SetTimerForFunction(
            DarkPassengerAreaBridge.POLL_INTERVAL_MS,
            "DarkPassengerAreaBridge.Poll",
            {
                generation = generation,
                attempt = attempt,
                gameRegion = gameRegion,
                settlement = settlement,
            }
        )
    end)
    if not ok then
        AreaLog("poll scheduling failed error=" .. tostring(timerOrError))
        return false
    end
    return true
end

function DarkPassengerAreaBridge.Poll(userData, timerId)
    local generation =
        userData ~= nil and tonumber(userData.generation) or nil
    local attempt = userData ~= nil and tonumber(userData.attempt) or 1
    local gameRegion = userData ~= nil and userData.gameRegion or nil
    local settlement = userData ~= nil and userData.settlement or nil
    if generation ~= DarkPassengerAreaBridge.pollGeneration then
        return
    end
    if DarkPassengerAreaBridge.EnsureSettlementLinked(gameRegion, settlement) then
        AreaLog(
            "ready settlement=" .. tostring(gameRegion) .. "/" ..
            tostring(settlement) .. " attempt=" .. tostring(attempt)
        )
        return
    end
    if attempt >= DarkPassengerAreaBridge.MAX_ATTEMPTS then
        AreaLog("poll exhausted attempts=" .. tostring(attempt))
        return
    end
    ScheduleAreaLinkPoll(generation, attempt + 1, gameRegion, settlement)
end

function DarkPassengerAreaBridge.StartPolling(reason, gameRegion, settlement)
    DarkPassengerAreaBridge.pollGeneration =
        DarkPassengerAreaBridge.pollGeneration + 1
    local generation = DarkPassengerAreaBridge.pollGeneration
    if gameRegion == nil or settlement == nil then
        gameRegion, settlement = ResolveActiveAreaCase()
    end
    if gameRegion == nil or settlement == nil then
        AreaLog(
            "poll skipped reason=" .. tostring(reason) ..
            " active settlement unavailable"
        )
        return false
    end
    AreaLog(
        "poll started reason=" .. tostring(reason) ..
        " settlement=" .. tostring(gameRegion) .. "/" ..
        tostring(settlement) ..
        " generation=" .. tostring(generation)
    )
    if DarkPassengerAreaBridge.EnsureSettlementLinked(gameRegion, settlement) then
        AreaLog("ready attempt=0")
        return true
    end
    return ScheduleAreaLinkPoll(generation, 1, gameRegion, settlement)
end

DarkPassengerAreaBridge.StartPolling("script_load")

DarkPassengerQuestBridge = DarkPassengerQuestBridge or {}
DarkPassengerQuestBridge.REQUESTS = {
    {
        region = "kutnohorsko",
        context = "dp_select_victim_kutnohorsko",
        deathContext = "dp_target_dead_kutnohorsko",
        rumorContext = "dp_rumor_heard_kutnohorsko",
        witnessContext = "dp_witness_heard_kutnohorsko",
    },
    {
        region = "trosecko",
        context = "dp_select_victim_trosecko",
        deathContext = "dp_target_dead_trosecko",
        rumorContext = "dp_rumor_heard_trosecko",
        witnessContext = "dp_witness_heard_trosecko",
    },
}
DarkPassengerQuestBridge.KILL_CONTEXT = "dp_ordinary_human_kill"
DarkPassengerQuestBridge.POLL_INTERVAL_MS = 1000
DarkPassengerQuestBridge.pollGeneration =
    DarkPassengerQuestBridge.pollGeneration or 0

local function SplitBridgeAction(action)
    local parts = {}
    if action == nil then return parts end
    for part in tostring(action):gmatch("[^|]+") do
        table.insert(parts, part)
    end
    return parts
end

function DarkPassengerQuestBridge.Call(action)
    local parts = SplitBridgeAction(action)
    local command = parts[1]
    TargetLog("quest bridge action=" .. tostring(action))

    if command == "select" then
        return DarkPassengerTarget.Select(parts[2], parts[3])
    end
    if command == "validate" then
        return DarkPassengerTarget.Revalidate(parts[2], parts[3], parts[4])
    end
    if command == "death" then
        return DarkPassengerTarget.OnTargetDeath(parts[2], parts[3], parts[4])
    end

    TargetLog("unknown quest bridge action: " .. tostring(action))
    return false
end

local function ScheduleSelectionRequestPoll()
    if Script == nil or Script.SetTimerForFunction == nil then
        TargetLog("quest-context poll unavailable: Script.SetTimerForFunction is nil")
        return false
    end

    local generation = DarkPassengerQuestBridge.pollGeneration
    local ok, timerOrError = pcall(function()
        return Script.SetTimerForFunction(
            DarkPassengerQuestBridge.POLL_INTERVAL_MS,
            "DarkPassengerQuestBridge.PollSelectionRequest",
            { generation = generation }
        )
    end)
    if not ok then
        TargetLog("quest-context poll scheduling failed: " .. tostring(timerOrError))
        return false
    end
    return true
end

function DarkPassengerQuestBridge.StartPolling(reason)
    if reason ~= "first_player_action" then
        DarkPassengerQuestBridge.playerActionRestartRequested = false
    end
    DarkPassengerQuestBridge.pollGeneration =
        DarkPassengerQuestBridge.pollGeneration + 1
    DarkPassengerQuestBridge.pollAliveLoggedGeneration = nil
    DarkPassengerQuestBridge.lastRequestStates = {}
    DarkPassengerQuestBridge.lastDeathStates = {}
    DarkPassengerQuestBridge.lastKillState = nil
    DarkPassengerQuestBridge.lastRumorStates = {}
    DarkPassengerQuestBridge.lastWitnessStates = {}
    TargetLog(
        "quest-context polling started reason=" .. tostring(reason) ..
        " generation=" .. tostring(DarkPassengerQuestBridge.pollGeneration)
    )
    return ScheduleSelectionRequestPoll()
end

function DarkPassengerQuestBridge.EnsurePollingFromPlayerAction(...)
    if DarkPassengerQuestBridge.pollAliveLoggedGeneration ==
       DarkPassengerQuestBridge.pollGeneration then
        return false
    end
    if DarkPassengerQuestBridge.playerActionRestartRequested then
        return false
    end

    DarkPassengerQuestBridge.playerActionRestartRequested = true
    local started =
        DarkPassengerQuestBridge.StartPolling("first_player_action")
    if not started then
        DarkPassengerQuestBridge.playerActionRestartRequested = false
    end
    return started
end

function DarkPassengerQuestBridge.PollSelectionRequest(userData, timerId)
    local requestedGeneration =
        userData ~= nil and tonumber(userData.generation) or nil
    if requestedGeneration ~= DarkPassengerQuestBridge.pollGeneration then
        return
    end

    if DarkPassengerQuestBridge.pollAliveLoggedGeneration ~=
       requestedGeneration then
        DarkPassengerQuestBridge.pollAliveLoggedGeneration =
            requestedGeneration
        TargetLog(
            "quest-context poll alive generation=" ..
            tostring(requestedGeneration)
        )
    end

    local playerEntity = System.GetEntityByName("dude")
    local hasKillRequest = false
    if playerEntity ~= nil and
       playerEntity.soul ~= nil and
       playerEntity.soul.HasScriptContext ~= nil then
        local ok, contextOrError = pcall(function()
            return playerEntity.soul:HasScriptContext(
                DarkPassengerQuestBridge.KILL_CONTEXT
            )
        end)
        if ok then
            hasKillRequest = contextOrError == true or contextOrError == 1
        else
            TargetLog(
                "ordinary-kill context check failed error=" ..
                tostring(contextOrError)
            )
        end
    end
    local previousKillState = DarkPassengerQuestBridge.lastKillState
    local killRequestBecameActive =
        hasKillRequest and previousKillState ~= true
    if previousKillState ~= hasKillRequest then
        DarkPassengerQuestBridge.lastKillState = hasKillRequest
        TargetLog(
            "ordinary-kill context active=" .. tostring(hasKillRequest)
        )
    end
    if killRequestBecameActive and
       DarkPassengerTest.OnOrdinaryHumanKillObserved ~= nil then
        DarkPassengerTest.OnOrdinaryHumanKillObserved()
    end

    for _, request in ipairs(DarkPassengerQuestBridge.REQUESTS) do
        local hasRequest = false
        if playerEntity ~= nil and
           playerEntity.soul ~= nil and
           playerEntity.soul.HasScriptContext ~= nil then
            local ok, contextOrError = pcall(function()
                return playerEntity.soul:HasScriptContext(request.context)
            end)
            if ok then
                hasRequest = contextOrError == true or contextOrError == 1
            else
                TargetLog(
                    "quest-context check failed region=" ..
                    tostring(request.region) ..
                    " error=" .. tostring(contextOrError)
                )
            end
        end

        local previousState =
            DarkPassengerQuestBridge.lastRequestStates[request.region]
        local requestBecameActive =
            hasRequest and previousState ~= true
        local requestBecameInactive =
            not hasRequest and previousState == true

        if previousState ~= hasRequest then
            DarkPassengerQuestBridge.lastRequestStates[request.region] =
                hasRequest
            TargetLog(
                "quest-context request region=" ..
                tostring(request.region) ..
                " active=" .. tostring(hasRequest)
            )
        end

        local hasDeathRequest = false
        if playerEntity ~= nil and
           playerEntity.soul ~= nil and
           playerEntity.soul.HasScriptContext ~= nil then
            local ok, contextOrError = pcall(function()
                return playerEntity.soul:HasScriptContext(
                    request.deathContext
                )
            end)
            if ok then
                hasDeathRequest =
                    contextOrError == true or contextOrError == 1
            else
                TargetLog(
                    "target-death context check failed region=" ..
                    tostring(request.region) ..
                    " error=" .. tostring(contextOrError)
                )
            end
        end
        local previousDeathState =
            DarkPassengerQuestBridge.lastDeathStates[request.region]
        local deathRequestBecameActive =
            hasDeathRequest and previousDeathState ~= true
        if previousDeathState ~= hasDeathRequest then
            DarkPassengerQuestBridge.lastDeathStates[request.region] =
                hasDeathRequest
            TargetLog(
                "target-death context region=" ..
                tostring(request.region) ..
                " active=" .. tostring(hasDeathRequest)
            )
        end

        local hasRumorRequest = false
        if request.rumorContext ~= nil and
           playerEntity ~= nil and
           playerEntity.soul ~= nil and
           playerEntity.soul.HasScriptContext ~= nil then
            local ok, contextOrError = pcall(function()
                return playerEntity.soul:HasScriptContext(
                    request.rumorContext
                )
            end)
            if ok then
                hasRumorRequest =
                    contextOrError == true or contextOrError == 1
            else
                TargetLog(
                    "rumor context check failed region=" ..
                    tostring(request.region) ..
                    " error=" .. tostring(contextOrError)
                )
            end
        end
        local previousRumorState =
            DarkPassengerQuestBridge.lastRumorStates[request.region]
        if previousRumorState ~= hasRumorRequest then
            DarkPassengerQuestBridge.lastRumorStates[request.region] =
                hasRumorRequest
            TargetLog(
                "rumor context region=" .. tostring(request.region) ..
                " active=" .. tostring(hasRumorRequest)
            )
        end

        if hasRequest then
            local existingTargetPreserved =
                DarkPassengerTarget.RestoreExisting(request.region)
            if not existingTargetPreserved then
                if requestBecameActive then
                    DarkPassengerTarget.ResetCase(request.region)
                end
                TargetLog(
                    "quest context requested victim selection region=" ..
                    tostring(request.region) ..
                    " risingEdge=" .. tostring(requestBecameActive)
                )
                DarkPassengerTarget.SelectNearest(request.region)
            end
        elseif deathRequestBecameActive then
            local candidate = DarkPassengerTarget.targetCandidate
            if candidate ~= nil and
               candidate.gameRegion == request.region then
                DarkPassengerTarget.OnTargetDeath(
                    request.region,
                    candidate.settlement,
                    candidate.slot
                )
            else
                TargetLog(
                    "target-death context has no synchronized target region=" ..
                    tostring(request.region)
                )
            end
        elseif DarkPassengerTarget.targetCandidate ~= nil and
               not DarkPassengerTarget.IsRegionQuestActive(
                   request.region
               ) then
            DarkPassengerTarget.ResetCase(request.region)
        end

        if hasRumorRequest and
           DarkPassengerEvidence ~= nil and
           DarkPassengerEvidence.OnRumorCompleted ~= nil then
            DarkPassengerEvidence.OnRumorCompleted(request.region)
        end

        local hasWitnessRequest = false
        if request.witnessContext ~= nil and
           playerEntity ~= nil and
           playerEntity.soul ~= nil and
           playerEntity.soul.HasScriptContext ~= nil then
            local ok, contextOrError = pcall(function()
                return playerEntity.soul:HasScriptContext(
                    request.witnessContext
                )
            end)
            if ok then
                hasWitnessRequest =
                    contextOrError == true or contextOrError == 1
            else
                TargetLog(
                    "witness context check failed region=" ..
                    tostring(request.region) ..
                    " error=" .. tostring(contextOrError)
                )
            end
        end
        local previousWitnessState =
            DarkPassengerQuestBridge.lastWitnessStates[request.region]
        if previousWitnessState ~= hasWitnessRequest then
            DarkPassengerQuestBridge.lastWitnessStates[request.region] =
                hasWitnessRequest
            TargetLog(
                "witness context region=" .. tostring(request.region) ..
                " active=" .. tostring(hasWitnessRequest)
            )
        end
        if hasWitnessRequest and
           DarkPassengerWitnessLead ~= nil and
           DarkPassengerWitnessLead.OnDialogueCompleted ~= nil then
            DarkPassengerWitnessLead.OnDialogueCompleted(request.region)
        end
    end

    ScheduleSelectionRequestPoll()
end

DarkPassengerQuestBridge.StartPolling("mod_init")

function DarkPassengerTarget.Call(action)
    if action == "select_target_pritoky" then
        return DarkPassengerTarget.SelectNearest("kutnohorsko")
    end
    TargetLog("unknown quest action: " .. tostring(action))
    return false
end

-- Opens a case against the nearest NPC within `radius` meters.
function DarkPassengerTest.TagNearest(argsLine)
    if not CaseReady() then return end
    local parts = SplitArgs(argsLine)
    local radius = tonumber(parts[1]) or 15
    local archetype = parts[2]

    if g_localActor == nil then
        System.LogAlways("[DarkPassenger] TagNearest FAILED: g_localActor is nil.")
        return
    end
    local okPos, pos = pcall(function() return g_localActor:GetWorldPos() end)
    if not okPos or pos == nil then
        System.LogAlways("[DarkPassenger] TagNearest FAILED: could not read player position.")
        return
    end

    local okList, list = pcall(function() return System.GetEntitiesInSphere(pos, radius) end)
    if not okList or list == nil then
        System.LogAlways("[DarkPassenger] TagNearest FAILED: GetEntitiesInSphere errored.")
        return
    end

    local bestEnt, bestDist = nil, nil
    for _, ent in pairs(list) do
        local isSelf = (ent ~= nil and ent.id ~= nil and ent.id == g_localActor.id)
        local looksLikeNpc = (ent ~= nil and ent.soul ~= nil)
        if looksLikeNpc and not isSelf then
            local okD, ePos = pcall(function() return ent:GetWorldPos() end)
            if okD and ePos ~= nil then
                local dx, dy, dz = ePos.x - pos.x, ePos.y - pos.y, ePos.z - pos.z
                local d2 = dx * dx + dy * dy + dz * dz
                if bestDist == nil or d2 < bestDist then
                    bestDist = d2
                    bestEnt = ent
                end
            end
        end
    end

    if bestEnt == nil then
        System.LogAlways("[DarkPassenger] TagNearest: no NPC found within " .. tostring(radius) .. "m.")
        return
    end

    local name = "?"
    local okName, nameOrErr = pcall(function() return EntityUtils.GetName(bestEnt) end)
    if okName and nameOrErr ~= nil then name = nameOrErr end

    DarkPassengerCase.Open(bestEnt.id, name, archetype or "test")
end

-- Adds the nearest OTHER NPC (not the current target) as a decoy.
function DarkPassengerTest.DecoyNearest(argsLine)
    if not CaseReady() then return end
    local case = DarkPassengerCase.GetCurrent()
    if case == nil then
        System.LogAlways("[DarkPassenger] DecoyNearest: no open case, tag a target first.")
        return
    end
    local parts = SplitArgs(argsLine)
    local radius = tonumber(parts[1]) or 15

    local okPos, pos = pcall(function() return g_localActor:GetWorldPos() end)
    if not okPos or pos == nil then return end
    local okList, list = pcall(function() return System.GetEntitiesInSphere(pos, radius) end)
    if not okList or list == nil then return end

    local bestEnt, bestDist = nil, nil
    for _, ent in pairs(list) do
        local isSelf = (ent ~= nil and ent.id ~= nil and ent.id == g_localActor.id)
        local isTarget = (ent ~= nil and ent.id ~= nil and tostring(ent.id) == tostring(case.target_id))
        local looksLikeNpc = (ent ~= nil and ent.soul ~= nil)
        if looksLikeNpc and not isSelf and not isTarget then
            local okD, ePos = pcall(function() return ent:GetWorldPos() end)
            if okD and ePos ~= nil then
                local dx, dy, dz = ePos.x - pos.x, ePos.y - pos.y, ePos.z - pos.z
                local d2 = dx * dx + dy * dy + dz * dz
                if bestDist == nil or d2 < bestDist then
                    bestDist = d2
                    bestEnt = ent
                end
            end
        end
    end

    if bestEnt == nil then
        System.LogAlways("[DarkPassenger] DecoyNearest: no other NPC found within " .. tostring(radius) .. "m.")
        return
    end

    local name = "?"
    local okName, nameOrErr = pcall(function() return EntityUtils.GetName(bestEnt) end)
    if okName and nameOrErr ~= nil then name = nameOrErr end

    DarkPassengerCase.AddDecoy(bestEnt.id, name)
end

-- Manually adds confidence, simulating "found a clue" for this vertical slice.
function DarkPassengerTest.Evidence(argsLine)
    local parts = SplitArgs(argsLine)
    local amount = tonumber(parts[1]) or 0
    local label = table.concat(parts, " ", 2)
    if label == "" then label = "manual_test" end
    return DarkPassengerInvestigation.AddEvidence(amount, label)
end

-- v8: experimental marker test. GameRules.SetObjectiveEntity is a generic
-- CryEngine binding (doc dated 2012, likely MP-era) -- unverified whether it
-- does anything useful in KCD2's SP campaign. We call it defensively via
-- pcall and log whatever happens; success/failure here is itself the answer.
-- v9: 'GameRules' is not a real global in KCD2 SP (that name only exists in the
-- 2012-era generic CryEngine doc notation). The real live instance is the
-- global 'g_gameRules' (lowercase, see vanilla player.lua). We try two of its
-- bound native methods, each independently, each defensively via pcall:
--   AddMinimapEntity(entityId, type, lifetime) -- simplest, no quest system needed
--   AddObjective(teamId, name, status, entityId) -- MP-style objective marker
function DarkPassengerTest.TestMarker(argsLine)
    if not CaseReady() then return end
    local case = DarkPassengerCase.GetCurrent()
    if case == nil or case.target_id == nil then
        System.LogAlways("[DarkPassenger] TestMarker: no open case with a target. Run dp_tag_nearest first.")
        return
    end

    if g_gameRules == nil then
        System.LogAlways("[DarkPassenger] TestMarker FAILED: global 'g_gameRules' is nil (not in SP session?).")
        return
    end

    -- Attempt 1: AddMinimapEntity
    if g_gameRules.AddMinimapEntity == nil then
        System.LogAlways("[DarkPassenger] TestMarker: g_gameRules.AddMinimapEntity is nil (not bound).")
    else
        local ok1, err1 = pcall(function()
            g_gameRules:AddMinimapEntity(case.target_id, 1, 300.0)
        end)
        if ok1 then
            System.LogAlways("[DarkPassenger] TestMarker: AddMinimapEntity(target_id, 1, 300) SUCCEEDED (no Lua error). Check compass/minimap for '" .. tostring(case.target_name) .. "'.")
        else
            System.LogAlways("[DarkPassenger] TestMarker: AddMinimapEntity THREW: " .. tostring(err1))
        end
    end

    -- Attempt 2: AddObjective
    if g_gameRules.AddObjective == nil then
        System.LogAlways("[DarkPassenger] TestMarker: g_gameRules.AddObjective is nil (not bound).")
    else
        local ok2, err2 = pcall(function()
            g_gameRules:AddObjective(0, "dp_target", 1, case.target_id)
        end)
        if ok2 then
            System.LogAlways("[DarkPassenger] TestMarker: AddObjective(0, 'dp_target', 1, target_id) SUCCEEDED (no Lua error). Check compass/map/HUD for '" .. tostring(case.target_name) .. "'.")
        else
            System.LogAlways("[DarkPassenger] TestMarker: AddObjective THREW: " .. tostring(err2))
        end
    end
end
-- v10: LIVE test of Quest.RegisterQuestEntity, instead of trusting the doc
-- annotation "Not on master" at face value. The doc could mean "not in our
-- internal Perforce master branch used to generate this doc snapshot" which
-- is NOT the same claim as "absent from the shipped Modding Tools build".
-- Only a live pcall against the actual binding tells us the truth.
function DarkPassengerTest.TestQuestEntity(argsLine)
    if not CaseReady() then return end
    local case = DarkPassengerCase.GetCurrent()
    if case == nil or case.target_id == nil then
        System.LogAlways("[DarkPassenger] TestQuestEntity: no open case with a target. Run dp_tag_nearest first.")
        return
    end

    if Quest == nil then
        System.LogAlways("[DarkPassenger] TestQuestEntity FAILED: global 'Quest' is nil.")
        return
    end

    if Quest.RegisterQuestEntity == nil then
        System.LogAlways("[DarkPassenger] TestQuestEntity: Quest.RegisterQuestEntity is nil (not bound in this build).")
    else
        local ok, err = pcall(function()
            Quest.RegisterQuestEntity(case.target_id)
        end)
        if ok then
            System.LogAlways("[DarkPassenger] TestQuestEntity: Quest.RegisterQuestEntity(target_id) SUCCEEDED (no Lua error). Binding IS callable.")
        else
            System.LogAlways("[DarkPassenger] TestQuestEntity: Quest.RegisterQuestEntity THREW: " .. tostring(err))
        end
    end
end

-- Live compatibility probe for the shipped CryEngine MissionObjective bridge.
-- Scripts.pak/Scripts/Entities/Others/MissionObjective.lua uses the same
-- HUD.SetObjectiveEntity(missionId, entityName) call. KCD2's Skald objective
-- may or may not still consume it, so this is deliberately exposed as a
-- manual probe before the hunt lifecycle depends on it.
function DarkPassengerTest.TestHudObjectiveMarker(argsLine)
    if not CaseReady() then return end

    -- Always take a fresh nearby entity so old save/runtime case state cannot
    -- make the compatibility probe target an unloaded NPC.
    DarkPassengerTest.TagNearest("50 hud_probe")
    local currentCase = DarkPassengerCase.GetCurrent()

    if currentCase == nil or currentCase.target_id == nil then
        System.LogAlways(
            "[DarkPassenger] HUD marker probe FAILED: no target within 50m."
        )
        return
    end

    local target = System.GetEntity(currentCase.target_id)
    if target == nil then
        System.LogAlways(
            "[DarkPassenger] HUD marker probe FAILED: target entity unavailable."
        )
        return
    end

    local entityName = target:GetName()
    System.LogAlways(
        "[DarkPassenger] HUD marker probe target=" ..
        tostring(entityName) .. " id=" .. tostring(target.id) ..
        " HUD=" .. tostring(type(HUD)) ..
        " Quest=" .. tostring(type(Quest))
    )

    if Quest ~= nil and Quest.RegisterQuestEntity ~= nil then
        local registered, registerError = pcall(function()
            Quest.RegisterQuestEntity(target.id)
        end)
        System.LogAlways(
            "[DarkPassenger] Quest.RegisterQuestEntity ok=" ..
            tostring(registered) .. " err=" .. tostring(registerError)
        )
    else
        System.LogAlways(
            "[DarkPassenger] Quest.RegisterQuestEntity unavailable."
        )
    end

    if HUD == nil or HUD.SetObjectiveEntity == nil then
        System.LogAlways(
            "[DarkPassenger] HUD.SetObjectiveEntity unavailable."
        )
        return
    end

    for _, objectiveId in ipairs({
        "dark_within_obj",
        "dark_within_objk",
    }) do
        local bound, bindError = pcall(function()
            if objectiveId == "dark_within_obj" then
                HUD.SetObjectiveEntity("dark_within_obj", entityName)
            else
                HUD.SetObjectiveEntity("dark_within_objk", entityName)
            end
        end)
        System.LogAlways(
            "[DarkPassenger] HUD.SetObjectiveEntity objective=" ..
            objectiveId .. " ok=" .. tostring(bound) ..
            " err=" .. tostring(bindError)
        )
    end
end

function DarkPassengerTest.ClearHudObjectiveMarker()
    if HUD == nil or HUD.ClearObjectiveEntity == nil then return end
    pcall(function() HUD.ClearObjectiveEntity("dark_within_obj") end)
    pcall(function() HUD.ClearObjectiveEntity("dark_within_objk") end)
    System.LogAlways("[DarkPassenger] HUD objective marker probe cleared.")
end

DarkPassengerAftermathProbe = DarkPassengerAftermathProbe or {}

DarkPassengerAftermathProbe.CRIME_CONTEXTS = {
    "crime_interrupt",
    "crime_interruptScan",
    "crime_interruptReport",
    "crime_interruptReport_reporting",
    "crime_disableReport",
    "crime_nrbLevel_searching",
    "crime_escalationLevel_looking",
    "crime_preventDespawn",
    "crime_greyOutGrabBody",
}

DarkPassengerAftermathProbe.CRIME_LINKS = {
    "crime_anchor",
    "crime_playerAwareness",
    "crime_npcCooldowns",
    "crime_districtOrigin",
    "crimeScene",
}

DarkPassengerAftermathProbe.WITNESS_BRAIN_VARIABLES = {
    "amIWitness",
    "reportDestination",
    "reportDestinationType",
    "stimulusKind",
    "previousReaction",
    "criminalFreshness",
    "freshlyAttributedCrime",
    "reportedBy",
    "shooter",
    "target",
    "scanData",
}

local function AftermathProbeLog(message)
    System.LogAlways("[DarkPassenger][AftermathProbe] " .. tostring(message))
end

local function ProbeMethod(owner, methodName)
    return owner ~= nil and type(owner[methodName]) == "function"
end

local function ProbeEntityName(entity)
    if entity == nil then return "nil" end
    local ok, value = pcall(function()
        if EntityUtils ~= nil and EntityUtils.GetName ~= nil then
            return EntityUtils.GetName(entity)
        end
        return entity:GetName()
    end)
    if ok and value ~= nil then return tostring(value) end
    return "?"
end

local function ProbeEntityPosition(entity)
    if entity == nil then return nil end
    local ok, value = pcall(function() return entity:GetWorldPos() end)
    if ok then return value end
    return nil
end

local function ProbeEntityDead(entity)
    if entity == nil or entity.actor == nil or
       not ProbeMethod(entity.actor, "IsDead") then
        return nil
    end
    local ok, value = pcall(function() return entity.actor:IsDead() end)
    if ok then return value end
    return nil
end

local function ProbeSoulContext(entity, context)
    if entity == nil or entity.soul == nil or
       not ProbeMethod(entity.soul, "HasScriptContext") then
        return nil
    end
    local ok, value = pcall(function()
        return entity.soul:HasScriptContext(context)
    end)
    if ok then return value end
    return nil
end

local function ProbeDistanceSquared(left, right)
    if left == nil or right == nil then return nil end
    local dx = (left.x or 0) - (right.x or 0)
    local dy = (left.y or 0) - (right.y or 0)
    local dz = (left.z or 0) - (right.z or 0)
    return dx * dx + dy * dy + dz * dz
end

local function ProbeCurrentCase()
    if not CaseReady() then return nil end
    return DarkPassengerCase.GetCurrent()
end

function DarkPassengerAftermathProbe.Status()
    local currentCase = ProbeCurrentCase()
    AftermathProbeLog(
        "status case=" .. tostring(currentCase ~= nil) ..
        " state=" .. tostring(currentCase and currentCase.state) ..
        " region=" .. tostring(currentCase and currentCase.game_region) ..
        " settlement=" .. tostring(currentCase and currentCase.settlement) ..
        " target_id=" .. tostring(currentCase and currentCase.target_id)
    )
    AftermathProbeLog(
        "bindings entitiesInSphere=" ..
        tostring(ProbeMethod(System, "GetEntitiesInSphere")) ..
        " entityWorldPos=" ..
        tostring(g_localActor ~= nil and ProbeMethod(g_localActor, "GetWorldPos")) ..
        " soulContext=" ..
        tostring(g_localActor ~= nil and g_localActor.soul ~= nil and
            ProbeMethod(g_localActor.soul, "HasScriptContext")) ..
        " aiHostile=" .. tostring(ProbeMethod(AI, "Hostile")) ..
        " aiPersonallyHostile=" ..
        tostring(ProbeMethod(AI, "IsPersonallyHostile")) ..
        " findLinks=" .. tostring(ProbeMethod(XGenAIModule, "FindLinks"))
    )
end

function DarkPassengerAftermathProbe.Nearby(argsLine)
    if g_localActor == nil then
        AftermathProbeLog("nearby unavailable: player=nil")
        return
    end

    local radius = tonumber((SplitArgs(argsLine or "")[1])) or 30
    radius = math.max(1, math.min(radius, 200))
    local origin = ProbeEntityPosition(g_localActor)
    if origin == nil then
        AftermathProbeLog("nearby unavailable: player position=nil")
        return
    end

    local ok, entities = pcall(function()
        return System.GetEntitiesInSphere(origin, radius)
    end)
    if not ok or entities == nil then
        AftermathProbeLog("nearby failed: " .. tostring(entities))
        return
    end

    local rows = {}
    for _, entity in pairs(entities) do
        if entity ~= nil and entity.id ~= nil and
           entity.id ~= g_localActor.id and entity.soul ~= nil then
            local position = ProbeEntityPosition(entity)
            local distanceSquared = ProbeDistanceSquared(origin, position)
            local contexts = {}
            for _, context in ipairs(DarkPassengerAftermathProbe.CRIME_CONTEXTS) do
                if ProbeSoulContext(entity, context) == true then
                    table.insert(contexts, context)
                end
            end
            table.insert(rows, {
                entity = entity,
                distanceSquared = distanceSquared or math.huge,
                contexts = contexts,
            })
        end
    end

    table.sort(rows, function(left, right)
        return left.distanceSquared < right.distanceSquared
    end)

    AftermathProbeLog(
        "nearby radius=" .. tostring(radius) ..
        " npc_count=" .. tostring(#rows)
    )
    for index, row in ipairs(rows) do
        if index > 40 then
            AftermathProbeLog("nearby output truncated at 40 NPCs")
            break
        end
        AftermathProbeLog(
            "npc name=" .. ProbeEntityName(row.entity) ..
            " id=" .. tostring(row.entity.id) ..
            " distance=" .. string.format("%.1f", math.sqrt(row.distanceSquared)) ..
            " dead=" .. tostring(ProbeEntityDead(row.entity)) ..
            " contexts=" .. table.concat(row.contexts, ",")
        )
    end
end

function DarkPassengerAftermathProbe.Crime(argsLine)
    local radius = tonumber((SplitArgs(argsLine or "")[1])) or 40
    radius = math.max(1, math.min(radius, 200))
    AftermathProbeLog(
        "crime globals Crime=" .. tostring(type(Crime)) ..
        " Game=" .. tostring(type(Game)) ..
        " GameRules=" .. tostring(type(GameRules)) ..
        " g_gameRules=" .. tostring(type(g_gameRules))
    )

    if g_localActor ~= nil then
        for _, context in ipairs(DarkPassengerAftermathProbe.CRIME_CONTEXTS) do
            AftermathProbeLog(
                "player context=" .. context ..
                " value=" .. tostring(ProbeSoulContext(g_localActor, context))
            )
        end

        if ProbeMethod(XGenAIModule, "FindLinks") then
            for _, tag in ipairs(DarkPassengerAftermathProbe.CRIME_LINKS) do
                local ok, links = pcall(function()
                    return XGenAIModule.FindLinks(g_localActor.id, tag)
                end)
                local count = ok and type(links) == "table" and #links or nil
                AftermathProbeLog(
                    "player links tag=" .. tag ..
                    " ok=" .. tostring(ok) ..
                    " count=" .. tostring(count)
                )
            end
        end
    end

    DarkPassengerAftermathProbe.Nearby(tostring(radius))
end

function DarkPassengerAftermathProbe.Attribution()
    local currentCase = ProbeCurrentCase()
    local target = currentCase ~= nil and currentCase.target_id ~= nil and
        System.GetEntity(currentCase.target_id) or nil

    AftermathProbeLog(
        "attribution target_loaded=" .. tostring(target ~= nil) ..
        " target_id=" .. tostring(currentCase and currentCase.target_id) ..
        " target_name=" .. ProbeEntityName(target) ..
        " target_dead=" .. tostring(ProbeEntityDead(target))
    )
    AftermathProbeLog(
        "attribution bindings actorDamageInfo=" ..
        tostring(target ~= nil and target.actor ~= nil and
            ProbeMethod(target.actor, "DamageInfo")) ..
        " note=bindings are presence-only; probe does not call them"
    )

    if target ~= nil and g_localActor ~= nil then
        local hostileOk, hostile = pcall(function()
            return AI.Hostile(target.id, g_localActor.id)
        end)
        local personalOk, personallyHostile = pcall(function()
            return AI.IsPersonallyHostile(target.id, g_localActor.id)
        end)
        AftermathProbeLog(
            "attribution hostility hostile_ok=" .. tostring(hostileOk) ..
            " hostile=" .. tostring(hostile) ..
            " personal_ok=" .. tostring(personalOk) ..
            " personally_hostile=" .. tostring(personallyHostile)
        )
    end

    if target ~= nil then
        for _, fieldName in ipairs({
            "lastAttacker", "lastAttackerId", "lastKiller", "lastKillerId",
            "lastHit", "lastHitInfo", "shooterId", "damageOwner",
        }) do
            AftermathProbeLog(
                "attribution field=" .. fieldName ..
                " type=" .. tostring(type(target[fieldName])) ..
                " value=" .. tostring(target[fieldName])
            )
        end
    end
end

-- DP_WITNESS_PROBE_READ_ONLY_BEGIN

DarkPassengerAftermathProbe.WITNESS_WATCH_INTERVAL_MS = 500
DarkPassengerAftermathProbe.WITNESS_WATCH_TICKS = 90
DarkPassengerAftermathProbe.witnessWatchGeneration =
    DarkPassengerAftermathProbe.witnessWatchGeneration or 0

local function WitnessProbeValueSummary(value)
    local valueType = type(value)
    if valueType ~= "table" then
        return valueType .. ":" .. tostring(value)
    end

    local entries = {}
    for key, entryValue in pairs(value) do
        local entryType = type(entryValue)
        if entryType ~= "table" and entryType ~= "function" then
            table.insert(
                entries,
                tostring(key) .. "=" .. entryType .. ":" ..
                tostring(entryValue)
            )
        end
        if #entries >= 12 then break end
    end
    table.sort(entries)
    return "table:{" .. table.concat(entries, ",") .. "}"
end

local function WitnessProbeSoulId(entity)
    if entity == nil or entity.soul == nil or
       not ProbeMethod(entity.soul, "GetId") then
        return nil
    end
    local ok, value = pcall(function()
        return entity.soul:GetId()
    end)
    if ok then return value end
    return nil
end

local function WitnessProbeAiRelation(methodName, entity)
    if entity == nil or entity.id == nil or g_localActor == nil or
       g_localActor.id == nil or not ProbeMethod(AI, methodName) then
        return nil
    end
    local ok, value = pcall(function()
        return AI[methodName](entity.id, g_localActor.id)
    end)
    if ok then return value end
    return nil
end

local function WitnessProbeContexts(entity)
    local active = {}
    for _, context in ipairs(
        DarkPassengerAftermathProbe.CRIME_CONTEXTS
    ) do
        local value = ProbeSoulContext(entity, context)
        if value ~= nil then
            table.insert(
                active,
                context .. "=" .. tostring(value)
            )
        end
    end
    table.sort(active)
    return table.concat(active, ",")
end

local function WitnessProbeLinks(entity)
    if entity == nil or
       not ProbeMethod(XGenAIModule, "FindLinks") then
        return ""
    end

    local linkSourceId = WitnessProbeSoulId(entity)
    if linkSourceId == nil then return "" end

    local summaries = {}
    for _, tag in ipairs(DarkPassengerAftermathProbe.CRIME_LINKS) do
        local ok, links = pcall(function()
            return XGenAIModule.FindLinks(linkSourceId, tag)
        end)
        local count = 0
        if ok and type(links) == "table" then
            for _ in pairs(links) do count = count + 1 end
        end
        table.insert(
            summaries,
            tag .. "=" .. tostring(ok) .. ":" ..
            type(links) .. ":" .. tostring(count)
        )
    end
    table.sort(summaries)
    return table.concat(summaries, ",")
end

local function WitnessProbeBrain(entity)
    if entity == nil or
       not ProbeMethod(XGenAIModule, "GetBrainVariable") then
        return ""
    end

    local soulId = WitnessProbeSoulId(entity)
    if soulId == nil then return "" end

    local summaries = {}
    for _, variableName in ipairs(
        DarkPassengerAftermathProbe.WITNESS_BRAIN_VARIABLES
    ) do
        local ok, value = pcall(function()
            return XGenAIModule.GetBrainVariable(
                soulId,
                variableName
            )
        end)
        table.insert(
            summaries,
            variableName .. "=" .. tostring(ok) .. ":" ..
            WitnessProbeValueSummary(value)
        )
    end
    table.sort(summaries)
    return table.concat(summaries, ",")
end

local function WitnessProbeRow(entity, origin, includeBrain)
    local position = ProbeEntityPosition(entity)
    local distanceSquared = ProbeDistanceSquared(origin, position)
    local name = ProbeEntityName(entity)
    local id = entity ~= nil and entity.id or nil
    local soulId = WitnessProbeSoulId(entity)
    local reporting =
        ProbeSoulContext(entity, "crime_interruptReport")
    local brain = "skipped"
    if includeBrain ~= false or reporting == true then
        brain = WitnessProbeBrain(entity)
    end
    local row = {
        key = name .. "|" .. tostring(id),
        name = name,
        id = tostring(id),
        soulId = tostring(soulId),
        distance = distanceSquared ~= nil and
            string.format("%.1f", math.sqrt(distanceSquared)) or "?",
        dead = tostring(ProbeEntityDead(entity)),
        hostile = tostring(WitnessProbeAiRelation("Hostile", entity)),
        personallyHostile = tostring(
            WitnessProbeAiRelation("IsPersonallyHostile", entity)
        ),
        contexts = WitnessProbeContexts(entity),
        links = WitnessProbeLinks(entity),
        brain = brain,
    }
    row.signature = table.concat({
        row.dead,
        row.hostile,
        row.personallyHostile,
        row.contexts,
        row.links,
        row.brain,
    }, "|")
    return row
end

local function WitnessProbePlayerSignature(includeBrain)
    if g_localActor == nil then return "player=nil" end
    return table.concat({
        "contexts=" .. WitnessProbeContexts(g_localActor),
        "links=" .. WitnessProbeLinks(g_localActor),
        "brain=" .. (
            includeBrain == false and "skipped" or
            WitnessProbeBrain(g_localActor)
        ),
    }, "|")
end

local function WitnessProbeCapture(radius, includeBrain)
    if g_localActor == nil or
       not ProbeMethod(System, "GetEntitiesInSphere") then
        return nil, "player or sphere binding unavailable"
    end

    local origin = ProbeEntityPosition(g_localActor)
    if origin == nil then
        return nil, "player position unavailable"
    end

    local ok, entities = pcall(function()
        return System.GetEntitiesInSphere(origin, radius)
    end)
    if not ok or type(entities) ~= "table" then
        return nil, "sphere query failed: " .. tostring(entities)
    end

    local rows = {}
    for _, entity in pairs(entities) do
        if entity ~= nil and entity.id ~= nil and
           entity.id ~= g_localActor.id and entity.soul ~= nil then
            local row = WitnessProbeRow(entity, origin, includeBrain)
            rows[row.key] = row
        end
    end
    return {
        radius = radius,
        player = WitnessProbePlayerSignature(includeBrain),
        rows = rows,
    }
end

local function WitnessProbeRadius(argsLine, fallback)
    local radius = tonumber((SplitArgs(argsLine or "")[1])) or fallback
    return math.max(1, math.min(radius, 200))
end

local function WitnessProbeRowLog(prefix, row)
    AftermathProbeLog(
        prefix ..
        " name=" .. tostring(row.name) ..
        " id=" .. tostring(row.id) ..
        " soul_id=" .. tostring(row.soulId) ..
        " distance=" .. tostring(row.distance) ..
        " dead=" .. tostring(row.dead) ..
        " hostile=" .. tostring(row.hostile) ..
        " personally_hostile=" .. tostring(row.personallyHostile) ..
        " contexts=" .. tostring(row.contexts) ..
        " links=" .. tostring(row.links) ..
        " brain=" .. tostring(row.brain)
    )
end

function DarkPassengerAftermathProbe.WitnessArm(argsLine, includeBrain)
    local radius = WitnessProbeRadius(argsLine, 50)
    local snapshot, errorMessage =
        WitnessProbeCapture(radius, includeBrain)
    if snapshot == nil then
        AftermathProbeLog("witness arm failed: " .. tostring(errorMessage))
        return false
    end

    DarkPassengerAftermathProbe.witnessBaseline = snapshot
    local keys = {}
    for key in pairs(snapshot.rows) do table.insert(keys, key) end
    table.sort(keys)
    AftermathProbeLog(
        "witness arm radius=" .. tostring(radius) ..
        " npc_count=" .. tostring(#keys) ..
        " player=" .. tostring(snapshot.player)
    )
    for _, key in ipairs(keys) do
        WitnessProbeRowLog("witness baseline", snapshot.rows[key])
    end
    return true
end

function DarkPassengerAftermathProbe.WitnessSample(
    argsLine,
    includeBrain
)
    local previous = DarkPassengerAftermathProbe.witnessBaseline
    if previous == nil then
        AftermathProbeLog("witness sample unavailable: arm first")
        return false
    end

    local radius = WitnessProbeRadius(argsLine, previous.radius or 50)
    local current, errorMessage =
        WitnessProbeCapture(radius, includeBrain)
    if current == nil then
        AftermathProbeLog(
            "witness sample failed: " .. tostring(errorMessage)
        )
        return false
    end

    local changes = {}
    if current.player ~= previous.player then
        table.insert(
            changes,
            "player before=" .. tostring(previous.player) ..
            " after=" .. tostring(current.player)
        )
    end

    for key, row in pairs(current.rows) do
        local before = previous.rows[key]
        if before == nil then
            table.insert(changes, "added key=" .. key)
        elseif before.signature ~= row.signature then
            table.insert(changes, "changed key=" .. key)
        end
    end
    for key in pairs(previous.rows) do
        if current.rows[key] == nil then
            table.insert(changes, "removed key=" .. key)
        end
    end
    table.sort(changes)

    AftermathProbeLog(
        "witness sample radius=" .. tostring(radius) ..
        " changes=" .. tostring(#changes)
    )
    for _, change in ipairs(changes) do
        AftermathProbeLog("witness delta " .. change)
        local key = string.match(change, "key=(.+)$")
        if key ~= nil and current.rows[key] ~= nil then
            WitnessProbeRowLog("witness current", current.rows[key])
        elseif key ~= nil and previous.rows[key] ~= nil then
            WitnessProbeRowLog("witness previous", previous.rows[key])
        end
    end

    DarkPassengerAftermathProbe.witnessBaseline = current
    return true
end

function DarkPassengerAftermathProbe.WitnessClear()
    DarkPassengerAftermathProbe.witnessBaseline = nil
    AftermathProbeLog("witness baseline cleared")
    return true
end

function DarkPassengerAftermathProbe.WitnessWatchStop()
    DarkPassengerAftermathProbe.witnessWatchGeneration =
        (DarkPassengerAftermathProbe.witnessWatchGeneration or 0) + 1
    AftermathProbeLog("witness watch stopped")
    return true
end

function DarkPassengerAftermathProbe.WitnessWatch(argsLine)
    if Script == nil or Script.SetTimer == nil then
        AftermathProbeLog("witness watch unavailable: timer binding missing")
        return false
    end

    local radius = WitnessProbeRadius(argsLine, 30)
    DarkPassengerAftermathProbe.witnessWatchGeneration =
        (DarkPassengerAftermathProbe.witnessWatchGeneration or 0) + 1
    local generation =
        DarkPassengerAftermathProbe.witnessWatchGeneration
    local ticksRemaining =
        DarkPassengerAftermathProbe.WITNESS_WATCH_TICKS

    if not DarkPassengerAftermathProbe.WitnessArm(
        tostring(radius),
        false
    ) then
        return false
    end

    local tick
    tick = function()
        if generation ~=
           DarkPassengerAftermathProbe.witnessWatchGeneration then
            return
        end

        DarkPassengerAftermathProbe.WitnessSample(tostring(radius), false)
        ticksRemaining = ticksRemaining - 1
        if ticksRemaining <= 0 then
            AftermathProbeLog("witness watch complete")
            return
        end

        Script.SetTimer(
            DarkPassengerAftermathProbe.WITNESS_WATCH_INTERVAL_MS,
            tick
        )
    end

    Script.SetTimer(
        DarkPassengerAftermathProbe.WITNESS_WATCH_INTERVAL_MS,
        tick
    )
    AftermathProbeLog(
        "witness watch started radius=" .. tostring(radius) ..
        " ticks=" .. tostring(ticksRemaining)
    )
    return true
end

-- DP_WITNESS_PROBE_READ_ONLY_END

pcall(function()
    if System ~= nil and System.AddCCommand ~= nil then
        System.AddCCommand("dp_aftermath_recover",
            "DarkPassengerAftermath.EnsureRestoreFromPlayerAction()",
            "Dark Passenger: retry aftermath recovery after save loading"
        )
    end
end)

local okCmd, errCmd = pcall(function()
    if System ~= nil and System.AddCCommand ~= nil then
        System.AddCCommand("dp_tag_nearest", "DarkPassengerTest.TagNearest(%line)",
            "Dark Passenger: open a case on the nearest NPC (radius, archetype)")
        System.AddCCommand("dp_decoy_nearest", "DarkPassengerTest.DecoyNearest(%line)",
            "Dark Passenger: add the nearest OTHER NPC as a decoy on the current case (radius)")
        System.AddCCommand("dp_evidence", "DarkPassengerTest.Evidence(%line)",
            "Dark Passenger: manually add confidence to the current case (amount, label)")
        System.AddCCommand("dp_test_marker", "DarkPassengerTest.TestMarker(%line)",
            "Dark Passenger: try GameRules.SetObjectiveEntity on the current case target (experimental)")
        System.AddCCommand("dp_test_quest", "DarkPassengerTest.TestQuestEntity(%line)",
            "Dark Passenger: live test of Quest.RegisterQuestEntity on current case target")
        System.AddCCommand("dp_test_hud_marker", "DarkPassengerTest.TestHudObjectiveMarker(%line)",
            "Dark Passenger: bind current/nearest NPC to the live quest objective")
        System.AddCCommand("dp_clear_hud_marker", "DarkPassengerTest.ClearHudObjectiveMarker()",
            "Dark Passenger: clear the live HUD objective marker probe")
        System.AddCCommand("dp_target_select", "DarkPassengerTarget.SelectCommand(%line)",
            "Dark Passenger: select and tag a safe candidate (game region, settlement)")
        System.AddCCommand("dp_target_validate", "DarkPassengerTarget.ValidateCommand(%line)",
            "Dark Passenger: revalidate selected target before marker activation")
        System.AddCCommand("dp_target_death", "DarkPassengerTarget.DeathCommand(%line)",
            "Dark Passenger: start aftermath for a selected target death")
        System.AddCCommand("dp_target_clear", "DarkPassengerTarget.Clear()",
            "Dark Passenger: clear the current hidden target tag")
        System.AddCCommand("dp_quest_status", "DarkPassengerTarget.QuestStatus()",
            "Dark Passenger: report whether the hunt quest is active")
        System.AddCCommand("dp_quest_objectives", "DarkPassengerTarget.DumpActiveObjectives()",
            "Dark Passenger: report active objective ids for both regional quests")
        System.AddCCommand("dp_aftermath_probe_status", "DarkPassengerAftermathProbe.Status()",
            "Dark Passenger: read-only aftermath API and case status")
        System.AddCCommand("dp_aftermath_probe_nearby", "DarkPassengerAftermathProbe.Nearby(%line)",
            "Dark Passenger: read-only nearby NPC state (radius, default 30)")
        System.AddCCommand("dp_aftermath_probe_crime", "DarkPassengerAftermathProbe.Crime(%line)",
            "Dark Passenger: read-only crime contexts and links (radius, default 40)")
        System.AddCCommand("dp_aftermath_probe_attribution", "DarkPassengerAftermathProbe.Attribution()",
            "Dark Passenger: read-only target death and attribution API state")
        System.AddCCommand("dp_witness_probe_arm", "DarkPassengerAftermathProbe.WitnessArm(%line)",
            "Dark Passenger: arm a read-only nearby witness snapshot")
        System.AddCCommand("dp_witness_probe_sample", "DarkPassengerAftermathProbe.WitnessSample(%line)",
            "Dark Passenger: diff nearby witness state against the last snapshot")
        System.AddCCommand("dp_witness_probe_clear", "DarkPassengerAftermathProbe.WitnessClear()",
            "Dark Passenger: clear the read-only witness snapshot")
        System.AddCCommand("dp_witness_probe_watch", "DarkPassengerAftermathProbe.WitnessWatch(%line)",
            "Dark Passenger: watch nearby witness state for 45 seconds")
        System.AddCCommand("dp_witness_probe_stop", "DarkPassengerAftermathProbe.WitnessWatchStop()",
            "Dark Passenger: stop the read-only witness watcher")
        System.AddCCommand("dp_witness_status", "DarkPassengerWitness.Status()",
            "Dark Passenger: print the persistent witness ledger")
        System.AddCCommand("dp_witness_confirm", "DarkPassengerWitness.DebugConfirm(%line)",
            "Dark Passenger: confirm a synthetic witness (identity high, low)")
        System.AddCCommand("dp_witness_report", "DarkPassengerWitness.DebugReport(%line)",
            "Dark Passenger: mark a synthetic witness as reported")
        System.AddCCommand("dp_witness_dead", "DarkPassengerWitness.DebugDead(%line)",
            "Dark Passenger: mark a synthetic witness as dead")
        System.AddCCommand("dp_witness_lost", "DarkPassengerWitness.DebugLost(%line)",
            "Dark Passenger: mark a synthetic witness as lost")
        System.AddCCommand("dp_witness_detector_status", "DarkPassengerWitnessDetector.Status()",
            "Dark Passenger: print the runtime witness detector state")
        System.AddCCommand("dp_witness_detector_scan", "DarkPassengerWitnessDetector.Scan()",
            "Dark Passenger: scan the active aftermath zone now")
        System.AddCCommand("dp_aftermath_begin", "DarkPassengerAftermath.DebugBegin(%line)",
            "Dark Passenger: begin a synthetic aftermath case (zone radius)")
        System.AddCCommand("dp_aftermath_suspicion", "DarkPassengerAftermath.RecordSuspicion(%line)",
            "Dark Passenger: inject synthetic suspicion into the active aftermath case")
        System.AddCCommand("dp_aftermath_witness_removed", "DarkPassengerAftermath.RecordWitnessRemoved(%line)",
            "Dark Passenger: record a synthetic removed witness")
        System.AddCCommand("dp_aftermath_exit", "DarkPassengerAftermath.DebugExit(%line)",
            "Dark Passenger: simulate leaving the active aftermath zone")
        System.AddCCommand("dp_aftermath_status", "DarkPassengerAftermath.Status()",
            "Dark Passenger: print the active aftermath state")
        System.AddCCommand("dp_aftermath_restore", "DarkPassengerAftermath.Restore(%line)",
            "Dark Passenger: restore the persisted aftermath state")
    end
end)
if not okCmd then
    System.LogAlways("[DarkPassenger] console command registration failed (non-fatal): " .. tostring(errCmd))
end

local function ResolveVictim(victim, fallbackSlotId)
    if victim ~= nil and victim.id ~= nil then
        local name = "?"
        local okName, nameOrErr = pcall(function() return EntityUtils.GetName(victim) end)
        if okName and nameOrErr ~= nil then name = nameOrErr end
        return victim.id, name
    end
    return fallbackSlotId, "?"
end

local function IsVerifiedHenry(user)
    return user ~= nil and
        user.id ~= nil and
        g_localActor ~= nil and
        g_localActor.id ~= nil and
        user.id == g_localActor.id
end

local function Report(user, victimId, victimName, method, victim)
    if not CaseReady() then return end
    if not IsVerifiedHenry(user) then
        System.LogAlways(
            "[DarkPassenger] ignored unverified kill event method=" ..
            tostring(method)
        )
        return nil
    end
    if DarkPassengerWitnessDetector ~= nil and
       DarkPassengerWitnessDetector.RecordAttributedDeath ~= nil then
        DarkPassengerWitnessDetector.RecordAttributedDeath(victim, method)
    end

    local currentCase = DarkPassengerCase.GetCurrent()
    local previousState =
        currentCase ~= nil and currentCase.state or nil
    local result =
        DarkPassengerCase.ReportKill(victimId, victimName, method)

    if result == "RESOLVED_CORRECT" and
       previousState ~= "RESOLVED_CORRECT" then
        System.LogAlways(
            "[DarkPassenger] selected target kill attributed method=" ..
            tostring(method) ..
            "; quest graph owns satisfaction reward"
        )
    end

    return result
end

function DarkPassengerTest.OnStealthKill(user, slotId, victim)
    local victimId, victimName = ResolveVictim(victim, slotId)
    System.LogAlways("[DarkPassenger] === STEALTH_KILL (dagger) FIRED === victim=" .. tostring(victimName))
    Report(user, victimId, victimName, "stealth_kill", victim)
end

function DarkPassengerTest.OnKnockout(user, slotId, victim)
    local victimId, victimName = ResolveVictim(victim, slotId)
    System.LogAlways("[DarkPassenger] === KNOCKOUT (choke, non-lethal) FIRED === victim=" .. tostring(victimName))
    -- knockout alone is not lethal; no case report.
end

function DarkPassengerTest.OnMercyKill(user, slotId, victim)
    local victimId, victimName = ResolveVictim(victim, slotId)
    System.LogAlways("[DarkPassenger] === MERCY_KILL (finish downed) FIRED === victim=" .. tostring(victimName))
    Report(user, victimId, victimName, "mercy_kill", victim)
end

function DarkPassengerTest.OnGrabCorpse(user, slotId, victim)
    local victimId, victimName = ResolveVictim(victim, slotId)
    System.LogAlways("[DarkPassenger] === GRAB_CORPSE FIRED === corpse=" .. tostring(victimName))
end

function DarkPassengerTest.OnOrdinaryHumanKillObserved()
    if DarkPassengerHunger == nil or
       DarkPassengerHunger.RelieveFromOrdinaryKill == nil then
        return {
            accepted = false,
            reason = "hunger_runtime_unavailable",
        }
    end

    local relief = DarkPassengerHunger.RelieveFromOrdinaryKill()
    System.LogAlways(
        "[DarkPassenger] ordinary human kill observed relief=" .. tostring(
            relief ~= nil and relief.reason or nil
        )
    )
    return relief
end

-- PlayerEventDispatcher emits BasicAIActionsOnStealthKill/MercyKill without
-- the NPC `self`, so those events cannot attribute the victim. Wrap the two
-- lethal interaction methods and forward `self` before the original action
-- starts; this also lets satisfaction close the quest before SoulDeathTrigger
-- can request a replacement target.
local function InstallVictimAwareActionHook(methodName, callback)
    if BasicAIActions == nil or BasicAIActions[methodName] == nil then
        System.LogAlways(
            "[DarkPassenger] victim-aware hook unavailable method=" ..
            tostring(methodName)
        )
        return false
    end

    DarkPassengerTest._victimActionHooks =
        DarkPassengerTest._victimActionHooks or {}
    local existing = DarkPassengerTest._victimActionHooks[methodName]
    if existing ~= nil and BasicAIActions[methodName] == existing.wrapper then
        return true
    end

    local original = BasicAIActions[methodName]
    local wrapper = function(self, user, slotId, ...)
        callback(user, slotId, self)
        return original(self, user, slotId, ...)
    end
    DarkPassengerTest._victimActionHooks[methodName] = {
        original = original,
        wrapper = wrapper
    }
    BasicAIActions[methodName] = wrapper
    System.LogAlways(
        "[DarkPassenger] victim-aware hook installed method=" ..
        tostring(methodName)
    )
    return true
end

local function EnsureVictimAwareActionHooks()
    InstallVictimAwareActionHook("OnStealthKill", function(user, slotId, victim)
        return DarkPassengerTest.OnStealthKill(user, slotId, victim)
    end)
    InstallVictimAwareActionHook("OnMercyKill", function(user, slotId, victim)
        return DarkPassengerTest.OnMercyKill(user, slotId, victim)
    end)
end

EnsureVictimAwareActionHooks()

-- Hot-reload safe: register thin trampolines ONCE. The dispatcher's Register
-- does a bare table.insert with no dedup, so re-running this file on a live
-- reload would stack duplicate listeners. Trampolines resolve DarkPassengerTest.*
-- at call time, so reloading redefines the handlers without re-registering.
if PlayerEventDispatcher ~= nil then
    if not DarkPassengerTest._hooksRegistered then
        PlayerEventDispatcher:Register("BasicAIActionsOnKnockout",    function(...) return DarkPassengerTest.OnKnockout(...) end)
        PlayerEventDispatcher:Register("BasicAIActionsOnGrabCorpse",  function(...) return DarkPassengerTest.OnGrabCorpse(...) end)
        PlayerEventDispatcher:Register("OnReloadEvent", function(...)
            EnsureVictimAwareActionHooks()
            DarkPassengerAreaBridge.StartPolling("player_reload")
            if DarkPassengerHunger ~= nil and
               DarkPassengerHunger.StartEvaluation ~= nil then
                DarkPassengerHunger.StartEvaluation("player_reload")
            end
            if DarkPassengerAftermath ~= nil and
               DarkPassengerAftermath.ScheduleRestore ~= nil then
                DarkPassengerAftermath.ScheduleRestore("player_reload")
            end
            return DarkPassengerQuestBridge.StartPolling("player_reload")
        end)
        PlayerEventDispatcher:Register("OnInitEvent", function(...)
            EnsureVictimAwareActionHooks()
            DarkPassengerAreaBridge.StartPolling("player_init")
            if DarkPassengerHunger ~= nil and
               DarkPassengerHunger.StartEvaluation ~= nil then
                DarkPassengerHunger.StartEvaluation("player_init")
            end
            if DarkPassengerAftermath ~= nil and
               DarkPassengerAftermath.ScheduleRestore ~= nil then
                DarkPassengerAftermath.ScheduleRestore("player_init")
            end
            return DarkPassengerQuestBridge.StartPolling("player_init")
        end)
        PlayerEventDispatcher:Register("OnActionEvent", function(...)
            if DarkPassengerHunger ~= nil and
               DarkPassengerHunger.EnsureEvaluationFromPlayerAction ~= nil then
                DarkPassengerHunger.EnsureEvaluationFromPlayerAction(...)
            end
            if DarkPassengerAftermath ~= nil and
               DarkPassengerAftermath.EnsureRestoreFromPlayerAction ~= nil then
                DarkPassengerAftermath.EnsureRestoreFromPlayerAction(...)
            end
            return DarkPassengerQuestBridge.EnsurePollingFromPlayerAction(...)
        end)
        DarkPassengerTest._hooksRegistered = true
        System.LogAlways("[DarkPassenger] v11 loaded OK (cold). Hooks registered via trampolines. Hot-reload safe.")
    else
        System.LogAlways("[DarkPassenger] v11 RELOADED OK. Handlers redefined; hooks already live (no double-register).")
    end
else
    System.LogAlways("[DarkPassenger] WARNING: PlayerEventDispatcher global not found! Check 'a_PlayerEventDispatcher' is installed and active.")
end
