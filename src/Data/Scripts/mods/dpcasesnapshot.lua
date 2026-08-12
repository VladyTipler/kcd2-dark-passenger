DarkPassengerCaseSnapshot = DarkPassengerCaseSnapshot or {}

DarkPassengerCaseSnapshot.SCHEMA_VERSION = 2

local KEYS = {
    schema = "dp_case_snapshot_schema_version",
    generation = "dp_case_snapshot_generation",
    caseCode = "dp_case_snapshot_case_code",
    openerCode = "dp_case_snapshot_opener_code",
    variantCode = "dp_case_snapshot_variant_code",
    bindingCode = "dp_case_snapshot_binding_code",
    targetSlot = "dp_case_snapshot_target_slot",
    interrogationOffered = "dp_case_snapshot_interrogation_offered",
}

local function Log(message)
    if System ~= nil and System.LogAlways ~= nil then
        System.LogAlways(
            "[DarkPassenger][CaseSnapshot] " .. tostring(message)
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
    return {
        generation = 0,
        caseCode = 0,
        openerCode = 0,
        variantCode = 0,
        bindingCode = 0,
        targetSlot = 0,
        interrogationOffered = false,
    }
end

local function CopyState(state)
    return {
        generation = tonumber(state ~= nil and state.generation) or 0,
        caseCode = tonumber(state ~= nil and state.caseCode) or 0,
        openerCode = tonumber(state ~= nil and state.openerCode) or 0,
        variantCode = tonumber(state ~= nil and state.variantCode) or 0,
        bindingCode = tonumber(state ~= nil and state.bindingCode) or 0,
        targetSlot = tonumber(state ~= nil and state.targetSlot) or 0,
        interrogationOffered =
            state ~= nil and state.interrogationOffered == true or false,
    }
end

function DarkPassengerCaseSnapshot.MigrateLegacyState(legacy)
    local state = CopyState(legacy)
    state.variantCode = 0
    state.bindingCode = 0
    state.interrogationOffered = false
    return state, { accepted = true, reason = "legacy_v1" }
end

local function ReadState()
    local schema = tonumber(ReadScalar(KEYS.schema))
    if schema == DarkPassengerCaseSnapshot.SCHEMA_VERSION then
        return {
            generation = tonumber(ReadScalar(KEYS.generation)) or 0,
            caseCode = tonumber(ReadScalar(KEYS.caseCode)) or 0,
            openerCode = tonumber(ReadScalar(KEYS.openerCode)) or 0,
            variantCode = tonumber(ReadScalar(KEYS.variantCode)) or 0,
            bindingCode = tonumber(ReadScalar(KEYS.bindingCode)) or 0,
            targetSlot = tonumber(ReadScalar(KEYS.targetSlot)) or 0,
            interrogationOffered =
                tonumber(ReadScalar(KEYS.interrogationOffered)) == 1,
        }
    end
    if schema == 1 then
        local migrated = DarkPassengerCaseSnapshot.MigrateLegacyState({
            generation = tonumber(ReadScalar(KEYS.generation)) or 0,
            caseCode = tonumber(ReadScalar(KEYS.caseCode)) or 0,
            openerCode = tonumber(ReadScalar(KEYS.openerCode)) or 0,
            targetSlot = tonumber(ReadScalar(KEYS.targetSlot)) or 0,
        })
        return migrated
    end
    return DefaultState()
end

local function PersistState(state)
    local writes = {
        WriteScalar(
            KEYS.schema,
            DarkPassengerCaseSnapshot.SCHEMA_VERSION
        ),
        WriteScalar(KEYS.generation, state.generation),
        WriteScalar(KEYS.caseCode, state.caseCode),
        WriteScalar(KEYS.openerCode, state.openerCode),
        WriteScalar(KEYS.variantCode, state.variantCode),
        WriteScalar(KEYS.bindingCode, state.bindingCode),
        WriteScalar(KEYS.targetSlot, state.targetSlot),
        WriteScalar(
            KEYS.interrogationOffered,
            state.interrogationOffered and 1 or 0
        ),
    }
    for _, succeeded in ipairs(writes) do
        if not succeeded then return false end
    end
    return true
end

local function FindCandidate(targetSlot)
    local expected = tonumber(targetSlot)
    if expected == nil or expected <= 0 or
       DarkPassengerGeneratedCandidates == nil then
        return nil
    end
    for _, candidate in ipairs(DarkPassengerGeneratedCandidates) do
        if tonumber(candidate.slot) == expected then return candidate end
    end
    return nil
end

local function SameIdentity(left, right)
    return tonumber(left.generation) == tonumber(right.generation) and
        tonumber(left.caseCode) == tonumber(right.caseCode) and
        tonumber(left.openerCode) == tonumber(right.openerCode) and
        tonumber(left.variantCode) == tonumber(right.variantCode) and
        tonumber(left.bindingCode) == tonumber(right.bindingCode) and
        tonumber(left.targetSlot) == tonumber(right.targetSlot)
end

-- New saves persist the stable variant and binding hashes plus the stable
-- target slot. Existing schema-v1 saves remain legacy CaseInstances and keep
-- their original target; they are never replaced during migration.
function DarkPassengerCaseSnapshot.Transition(state, event)
    local nextState = CopyState(state)
    local requested = CopyState(event)
    local allowBindingMigration = event ~= nil and
        event.allowBindingMigration == true
    if requested.generation <= 0 or requested.caseCode <= 0 or
       requested.openerCode <= 0 or requested.targetSlot <= 0 then
        return nextState, { accepted = false, reason = "invalid_snapshot" }
    end
    if requested.variantCode > 0 and requested.bindingCode <= 0 then
        return nextState, { accepted = false, reason = "invalid_binding" }
    end
    if requested.generation < nextState.generation then
        return nextState, { accepted = false, reason = "stale_generation" }
    end
    if requested.generation == nextState.generation then
        if SameIdentity(nextState, requested) then
            nextState.interrogationOffered =
                nextState.interrogationOffered or
                requested.interrogationOffered
            return nextState, { accepted = true, reason = "restored" }
        end
        if allowBindingMigration and
           requested.caseCode == nextState.caseCode and
           requested.openerCode == nextState.openerCode and
           requested.targetSlot == nextState.targetSlot and
           requested.variantCode > 0 and requested.bindingCode > 0 then
            requested.interrogationOffered =
                nextState.interrogationOffered or
                requested.interrogationOffered
            return requested, {
                accepted = true,
                reason = "variant_migrated",
            }
        end
        return nextState, { accepted = false, reason = "snapshot_conflict" }
    end
    return requested, { accepted = true, reason = "captured" }
end

local function Resolve(state)
    if state == nil or state.generation <= 0 then
        return nil, "snapshot_missing"
    end
    if DarkPassengerCaseContent == nil or
       DarkPassengerCaseContent.GetSelected == nil then
        return nil, "case_content_unavailable"
    end
    local selected = DarkPassengerCaseContent.GetSelected(state.generation)
    if selected == nil or
       tonumber(selected.caseCode) ~= tonumber(state.caseCode) or
       tonumber(selected.openerCode) ~= tonumber(state.openerCode) or
       tonumber(selected.variantCode) ~= tonumber(state.variantCode) then
        return nil, "snapshot_conflict"
    end
    if state.variantCode > 0 and
       tonumber(selected.bindingCode) ~= tonumber(state.bindingCode) then
        return nil, "binding_conflict"
    end
    local candidate = FindCandidate(state.targetSlot)
    if candidate == nil then return nil, "candidate_unavailable" end
    if state.variantCode > 0 and
       tonumber(selected.targetSlot) ~= tonumber(state.targetSlot) then
        return nil, "target_conflict"
    end
    local caseTemplate = selected.caseTemplate
    local constraints = caseTemplate ~= nil and
        caseTemplate.constraints or {}
    if constraints.region ~= nil and
       constraints.region ~= candidate.gameRegion then
        return nil, "candidate_region_mismatch"
    end
    if constraints.settlement ~= nil and
       constraints.settlement ~= candidate.settlement then
        return nil, "candidate_settlement_mismatch"
    end
    local snapshot = {
        generation = state.generation,
        caseCode = state.caseCode,
        openerCode = state.openerCode,
        variantCode = state.variantCode,
        variantId = selected.variantId,
        bindingCode = state.bindingCode,
        targetSlot = state.targetSlot,
        interrogationOffered = state.interrogationOffered,
        candidate = candidate,
        region = candidate.gameRegion,
        settlement = candidate.settlement,
        selected = selected,
        variant = selected.variant,
        caseTemplate = caseTemplate,
        opener = selected.rumor,
        bindings = caseTemplate.bindings,
        sceneDefinitions = selected.sceneDefinitions or {},
    }
    if DarkPassengerSceneDirector ~= nil and
       DarkPassengerSceneDirector.BuildCaseInstance ~= nil then
        snapshot.caseInstance =
            DarkPassengerSceneDirector.BuildCaseInstance(snapshot)
        snapshot.sceneInstances = snapshot.caseInstance ~= nil and
            snapshot.caseInstance.sceneInstances or {}
    end
    return snapshot, state.variantCode > 0 and "resolved" or "legacy_v1"
end

function DarkPassengerCaseSnapshot.Capture(generation, candidate, selected)
    generation = tonumber(generation)
    if selected == nil and DarkPassengerCaseContent ~= nil and
       DarkPassengerCaseContent.GetSelected ~= nil then
        selected = DarkPassengerCaseContent.GetSelected(generation)
    end
    if candidate == nil and DarkPassengerInvestigation ~= nil and
       DarkPassengerInvestigation.GetCandidate ~= nil then
        candidate = DarkPassengerInvestigation.GetCandidate()
    end
    local current = ReadState()
    local allowBindingMigration = current.variantCode > 0 and
        (DarkPassengerCaseVariantCatalogByCode == nil or
         DarkPassengerCaseVariantCatalogByCode[current.variantCode] == nil)
    local nextState, result = DarkPassengerCaseSnapshot.Transition(
        current,
        {
            generation = generation,
            caseCode = selected ~= nil and selected.caseCode or 0,
            openerCode = selected ~= nil and selected.openerCode or 0,
            variantCode = selected ~= nil and selected.variantCode or 0,
            bindingCode = selected ~= nil and selected.bindingCode or 0,
            targetSlot = candidate ~= nil and candidate.slot or 0,
            interrogationOffered = current.generation == generation and
                current.interrogationOffered or false,
            allowBindingMigration = allowBindingMigration,
        }
    )
    if not result.accepted then
        Log(
            "capture rejected generation=" .. tostring(generation) ..
            " reason=" .. tostring(result.reason)
        )
        return nil, result.reason
    end
    if not PersistState(nextState) then return nil, "persistence_failed" end
    local snapshot, reason = Resolve(nextState)
    Log(
        "capture generation=" .. tostring(generation) ..
        " variantId=" .. tostring(snapshot ~= nil and snapshot.variantId) ..
        " reason=" .. tostring(result.reason) ..
        " resolved=" .. tostring(reason)
    )
    return snapshot, reason
end

function DarkPassengerCaseSnapshot.Get(generation)
    local state = ReadState()
    if generation ~= nil and
       tonumber(generation) ~= tonumber(state.generation) then
        return nil, "stale_generation"
    end
    return Resolve(state)
end

function DarkPassengerCaseSnapshot.Restore(generation)
    return DarkPassengerCaseSnapshot.Get(generation)
end

function DarkPassengerCaseSnapshot.MarkInterrogationOffered(generation)
    local state = ReadState()
    if tonumber(generation) ~= tonumber(state.generation) or
       state.generation <= 0 then
        return false, "stale_generation"
    end
    if state.interrogationOffered then return true, "already_offered" end
    state.interrogationOffered = true
    if not PersistState(state) then return false, "persistence_failed" end
    return true, "marked"
end

function DarkPassengerCaseSnapshot.RunSelfTest()
    local first, firstResult = DarkPassengerCaseSnapshot.Transition(
        DefaultState(),
        {
            generation = 4,
            caseCode = 1001,
            openerCode = 1101,
            variantCode = 777,
            bindingCode = 888,
            targetSlot = 9,
        }
    )
    local restored, restoredResult = DarkPassengerCaseSnapshot.Transition(
        first,
        {
            generation = 4,
            caseCode = 1001,
            openerCode = 1101,
            variantCode = 777,
            bindingCode = 888,
            targetSlot = 9,
        }
    )
    local _, conflict = DarkPassengerCaseSnapshot.Transition(
        first,
        {
            generation = 4,
            caseCode = 1001,
            openerCode = 1101,
            variantCode = 777,
            bindingCode = 888,
            targetSlot = 10,
        }
    )
    local rebound, reboundResult = DarkPassengerCaseSnapshot.Transition(
        first,
        {
            generation = 4,
            caseCode = 1001,
            openerCode = 1101,
            variantCode = 778,
            bindingCode = 889,
            targetSlot = 9,
            allowBindingMigration = true,
        }
    )
    local legacy, migration = DarkPassengerCaseSnapshot.MigrateLegacyState({
        generation = 4,
        caseCode = 1001,
        openerCode = 1101,
        targetSlot = 9,
    })
    local passed = firstResult.accepted and
        firstResult.reason == "captured" and
        restoredResult.accepted and restoredResult.reason == "restored" and
        SameIdentity(first, restored) and
        conflict.reason == "snapshot_conflict" and
        reboundResult.accepted and
        reboundResult.reason == "variant_migrated" and
        rebound.variantCode == 778 and rebound.targetSlot == 9 and
        migration.reason == "legacy_v1" and legacy.variantCode == 0 and
        legacy.targetSlot == 9
    Log("selftest=" .. tostring(passed))
    return passed
end

pcall(function()
    if System ~= nil and System.AddCCommand ~= nil then
        System.AddCCommand(
            "dp_case_snapshot_selftest",
            "DarkPassengerCaseSnapshot.RunSelfTest()",
            "Dark Passenger: run immutable case-snapshot checks"
        )
    end
end)

Log("module loaded")
