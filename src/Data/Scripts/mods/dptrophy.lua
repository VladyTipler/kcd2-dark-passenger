DarkPassengerTrophy = DarkPassengerTrophy or {}

DarkPassengerTrophy.SCHEMA_VERSION = 2
DarkPassengerTrophy.POLL_INTERVAL_MS = 750
DarkPassengerTrophy.timerSerial =
    tonumber(DarkPassengerTrophy.timerSerial) or 0

local STATUS_PENDING = "pending"
local STATUS_PLACED = "placed"
local STATUS_COLLECTED = "collected"
local STATUS_CODES = {
    [STATUS_PENDING] = 0,
    [STATUS_PLACED] = 1,
    [STATUS_COLLECTED] = 2,
}
local CODE_STATUSES = {
    [0] = STATUS_PENDING,
    [1] = STATUS_PLACED,
    [2] = STATUS_COLLECTED,
}
local KEYS = {
    schema = "dp_trophy_schema_version",
    generation = "dp_trophy_generation",
    variantCode = "dp_trophy_variant_code",
    status = "dp_trophy_status",
    playerBaseline = "dp_trophy_player_baseline",
}

local function Log(message)
    if System ~= nil and System.LogAlways ~= nil then
        System.LogAlways("[DarkPassenger][Trophy] " .. tostring(message))
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
        generation = 0,
        variantCode = 0,
        status = STATUS_PENDING,
        corpseName = "",
        playerBaseline = 0,
    }
end

local function CopyState(state)
    local status = state ~= nil and state.status or STATUS_PENDING
    if STATUS_CODES[status] == nil then status = STATUS_PENDING end
    return {
        generation = tonumber(state ~= nil and state.generation) or 0,
        variantCode = tonumber(state ~= nil and state.variantCode) or 0,
        status = status,
        corpseName = tostring(state ~= nil and state.corpseName or ""),
        playerBaseline =
            tonumber(state ~= nil and state.playerBaseline) or 0,
    }
end

local function ReadState()
    if tonumber(ReadScalar(KEYS.schema)) ~=
       DarkPassengerTrophy.SCHEMA_VERSION then
        return DefaultState()
    end
    return {
        generation = tonumber(ReadScalar(KEYS.generation)) or 0,
        variantCode = tonumber(ReadScalar(KEYS.variantCode)) or 0,
        status = CODE_STATUSES[tonumber(ReadScalar(KEYS.status)) or 0] or
            STATUS_PENDING,
        corpseName = "",
        playerBaseline =
            tonumber(ReadScalar(KEYS.playerBaseline)) or 0,
    }
end

local function PersistState(state)
    local writes = {
        WriteScalar(KEYS.schema, DarkPassengerTrophy.SCHEMA_VERSION),
        WriteScalar(KEYS.generation, state.generation),
        WriteScalar(KEYS.variantCode, state.variantCode),
        WriteScalar(KEYS.status, STATUS_CODES[state.status] or 0),
        WriteScalar(KEYS.playerBaseline, state.playerBaseline or 0),
    }
    for _, succeeded in ipairs(writes) do
        if not succeeded then return false end
    end
    return true
end

function DarkPassengerTrophy.GetState()
    return ReadState()
end

function DarkPassengerTrophy.Transition(state, event)
    local nextState = CopyState(state)
    local eventType = event ~= nil and event.type or nil
    local generation = tonumber(event ~= nil and event.generation)
    local variantCode = tonumber(event ~= nil and event.variantCode)

    if eventType == "arm" then
        if generation == nil or generation <= 0 or
           variantCode == nil or variantCode <= 0 then
            return nextState, { accepted = false, reason = "invalid_identity" }
        end
        if generation < nextState.generation then
            return nextState, { accepted = false, reason = "stale_generation" }
        end
        if generation == nextState.generation and
           variantCode == nextState.variantCode then
            return nextState, {
                accepted = true,
                reason = "already_" .. nextState.status,
            }
        end
        return {
            generation = generation,
            variantCode = variantCode,
            status = STATUS_PENDING,
            corpseName = tostring(event.corpseName or ""),
            playerBaseline = tonumber(event.playerBaseline) or 0,
        }, { accepted = true, reason = "armed" }
    end

    if generation ~= nextState.generation or
       variantCode ~= nextState.variantCode or generation == nil then
        return nextState, { accepted = false, reason = "stale_generation" }
    end
    if eventType == "place" then
        if nextState.status == STATUS_COLLECTED then
            return nextState, { accepted = false, reason = "already_collected" }
        end
        if nextState.status == STATUS_PLACED then
            return nextState, { accepted = false, reason = "already_placed" }
        end
        nextState.status = STATUS_PLACED
        return nextState, { accepted = true, reason = "placed" }
    end
    if eventType == "collect" then
        if nextState.status == STATUS_COLLECTED then
            return nextState, { accepted = false, reason = "already_collected" }
        end
        nextState.status = STATUS_COLLECTED
        return nextState, { accepted = true, reason = "collected" }
    end
    return nextState, { accepted = false, reason = "unknown_event" }
