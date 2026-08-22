DarkPassengerCaseContent = DarkPassengerCaseContent or {}

DarkPassengerCaseContent.SCHEMA_VERSION = 4
DarkPassengerCaseContent.CASE_REPLAY_COOLDOWN_GENERATIONS = 4

local KEYS = {
    schema = "dp_case_content_schema_version",
    generation = "dp_case_content_generation",
    caseCode = "dp_case_content_case_code",
    openerCode = "dp_case_content_opener_code",
    variantCode = "dp_case_content_variant_code",
    previousVariantCode = "dp_case_content_previous_variant_code",
    innkeeperActorCode = "dp_case_content_innkeeper_actor_code",
    witnessActorCode = "dp_case_content_witness_actor_code",
    legacyTemplateSlot = "dp_case_content_template_slot",
    legacyRumorSlot = "dp_case_content_rumor_slot",
}

local LEGACY_V1_SELECTIONS = {
    [1] = {
        [1] = { caseCode = 1001, openerCode = 1101 },
    },
}

local function Log(message)
    if System ~= nil and System.LogAlways ~= nil then
        System.LogAlways(
            "[DarkPassenger][CaseContent] " .. tostring(message)
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
        previousVariantCode = 0,
        innkeeperActorCode = 0,
        witnessActorCode = 0,
    }
end

local function CopyState(state)
    return {
        generation = tonumber(state ~= nil and state.generation) or 0,
        caseCode = tonumber(state ~= nil and state.caseCode) or 0,
        openerCode = tonumber(state ~= nil and state.openerCode) or 0,
        variantCode = tonumber(state ~= nil and state.variantCode) or 0,
        previousVariantCode =
            tonumber(state ~= nil and state.previousVariantCode) or 0,
        innkeeperActorCode =
            tonumber(state ~= nil and state.innkeeperActorCode) or 0,
        witnessActorCode =
            tonumber(state ~= nil and state.witnessActorCode) or 0,
    }
end

local function PersistState(state)
    local writes = {
        WriteScalar(KEYS.schema, DarkPassengerCaseContent.SCHEMA_VERSION),
        WriteScalar(KEYS.generation, state.generation),
        WriteScalar(KEYS.caseCode, state.caseCode),
        WriteScalar(KEYS.openerCode, state.openerCode),
        WriteScalar(KEYS.variantCode, state.variantCode),
        WriteScalar(KEYS.previousVariantCode, state.previousVariantCode),
        WriteScalar(KEYS.innkeeperActorCode, state.innkeeperActorCode),
        WriteScalar(KEYS.witnessActorCode, state.witnessActorCode),
    }
    for _, succeeded in ipairs(writes) do
        if not succeeded then return false end
    end
    return true
end

function DarkPassengerCaseContent.MigrateLegacyState(legacy)
    local templateSlot = tonumber(legacy ~= nil and legacy.templateSlot) or 0
    local rumorSlot = tonumber(legacy ~= nil and legacy.rumorSlot) or 0
    local template = LEGACY_V1_SELECTIONS[templateSlot]
    local mapping = template ~= nil and template[rumorSlot] or nil
    if mapping == nil then
        return {
            generation = tonumber(legacy ~= nil and legacy.generation) or 0,
            caseCode = 0,
            openerCode = 0,
            variantCode = 0,
            previousVariantCode = 0,
            innkeeperActorCode = 0,
            witnessActorCode = 0,
        }, { accepted = false, reason = "legacy_unknown" }
    end
    return {
        generation = tonumber(legacy.generation) or 0,
        caseCode = mapping.caseCode,
        openerCode = mapping.openerCode,
        variantCode = 0,
        previousVariantCode = 0,
        innkeeperActorCode = 0,
        witnessActorCode = 0,
    }, { accepted = true, reason = "legacy_v1" }
end

local function ReadState()
    local schema = tonumber(ReadScalar(KEYS.schema))
    if schema == DarkPassengerCaseContent.SCHEMA_VERSION then
        return {
            generation = tonumber(ReadScalar(KEYS.generation)) or 0,
            caseCode = tonumber(ReadScalar(KEYS.caseCode)) or 0,
            openerCode = tonumber(ReadScalar(KEYS.openerCode)) or 0,
            variantCode = tonumber(ReadScalar(KEYS.variantCode)) or 0,
            previousVariantCode =
                tonumber(ReadScalar(KEYS.previousVariantCode)) or 0,
            innkeeperActorCode =
                tonumber(ReadScalar(KEYS.innkeeperActorCode)) or 0,
            witnessActorCode =
                tonumber(ReadScalar(KEYS.witnessActorCode)) or 0,
        }
    end
    if schema == 3 then
        -- Case identity remains stable; actor bindings are resolved from the generated pool.
        return {
            generation = tonumber(ReadScalar(KEYS.generation)) or 0,
            caseCode = tonumber(ReadScalar(KEYS.caseCode)) or 0,
            openerCode = tonumber(ReadScalar(KEYS.openerCode)) or 0,
            variantCode = tonumber(ReadScalar(KEYS.variantCode)) or 0,
            previousVariantCode =
                tonumber(ReadScalar(KEYS.previousVariantCode)) or 0,
            innkeeperActorCode = 0,
            witnessActorCode = 0,
        }
    end
    if schema == 2 then
        -- Existing 1001/2001 saves stay on their exact target. The case remains
        -- a legacy CaseInstance until it completes; no variant is rerolled.
        return {
            generation = tonumber(ReadScalar(KEYS.generation)) or 0,
            caseCode = tonumber(ReadScalar(KEYS.caseCode)) or 0,
            openerCode = tonumber(ReadScalar(KEYS.openerCode)) or 0,
            variantCode = 0,
            previousVariantCode = 0,
            innkeeperActorCode = 0,
            witnessActorCode = 0,
        }
    end
    if schema == 1 then
        local migratedState, result =
            DarkPassengerCaseContent.MigrateLegacyState({
                generation = tonumber(ReadScalar(KEYS.generation)) or 0,
                templateSlot =
                    tonumber(ReadScalar(KEYS.legacyTemplateSlot)) or 0,
                rumorSlot = tonumber(ReadScalar(KEYS.legacyRumorSlot)) or 0,
            })
        if result.accepted then
            Log(
                "migrated legacy selection generation=" ..
                tostring(migratedState.generation) ..
                " caseCode=" .. tostring(migratedState.caseCode) ..
                " openerCode=" .. tostring(migratedState.openerCode)
            )
        end
        return migratedState
    end
    return DefaultState()
