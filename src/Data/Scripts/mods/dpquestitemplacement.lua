DarkPassengerQuestItemPlacement = DarkPassengerQuestItemPlacement or {}

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
    return catalog[tostring(itemGuid)]
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
    if HasRequest(actor, entry) then return true end
    local ok, result = pcall(function()
        return actor.soul:AddBuff(entry.buff_guid)
    end)
    if not ok or result == false then
        Log(
            "native request failed item=" .. tostring(entry.item_guid) ..
            " error=" .. tostring(result)
        )
        return false
    end
    return true
end

function DarkPassengerQuestItemPlacement.Count(inventory, itemGuid)
    return InventoryCount(inventory, itemGuid)
end

function DarkPassengerQuestItemPlacement.Request(
    itemGuid,
    destination,
    playerBaseline
)
    itemGuid = tostring(itemGuid or "")
    playerBaseline = tonumber(playerBaseline) or 0
    local entry = CatalogEntry(itemGuid)
    if entry == nil then
        Log("request rejected: no native signal item=" .. itemGuid)
        return false, "signal_unavailable"
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
        if entry.backend ~= "quest_effect_stash" then
            ClearRequest(actor, entry)
        end
        return true, "already_placed"
    end

    if entry.backend == "quest_effect_stash" then
        if not AddRequest(actor, entry) then
            return false, "request_failed"
        end
        return false, "native_requested"
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
        ClearRequest(actor, entry)
        return InventoryCount(destination.inventory, itemGuid) > 0
    end

    if MoveCreatedItem() then return true, "moved" end

    if not AddRequest(actor, entry) then
        return false, "request_failed"
    end
    if MoveCreatedItem() then return true, "moved" end
    return false, "native_requested"
end

function DarkPassengerQuestItemPlacement.Cancel(itemGuid)
    local actor = PlayerEntity()
    local entry = CatalogEntry(tostring(itemGuid or ""))
    return ClearRequest(actor, entry)
end

Log("module loaded")