end

local function PlayerEntity()
    if g_localActor ~= nil then return g_localActor end
    if player ~= nil then return player end
    if System ~= nil and System.GetEntityByName ~= nil then
        return System.GetEntityByName("dude")
    end
    return nil
end

local function InventoryHas(inventory, itemGuid)
    if inventory == nil or inventory.FindItem == nil then return false end
    local ok, itemId = pcall(function()
        return inventory:FindItem(itemGuid)
    end)
    return ok and itemId ~= nil and itemId ~= 0
end

local function PlayerInventoryHas(itemGuid)
    local actor = PlayerEntity()
    return actor ~= nil and InventoryHas(actor.inventory, itemGuid)
end

local function PlayerInventoryCount(itemGuid)
    local actor = PlayerEntity()
    if actor == nil or actor.inventory == nil then return 0 end
    if DarkPassengerQuestItemPlacement ~= nil and
       DarkPassengerQuestItemPlacement.Count ~= nil then
        return DarkPassengerQuestItemPlacement.Count(
            actor.inventory,
            itemGuid
        )
    end
    return PlayerInventoryHas(itemGuid) and 1 or 0
end

local function ResolveSnapshot(generation)
    if DarkPassengerCaseSnapshot == nil or
       DarkPassengerCaseSnapshot.Get == nil then
        return nil, "snapshot_unavailable"
    end
    return DarkPassengerCaseSnapshot.Get(generation)
end

local function ResolveTrophy(generation)
    local snapshot, reason = ResolveSnapshot(generation)
    local variant = snapshot ~= nil and snapshot.variant or nil
    local trophy = variant ~= nil and variant.trophy or nil
    if trophy == nil or trophy.item_guid == nil then
        return nil, reason or "trophy_unavailable", snapshot
    end
    return trophy, "resolved", snapshot
end

local function ResolveExpectedCorpseName(state)
    if state ~= nil and tostring(state.corpseName or "") ~= "" then
        return tostring(state.corpseName)
    end
    local snapshot = ResolveSnapshot(state ~= nil and state.generation or nil)
    local candidate = snapshot ~= nil and snapshot.candidate or nil
    return tostring(candidate ~= nil and candidate.entityName or "")
end

local function EntityName(entity)
    if entity == nil or entity.GetName == nil then return "" end
    local ok, name = pcall(function() return entity:GetName() end)
    if not ok or name == nil then return "" end
    return tostring(name)
end

local function ResolveCorpse(state)
    if state == nil or System == nil or System.GetEntityByName == nil then
        return nil
    end
    if state.corpseName ~= "" then
        local corpse = System.GetEntityByName(state.corpseName)
        if corpse ~= nil then return corpse end
    end
    local entityName = ResolveExpectedCorpseName(state)
    if entityName == nil or tostring(entityName) == "" then return nil end
    return System.GetEntityByName(tostring(entityName))
end

local function ApplyTransition(state, event)
    local nextState, result = DarkPassengerTrophy.Transition(state, event)
    if result.accepted and not PersistState(nextState) then
        return state, { accepted = false, reason = "persistence_failed" }
    end
    return nextState, result
end