end

local function Catalog()
    local result = {}
    for _, caseId in ipairs(DarkPassengerCaseCatalogOrder or {}) do
        local caseTemplate =
            DarkPassengerCaseCatalog ~= nil and
            DarkPassengerCaseCatalog[caseId] or nil
        if caseTemplate ~= nil then table.insert(result, caseTemplate) end
    end
    return result
end

local function VariantCatalog()
    local result = {}
    for _, variantId in ipairs(DarkPassengerCaseVariantCatalogOrder or {}) do
        local variant = DarkPassengerCaseVariantCatalog ~= nil and
            DarkPassengerCaseVariantCatalog[variantId] or nil
        if variant ~= nil then table.insert(result, variant) end
    end
    return result
end

local function CaseByCode(code, catalog)
    if catalog == nil and DarkPassengerCaseCatalogByCode ~= nil then
        local direct = DarkPassengerCaseCatalogByCode[tonumber(code)]
        if direct ~= nil then return direct end
    end
    for _, caseTemplate in ipairs(catalog or Catalog()) do
        if tonumber(caseTemplate.code) == tonumber(code) then
            return caseTemplate
        end
    end
    return nil
end

local function VariantByCode(code)
    if DarkPassengerCaseVariantCatalogByCode == nil then return nil end
    return DarkPassengerCaseVariantCatalogByCode[tonumber(code)]
end

local function EvidenceByCode(entries, code)
    for _, entry in ipairs(entries or {}) do
        if tonumber(entry.code) == tonumber(code) then return entry end
    end
    return nil
end

local function MatchesConstraints(constraints, context)
    if constraints == nil then return true end
    if context == nil then return false end
    if constraints.region ~= nil and constraints.region ~= context.region then
        return false
    end
    if constraints.settlement ~= nil and
       constraints.settlement ~= context.settlement then
        return false
    end
    return true
end

