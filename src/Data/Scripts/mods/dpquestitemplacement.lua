DarkPassengerQuestItemPlacement = DarkPassengerQuestItemPlacement or {}

DarkPassengerQuestItemPlacement.REISSUE_INTERVAL_SECONDS = 5
DarkPassengerQuestItemPlacement.pendingRequests =
    DarkPassengerQuestItemPlacement.pendingRequests or {}

local function Log(message)
    if System ~= nil and System.LogAlways ~= nil then
        System.LogAlways(
            "[DarkPassenger][QuestItemPlacement] " .. tostring(message)
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

local function InventoryCount(inventory, itemGuid)
    if inventory == nil then return 0 end
    if inventory.GetCountOfClass ~= nil then
        local ok, count = pcall(function()
            return inventory:GetCountOfClass(itemGuid)
        end)
        if ok then return tonumber(count) or 0 end
    end
    if inventory.FindItem ~= nil then
        local ok, itemId = pcall(function()
            return inventory:FindItem(itemGuid)
        end)
        if ok and itemId ~= nil and itemId ~= 0 then return 1 end
    end
    return 0
end

local function CatalogEntry(itemGuid)
    local catalog = DarkPassengerQuestItemPlacementCatalog
    if type(catalog) ~= "table" then return nil end
    return catalog[string.lower(tostring(itemGuid or ""))]
end

local function CurrentTime()
    if System ~= nil and System.GetCurrTime ~= nil then
        local ok, value = pcall(function()
            return System.GetCurrTime()
        end)
        if ok then return tonumber(value) end
    end
    if os ~= nil and os.clock ~= nil then
        local ok, value = pcall(os.clock)
        if ok then return tonumber(value) end
    end
    return nil
end

local function PendingKey(itemGuid, requestKey, request)
    local destination = tostring(requestKey or "")
    if destination == "" and request ~= nil then
        destination = tostring(request.buff_guid or "")
    end
    return string.lower(tostring(itemGuid or "")) .. ":" ..
        string.lower(destination)
end

local function ClearPending(itemGuid, requestKey, request)
    DarkPassengerQuestItemPlacement.pendingRequests[
        PendingKey(itemGuid, requestKey, request)
    ] = nil
end

local function ClearPendingItem(itemGuid)
    local prefix = string.lower(tostring(itemGuid or "")) .. ":"
    for key, _ in pairs(DarkPassengerQuestItemPlacement.pendingRequests) do
        if string.sub(key, 1, string.len(prefix)) == prefix then
            DarkPassengerQuestItemPlacement.pendingRequests[key] = nil
        end
    end
end

local function ResolveRequest(entry, requestKey)
    if entry == nil then return nil end
    if type(entry.requests) ~= "table" then return entry end
    local key = string.lower(tostring(requestKey or ""))
    if key ~= "" and entry.requests[key] ~= nil then
        return entry.requests[key]
    end
    local defaultKey = string.lower(tostring(entry.default_request_key or ""))
    if defaultKey ~= "" then return entry.requests[defaultKey] end
    return nil
end

local function ClearRequest(actor, entry)
    if actor == nil or actor.soul == nil or
       actor.soul.RemoveAllBuffsByGuid == nil or entry == nil then
        return false
    end
    local ok = pcall(function()
        actor.soul:RemoveAllBuffsByGuid(entry.buff_guid)
    end)
    return ok
end

local function HasRequest(actor, entry)
    if actor == nil or actor.soul == nil or
       actor.soul.HasBuffDebug == nil or entry == nil then
        return false
    end
    local ok, result = pcall(function()
        return actor.soul:HasBuffDebug(entry.buff_guid)
    end)
    return ok and result == true
end

local function AddRequest(actor, entry)
    if HasRequest(actor, entry) then return true, false end
    local ok, result = pcall(function()
        return actor.soul:AddBuff(entry.buff_guid)
    end)
    if not ok or result == false then
        Log(
            "native request failed item=" .. tostring(entry.item_guid) ..
            " error=" .. tostring(result)
        )
        return false, false
    end
    return true, true
end

function DarkPassengerQuestItemPlacement.Count(inventory, itemGuid)
    return InventoryCount(inventory, itemGuid)
end

function DarkPassengerQuestItemPlacement.Request(
    itemGuid,
    destination,
    playerBaseline,
    requestKey
)
    itemGuid = tostring(itemGuid or "")
    playerBaseline = tonumber(playerBaseline) or 0
    local entry = CatalogEntry(itemGuid)
    if entry == nil then
        Log("request rejected: no native signal item=" .. itemGuid)
        return false, "signal_unavailable"
    end
    local request = ResolveRequest(entry, requestKey)
    if request == nil then
        Log(
            "request rejected: no destination signal item=" .. itemGuid ..
            " key=" .. tostring(requestKey)
        )
        return false, "destination_signal_unavailable"
    end
    if destination == nil or destination.inventory == nil or
       destination.inventory.GetId == nil then
        return false, "destination_unavailable"
    end
    local actor = PlayerEntity()
    if actor == nil or actor.inventory == nil or actor.soul == nil or
       actor.soul.AddBuff == nil then
        return false, "player_unavailable"
    end

    if InventoryCount(destination.inventory, itemGuid) > 0 then
        ClearPending(itemGuid, requestKey, request)
        if entry.backend ~= "quest_effect_stash" then
            ClearRequest(actor, request)
        end
        return true, "already_placed"
    end

    if entry.backend == "quest_effect_stash" then
        local pendingKey = PendingKey(itemGuid, requestKey, request)
        local now = CurrentTime()
        local lastIssuedAt = tonumber(
            DarkPassengerQuestItemPlacement.pendingRequests[pendingKey]
        )
        if lastIssuedAt ~= nil and (
            now == nil or now - lastIssuedAt <
                DarkPassengerQuestItemPlacement.REISSUE_INTERVAL_SECONDS
        ) then
            return false, "native_pending"
        end
        local accepted, issued = AddRequest(actor, request)
        if not accepted then
            return false, "request_failed"
        end
        DarkPassengerQuestItemPlacement.pendingRequests[pendingKey] = now or 0
        if issued then return false, "native_requested" end
        return false, "native_pending"
    end

    local function MoveCreatedItem()
        if InventoryCount(actor.inventory, itemGuid) <= playerBaseline or
           actor.inventory.MoveItemOfClass == nil then
            return false
        end
        local ok, moved = pcall(function()
            return actor.inventory:MoveItemOfClass(
                destination.inventory:GetId(),
                itemGuid,
                1,
                true
            )
        end)
        if not ok or (tonumber(moved) or 0) < 1 then return false end
        ClearRequest(actor, request)
        return InventoryCount(destination.inventory, itemGuid) > 0
    end

    if MoveCreatedItem() then return true, "moved" end

    if not AddRequest(actor, request) then
        return false, "request_failed"
    end
    if MoveCreatedItem() then return true, "moved" end
    return false, "native_requested"
end

function DarkPassengerQuestItemPlacement.Cancel(itemGuid)
    local actor = PlayerEntity()
    local entry = CatalogEntry(tostring(itemGuid or ""))
    if entry == nil then return false end
    ClearPendingItem(itemGuid)
    if type(entry.requests) ~= "table" then
        return ClearRequest(actor, entry)
    end
    local cleared = false
    for _, request in pairs(entry.requests) do
        if ClearRequest(actor, request) then cleared = true end
    end
    return cleared
end

Log("module loaded")