local function Reconcile(state, trophy, corpse)
    if state.status == STATUS_PLACED and
       PlayerInventoryCount(trophy.item_guid) > state.playerBaseline then
        local nextState, result = ApplyTransition(state, {
            type = "collect",
            generation = state.generation,
            variantCode = state.variantCode,
        })
        if result.accepted then
            Log(
                "collected generation=" .. tostring(state.generation) ..
                " item=" .. tostring(trophy.item_guid)
            )
        end
        return nextState.status == STATUS_COLLECTED, result.reason, nextState
    end
    if corpse ~= nil and corpse.inventory ~= nil and
       InventoryHas(corpse.inventory, trophy.item_guid) then
        local nextState, result = ApplyTransition(state, {
            type = "place",
            generation = state.generation,
            variantCode = state.variantCode,
        })
        return true, result.reason, nextState
    end
    if state.status == STATUS_COLLECTED then
        return true, "already_collected", state
    end
    if state.status == STATUS_PLACED then
        return false, "already_placed", state
    end
    if corpse == nil or corpse.inventory == nil then
        return false, "streaming_deferred", state
    end

    if corpse.inventory.CreateItem == nil then
        return false, "inventory_create_unavailable", state
    end
    local created, createResult = pcall(function()
        return corpse.inventory:CreateItem(trophy.item_guid, 1, 1)
    end)
    if not created then
        Log("creation failed error=" .. tostring(createResult))
        return false, "creation_failed", state
    end
    if not InventoryHas(corpse.inventory, trophy.item_guid) then
        return false, "creation_not_confirmed", state
    end
    local nextState, result = ApplyTransition(state, {
        type = "place",
        generation = state.generation,
        variantCode = state.variantCode,
    })
    if result.accepted then
        Log(
            "placed generation=" .. tostring(state.generation) ..
            " corpse=" .. tostring(state.corpseName) ..
            " item=" .. tostring(trophy.item_guid)
        )
    end
    return result.accepted, result.reason, nextState
end

function DarkPassengerTrophy.CanBuryCorpse(corpse)
    local state = ReadState()
    if state.generation <= 0 or state.variantCode <= 0 then
        return true, "not_armed"
    end

    local corpseName = EntityName(corpse)
    local expectedCorpseName = ResolveExpectedCorpseName(state)
    if expectedCorpseName == "" then
        Log("burial allowed reason=target_identity_unavailable")
        return true, "target_identity_unavailable"
    end
    if corpseName == "" or corpseName ~= expectedCorpseName then
        return true, "not_target"
    end
    if state.status == STATUS_COLLECTED then
        return true, "already_collected"
    end

    local trophy, reason = ResolveTrophy(state.generation)
    if trophy == nil then
        Log("burial blocked reason=" .. tostring(reason))
        return false, reason or "trophy_unavailable"
    end

    local _, reconcileReason, nextState = Reconcile(state, trophy, corpse)
    if nextState.status == STATUS_COLLECTED then
        return true, reconcileReason
    end
    return false, "trophy_not_collected"
end

local function Schedule(state)
    if Script == nil or Script.SetTimerForFunction == nil then
        return false
    end
    DarkPassengerTrophy.timerSerial =
        DarkPassengerTrophy.timerSerial + 1
    local serial = DarkPassengerTrophy.timerSerial
    local ok, errorMessage = pcall(function()
        return Script.SetTimerForFunction(
            DarkPassengerTrophy.POLL_INTERVAL_MS,
            "DarkPassengerTrophy.Poll",
            {
                generation = state.generation,
                variantCode = state.variantCode,
                timerSerial = serial,
            }
        )
    end)
    if not ok then
        Log("poll scheduling failed error=" .. tostring(errorMessage))
    end
    return ok
end

function DarkPassengerTrophy.Poll(payload)
    if payload == nil or
       tonumber(payload.timerSerial) ~= DarkPassengerTrophy.timerSerial then
        return false
    end
    local state = ReadState()
    if state.generation ~= tonumber(payload.generation) or
       state.variantCode ~= tonumber(payload.variantCode) then
        return false
    end
    local trophy, reason = ResolveTrophy(state.generation)
    if trophy == nil then
        if reason == "stale_generation" then
            Log("poll stopped reason=stale_generation")
            return false
        end
        Log("poll deferred reason=" .. tostring(reason))
        Schedule(state)
        return false
    end
    local complete, reconcileReason, nextState = Reconcile(
        state,
        trophy,
        ResolveCorpse(state)
    )
    if nextState.status == STATUS_COLLECTED then return true end
    if reconcileReason == "streaming_deferred" or
       reconcileReason == "already_placed" or not complete then
        Schedule(nextState)
    end
    return complete