local function WeightedChoice(entries, roll)
    local total = 0
    for _, entry in ipairs(entries or {}) do
        total = total + math.max(0, tonumber(entry.weight) or 0)
    end
    if total <= 0 then return nil end
    local normalizedRoll = tonumber(roll)
    if normalizedRoll == nil then
        normalizedRoll = random(1, 1000000) / 1000000
    end
    if normalizedRoll < 0 then normalizedRoll = 0 end
    if normalizedRoll >= 1 then normalizedRoll = 0.999999 end
    local threshold = normalizedRoll * total
    local cursor = 0
    for _, entry in ipairs(entries) do
        cursor = cursor + math.max(0, tonumber(entry.weight) or 0)
        if threshold < cursor then return entry.value end
    end
    return entries[#entries].value
end

local function ReplayKey(caseCode, field)
    return "dp_case_replay_" .. tostring(caseCode) .. "_" .. field
end

function DarkPassengerCaseContent.ReadReplayHistory(
    caseCodes,
    currentState
)
    local history = {}
    if caseCodes == nil then
        caseCodes = {}
        for _, caseTemplate in ipairs(Catalog()) do
            table.insert(caseCodes, tonumber(caseTemplate.code))
        end
    end
    for _, rawCode in ipairs(caseCodes or {}) do
        local caseCode = tonumber(rawCode)
        if caseCode ~= nil and caseCode > 0 then
            local plays = tonumber(ReadScalar(
                ReplayKey(caseCode, "plays")
            )) or 0
            local lastGeneration = tonumber(ReadScalar(
                ReplayKey(caseCode, "last_generation")
            )) or 0
            if currentState ~= nil and
               tonumber(currentState.caseCode) == caseCode and
               tonumber(currentState.generation) > lastGeneration then
                plays = math.max(plays, 1)
                lastGeneration = tonumber(currentState.generation)
            end
            history[caseCode] = {
                plays = plays,
                lastGeneration = lastGeneration,
            }
        end
    end
    return history
end

function DarkPassengerCaseContent.GetStoryReplayWeight(
    baseWeight,
    history,
    generation
)
    local weight = math.max(0, tonumber(baseWeight) or 0)
    local plays = tonumber(history ~= nil and history.plays) or 0
    if plays <= 0 then return weight end
    local lastGeneration =
        tonumber(history ~= nil and history.lastGeneration) or 0
    local age = math.max(1, (tonumber(generation) or 1) - lastGeneration)
    local cooldown = math.max(
        1,
        tonumber(
            DarkPassengerCaseContent.CASE_REPLAY_COOLDOWN_GENERATIONS
        ) or 1
    )
    local recovery = math.min(1, age / cooldown)
    local temporaryPenalty = 0.05 + 0.95 * recovery * recovery
    local familiarityPenalty = 1 / (1 + math.max(0, plays - 1) * 0.1)
    return weight * temporaryPenalty * familiarityPenalty
end

function DarkPassengerCaseContent.BuildReplayCaseChoices(
    caseGroups,
    caseOrder,
    replayHistory,
    generation,
    previousCaseCode
)
    local unplayed = {}
    for _, caseCode in ipairs(caseOrder or {}) do
        local history = replayHistory ~= nil and
            replayHistory[caseCode] or nil
        if (tonumber(history ~= nil and history.plays) or 0) <= 0 then
            table.insert(unplayed, caseCode)
        end
    end
    local selectableCases = #unplayed > 0 and unplayed or caseOrder
    local immediateRepeatBlocked = false
    previousCaseCode = tonumber(previousCaseCode)
    if #selectableCases > 1 and previousCaseCode ~= nil and
       previousCaseCode > 0 then
        local withoutImmediateRepeat = {}
        for _, caseCode in ipairs(selectableCases) do
            if caseCode ~= previousCaseCode then
                table.insert(withoutImmediateRepeat, caseCode)
            end
        end
        if #withoutImmediateRepeat > 0 then
            selectableCases = withoutImmediateRepeat
            immediateRepeatBlocked = true
        end
    end
    local choices = {}
    for _, caseCode in ipairs(selectableCases or {}) do
        local first = caseGroups[caseCode] ~= nil and
            caseGroups[caseCode][1] or nil
        if first ~= nil then
            table.insert(choices, {
                value = caseCode,
                weight = DarkPassengerCaseContent.GetStoryReplayWeight(
                    first.weight,
                    replayHistory ~= nil and
                        replayHistory[caseCode] or nil,
                    generation
                ),
            })
        end
    end
    return choices, {
        unplayed = #unplayed > 0,
        immediate_repeat = immediateRepeatBlocked,
    }
end

local function PersistStoryPlayed(caseCode, generation, history)
    caseCode = tonumber(caseCode)
    generation = tonumber(generation)
    if caseCode == nil or caseCode <= 0 or
       generation == nil or generation <= 0 then
        return false
    end
    local entry = history ~= nil and history[caseCode] or nil
    local plays = tonumber(entry ~= nil and entry.plays)
    if plays == nil then
        plays = tonumber(ReadScalar(ReplayKey(caseCode, "plays"))) or 0
    end
    return WriteScalar(ReplayKey(caseCode, "plays"), plays + 1) and
        WriteScalar(
            ReplayKey(caseCode, "last_generation"),
            generation
        )
end

local function CopyTable(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

local ACTOR_SELECTION_ROLES = { "innkeeper", "witness" }

local function ActorStateKey(role)
    if role == "innkeeper" then return "innkeeperActorCode" end
    if role == "witness" then return "witnessActorCode" end
    return nil
end

local function ShiftedActorRoll(roll, roleIndex)
    local value = tonumber(roll)
    if value == nil then value = random(1, 1000000) / 1000000 end
    if value < 0 then value = 0 end
    if value >= 1 then value = 0.999999 end
    return (value + ((roleIndex - 1) * 0.61803398875)) % 1
end

function DarkPassengerCaseContent.SelectActors(variant, roll, actorCodes)
    if variant == nil or variant.actor_pools == nil or
       variant.actor_selection == nil then
        return nil, "actor_pool_unavailable"
    end
    local selected = {}
    for roleIndex, role in ipairs(ACTOR_SELECTION_ROLES) do
        local pool = variant.actor_pools[role] or {}
        local selection = variant.actor_selection[role]
        if #pool == 0 or selection == nil or
           selection.buff_guid == nil or selection.buff_guid == "" then
            return nil, "actor_pool_incomplete_" .. role
        end
        local requestedCode = tonumber(
            actorCodes ~= nil and actorCodes[ActorStateKey(role)]
        ) or 0
        local actor = nil
        if requestedCode > 0 then
            for _, candidate in ipairs(pool) do
                if tonumber(candidate.actor_code) == requestedCode then
                    actor = candidate
                    break
                end
            end
            if actor == nil then return nil, "actor_binding_invalid_" .. role end
        else
            local choices = {}
            for _, candidate in ipairs(pool) do
                table.insert(choices, { value = candidate, weight = 1 })
            end
            actor = WeightedChoice(
                choices,
                actorCodes ~= nil and 0 or
                    ShiftedActorRoll(roll, roleIndex)
            )
        end
        if actor == nil then return nil, "actor_selection_failed_" .. role end
        selected[role] = CopyTable(actor)
        selected[role].buff_guid = selection.buff_guid
        selected[role].signal_tag = tonumber(selection.signal_tag) or 0
    end
    return selected, "selected"
end

local function MergeRoleBinding(base, semantic)
    local result = CopyTable(base)
    if semantic ~= nil then
        if semantic.entity_name ~= nil and semantic.entity_name ~= "" then
            result.entityName = semantic.entity_name
        end
        result.entityGuid = semantic.entity_guid
        result.soulGuid = semantic.soul_guid
        result.candidateSlot = tonumber(semantic.candidate_slot) or 0
        if semantic.dialogue_role ~= nil and
           semantic.dialogue_role ~= "" then
            result.dialogueRole = semantic.dialogue_role
        end
    end
    return result
end

local function BuildVariantCaseTemplate(base, variant, selectedActors)
    if base == nil or variant == nil then return base end
    local result = CopyTable(base)
    result.constraints = {
        region = variant.region,
        settlement = variant.settlement,
    }
    local baseBindings = base.bindings or {}
    local semantic = variant.bindings or {}
    local bindings = CopyTable(baseBindings)
    bindings.target = semantic.target
    local selectedInnkeeper = selectedActors ~= nil and
        selectedActors.innkeeper or nil
    local selectedWitness = selectedActors ~= nil and
        selectedActors.witness or nil
    bindings.innkeeper = MergeRoleBinding(
        baseBindings.innkeeper,
        selectedInnkeeper or semantic.rumorSource
    )
    bindings.witness = MergeRoleBinding(
        baseBindings.witness,
        selectedWitness or semantic.witness
    )
    bindings.document = MergeRoleBinding(
        baseBindings.document,
        semantic.evidenceContainer
    )
    if semantic.evidenceContainer ~= nil then
        bindings.document.containerGuid = semantic.evidenceContainer.entity_guid
    end
    local resolvedSemantic = CopyTable(semantic)
    if selectedInnkeeper ~= nil then
        resolvedSemantic.rumorSource = selectedInnkeeper
    end
    if selectedWitness ~= nil then
        resolvedSemantic.witness = selectedWitness
    end
    bindings.semantic = resolvedSemantic
    result.bindings = bindings
    result.variant_id = variant.variant_id
    result.variant_code = variant.variant_code
    result.binding_code = variant.binding_code
    result.scene_definitions = variant.scenes or {}
    result.timed_area_actions = variant.timed_area_actions or {}
    result.guidance = variant.guidance or {}
    return result
end

-- Compatibility selector retained for legacy fixtures and direct pure tests.
function DarkPassengerCaseContent.Select(catalog, context, roll)
    local eligibleCases = {}
    for _, caseTemplate in ipairs(catalog or {}) do
        if MatchesConstraints(caseTemplate.constraints, context) then
            table.insert(eligibleCases, {
                value = caseTemplate,
                weight = caseTemplate.weight,
            })
        end
    end
    local selectedCase = WeightedChoice(eligibleCases, roll)
    if selectedCase == nil then return nil, "no_case" end
    local eligibleOpeners = {}
    for _, opener in ipairs(selectedCase.rumors or {}) do
        if MatchesConstraints(opener.constraints, context) then
            table.insert(eligibleOpeners, {
                value = opener,
                weight = opener.weight,
            })
        end
    end
    local selectedOpener = WeightedChoice(eligibleOpeners, roll)
    if selectedOpener == nil then return nil, "no_opener" end
    return {
        caseCode = tonumber(selectedCase.code),
        openerCode = tonumber(selectedOpener.code),
        caseTemplate = selectedCase,
        rumor = selectedOpener,
    }, "selected"
end

function DarkPassengerCaseContent.IsSettlementSupported(region, settlement)
    for _, variant in ipairs(VariantCatalog()) do
        if variant.native_ready == true and variant.region == region and
           variant.settlement == settlement then
            return true
        end
    end
    return false
end

-- Variants are chosen in three finite passes: story, anti-repeat target, then
-- binding variation. candidateBySlot contains only policy-valid live actors.
function DarkPassengerCaseContent.SelectVariant(
    catalog,
    context,
    roll,
    previousVariantCode,
    replayHistory,
    generation,
    previousCaseCode
)
    local candidateBySlot = context ~= nil and context.candidateBySlot or nil
    if candidateBySlot == nil then return nil, "candidates_unavailable" end
    local eligible = {}
    local caseGroups = {}
    local caseOrder = {}
    for _, variant in ipairs(catalog or VariantCatalog()) do
        local targetSlot = tonumber(variant.target_slot) or 0
        if variant.native_ready == true and
           variant.region == context.region and
           variant.settlement == context.settlement and
           candidateBySlot[targetSlot] ~= nil then
            table.insert(eligible, variant)
            local caseCode = tonumber(variant.case_code)
            if caseGroups[caseCode] == nil then
                caseGroups[caseCode] = {}
                table.insert(caseOrder, caseCode)
            end
            table.insert(caseGroups[caseCode], variant)
        end
    end
    if #eligible == 0 then return nil, "no_variant" end

    local caseChoices, replayPolicy =
        DarkPassengerCaseContent.BuildReplayCaseChoices(
            caseGroups,
            caseOrder,
            replayHistory,
            generation,
            previousCaseCode
        )
    local selectedCaseCode = WeightedChoice(caseChoices, roll)
    local caseVariants = caseGroups[selectedCaseCode] or {}
    local previous = VariantByCode(previousVariantCode)
    local previousKey = previous ~= nil and previous.anti_repeat_key or nil
    local targetGroups = {}
    local targetOrder = {}
    for _, variant in ipairs(caseVariants) do
        local key = variant.anti_repeat_key
        if targetGroups[key] == nil then
            targetGroups[key] = {}
            table.insert(targetOrder, key)
        end
        table.insert(targetGroups[key], variant)
    end
    if #targetOrder > 1 and previousKey ~= nil then
        local filtered = {}
        for _, key in ipairs(targetOrder) do
            if key ~= previousKey then table.insert(filtered, key) end
        end
        if #filtered > 0 then targetOrder = filtered end
    end
    local targetChoices = {}
    for _, key in ipairs(targetOrder) do
        table.insert(targetChoices, { value = key, weight = 1 })
    end
    local selectedTargetKey = WeightedChoice(targetChoices, roll)
    local bindingVariants = targetGroups[selectedTargetKey] or {}
    local bindingChoices = {}
    for _, variant in ipairs(bindingVariants) do
        table.insert(bindingChoices, { value = variant, weight = 1 })
    end
    local variant = WeightedChoice(bindingChoices, roll)
    if variant == nil then return nil, "no_binding" end
    local caseTemplate = CaseByCode(variant.case_code, nil)
    if caseTemplate == nil then return nil, "case_unavailable" end
    local opener = WeightedChoice((function()
        local choices = {}
        for _, rumor in ipairs(caseTemplate.rumors or {}) do
            table.insert(choices, { value = rumor, weight = rumor.weight })
        end
        return choices
    end)(), roll)
    if opener == nil then return nil, "no_opener" end
    local selectedActors, actorReason =
        DarkPassengerCaseContent.SelectActors(variant, roll, nil)
    if selectedActors == nil then return nil, actorReason end
    return {
        variantId = variant.variant_id,
        variantCode = tonumber(variant.variant_code),
        bindingCode = tonumber(variant.binding_code),
        caseCode = tonumber(variant.case_code),
        openerCode = tonumber(opener.code),
        targetSlot = tonumber(variant.target_slot),
        candidateEntry = candidateBySlot[tonumber(variant.target_slot)],
        variant = variant,
        selectedActors = selectedActors,
        caseTemplate = BuildVariantCaseTemplate(
            caseTemplate,
            variant,
            selectedActors
        ),
        rumor = opener,
        sceneDefinitions = variant.scenes or {},
        replayPolicy = replayPolicy,
    }, "selected"
end

function DarkPassengerCaseContent.FindCompatibleVariant(
    state,
    context,
    catalog
)
    local caseCode = tonumber(state ~= nil and state.caseCode) or 0
    local openerCode = tonumber(state ~= nil and state.openerCode) or 0
    local candidateBySlot = context ~= nil and context.candidateBySlot or nil
    if caseCode <= 0 or openerCode <= 0 or candidateBySlot == nil then
        return nil, "migration_context_unavailable"
    end
    local compatible = {}
    for _, variant in ipairs(catalog or VariantCatalog()) do
        local targetSlot = tonumber(variant.target_slot) or 0
        if variant.native_ready == true and
           tonumber(variant.case_code) == caseCode and
           variant.region == context.region and
           variant.settlement == context.settlement and
           candidateBySlot[targetSlot] ~= nil then
            table.insert(compatible, variant)
        end
    end
    table.sort(compatible, function(left, right)
        return tostring(left.variant_id) < tostring(right.variant_id)
    end)
    local variant = compatible[1]
    if variant == nil then return nil, "compatible_variant_unavailable" end
    local caseTemplate = CaseByCode(caseCode, nil)
    local opener = caseTemplate ~= nil and
        EvidenceByCode(caseTemplate.rumors, openerCode) or nil
    if caseTemplate == nil or opener == nil then
        return nil, "compatible_case_unavailable"
    end
    local selectedActors, actorReason =
        DarkPassengerCaseContent.SelectActors(variant, 0, nil)
    if selectedActors == nil then return nil, actorReason end
    return {
        variantId = variant.variant_id,
        variantCode = tonumber(variant.variant_code),
        bindingCode = tonumber(variant.binding_code),
        caseCode = caseCode,
        openerCode = openerCode,
        targetSlot = tonumber(variant.target_slot),
        candidateEntry = candidateBySlot[tonumber(variant.target_slot)],
        variant = variant,
        selectedActors = selectedActors,
        caseTemplate = BuildVariantCaseTemplate(
            caseTemplate,
            variant,
            selectedActors
        ),
        rumor = opener,
        sceneDefinitions = variant.scenes or {},
    }, "compatible_variant"
end

function DarkPassengerCaseContent.Resolve(state, catalog)
    local caseCode = tonumber(state ~= nil and state.caseCode) or 0
    local openerCode = tonumber(state ~= nil and state.openerCode) or 0
    local variantCode = tonumber(state ~= nil and state.variantCode) or 0
    local caseTemplate = CaseByCode(caseCode, catalog)
    local opener = caseTemplate ~= nil and
        EvidenceByCode(caseTemplate.rumors, openerCode) or nil
    if caseTemplate == nil or opener == nil then return nil end
    local variant = variantCode > 0 and VariantByCode(variantCode) or nil
    if variantCode > 0 and variant == nil then return nil end
    local selectedActors = nil
    if variant ~= nil then
        selectedActors = DarkPassengerCaseContent.SelectActors(
            variant,
            nil,
            state
        )
        if selectedActors == nil then return nil end
    end
    local resolvedTemplate = BuildVariantCaseTemplate(
        caseTemplate,
        variant,
        selectedActors
    )
    return {
        generation = tonumber(state.generation) or 0,
        caseCode = caseCode,
        openerCode = openerCode,
        variantCode = variantCode,
        previousVariantCode =
            tonumber(state.previousVariantCode) or 0,
        variantId = variant ~= nil and variant.variant_id or nil,
        bindingCode = variant ~= nil and variant.binding_code or 0,
        targetSlot = variant ~= nil and variant.target_slot or 0,
        variant = variant,
        selectedActors = selectedActors,
        caseTemplate = resolvedTemplate,
        rumor = opener,
        sceneDefinitions = variant ~= nil and variant.scenes or {},
    }
end

-- Legacy transition remains deterministic for migration tests.
function DarkPassengerCaseContent.Transition(state, event, catalog)
    local nextState = CopyState(state)
    local generation = tonumber(event ~= nil and event.generation)
    if generation == nil or generation <= 0 then
        return nextState, { accepted = false, reason = "invalid_generation" }
    end
    if nextState.generation == generation then
        if DarkPassengerCaseContent.Resolve(nextState, catalog) ~= nil then
            return nextState, { accepted = true, reason = "restored" }
        end
        return nextState, {
            accepted = false,
            reason = "invalid_saved_selection",
        }
    end
    local selection, reason = DarkPassengerCaseContent.Select(
        catalog or {},
        event.context,
        event.roll
    )
    if selection == nil then
        return nextState, { accepted = false, reason = reason }
    end
    nextState.generation = generation
    nextState.caseCode = selection.caseCode
    nextState.openerCode = selection.openerCode
    nextState.variantCode = 0
    nextState.innkeeperActorCode = 0
    nextState.witnessActorCode = 0
    return nextState, { accepted = true, reason = "selected" }
end

function DarkPassengerCaseContent.PrepareVariant(
    generation,
    context,
    roll
)
    generation = tonumber(generation)
    local current = ReadState()
    if generation == nil or generation <= 0 then
        return nil, "invalid_generation"
    end
    if current.generation == generation then
        local restored = DarkPassengerCaseContent.Resolve(current, nil)
        if restored ~= nil then
            local candidateBySlot = context ~= nil and
                context.candidateBySlot or nil
            restored.candidateEntry = candidateBySlot ~= nil and
                candidateBySlot[tonumber(restored.targetSlot)] or nil
            return restored, "restored"
        end
        local migrated, migrationReason =
            DarkPassengerCaseContent.FindCompatibleVariant(current, context, nil)
        if migrated ~= nil then
            local migratedState = CopyState(current)
            migratedState.variantCode = migrated.variantCode
            migratedState.innkeeperActorCode =
                tonumber(migrated.selectedActors.innkeeper.actor_code) or 0
            migratedState.witnessActorCode =
                tonumber(migrated.selectedActors.witness.actor_code) or 0
            if not PersistState(migratedState) then
                return nil, "migration_persistence_failed"
            end
            migrated.generation = generation
            Log(
                "variant migrated generation=" .. tostring(generation) ..
                " old=" .. tostring(current.variantCode) ..
                " new=" .. tostring(migrated.variantCode) ..
                " target=" .. tostring(migrated.targetSlot)
            )
            return migrated, "migrated_variant"
        end
        Log(
            "variant migration unavailable generation=" ..
            tostring(generation) .. " reason=" ..
            tostring(migrationReason)
        )
        return nil, "invalid_saved_selection"
    end
    if generation < current.generation then return nil, "stale_generation" end
    local replayHistory = DarkPassengerCaseContent.ReadReplayHistory(
        nil,
        current
    )
    local selection, reason = DarkPassengerCaseContent.SelectVariant(
        nil,
        context,
        roll,
        current.variantCode,
        replayHistory,
        generation,
        current.caseCode
    )
    if selection == nil then return nil, reason end
    local nextState = {
        generation = generation,
        caseCode = selection.caseCode,
        openerCode = selection.openerCode,
        variantCode = selection.variantCode,
        previousVariantCode = current.variantCode,
        innkeeperActorCode =
            tonumber(selection.selectedActors.innkeeper.actor_code) or 0,
        witnessActorCode =
            tonumber(selection.selectedActors.witness.actor_code) or 0,
    }
    if not PersistState(nextState) then return nil, "persistence_failed" end
    if not PersistStoryPlayed(
        selection.caseCode,
        generation,
        replayHistory
    ) then
        Log(
            "replay history persistence failed caseCode=" ..
            tostring(selection.caseCode) ..
            " generation=" .. tostring(generation)
        )
    end
    local resolved = DarkPassengerCaseContent.Resolve(nextState, nil)
    if resolved ~= nil then
        resolved.candidateEntry = selection.candidateEntry
    end
    return resolved, "selected"
end

local function CandidateContext(candidate)
    local candidateBySlot = {}
    if candidate ~= nil and candidate.slot ~= nil then
        candidateBySlot[tonumber(candidate.slot)] = { candidate = candidate }
    end
    return {
        region = candidate ~= nil and candidate.gameRegion or nil,
        settlement = candidate ~= nil and candidate.settlement or nil,
        archetype = candidate ~= nil and candidate.archetype or nil,
        faction = candidate ~= nil and candidate.faction or nil,
        candidateBySlot = candidateBySlot,
    }
end

local function PersistResolvedActorSelection(state, selected)
    if selected == nil or selected.selectedActors == nil then return true end
    local innkeeperCode =
        tonumber(selected.selectedActors.innkeeper.actor_code) or 0
    local witnessCode =
        tonumber(selected.selectedActors.witness.actor_code) or 0
    if innkeeperCode <= 0 or witnessCode <= 0 then return false end
    if tonumber(state.innkeeperActorCode) == innkeeperCode and
       tonumber(state.witnessActorCode) == witnessCode then
        return true
    end
    local migrated = CopyState(state)
    migrated.innkeeperActorCode = innkeeperCode
    migrated.witnessActorCode = witnessCode
    return PersistState(migrated)
end

local function ApplyCaseActivation(selected)
    local buffGuid = selected ~= nil and selected.variant ~= nil and
        selected.variant.case_activation_buff_guid or nil
    local actor = g_localActor or player
    if buffGuid == nil or buffGuid == "" or actor == nil or
       actor.soul == nil or actor.soul.AddBuff == nil then
        return false
    end
    if actor.soul.HasBuffDebug ~= nil then
        local ok, present = pcall(function()
            return actor.soul:HasBuffDebug(buffGuid)
        end)
        if ok and (present == true or present == 1) then return true end
    end
    local ok, buffHandleOrError = pcall(function()
        return actor.soul:AddBuff(buffGuid)
    end)
    return ok and buffHandleOrError ~= nil
end

DarkPassengerCaseContent.ApplyCaseActivation = ApplyCaseActivation

local function ClearActorSelectionForCase(selected)
    if selected == nil or selected.variant == nil or
       selected.selectedActors == nil or System == nil or
       System.GetEntityByName == nil then
        return false
    end
    local removed = {}
    for _, role in ipairs(ACTOR_SELECTION_ROLES) do
        local selectedActor = selected.selectedActors[role]
        local buffGuid = selectedActor ~= nil and
            selectedActor.buff_guid or nil
        if buffGuid ~= nil and buffGuid ~= "" then
            for _, variant in ipairs(VariantCatalog()) do
                if tonumber(variant.case_code) == tonumber(selected.caseCode) then
                    local pool = variant.actor_pools ~= nil and
                        variant.actor_pools[role] or nil
                    for _, actorBinding in ipairs(pool or {}) do
                        local removalKey = tostring(actorBinding.entity_name) ..
                            "|" .. tostring(buffGuid)
                        if removed[removalKey] ~= true then
                            removed[removalKey] = true
                            local entity =
                                System.GetEntityByName(actorBinding.entity_name)
                            if entity ~= nil and entity.soul ~= nil and
                               entity.soul.RemoveAllBuffsByGuid ~= nil then
                                pcall(function()
                                    entity.soul:RemoveAllBuffsByGuid(buffGuid)
                                end)
                            end
                        end
                    end
                end
            end
        end
    end
    return true
end

local function ApplyActorSelection(selected)
    if selected == nil or selected.selectedActors == nil or
       System == nil or System.GetEntityByName == nil then
        return false
    end
    ClearActorSelectionForCase(selected)
    for _, role in ipairs(ACTOR_SELECTION_ROLES) do
        local actorBinding = selected.selectedActors[role]
        local buffGuid = actorBinding ~= nil and actorBinding.buff_guid or nil
        local entity = actorBinding ~= nil and
            System.GetEntityByName(actorBinding.entity_name) or nil
        if buffGuid == nil or buffGuid == "" or entity == nil or
           entity.soul == nil or entity.soul.AddBuff == nil then
            ClearActorSelectionForCase(selected)
            return false
        end
        local ok, buffHandleOrError = pcall(function()
            return entity.soul:AddBuff(buffGuid)
        end)
        if not ok or buffHandleOrError == nil then
            ClearActorSelectionForCase(selected)
            return false
        end
    end
    return true
end

function DarkPassengerCaseContent.ClearActorSelection(generation)
    local selected = DarkPassengerCaseContent.GetSelected(generation)
    if selected == nil then return false end
    if selected.selectedActors == nil then return true end
    return ClearActorSelectionForCase(selected)
end

function DarkPassengerCaseContent.OnInvestigationOpened(generation, candidate)
    local state = ReadState()
    local selected = DarkPassengerCaseContent.Resolve(state, nil)
    local reason = "restored"
    if selected == nil or tonumber(selected.generation) ~= tonumber(generation) then
        selected, reason = DarkPassengerCaseContent.PrepareVariant(
            generation,
            CandidateContext(candidate),
            nil
        )
    end
    if selected == nil then
        Log(
            "selection unavailable generation=" .. tostring(generation) ..
            " reason=" .. tostring(reason)
        )
        return nil
    end
    state = ReadState()
    if not PersistResolvedActorSelection(state, selected) then
        Log(
            "actor selection persistence failed generation=" ..
            tostring(generation)
        )
        return nil, "actor_selection_persistence_failed"
    end
    if not ApplyActorSelection(selected) then
        Log(
            "actor selection unavailable generation=" .. tostring(generation) ..
            " case=" .. tostring(selected.caseCode)
        )
        return nil, "actor_selection_failed"
    end
    if not ApplyCaseActivation(selected) then
        ClearActorSelectionForCase(selected)
        Log(
            "case activation unavailable generation=" .. tostring(generation) ..
            " case=" .. tostring(selected.caseCode)
        )
        return nil, "case_activation_failed"
    end
    local snapshot = nil
    if DarkPassengerCaseSnapshot ~= nil and
       DarkPassengerCaseSnapshot.Capture ~= nil then
        snapshot = DarkPassengerCaseSnapshot.Capture(
            generation,
            candidate,
            selected
        )
    end
    if snapshot ~= nil and DarkPassengerSceneDirector ~= nil and
       DarkPassengerSceneDirector.Materialize ~= nil then
        DarkPassengerSceneDirector.Materialize(generation, snapshot)
    end
    Log(
        "resolved generation=" .. tostring(generation) ..
        " case=" .. tostring(selected.caseTemplate.id) ..
        " variantId=" .. tostring(selected.variantId) ..
        " opener=" .. tostring(selected.rumor.id) ..
        " reason=" .. tostring(reason)
    )
    return selected
end

function DarkPassengerCaseContent.GetSelected(generation)
    local state = ReadState()
    if generation ~= nil and state.generation ~= tonumber(generation) then
        return nil
    end
    return DarkPassengerCaseContent.Resolve(state, nil)
end

function DarkPassengerCaseContent.Restore(investigationState, candidate)
    if investigationState == nil or investigationState.active ~= true then
        return nil
    end
    return DarkPassengerCaseContent.OnInvestigationOpened(
        investigationState.generation,
        candidate
    )
end

function DarkPassengerCaseContent.RunSelfTest()
    local failures = {}
    local function Expect(condition, label)
        if not condition then table.insert(failures, label) end
    end
    local selectedActors = DarkPassengerCaseContent.SelectActors({
        actor_pools = {
            innkeeper = {
                { actor_code = 11, entity_name = "innkeeper_a" },
                { actor_code = 12, entity_name = "innkeeper_b" },
            },
            witness = {
                { actor_code = 21, entity_name = "witness_a" },
                { actor_code = 22, entity_name = "witness_b" },
            },
        },
        actor_selection = {
            innkeeper = { signal_tag = 151, buff_guid = "buff-innkeeper" },
            witness = { signal_tag = 152, buff_guid = "buff-witness" },
        },
    }, 0.75, nil)
    Expect(
        selectedActors ~= nil and
        selectedActors.innkeeper.actor_code == 12 and
        selectedActors.witness.actor_code == 21,
        "actor selection"
    )
    local catalog = Catalog()
    local roleProbe = MergeRoleBinding(
        { entityName = "kpri_innkeeper", dialogueRole = "DP_OLD_ROLE" },
        { entity_name = "ttkc_inkeeper", dialogue_role = "DP_NEW_ROLE" }
    )
    Expect(
        roleProbe.entityName == "ttkc_inkeeper" and
        roleProbe.dialogueRole == "DP_NEW_ROLE",
        "settlement dialogue role overlay"
    )
    local context = { region = "kutnohorsko", settlement = "pritoky" }
    local state, first = DarkPassengerCaseContent.Transition(
        DefaultState(),
        { generation = 4, context = context, roll = 0 },
        catalog
    )
    local selected = DarkPassengerCaseContent.Resolve(state, catalog)
    Expect(first.accepted and first.reason == "selected", "select")
    Expect(
        selected ~= nil and state.caseCode == 1001 and
        state.openerCode == 1101 and
        selected.caseTemplate.id == "convenient_accident" and
        selected.rumor.id == "pritoky_innkeeper_strong_suspicion",
        "identity"
    )
    local restoredState, restored = DarkPassengerCaseContent.Transition(
        state,
        { generation = 4, context = context, roll = 0.99 },
        catalog
    )
    Expect(
        restored.accepted and restored.reason == "restored" and
        restoredState.caseCode == state.caseCode and
        restoredState.openerCode == state.openerCode,
        "stable restore"
    )
    local migrated, migration = DarkPassengerCaseContent.MigrateLegacyState({
        generation = 4,
        templateSlot = 1,
        rumorSlot = 1,
    })
    Expect(
        migration.accepted and migration.reason == "legacy_v1" and
        migrated.generation == 4 and migrated.caseCode == 1001 and
        migrated.openerCode == 1101 and migrated.variantCode == 0,
        "legacy migration"
    )

    local runtimeCatalog = VariantCatalog()
    local runtimeContext = nil
    local targetKeys = {}
    local targetKeyCount = 0
    for _, variant in ipairs(runtimeCatalog) do
        if variant.native_ready == true and runtimeContext == nil then
            runtimeContext = {
                region = variant.region,
                settlement = variant.settlement,
                candidateBySlot = {},
            }
        end
        if runtimeContext ~= nil and variant.native_ready == true and
           variant.region == runtimeContext.region and
           variant.settlement == runtimeContext.settlement then
            local targetSlot = tonumber(variant.target_slot)
            runtimeContext.candidateBySlot[targetSlot] = {
                candidate = { slot = targetSlot },
            }
            local targetKey = tostring(variant.anti_repeat_key)
            if targetKeys[targetKey] ~= true then
                targetKeys[targetKey] = true
                targetKeyCount = targetKeyCount + 1
            end
        end
    end
    local firstVariant = DarkPassengerCaseContent.SelectVariant(
        runtimeCatalog,
        runtimeContext,
        0,
        nil
    )
    Expect(
        firstVariant ~= nil and firstVariant.candidateEntry ~= nil,
        "variant selection"
    )
    local migratedVariant = nil
    if firstVariant ~= nil then
        migratedVariant = DarkPassengerCaseContent.FindCompatibleVariant(
            {
                caseCode = firstVariant.caseCode,
                openerCode = firstVariant.openerCode,
                variantCode = 999999999,
            },
            {
                region = firstVariant.variant.region,
                settlement = firstVariant.variant.settlement,
                candidateBySlot = {
                    [firstVariant.targetSlot] = firstVariant.candidateEntry,
                },
            },
            { firstVariant.variant }
        )
    end
    Expect(
        migratedVariant ~= nil and firstVariant ~= nil and
        migratedVariant.caseCode == firstVariant.caseCode and
        migratedVariant.targetSlot == firstVariant.targetSlot and
        migratedVariant.variantCode == firstVariant.variantCode,
        "variant migration"
    )
    local secondVariant = nil
    if firstVariant ~= nil then
        secondVariant = DarkPassengerCaseContent.SelectVariant(
            runtimeCatalog,
            runtimeContext,
            0,
            firstVariant.variantCode
        )
    end
    Expect(
        targetKeyCount > 1 and secondVariant ~= nil and
        secondVariant.variant.anti_repeat_key ~=
            firstVariant.variant.anti_repeat_key,
        "variant anti-repeat"
    )
    local replayGroups = {
        [1001] = { { weight = 1 } },
        [2001] = { { weight = 1 } },
        [3001] = { { weight = 1 } },
    }
    local replayOrder = { 1001, 2001, 3001 }
    local function ChoiceContains(choices, caseCode)
        for _, choice in ipairs(choices or {}) do
            if tonumber(choice.value) == tonumber(caseCode) then return true end
        end
        return false
    end
    local firstRunChoices, firstRunPolicy =
        DarkPassengerCaseContent.BuildReplayCaseChoices(
            replayGroups,
            replayOrder,
            {
                [1001] = { plays = 1, lastGeneration = 7 },
                [2001] = { plays = 0, lastGeneration = 0 },
                [3001] = { plays = 0, lastGeneration = 0 },
            },
            8,
            1001
        )
    Expect(
        firstRunPolicy.unplayed == true and
        not ChoiceContains(firstRunChoices, 1001) and
        ChoiceContains(firstRunChoices, 2001) and
        ChoiceContains(firstRunChoices, 3001),
        "unplayed stories first"
    )
    local replayChoices, replayPolicy =
        DarkPassengerCaseContent.BuildReplayCaseChoices(
            replayGroups,
            replayOrder,
            {
                [1001] = { plays = 2, lastGeneration = 4 },
                [2001] = { plays = 1, lastGeneration = 7 },
                [3001] = { plays = 1, lastGeneration = 6 },
            },
            8,
            2001
        )
    Expect(
        replayPolicy.unplayed == false and
        replayPolicy.immediate_repeat == true and
        not ChoiceContains(replayChoices, 2001),
        "immediate story repeat blocked"
    )
    local onlyChoice, onlyPolicy =
        DarkPassengerCaseContent.BuildReplayCaseChoices(
            { [2001] = replayGroups[2001] },
            { 2001 },
            { [2001] = { plays = 1, lastGeneration = 7 } },
            8,
            2001
        )
    Expect(
        #onlyChoice == 1 and onlyChoice[1].value == 2001 and
        onlyPolicy.immediate_repeat == false,
        "single available story remains replayable"
    )
    Expect(
        DarkPassengerCaseContent.GetStoryReplayWeight(
            1,
            { plays = 1, lastGeneration = 7 },
            8
        ) < DarkPassengerCaseContent.GetStoryReplayWeight(
            1,
            { plays = 1, lastGeneration = 3 },
            8
        ),
        "temporary replay penalty recovers"
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
            "dp_case_content_selftest",
            "DarkPassengerCaseContent.RunSelfTest()",
            "Dark Passenger: run persistent case-content self-test"
        )
    end
end)

Log("module loaded")
