DarkPassengerBelongings = DarkPassengerBelongings or {}

DarkPassengerBelongings.SCHEMA_VERSION = 2
DarkPassengerBelongings.POLL_INTERVAL_MS = 500
DarkPassengerBelongings.timerSerial =
    tonumber(DarkPassengerBelongings.timerSerial) or 0

local KEYS = {
    schema = "dp_belongings_schema_version",
    placedGeneration = "dp_belongings_placed_generation",
    readGeneration = "dp_belongings_read_generation",
}

local function Log(message)
    if System ~= nil and System.LogAlways ~= nil then
        System.LogAlways(
            "[DarkPassenger][Belongings] " .. tostring(message)
        )
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
    return { placedGeneration = 0, readGeneration = 0 }
end

local function CopyState(state)
    return {
        placedGeneration =
            tonumber(state ~= nil and state.placedGeneration) or 0,
        readGeneration =
            tonumber(state ~= nil and state.readGeneration) or 0,
    }
end

local function ReadState()
    if tonumber(ReadScalar(KEYS.schema)) ~=
       DarkPassengerBelongings.SCHEMA_VERSION then
        return DefaultState()
    end
    return {
        placedGeneration =
            tonumber(ReadScalar(KEYS.placedGeneration)) or 0,
        readGeneration =
            tonumber(ReadScalar(KEYS.readGeneration)) or 0,
    }
end

local function PersistState(state)
    local results = {
        WriteScalar(KEYS.schema, DarkPassengerBelongings.SCHEMA_VERSION),
        WriteScalar(KEYS.placedGeneration, state.placedGeneration),
        WriteScalar(KEYS.readGeneration, state.readGeneration),
    }
    for _, succeeded in ipairs(results) do
        if not succeeded then return false end
    end
    return true
end

function DarkPassengerBelongings.Transition(state, event)
    local nextState = CopyState(state)
    local generation = tonumber(event ~= nil and event.generation)
    local eventType = event ~= nil and event.type or nil
    if generation == nil or generation <= 0 then
        return nextState, { accepted = false, reason = "invalid_generation" }
    end
    if eventType == "place" then
        if nextState.readGeneration == generation then
            return nextState, { accepted = false, reason = "already_read" }
        end
        if nextState.placedGeneration == generation then
            return nextState, { accepted = false, reason = "already_placed" }
        end
        nextState.placedGeneration = generation
        return nextState, { accepted = true, reason = "placed" }
    end
    if eventType == "read" then
        if nextState.readGeneration == generation then
            return nextState, { accepted = false, reason = "already_read" }
        end
        if nextState.placedGeneration ~= generation then
            return nextState, { accepted = false, reason = "not_placed" }
        end
        nextState.readGeneration = generation
        return nextState, { accepted = true, reason = "read" }
    end
    return nextState, { accepted = false, reason = "unknown_event" }
end

local function CurrentGenerationMatches(generation)
    if DarkPassengerInvestigation == nil or
       DarkPassengerInvestigation.GetState == nil then
        return false
    end
    local investigation = DarkPassengerInvestigation.GetState()
    return investigation ~= nil and investigation.active == true and
        tonumber(investigation.generation) == tonumber(generation)
end

local function InventoryHas(inventory, itemGuid)
    if inventory == nil or inventory.FindItem == nil then return false end
    local ok, itemId = pcall(function()
        return inventory:FindItem(itemGuid)
    end)
    return ok and itemId ~= nil and itemId ~= 0
end

local function PlayerEntity()
    if g_localActor ~= nil then return g_localActor end
    if player ~= nil then return player end
    if System ~= nil and System.GetEntityByName ~= nil then
        return System.GetEntityByName("dude")
    end
    return nil
end

local function ResolveDocument(generation)
    if DarkPassengerCaseEvidence == nil or
       DarkPassengerCaseEvidence.ResolveActive == nil then
        return nil
    end
    local resolved = DarkPassengerCaseEvidence.ResolveActive("document")
    if resolved == nil then return nil end
    if generation ~= nil and
       tonumber(resolved.generation) ~= tonumber(generation) then
        return nil
    end
    return resolved
end

local function PlayerInventoryHas(itemGuid)
    local actor = PlayerEntity()
    return actor ~= nil and InventoryHas(actor.inventory, itemGuid)
end