end

function DarkPassengerTrophy.OnTargetDeath(targetEntity, generation)
    generation = tonumber(generation)
    if generation == nil and DarkPassengerInvestigation ~= nil and
       DarkPassengerInvestigation.GetState ~= nil then
        generation = tonumber(DarkPassengerInvestigation.GetState().generation)
    end
    local trophy, reason, snapshot = ResolveTrophy(generation)
    if trophy == nil or snapshot == nil then
        Log("death placement deferred reason=" .. tostring(reason))
        return false, reason
    end

    local corpseName = EntityName(targetEntity)
    if corpseName == "" and snapshot.candidate ~= nil then
        corpseName = tostring(snapshot.candidate.entityName or "")
    end
    local state = ReadState()
    local armed, armResult = DarkPassengerTrophy.Transition(state, {
        type = "arm",
        generation = generation,
        variantCode = snapshot.variantCode,
        corpseName = corpseName,
        playerBaseline = PlayerInventoryCount(trophy.item_guid),
    })
    if not armResult.accepted then return false, armResult.reason end
    if armed.corpseName == "" and corpseName ~= "" then
        armed.corpseName = corpseName
    end
    if not PersistState(armed) then return false, "persistence_failed" end

    local complete, reconcileReason, nextState = Reconcile(
        armed,
        trophy,
        targetEntity or ResolveCorpse(armed)
    )
    if nextState.status ~= STATUS_COLLECTED then Schedule(nextState) end
    return complete, reconcileReason
end

function DarkPassengerTrophy.Restore()
    local state = ReadState()
    if state.generation <= 0 or state.variantCode <= 0 then
        return false, "not_armed"
    end
    local trophy, reason = ResolveTrophy(state.generation)
    if trophy == nil then
        if reason == "stale_generation" then
            DarkPassengerTrophy.timerSerial = DarkPassengerTrophy.timerSerial + 1
            Log("restore stopped reason=stale_generation")
            return false, reason
        end
        Schedule(state)
        return false, reason or "streaming_deferred"
    end
    local complete, reconcileReason, nextState = Reconcile(
        state,
        trophy,
        ResolveCorpse(state)
    )
    if nextState.status ~= STATUS_COLLECTED then Schedule(nextState) end
    return complete, reconcileReason
end

function DarkPassengerTrophy.RunSelfTest()
    local armed, arm = DarkPassengerTrophy.Transition(DefaultState(), {
        type = "arm",
        generation = 5,
        variantCode = 9001,
        corpseName = "fixture_target",
    })
    local placed, place = DarkPassengerTrophy.Transition(armed, {
        type = "place",
        generation = 5,
        variantCode = 9001,
    })
    local _, duplicate = DarkPassengerTrophy.Transition(placed, {
        type = "place",
        generation = 5,
        variantCode = 9001,
    })
    local collected, collect = DarkPassengerTrophy.Transition(placed, {
        type = "collect",
        generation = 5,
        variantCode = 9001,
    })
    local _, stale = DarkPassengerTrophy.Transition(collected, {
        type = "place",
        generation = 4,
        variantCode = 9001,
    })
    local passed = arm.accepted and armed.status == STATUS_PENDING and
        place.accepted and placed.status == STATUS_PLACED and
        duplicate.reason == "already_placed" and
        collect.accepted and collected.status == STATUS_COLLECTED and
        stale.reason == "stale_generation"
    Log("selftest=" .. tostring(passed))
    return passed
end

pcall(function()
    if System ~= nil and System.AddCCommand ~= nil then
        System.AddCCommand(
            "dp_trophy_status",
            "DarkPassengerTrophy.GetState()",
            "Dark Passenger: show persisted target trophy state"
        )
        System.AddCCommand(
            "dp_trophy_selftest",
            "DarkPassengerTrophy.RunSelfTest()",
            "Dark Passenger: run target trophy lifecycle checks"
        )
    end
end)

pcall(function() DarkPassengerTrophy.Restore() end)
Log("module loaded")