local function DeleteAllFromInventory(inventory, itemGuid)
    if inventory == nil or inventory.FindItem == nil or
       inventory.DeleteItem == nil then
        return 0
    end
    local removed = 0
    for _ = 1, 64 do
        local found, itemId = pcall(function()
            return inventory:FindItem(itemGuid)
        end)
        if not found or itemId == nil or itemId == 0 then break end
        local deleted, result = pcall(function()
            return inventory:DeleteItem(itemId, 1)
        end)
        if not deleted or result == false then break end
        removed = removed + 1
    end
    return removed
end

local function WasOpened(generation)
    local resolved = ResolveDocument(generation)
    local documentGuid = resolved ~= nil and
        resolved.binding.documentGuid or nil
    if documentGuid == nil then return nil end
    if Minigame == nil or Minigame.WasBookOpened == nil then return nil end
    local ok, opened = pcall(function()
        return Minigame.WasBookOpened(documentGuid)
    end)
    if not ok then
        Log("read probe failed error=" .. tostring(opened))
        return nil
    end
    return opened == true or opened == 1
end

local function ResolveChest(generation)
    local resolved = ResolveDocument(generation)
    local containerGuid = resolved ~= nil and
        resolved.binding.containerGuid or nil
    if containerGuid == nil then return nil end
    if System == nil or System.GetEntityByTextGUID == nil then return nil end
    return System.GetEntityByTextGUID(containerGuid)
end

local function EnsurePlaced(generation)
    local resolved = ResolveDocument(generation)
    if resolved == nil then
        Log("placement deferred: document case binding unavailable")
        return false
    end
    local documentGuid = resolved.binding.documentGuid
    local containerGuid = resolved.binding.containerGuid
    local state = ReadState()
    if state.readGeneration == generation then return true end

    local opened = WasOpened(generation)
    if state.placedGeneration == generation and opened == true then
        return true
    end

    local chest = ResolveChest(generation)
    if chest == nil or chest.inventory == nil or
       chest.inventory.CreateItem == nil then
        Log("placement deferred: bedside chest unavailable")
        return false
    end

    local exists = InventoryHas(
        chest.inventory,
        documentGuid
    ) or PlayerInventoryHas(documentGuid)
    if state.placedGeneration == generation and exists then return true end
    if opened == true then
        Log("placement blocked: vanilla document was already opened")
        return false
    end
    if not exists then
        local ok, result = pcall(function()
            return chest.inventory:CreateItem(
                documentGuid,
                1,
                1
            )
        end)
        if not ok then
            Log("placement failed error=" .. tostring(result))
            return false
        end
    end

    if state.placedGeneration == generation then
        Log(
            "document placement repaired generation=" ..
            tostring(generation) ..
            " chest=" .. tostring(containerGuid)
        )
        return true
    end

    local nextState, transition = DarkPassengerBelongings.Transition(
        state,
        { type = "place", generation = generation }
    )
    if not transition.accepted then return transition.reason == "already_placed" end
    if not PersistState(nextState) then return false end
    Log(
        "document placed generation=" .. tostring(generation) ..
        " chest=" .. tostring(containerGuid) ..
        " existing=" .. tostring(exists)
    )
    return true
end

local function Schedule(generation, timerSerial)
    if Script == nil or Script.SetTimerForFunction == nil then
        Log("poll unavailable")
        return false
    end
    local ok, timerOrError = pcall(function()
        return Script.SetTimerForFunction(
            DarkPassengerBelongings.POLL_INTERVAL_MS,
            "DarkPassengerBelongings.Poll",
            { generation = generation, timerSerial = timerSerial }
        )
    end)
    if not ok then
        Log("poll scheduling failed error=" .. tostring(timerOrError))
        return false
    end
    return true
end

local function AwardReadEvidence(generation)
    local state = ReadState()
    if state.readGeneration == generation then return true end
    if DarkPassengerInvestigation == nil or
       DarkPassengerInvestigation.AddEvidence == nil then
        return false
    end
    local resolved = ResolveDocument(generation)
    if resolved == nil then return false end
    local result = DarkPassengerInvestigation.AddEvidence(
        resolved.evidence.confidence,
        resolved.evidence.id,
        generation
    )
    if result == nil or result.accepted ~= true then
        Log(
            "read evidence rejected reason=" ..
            tostring(result ~= nil and result.reason or nil)
        )
        return false
    end
    local nextState, transition = DarkPassengerBelongings.Transition(
        state,
        { type = "read", generation = generation }
    )
    if not transition.accepted or not PersistState(nextState) then return false end
    local reaction = nil
    if DarkPassengerEvidenceReaction ~= nil and
       DarkPassengerEvidenceReaction.Dispatch ~= nil then
        reaction = DarkPassengerEvidenceReaction.Dispatch(
            resolved.evidence.id,
            generation
        )
    end
    Log(
        "document read generation=" .. tostring(generation) ..
        " confidence=" .. tostring(result.current) ..
        " reaction=" ..
        tostring(reaction ~= nil and reaction.reaction or nil)
    )
    if DarkPassengerWitnessLead ~= nil and
       DarkPassengerWitnessLead.Start ~= nil then
        DarkPassengerWitnessLead.Start(generation)
    end
    return true
end

local function EnsureReaction(generation)
    if DarkPassengerEvidenceReaction == nil or
       DarkPassengerEvidenceReaction.Restore == nil then
        return false
    end
    local resolved = ResolveDocument(generation)
    if resolved == nil then return false end
    local result = DarkPassengerEvidenceReaction.Restore(
        resolved.evidence.id,
        generation
    )
    return result ~= nil and (
        result.accepted == true or result.reason == "already_dispatched"
    )
end

function DarkPassengerBelongings.Poll(payload, timerId)
    local generation = payload ~= nil and tonumber(payload.generation) or nil
    local timerSerial =
        payload ~= nil and tonumber(payload.timerSerial) or nil
    if generation == nil or
       timerSerial ~= DarkPassengerBelongings.timerSerial or
       not CurrentGenerationMatches(generation) then
        return false
    end
    local state = ReadState()
    if state.readGeneration == generation then
        EnsureReaction(generation)
        if DarkPassengerWitnessLead ~= nil and
           DarkPassengerWitnessLead.Restore ~= nil then
            DarkPassengerWitnessLead.Restore(generation)
        end
        return true
    end
    if not EnsurePlaced(generation) then
        return Schedule(generation, timerSerial)
    end
    if WasOpened(generation) == true then return AwardReadEvidence(generation) end
    return Schedule(generation, timerSerial)
end

function DarkPassengerBelongings.Start(generation)
    generation = tonumber(generation)
    if generation == nil or not CurrentGenerationMatches(generation) then
        Log("start rejected generation=" .. tostring(generation))
        return false
    end
    local state = ReadState()
    if state.readGeneration == generation then
        EnsureReaction(generation)
        if DarkPassengerWitnessLead ~= nil and
           DarkPassengerWitnessLead.Restore ~= nil then
            DarkPassengerWitnessLead.Restore(generation)
        end
        Log("start restored: document already read generation=" .. tostring(generation))
        return true
    end
    DarkPassengerBelongings.timerSerial =
        DarkPassengerBelongings.timerSerial + 1
    local timerSerial = DarkPassengerBelongings.timerSerial
    EnsurePlaced(generation)
    Log(
        "poll started generation=" .. tostring(generation) ..
        " serial=" .. tostring(timerSerial) ..
        " opened=" .. tostring(WasOpened(generation))
    )
    return DarkPassengerBelongings.Poll(
        { generation = generation, timerSerial = timerSerial }
    )
end

function DarkPassengerBelongings.OnRumorAwarded(generation)
    return DarkPassengerBelongings.Start(generation)
end

function DarkPassengerBelongings.Status()
    local state = ReadState()
    local investigation =
        DarkPassengerInvestigation ~= nil and
        DarkPassengerInvestigation.GetState ~= nil and
        DarkPassengerInvestigation.GetState() or nil
    local generation = investigation ~= nil and investigation.generation or nil
    Log(
        "status placedGeneration=" .. tostring(state.placedGeneration) ..
        " readGeneration=" .. tostring(state.readGeneration) ..
        " timerSerial=" .. tostring(DarkPassengerBelongings.timerSerial) ..
        " opened=" .. tostring(WasOpened(generation))
    )
    return state
end

function DarkPassengerBelongings.ResetCanary(generation)
    if DarkPassengerInvestigation == nil or
       DarkPassengerInvestigation.GetState == nil or
       DarkPassengerInvestigation.DebugSetConfidence == nil then
        Log("canary reset rejected: investigation debug API unavailable")
        return false
    end
    local investigation = DarkPassengerInvestigation.GetState()
    generation = tonumber(generation) or
        tonumber(investigation ~= nil and investigation.generation)
    if investigation == nil or investigation.active ~= true or
       generation == nil or generation ~= tonumber(investigation.generation) then
        Log("canary reset rejected: no matching active investigation")
        return false
    end
    local resolved = ResolveDocument(generation)
    if resolved == nil then
        Log("canary reset rejected: document case binding unavailable")
        return false
    end
    local documentGuid = resolved.binding.documentGuid
    local legacyDocumentGuid = resolved.binding.legacyDocumentGuid
    local openerConfidence =
        resolved.selected ~= nil and resolved.selected.rumor ~= nil and
        tonumber(resolved.selected.rumor.confidence) or 0
    if WasOpened(generation) == true then
        Log(
            "canary reset rejected: native opened state cannot be cleared " ..
            "for document=" .. tostring(documentGuid)
        )
        return false
    end

    local chest = ResolveChest(generation)
    local actor = PlayerEntity()
    if chest == nil or chest.inventory == nil or
       actor == nil or actor.inventory == nil then
        Log("canary reset rejected: inventory unavailable")
        return false
    end
    if not DarkPassengerInvestigation.DebugSetConfidence(
        openerConfidence,
        generation
    ) then
        Log("canary reset rejected: confidence reset failed")
        return false
    end

    local playerRemoved =
        DeleteAllFromInventory(
            actor.inventory,
            documentGuid
        )
    if legacyDocumentGuid ~= nil then
        playerRemoved = playerRemoved + DeleteAllFromInventory(
            actor.inventory,
            legacyDocumentGuid
        )
    end
    local chestRemoved =
        DeleteAllFromInventory(
            chest.inventory,
            documentGuid
        )
    if legacyDocumentGuid ~= nil then
        chestRemoved = chestRemoved + DeleteAllFromInventory(
            chest.inventory,
            legacyDocumentGuid
        )
    end

    if not PersistState(DefaultState()) then return false end
    if DarkPassengerEvidenceReaction ~= nil and
       DarkPassengerEvidenceReaction.Reset ~= nil then
        DarkPassengerEvidenceReaction.Reset(
            resolved.evidence.id
        )
    end
    if not EnsurePlaced(generation) then return false end

    DarkPassengerBelongings.timerSerial =
        DarkPassengerBelongings.timerSerial + 1
    local serial = DarkPassengerBelongings.timerSerial
    Schedule(generation, serial)
    Log(
        "canary reset generation=" .. tostring(generation) ..
        " confidence=" .. tostring(openerConfidence) ..
        " playerRemoved=" .. tostring(playerRemoved) ..
        " chestRemoved=" .. tostring(chestRemoved) ..
        " playerHas=" .. tostring(PlayerInventoryHas(
            documentGuid
        )) ..
        " chestHas=" .. tostring(InventoryHas(
            chest.inventory,
            documentGuid
        ))
    )
    return true
end

function DarkPassengerBelongings.RunSelfTest()
    local failures = {}
    local function Expect(condition, label)
        if not condition then table.insert(failures, label) end
    end
    local state = DefaultState()
    local placed
    state, placed = DarkPassengerBelongings.Transition(
        state,
        { type = "place", generation = 7 }
    )
    Expect(placed.accepted and state.placedGeneration == 7, "place")
    local duplicateState, duplicate = DarkPassengerBelongings.Transition(
        state,
        { type = "place", generation = 7 }
    )
    Expect(
        not duplicate.accepted and duplicate.reason == "already_placed" and
        duplicateState.placedGeneration == 7,
        "duplicate place"
    )
    local read
    state, read = DarkPassengerBelongings.Transition(
        state,
        { type = "read", generation = 7 }
    )
    Expect(read.accepted and state.readGeneration == 7, "read")
    local staleState, stale = DarkPassengerBelongings.Transition(
        DefaultState(),
        { type = "read", generation = 6 }
    )
    Expect(
        not stale.accepted and stale.reason == "not_placed" and
        staleState.readGeneration == 0,
        "read requires placement"
    )
    local passed = #failures == 0
    Log(
        "selftest=" .. tostring(passed) ..
        " failures=" .. table.concat(failures, ",")
    )
    return passed
end

pcall(function()
    if System ~= nil and System.AddCCommand ~= nil then
        System.AddCCommand(
            "dp_belongings_status",
            "DarkPassengerBelongings.Status()",
            "Dark Passenger: print Vojtech belongings state"
        )
        System.AddCCommand(
            "dp_belongings_start",
            "DarkPassengerBelongings.Start(%line)",
            "Dark Passenger: start Vojtech belongings canary"
        )
        System.AddCCommand(
            "dp_belongings_selftest",
            "DarkPassengerBelongings.RunSelfTest()",
            "Dark Passenger: run Vojtech belongings self-test"
        )
        System.AddCCommand(
            "dp_belongings_reset_canary",
            "DarkPassengerBelongings.ResetCanary(%line)",
            "Dark Passenger: reset fresh Vojtech document canary"
        )
    end
end)

Log("module loaded")
