Set-StrictMode -Version Latest

function Read-DpJsonFile {
    param([Parameter(Mandatory)][string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "JSON source not found: $LiteralPath"
    }
    try {
        return [System.IO.File]::ReadAllText($LiteralPath) |
            ConvertFrom-Json -Depth 100
    }
    catch {
        throw "Invalid JSON in '$LiteralPath': $($_.Exception.Message)"
    }
}

function Read-DpCaseSpec {
    param([Parameter(Mandatory)][string]$LiteralPath)
    return Read-DpJsonFile -LiteralPath $LiteralPath
}

function Read-DpCaseSettlementBindings {
    param([Parameter(Mandatory)][string]$LiteralPath)
    return Read-DpJsonFile -LiteralPath $LiteralPath
}

function Test-DpTextValue {
    param($Value)
    return -not [string]::IsNullOrWhiteSpace([string]$Value)
}

function Get-DpSettlementDialogueRoleNames {
    param([Parameter(Mandatory)]$SettlementBinding)

    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($semanticRole in 'innkeeper', 'witness') {
        $bindingProperty =
            $SettlementBinding.roles.PSObject.Properties[$semanticRole]
        if ($null -eq $bindingProperty) { continue }
        $dialogueRoleProperty =
            $bindingProperty.Value.PSObject.Properties['dialogueRole']
        if ($null -ne $dialogueRoleProperty -and
            (Test-DpTextValue $dialogueRoleProperty.Value)) {
            $names.Add([string]$dialogueRoleProperty.Value)
        }
    }

    $overheardProperty =
        $SettlementBinding.roles.PSObject.Properties['overheard']
    if ($null -ne $overheardProperty) {
        foreach ($pair in @($overheardProperty.Value.pairs)) {
            foreach ($speaker in @($pair.speakers)) {
                if (Test-DpTextValue $speaker.dialogueRole) {
                    $names.Add([string]$speaker.dialogueRole)
                }
            }
        }
    }
    return @($names | Sort-Object -Unique)
}

function Get-DpDialogueRoleRegistryErrors {
    param([Parameter(Mandatory)]$Bindings)

    $errors = [System.Collections.Generic.List[string]]::new()
    $registryProperty = $Bindings.PSObject.Properties['dialogueRoles']
    $definitions = if ($null -ne $registryProperty) {
        @($registryProperty.Value)
    }
    else { @() }
    if ($definitions.Count -eq 0) {
        $errors.Add('dialogueRoles registry is required')
        return $errors.ToArray()
    }

    $names = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $ids = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($definition in $definitions) {
        $name = [string]$definition.name
        $roleId = [string]$definition.roleId
        $metaRole = [string]$definition.metaRole
        if ($name -notmatch '^[A-Z][A-Z0-9_]*$') {
            $errors.Add("dialogue role name '$name' is invalid")
        }
        elseif (-not $names.Add($name)) {
            $errors.Add("dialogue role name '$name' is duplicated")
        }
        if ($roleId -notmatch
            '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
            $errors.Add("dialogue role '$name' roleId is invalid")
        }
        elseif (-not $ids.Add($roleId)) {
            $errors.Add("dialogue role roleId '$roleId' is duplicated")
        }
        if (-not (Test-DpTextValue $metaRole)) {
            $errors.Add("dialogue role '$name' metaRole is required")
        }
    }
    return $errors.ToArray()
}

function Get-DpStableGuid {
    param([Parameter(Mandatory)][string]$Seed)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Seed)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    $hex = [System.Convert]::ToHexString($hash).ToLowerInvariant().Substring(0, 32)
    return '{0}-{1}-{2}-{3}-{4}' -f `
        $hex.Substring(0, 8),
        $hex.Substring(8, 4),
        $hex.Substring(12, 4),
        $hex.Substring(16, 4),
        $hex.Substring(20, 12)
}

function Get-DpDirectionEvidence {
    param([Parameter(Mandatory)]$CaseSpec)

    return @($CaseSpec.evidence | Where-Object {
        [string]$_.role -ne 'innkeeper' -and
        $null -ne $_.PSObject.Properties['direction']
    })
}

function Get-DpJournalStates {
    param([Parameter(Mandatory)]$CaseSpec)

    $directions = @(Get-DpDirectionEvidence -CaseSpec $CaseSpec)
    $stateCount = [int][math]::Pow(2, $directions.Count)
    $states = [System.Collections.Generic.List[object]]::new()
    for ($mask = 0; $mask -lt $stateCount; $mask++) {
        $selected = [System.Collections.Generic.List[object]]::new()
        for ($index = 0; $index -lt $directions.Count; $index++) {
            if (($mask -band (1 -shl $index)) -ne 0) {
                $selected.Add($directions[$index])
            }
        }
        $codeSuffix = if ($selected.Count -eq 0) {
            'none'
        }
        else {
            @($selected | ForEach-Object { [int]$_.code }) -join '_'
        }
        $stateSuffix = if ($selected.Count -eq 0) {
            'None'
        }
        else {
            @($selected | ForEach-Object { [int]$_.code }) -join '_'
        }
        $states.Add([ordered]@{
            code = $mask
            state_name = "Directions$stateSuffix"
            signal_tag = 37 + $mask
            buff_guid = Get-DpStableGuid `
                -Seed "darkpassenger-lead-state-$mask"
            localization_key =
                "dp_case_$([int]$CaseSpec.code)_directions_$codeSuffix"
            direction_keys = @($selected | ForEach-Object {
                [string]$_.direction.key
            })
        })
    }
    return $states.ToArray()
}

function Get-DpDialogueVariants {
    param([Parameter(Mandatory)]$CaseSpec)

    $evidenceById = @{}
    foreach ($evidence in @($CaseSpec.evidence)) {
        $evidenceById[[string]$evidence.id] = $evidence
    }
    $result = [System.Collections.Generic.List[object]]::new()
    $slot = 0
    foreach ($dialogue in @($CaseSpec.native.dialogues)) {
        $variantsProperty = $dialogue.PSObject.Properties['variants']
        if ($null -eq $variantsProperty) { continue }
        $evidenceId = [string]$dialogue.evidenceId
        if (-not $evidenceById.ContainsKey($evidenceId)) {
            throw "Dialogue '$($dialogue.graphName)' has unknown evidence '$evidenceId'."
        }
        foreach ($variant in @($variantsProperty.Value)) {
            $discoveredCodes = @($variant.when.allDiscovered |
                ForEach-Object { [int]$evidenceById[[string]$_].code })
            $undiscoveredCodes = @($variant.when.allUndiscovered |
                ForEach-Object { [int]$evidenceById[[string]$_].code })
            $variantId = [string]$variant.id
            $result.Add([ordered]@{
                dialogue_name = [string]$dialogue.graphName
                dialogue_kind = [string]$dialogue.kind
                evidence_id = $evidenceId
                evidence_code = [int]$evidenceById[$evidenceId].code
                id = $variantId
                port_name = "variant_$variantId"
                sequence_name = "$($dialogue.sequenceName)_$variantId"
                prompt_key = [string]$variant.promptKey
                responses = @($variant.responses)
                all_discovered_codes = $discoveredCodes
                all_undiscovered_codes = $undiscoveredCodes
                signal_tag = 69 + $slot
                buff_guid = Get-DpStableGuid `
                    -Seed "darkpassenger-dialogue-variant-$slot"
            })
            $slot++
        }
    }
    return $result.ToArray()
}

function Get-DpOverheardDefinition {
    param(
        [Parameter(Mandatory)]$CaseSpec,
        [Parameter(Mandatory)]$Binding
    )

    $property = $CaseSpec.native.PSObject.Properties['overheard']
    if ($null -eq $property) { return $null }
    $overheard = $property.Value
    $evidence = @($CaseSpec.evidence | Where-Object {
        [string]$_.id -eq [string]$overheard.evidenceId
    })
    if ($evidence.Count -ne 1) {
        throw "Overheard dialogue '$($overheard.graphName)' has unknown evidence."
    }
    $bindingProperty = $Binding.roles.PSObject.Properties['overheard']
    if ($null -eq $bindingProperty) {
        throw "Case '$($CaseSpec.id)' has no overheard settlement binding."
    }
    $pairs = @($bindingProperty.Value.pairs)
    return [ordered]@{
        evidence_id = [string]$overheard.evidenceId
        evidence_code = [int]$evidence[0].code
        graph_name = [string]$overheard.graphName
        file_name = [string]$overheard.fileName
        root_key = [string]$overheard.rootKey
        decision_alias = [string]$overheard.decisionAlias
        sequence_name = [string]$overheard.sequenceName
        clue_port = [string]$overheard.cluePort
        clue_label = [string]$overheard.clueLabel
        context = [string]$overheard.context
        hearing_distance = [int]$overheard.hearingDistance
        repeat_after_seconds = [int]$overheard.repeatAfterSeconds
        available_tag = [int]$overheard.availableTag
        buff_guid = Get-DpStableGuid -Seed 'darkpassenger-overheard-available'
        responses = @($overheard.responses)
        pairs = $pairs
    }
}

function ConvertTo-DpLuaString {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) { return 'nil' }
    $escaped = $Value.Replace('\', '\\')
    $escaped = $escaped.Replace('"', '\"')
    $escaped = $escaped.Replace("`r", '\r')
    $escaped = $escaped.Replace("`n", '\n')
    $escaped = $escaped.Replace("`t", '\t')
    return '"' + $escaped + '"'
}

function ConvertTo-DpLuaValue {
    param(
        [AllowNull()]$Value,
        [int]$Indent = 0
    )

    if ($null -eq $Value) { return 'nil' }
    if ($Value -is [string] -or $Value -is [char]) {
        return ConvertTo-DpLuaString ([string]$Value)
    }
    if ($Value -is [bool]) {
        if ($Value) { return 'true' }
        return 'false'
    }
    if ($Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64] -or
        $Value -is [single] -or $Value -is [double] -or
        $Value -is [decimal]) {
        return ([System.IFormattable]$Value).ToString(
            $null,
            [System.Globalization.CultureInfo]::InvariantCulture
        )
    }

    $padding = ' ' * $Indent
    $childPadding = ' ' * ($Indent + 4)
    $rows = [System.Collections.Generic.List[string]]::new()

    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            $name = [string]$key
            $luaKey = if ($name -match '^[A-Za-z_][A-Za-z0-9_]*$') {
                $name
            }
            else {
                '[' + (ConvertTo-DpLuaString $name) + ']'
            }
            $rendered = ConvertTo-DpLuaValue -Value $Value[$key] `
                -Indent ($Indent + 4)
            $rows.Add("$childPadding$luaKey = $rendered,")
        }
    }
    elseif ($Value -is [System.Management.Automation.PSCustomObject]) {
        foreach ($property in $Value.PSObject.Properties) {
            $name = [string]$property.Name
            $luaKey = if ($name -match '^[A-Za-z_][A-Za-z0-9_]*$') {
                $name
            }
            else {
                '[' + (ConvertTo-DpLuaString $name) + ']'
            }
            $rendered = ConvertTo-DpLuaValue -Value $property.Value `
                -Indent ($Indent + 4)
            $rows.Add("$childPadding$luaKey = $rendered,")
        }
    }
    elseif ($Value -is [System.Collections.IEnumerable]) {
        foreach ($item in $Value) {
            $rendered = ConvertTo-DpLuaValue -Value $item `
                -Indent ($Indent + 4)
            $rows.Add("$childPadding$rendered,")
        }
    }
    else {
        return ConvertTo-DpLuaString ([string]$Value)
    }

    if ($rows.Count -eq 0) { return '{}' }
    return "{`n$($rows -join "`n")`n$padding}"
}

function ConvertTo-DpRuntimeEvidence {
    param(
        [Parameter(Mandatory)]$Evidence,
        [int]$DirectionCode = 0
    )

    return [ordered]@{
        id = [string]$Evidence.id
        code = [int]$Evidence.code
        kind = [string]$Evidence.kind
        role = [string]$Evidence.role
        item = if ($null -ne $Evidence.PSObject.Properties['item']) {
            $Evidence.item
        }
        else { $null }
        weight = if ($null -ne $Evidence.PSObject.Properties['weight']) {
            [double]$Evidence.weight
        }
        else { 1 }
        purpose = if ($null -ne $Evidence.PSObject.Properties['purpose']) {
            [string]$Evidence.purpose
        }
        else { $null }
        source_stance = if (
            $null -ne $Evidence.PSObject.Properties['sourceStance']
        ) { [string]$Evidence.sourceStance } else { $null }
        confidence = [int]$Evidence.confidence
        placement = [string]$Evidence.placement
        discoverable_without_hint = [bool]$Evidence.discoverableWithoutHint
        hints_unlocked_by = @($Evidence.hintsUnlockedBy | ForEach-Object {
            [string]$_
        })
        reveals = @($Evidence.reveals | ForEach-Object { [string]$_ })
        prompt_key = if (
            $null -ne $Evidence.PSObject.Properties['promptKey']
        ) { [string]$Evidence.promptKey } else { $null }
        direction_code = $DirectionCode
        direction_key = if (
            $null -ne $Evidence.PSObject.Properties['direction']
        ) { [string]$Evidence.direction.key } else { $null }
    }
}

function ConvertTo-DpRuntimeCase {
    param(
        [Parameter(Mandatory)]$CaseSpec,
        [Parameter(Mandatory)]$Binding
    )

    $evidence = [System.Collections.Generic.List[object]]::new()
    $directionIndex = 0
    foreach ($definition in @($CaseSpec.evidence)) {
        $directionCode = 0
        if ([string]$definition.role -ne 'innkeeper' -and
            $null -ne $definition.PSObject.Properties['direction']) {
            $directionCode = 1 -shl $directionIndex
            $directionIndex++
        }
        $evidence.Add((ConvertTo-DpRuntimeEvidence `
            -Evidence $definition `
            -DirectionCode $directionCode))
    }
    $rumors = @($evidence | Where-Object {
        $_.kind -eq 'dialogue' -and $_.role -eq 'innkeeper'
    })

    $dialogueVariants = @(Get-DpDialogueVariants -CaseSpec $CaseSpec |
        ForEach-Object {
            [ordered]@{
                dialogue_name = $_.dialogue_name
                dialogue_kind = $_.dialogue_kind
                evidence_id = $_.evidence_id
                evidence_code = $_.evidence_code
                id = $_.id
                all_discovered_codes = $_.all_discovered_codes
                all_undiscovered_codes = $_.all_undiscovered_codes
                signal_tag = $_.signal_tag
                buff_guid = $_.buff_guid
            }
        })
    $overheard = Get-DpOverheardDefinition `
        -CaseSpec $CaseSpec `
        -Binding $Binding
    return [ordered]@{
        id = [string]$CaseSpec.id
        code = [int]$CaseSpec.code
        weight = [double]$CaseSpec.weight
        constraints = [ordered]@{
            region = [string]$CaseSpec.constraints.region
            settlement = [string]$CaseSpec.constraints.settlement
        }
        target_policy = $CaseSpec.targetPolicy
        crime_profile = $CaseSpec.crimeProfile
        reveal_threshold = [int]$CaseSpec.revealThreshold
        rumors = $rumors
        evidence_steps = @($evidence | Select-Object -Skip 1)
        evidence = $evidence.ToArray()
        journal_states = @(Get-DpJournalStates -CaseSpec $CaseSpec)
        dialogue_variants = $dialogueVariants
        overheard = $overheard
        bindings = $Binding.roles
        text = $CaseSpec.text
    }
}

function ConvertTo-DpCaseCatalogLua {
    param(
        [Parameter(Mandatory)][object[]]$CaseSpecs,
        [Parameter(Mandatory)]$Bindings
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('-- Generated by Compile-CaseSpecs.ps1. Do not edit.')
    $lines.Add('DarkPassengerCaseCatalog = {}')
    $lines.Add('DarkPassengerCaseCatalogOrder = {')
    foreach ($case in $CaseSpecs) {
        $lines.Add('    ' + (ConvertTo-DpLuaString ([string]$case.id)) + ',')
    }
    $lines.Add('}')
    $lines.Add('DarkPassengerCaseCatalogByCode = {}')
    $lines.Add('')

    foreach ($case in $CaseSpecs) {
        $binding = @($Bindings.settlements | Where-Object {
            [string]$_.region -eq [string]$case.constraints.region -and
            [string]$_.settlement -eq [string]$case.constraints.settlement
        })[0]
        $runtimeCase = ConvertTo-DpRuntimeCase `
            -CaseSpec $case `
            -Binding $binding
        $caseId = ConvertTo-DpLuaString ([string]$case.id)
        $lines.Add("DarkPassengerCaseCatalog[$caseId] = " +
            (ConvertTo-DpLuaValue -Value $runtimeCase))
        $lines.Add(
            "DarkPassengerCaseCatalogByCode[$([int]$case.code)] = " +
            "DarkPassengerCaseCatalog[$caseId]"
        )
        $lines.Add('')
    }

    return ($lines -join "`n") + "`n"
}

function Get-DpStableRuntimeCode {
    param([Parameter(Mandatory)][string]$Value)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    $code = (([int]$hash[0]) -shl 16) -bor
        (([int]$hash[1]) -shl 8) -bor ([int]$hash[2])
    if ($code -le 0) {
        throw "Stable runtime code resolved to zero for '$Value'."
    }
    return [int]$code
}

function Get-DpTrophyAssetPreset {
    param([Parameter(Mandatory)][string]$Name)

    switch ($Name) {
        'bird-feather' {
            return [ordered]@{
                item_guid = Get-DpStableGuid `
                    -Seed 'darkpassenger-trophy|bloodied-feather'
                item_name = 'dp_trophy_bloodied_feather'
                name_key = 'dp_trophy_bloodied_feather_name'
                info_key = 'dp_trophy_bloodied_feather_info'
                name = [ordered]@{
                    ru = 'Трофей - Окровавленное перо'
                    en = 'Trophy - Bloodied Feather'
                }
                description = [ordered]@{
                    ru = 'Красное перо, снятое с тела избранной жертвы. Ещё одна память о приговоре, который никто другой не вынес.'
                    en = 'A red feather taken from a chosen victim. Another reminder of a sentence no one else would pass.'
                }
                icon_id = 'special_featherRed'
                model =
                    'manmade/task_specific_props/read_and_write/inkwell/quill.cgf'
                type = 5
                sub_type = 4
                weight = '0'
                price = 0
                fade_coef = '6.0606'
                visibility_coef = '1'
                is_divisible = $true
                is_quest_item = $false
            }
        }
        default { throw "Unknown trophy asset preset '$Name'." }
    }
}

function ConvertTo-DpNativeTrophyDefinition {
    param([Parameter(Mandatory)]$Variant)

    $property = $Variant.PSObject.Properties['trophyDefinition']
    if ($null -eq $property -or $null -eq $property.Value) { return $null }
    $semantic = $property.Value
    $preset = Get-DpTrophyAssetPreset -Name ([string]$semantic.preset)
    return [ordered]@{
        preset = [string]$semantic.preset
        item_guid = [string]$preset.item_guid
        item_name = [string]$preset.item_name
        name_key = [string]$preset.name_key
        info_key = [string]$preset.info_key
        name = $preset.name
        description = $preset.description
        case_description = $semantic.description
        item = [ordered]@{
            classification = [string]$semantic.item.classification
            retention = [string]$semantic.item.retention
            weight = [double]$semantic.item.weight
        }
        asset = [ordered]@{
            icon_id = [string]$preset.icon_id
            model = [string]$preset.model
            type = [int]$preset.type
            sub_type = [int]$preset.sub_type
            weight = [string]$preset.weight
            price = [int]$preset.price
            fade_coef = [string]$preset.fade_coef
            visibility_coef = [string]$preset.visibility_coef
            is_divisible = [bool]$preset.is_divisible
            is_quest_item = [bool]$preset.is_quest_item
        }
    }
}

function ConvertTo-DpRuntimeVariantBinding {
    param(
        $Binding,
        [hashtable]$CandidateByEntityName
    )

    if ($null -eq $Binding) { return $null }
    $entityName = [string]$Binding.entityName
    $candidate = if ($CandidateByEntityName.ContainsKey($entityName)) {
        $CandidateByEntityName[$entityName]
    }
    else { $null }
    return [ordered]@{
        kind = [string]$Binding.kind
        entity_name = $entityName
        entity_guid = [string]$Binding.entityGuid
        soul_guid = if ($null -ne $Binding.PSObject.Properties['soulGuid']) {
            [string]$Binding.soulGuid
        }
        else { '' }
        candidate_slot = if ($null -ne $candidate) {
            [int]$candidate.slot
        }
        else { 0 }
        identity_mode = [string]$Binding.identityMode
        capabilities = @($Binding.capabilities | ForEach-Object { [string]$_ })
        policy_flags = @($Binding.policyFlags | ForEach-Object { [string]$_ })
    }
}

function ConvertTo-DpRuntimeSceneDefinitions {
    param(
        [Parameter(Mandatory)]$Story,
        [Parameter(Mandatory)]$VariantBindings,
        [Parameter(Mandatory)][hashtable]$CandidateByEntityName
    )

    $evidenceById = @{}
    foreach ($evidence in @($Story.evidence)) {
        $evidenceById[[string]$evidence.qualifiedId] = $evidence
    }
    $scenes = [System.Collections.Generic.List[object]]::new()
    foreach ($thread in @($Story.threads)) {
        foreach ($step in @($thread.steps)) {
            $qualifiedId = "$([string]$thread.id)/$([string]$step.id)"
            $evidence = $evidenceById[$qualifiedId]
            $resolvedBindings = [ordered]@{}
            if ($null -ne $step.action -and $null -ne $step.action.bindings) {
                foreach ($bindingProperty in $step.action.bindings.PSObject.Properties) {
                    $semanticSlot = [string]$bindingProperty.Value
                    $variantBinding = $VariantBindings.PSObject.Properties[
                        $semanticSlot
                    ].Value
                    $resolvedBindings[[string]$bindingProperty.Name] =
                        ConvertTo-DpRuntimeVariantBinding `
                            -Binding $variantBinding `
                            -CandidateByEntityName $CandidateByEntityName
                }
            }
            $scenes.Add([ordered]@{
                id = $qualifiedId
                thread_id = [string]$thread.id
                step_id = [string]$step.id
                kind = [string]$step.kind
                evidence_code = if ($null -ne $evidence) {
                    [int]$evidence.code
                }
                else { 0 }
                placement = if (
                    [string]$step.action.evidenceModule -eq
                        'document-in-container'
                ) { 'case_start' } else { 'on_event' }
                evidence_module = [string]$step.action.evidenceModule
                resolved_bindings = $resolvedBindings
                compiled_assets = $step.presentations
            })
        }
    }
    return $scenes.ToArray()
}

function Get-DpCaseCleanupManifest {
    param(
        [Parameter(Mandatory)]$CaseSpec,
        [Parameter(Mandatory)]$Variant,
        [Parameter(Mandatory)][object[]]$RuntimeScenes,
        $Binding,
        [object[]]$QuestItemPlacementSignals = @(),
        $Trophy
    )

    $evidenceCodes = @(
        $CaseSpec.evidence |
            ForEach-Object { [int]$_.code } |
            Sort-Object -Unique
    )
    $availabilityRoles = @(
        $CaseSpec.evidence |
            ForEach-Object { [string]$_.role } |
            Where-Object { $_ -in @('innkeeper', 'witness', 'overheard') } |
            Sort-Object -Unique
    )

    $signalBuffGuids = [System.Collections.Generic.List[string]]::new()
    foreach ($state in @(Get-DpJournalStates -CaseSpec $CaseSpec)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$state.buff_guid)) {
            $signalBuffGuids.Add([string]$state.buff_guid)
        }
    }
    foreach ($variantSignal in @(Get-DpDialogueVariants -CaseSpec $CaseSpec)) {
        if (-not [string]::IsNullOrWhiteSpace(
            [string]$variantSignal.buff_guid
        )) {
            $signalBuffGuids.Add([string]$variantSignal.buff_guid)
        }
    }
    if ($null -ne $Binding) {
        $overheard = Get-DpOverheardDefinition `
            -CaseSpec $CaseSpec `
            -Binding $Binding
        if ($null -ne $overheard -and
            -not [string]::IsNullOrWhiteSpace([string]$overheard.buff_guid)) {
            $signalBuffGuids.Add([string]$overheard.buff_guid)
        }
    }

    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($evidence in @($CaseSpec.evidence)) {
        $itemProperty = $evidence.PSObject.Properties['item']
        if ($null -eq $itemProperty -or $null -eq $itemProperty.Value) {
            continue
        }
        $source = "evidence:$([string]$evidence.id)"
        $signal = @($QuestItemPlacementSignals | Where-Object {
            [string]$_.source -eq $source
        })[0]
        if ($null -eq $signal) { continue }
        $scene = @($RuntimeScenes | Where-Object {
            [int]$_.evidence_code -eq [int]$evidence.code
        })[0]
        $destination = if ($null -ne $scene -and
            $null -ne $scene.resolved_bindings) {
            if ($scene.resolved_bindings -is
                [System.Collections.IDictionary]) {
                $scene.resolved_bindings['container']
            }
            else {
                $containerProperty =
                    $scene.resolved_bindings.PSObject.Properties['container']
                if ($null -ne $containerProperty) {
                $containerProperty.Value
                }
                else { $null }
            }
        }
        else { $null }
        $items.Add([ordered]@{
            evidence_code = [int]$evidence.code
            item_guid = [string]$signal.item_guid
            classification = [string]$signal.classification
            retention = [string]$signal.retention
            backend = [string]$signal.backend
            destination_entity_name = if ($null -ne $destination) {
                if ($destination -is [System.Collections.IDictionary]) {
                    [string]$destination['entity_name']
                }
                else { [string]$destination.entity_name }
            }
            else { '' }
            destination_entity_guid = if ($null -ne $destination) {
                if ($destination -is [System.Collections.IDictionary]) {
                    [string]$destination['entity_guid']
                }
                else { [string]$destination.entity_guid }
            }
            else { '' }
        })
        if (-not [string]::IsNullOrWhiteSpace([string]$signal.buff_guid)) {
            $signalBuffGuids.Add([string]$signal.buff_guid)
        }
    }
    if ($null -ne $Trophy) {
        $items.Add([ordered]@{
            evidence_code = 0
            item_guid = [string]$Trophy.item_guid
            classification = [string]$Trophy.item.classification
            retention = [string]$Trophy.item.retention
            backend = 'target_inventory'
            destination_entity_name = ''
            destination_entity_guid = ''
        })
    }

    $entityContexts = [System.Collections.Generic.List[string]]::new()
    $nativeProperty = $CaseSpec.PSObject.Properties['native']
    $native = if ($null -ne $nativeProperty) {
        $nativeProperty.Value
    }
    else { $null }
    $contextsProperty = if ($null -ne $native) {
        $native.PSObject.Properties['contexts']
    }
    else { $null }
    if ($null -ne $contextsProperty -and $null -ne $contextsProperty.Value) {
        foreach ($property in $contextsProperty.Value.PSObject.Properties) {
            $value = [string]$property.Value
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $entityContexts.Add($value)
            }
        }
    }
    $overheardProperty = if ($null -ne $native) {
        $native.PSObject.Properties['overheard']
    }
    else { $null }
    if ($null -ne $overheardProperty -and
        $null -ne $overheardProperty.Value -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$overheardProperty.Value.context
        )) {
        $entityContexts.Add([string]$overheardProperty.Value.context)
    }

    return [ordered]@{
        schema_version = 1
        case_code = [int]$CaseSpec.code
        variant_code = Get-DpStableRuntimeCode -Value ([string]$Variant.variantId)
        evidence_codes = $evidenceCodes
        availability_roles = $availabilityRoles
        signal_buff_guids = @($signalBuffGuids | Sort-Object -Unique)
        entity_contexts = @($entityContexts | Sort-Object -Unique)
        items = $items.ToArray()
        scene_ids = @(
            $RuntimeScenes |
                ForEach-Object { [string]$_.id } |
                Sort-Object -Unique
        )
    }
}

function ConvertTo-DpCaseVariantCatalogLua {
    param(
        [Parameter(Mandatory)]$CompiledDefinitions,
        [Parameter(Mandatory)][object[]]$CaseSpecs,
        [Parameter(Mandatory)][object[]]$Candidates,
        $Bindings,
        [object[]]$QuestItemPlacementSignals = @()
    )

    $storyById = @{}
    foreach ($story in @($CompiledDefinitions.stories)) {
        $storyById[[string]$story.storyId] = $story
    }
    $caseByCode = @{}
    foreach ($caseSpec in @($CaseSpecs)) {
        $caseByCode[[int]$caseSpec.code] = $caseSpec
    }
    $candidateByEntityName = @{}
    foreach ($candidate in @($Candidates)) {
        $entityName = [string]$candidate.entityName
        if (-not [string]::IsNullOrWhiteSpace($entityName)) {
            $candidateByEntityName[$entityName] = $candidate
        }
    }

    $variantCodes = @{}
    $bindingCodes = @{}
    $runtimeVariants = [System.Collections.Generic.List[object]]::new()
    foreach ($variant in @($CompiledDefinitions.variants | Sort-Object variantId)) {
        $story = $storyById[[string]$variant.storyId]
        if ($null -eq $story) {
            throw "Variant '$($variant.variantId)' references unknown story."
        }
        $caseSpec = $caseByCode[[int]$variant.caseCode]
        $variantCode = Get-DpStableRuntimeCode -Value ([string]$variant.variantId)
        $bindingCode = Get-DpStableRuntimeCode -Value ([string]$variant.bindingSeed)
        foreach ($entry in @(
            @{ Map = $variantCodes; Code = $variantCode; Kind = 'variant' },
            @{ Map = $bindingCodes; Code = $bindingCode; Kind = 'binding' }
        )) {
            if ($entry.Map.ContainsKey($entry.Code)) {
                throw "Stable $($entry.Kind) code collision: $($entry.Code)."
            }
            $entry.Map[$entry.Code] = [string]$variant.variantId
        }

        $runtimeBindings = [ordered]@{}
        foreach ($property in $variant.bindings.PSObject.Properties) {
            $runtimeBindings[[string]$property.Name] =
                ConvertTo-DpRuntimeVariantBinding `
                    -Binding $property.Value `
                    -CandidateByEntityName $candidateByEntityName
        }
        $target = $runtimeBindings.target
        $nativeReady = $null -ne $caseSpec -and
            [string]$caseSpec.constraints.region -eq [string]$variant.region -and
            [string]$caseSpec.constraints.settlement -eq
                [string]$variant.settlement -and
            [int]$target.candidate_slot -gt 0
        $runtimeScenes = @(ConvertTo-DpRuntimeSceneDefinitions `
            -Story $story -VariantBindings $variant.bindings `
            -CandidateByEntityName $candidateByEntityName)
        $trophy = ConvertTo-DpNativeTrophyDefinition -Variant $variant
        $caseBinding = if ($null -ne $Bindings) {
            @($Bindings.settlements | Where-Object {
                [string]$_.region -eq [string]$caseSpec.constraints.region -and
                [string]$_.settlement -eq [string]$caseSpec.constraints.settlement
            })[0]
        }
        else { $null }
        $cleanupManifest = if ($nativeReady) {
            Get-DpCaseCleanupManifest `
                -CaseSpec $caseSpec `
                -Variant $variant `
                -RuntimeScenes $runtimeScenes `
                -Binding $caseBinding `
                -QuestItemPlacementSignals $QuestItemPlacementSignals `
                -Trophy $trophy
        }
        else { $null }
        $runtimeVariants.Add([ordered]@{
            variant_id = [string]$variant.variantId
            variant_code = $variantCode
            binding_code = $bindingCode
            story_id = [string]$variant.storyId
            case_id = [string]$variant.caseId
            case_code = [int]$variant.caseCode
            composition_id = [string]$variant.compositionId
            region = [string]$variant.region
            settlement = [string]$variant.settlement
            rank = [int]$variant.rank
            weight = [double]$story.weight
            native_ready = $nativeReady
            anti_repeat_key = [string]$target.entity_name
            target_slot = [int]$target.candidate_slot
            trophy = $trophy
            bindings = $runtimeBindings
            scenes = $runtimeScenes
            cleanup_manifest = $cleanupManifest
        })
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('-- Generated by Compile-CaseSpecs.ps1. Do not edit.')
    $lines.Add('DarkPassengerCaseVariantCatalog = {}')
    $lines.Add('DarkPassengerCaseVariantCatalogOrder = {')
    foreach ($variant in $runtimeVariants) {
        $lines.Add('    ' + (ConvertTo-DpLuaString $variant.variant_id) + ',')
    }
    $lines.Add('}')
    $lines.Add('DarkPassengerCaseVariantCatalogByCode = {}')
    $lines.Add('')
    foreach ($variant in $runtimeVariants) {
        $variantId = ConvertTo-DpLuaString $variant.variant_id
        $lines.Add("DarkPassengerCaseVariantCatalog[$variantId] = " +
            (ConvertTo-DpLuaValue -Value $variant))
        $lines.Add(
            "DarkPassengerCaseVariantCatalogByCode[$($variant.variant_code)] = " +
            "DarkPassengerCaseVariantCatalog[$variantId]"
        )
        $lines.Add('')
    }
    return ($lines -join "`n") + "`n"
}

function ConvertTo-DpCaseCompatibilityReport {
    param([Parameter(Mandatory)][object[]]$CaseSpecs)

    $cases = @($CaseSpecs | ForEach-Object {
        [ordered]@{
            id = [string]$_.id
            code = [int]$_.code
            bindingKey =
                [string]$_.constraints.region + '/' +
                [string]$_.constraints.settlement
            evidenceIds = @($_.evidence | ForEach-Object { [string]$_.id })
            evidenceCodes = @($_.evidence | ForEach-Object { [int]$_.code })
        }
    })
    return [ordered]@{
        schemaVersion = 1
        cases = $cases
    }
}

function ConvertTo-DpXmlText {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return '' }
    return [System.Security.SecurityElement]::Escape($Value)
}

function ConvertTo-DpLocalizationXml {
    param(
        [Parameter(Mandatory)][string]$BaseLiteralPath,
        [Parameter(Mandatory)][object[]]$CaseSpecs,
        [Parameter(Mandatory)][ValidateSet('ru', 'en')][string]$Language,
        $CompiledDefinitions
    )

    [xml]$base = [System.IO.File]::ReadAllText($BaseLiteralPath)
    $rows = [System.Collections.Generic.List[object]]::new()
    $values = [ordered]@{}
    foreach ($row in @($base.Table.Row)) {
        $cells = @($row.Cell)
        if ($cells.Count -lt 2) { continue }
        $key = [string]$cells[0]
        $value = [string]$cells[1]
        if ($values.Contains($key)) {
            throw "Duplicate localization key '$key' in $BaseLiteralPath"
        }
        $values[$key] = $value
        $rows.Add([ordered]@{ key = $key; value = $value })
    }

    foreach ($case in @($CaseSpecs | Sort-Object code, id)) {
        if ($null -eq $case.PSObject.Properties['localization']) {
            continue
        }
        $languageRows = $case.localization.$Language
        if ($null -eq $languageRows) { continue }
        foreach ($property in $languageRows.PSObject.Properties) {
            $key = [string]$property.Name
            $value = [string]$property.Value
            if ($values.Contains($key)) {
                if ([string]$values[$key] -ne $value) {
                    throw (
                        "Localization key '$key' conflicts with existing " +
                        "$Language text."
                    )
                }
                continue
            }
            $values[$key] = $value
            $rows.Add([ordered]@{ key = $key; value = $value })
        }
        foreach ($state in @(Get-DpJournalStates -CaseSpec $case)) {
            if ([int]$state.code -eq 0) { continue }
            $key = [string]$state.localization_key
            $parts = @($state.direction_keys | ForEach-Object {
                $directionKey = [string]$_
                if (-not $values.Contains($directionKey)) {
                    throw (
                        "Journal direction key '$directionKey' is absent " +
                        "from $Language localization."
                    )
                }
                [string]$values[$directionKey]
            })
            $value = $parts -join ' '
            if ($values.Contains($key)) {
                if ([string]$values[$key] -ne $value) {
                    throw "Generated journal localization key '$key' conflicts."
                }
                continue
            }
            $values[$key] = $value
            $rows.Add([ordered]@{ key = $key; value = $value })
        }
    }

    $compiledVariants = if ($null -eq $CompiledDefinitions) {
        @()
    }
    else { @($CompiledDefinitions.variants) }
    foreach ($variant in @($compiledVariants | Sort-Object variantId)) {
        $trophy = ConvertTo-DpNativeTrophyDefinition -Variant $variant
        if ($null -eq $trophy) { continue }
        foreach ($entry in @(
            [ordered]@{
                key = [string]$trophy.name_key
                value = [string]$trophy.name[$Language]
            },
            [ordered]@{
                key = [string]$trophy.info_key
                value = [string]$trophy.description[$Language]
            }
        )) {
            if ($values.Contains($entry.key)) {
                if ([string]$values[$entry.key] -ne $entry.value) {
                    throw "Generated trophy localization key " +
                        "'$($entry.key)' conflicts."
                }
                continue
            }
            $values[$entry.key] = $entry.value
            $rows.Add($entry)
        }
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('<?xml version="1.0" encoding="utf-8"?>')
    $lines.Add('<Table>')
    foreach ($row in $rows) {
        $key = ConvertTo-DpXmlText ([string]$row.key)
        $value = ConvertTo-DpXmlText ([string]$row.value)
        $lines.Add("`t<Row><Cell>$key</Cell><Cell>$value</Cell></Row>")
    }
    $lines.Add('</Table>')
    return ($lines -join "`n") + "`n"
}

function ConvertTo-DpStormRoleXml {
    param(
        [Parameter(Mandatory)][string]$BaseXml,
        [Parameter(Mandatory)][object[]]$CaseSpecs,
        [Parameter(Mandatory)]$Bindings
    )

    $rules = @([regex]::Matches($BaseXml, '(?s)<rule\b.*?</rule>'))
    $additions = [System.Collections.Generic.List[string]]::new()
    foreach ($case in @($CaseSpecs | Sort-Object code, id)) {
        $binding = @($Bindings.settlements | Where-Object {
            [string]$_.region -eq [string]$case.constraints.region -and
            [string]$_.settlement -eq [string]$case.constraints.settlement
        })[0]
        $roleBindings = [System.Collections.Generic.List[object]]::new()
        foreach ($role in 'innkeeper', 'witness') {
            $property = $binding.roles.PSObject.Properties[$role]
            if ($null -eq $property) { continue }
            $roleBindings.Add([ordered]@{
                suffix = $role
                value = $property.Value
            })
        }
        $overheardProperty = $binding.roles.PSObject.Properties['overheard']
        if ($null -ne $overheardProperty) {
            foreach ($pair in @($overheardProperty.Value.pairs)) {
                foreach ($speaker in @($pair.speakers)) {
                    $roleBindings.Add([ordered]@{
                        suffix = 'overheard_' + [string]$pair.id + '_' +
                            [string]$speaker.role
                        value = $speaker
                    })
                }
            }
        }
        foreach ($entry in $roleBindings) {
            $roleBinding = $entry.value
            $entityName = [string]$roleBinding.entityName
            $dialogueRole = [string]$roleBinding.dialogueRole
            $existing = @($rules | Where-Object {
                $_.Value.Contains("<hasName name=`"$entityName`" />") -and
                $_.Value.Contains("<addRole name=`"$dialogueRole`" />")
            })
            if ($existing.Count -gt 0) { continue }

            $ruleName = 'darkpassenger_' +
                ([string]$case.constraints.settlement -replace '[^A-Za-z0-9_]', '_') +
                '_' + ([string]$entry.suffix -replace '[^A-Za-z0-9_]', '_')
            if ($BaseXml.Contains("<rule name=`"$ruleName`">") -or
                @($additions | Where-Object {
                    $_.Contains("<rule name=`"$ruleName`">")
                }).Count -gt 0) {
                throw "Storm rule name collision: $ruleName"
            }
            $entityXml = ConvertTo-DpXmlText $entityName
            $roleXml = ConvertTo-DpXmlText $dialogueRole
            $additions.Add(@"
    <rule name="$ruleName">
      <selectors>
        <hasName name="$entityXml" />
      </selectors>
      <operations>
        <addRole name="$roleXml" />
      </operations>
    </rule>
"@.TrimEnd())
        }
    }
    if ($additions.Count -eq 0) { return $BaseXml }
    $marker = '  </rules>'
    $index = $BaseXml.LastIndexOf($marker)
    if ($index -lt 0) { throw 'Storm role table has no rules terminator.' }
    return $BaseXml.Insert(
        $index,
        ($additions -join "`n") + "`n"
    )
}

function ConvertTo-DpDialogueRoleTableXml {
    param(
        [Parameter(Mandatory)][string]$BaseXml,
        [Parameter(Mandatory)][object[]]$CaseSpecs,
        [Parameter(Mandatory)]$Bindings
    )

    $registryErrors = @(Get-DpDialogueRoleRegistryErrors -Bindings $Bindings)
    if ($registryErrors.Count -gt 0) {
        throw "Dialogue role registry is invalid:`n - $($registryErrors -join "`n - ")"
    }

    $definitions = @($Bindings.dialogueRoles)
    $requiredNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($case in @($CaseSpecs | Sort-Object code, id)) {
        $matchingBindings = @($Bindings.settlements | Where-Object {
            [string]$_.region -eq [string]$case.constraints.region -and
            [string]$_.settlement -eq [string]$case.constraints.settlement
        })
        if ($matchingBindings.Count -ne 1) {
            throw "Case '$($case.id)' requires exactly one settlement binding."
        }
        foreach ($roleName in @(Get-DpSettlementDialogueRoleNames `
            -SettlementBinding $matchingBindings[0])) {
            [void]$requiredNames.Add([string]$roleName)
        }
    }

    $knownNames = [ordered]@{}
    $knownIds = [ordered]@{}
    foreach ($match in [regex]::Matches($BaseXml, '<role\b[^>]*/>')) {
        $nameMatch = [regex]::Match(
            $match.Value,
            '\brole_name="([^"]+)"'
        )
        $idMatch = [regex]::Match(
            $match.Value,
            '\brole_id="([^"]+)"'
        )
        $metaRoleMatch = [regex]::Match(
            $match.Value,
            '\bmetarole_name="([^"]+)"'
        )
        if (-not $nameMatch.Success -or -not $idMatch.Success -or
            -not $metaRoleMatch.Success) {
            throw "Malformed RPG role row: $($match.Value)"
        }
        $knownNames[[string]$nameMatch.Groups[1].Value] = [ordered]@{
            roleId = [string]$idMatch.Groups[1].Value
            metaRole = [string]$metaRoleMatch.Groups[1].Value
        }
        $knownIds[[string]$idMatch.Groups[1].Value] =
            [string]$nameMatch.Groups[1].Value
    }

    $additions = [System.Collections.Generic.List[string]]::new()
    foreach ($roleName in @($requiredNames | Sort-Object)) {
        $matches = @($definitions | Where-Object {
            [string]$_.name -eq $roleName
        })
        if ($matches.Count -ne 1) {
            throw "Dialogue role '$roleName' requires exactly one registry definition."
        }
        $definition = $matches[0]
        $roleId = [string]$definition.roleId
        $metaRole = [string]$definition.metaRole

        if ($knownNames.Contains($roleName)) {
            $known = $knownNames[$roleName]
            if ([string]$known.roleId -ne $roleId -or
                [string]$known.metaRole -ne $metaRole) {
                throw "Dialogue role '$roleName' conflicts with the base RPG table."
            }
            continue
        }
        if ($knownIds.Contains($roleId)) {
            throw "Dialogue role id '$roleId' is already used by '$($knownIds[$roleId])'."
        }

        $roleIdXml = ConvertTo-DpXmlText $roleId
        $metaRoleXml = ConvertTo-DpXmlText $metaRole
        $roleNameXml = ConvertTo-DpXmlText $roleName
        $additions.Add(
            "    <role role_id=`"$roleIdXml`" " +
            "metarole_name=`"$metaRoleXml`" role_name=`"$roleNameXml`" />"
        )
        $knownNames[$roleName] = [ordered]@{
            roleId = $roleId
            metaRole = $metaRole
        }
        $knownIds[$roleId] = $roleName
    }
    if ($additions.Count -eq 0) { return $BaseXml }
    $marker = '  </roles>'
    $index = $BaseXml.LastIndexOf($marker)
    if ($index -lt 0) { throw 'RPG role table has no roles terminator.' }
    return $BaseXml.Insert($index, ($additions -join "`n") + "`n")
}

function ConvertTo-DpScriptContextXml {
    param(
        [Parameter(Mandatory)][string]$BaseXml,
        [Parameter(Mandatory)][object[]]$CaseSpecs,
        [object[]]$Signals = @()
    )

    $names = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($match in [regex]::Matches(
        $BaseXml,
        '<ScriptContextDatabaseNode\s+Name="([^"]+)"'
    )) {
        [void]$names.Add([string]$match.Groups[1].Value)
    }
    $additions = [System.Collections.Generic.List[string]]::new()
    foreach ($case in @($CaseSpecs | Sort-Object code, id)) {
        $contexts = [System.Collections.Generic.List[string]]::new()
        foreach ($context in @(
            [string]$case.native.contexts.rumorHeard,
            [string]$case.native.contexts.witnessHeard
        )) {
            if (Test-DpTextValue $context) { $contexts.Add($context) }
        }
        $overheardProperty = $case.native.PSObject.Properties['overheard']
        if ($null -ne $overheardProperty -and
            (Test-DpTextValue $overheardProperty.Value.context)) {
            $contexts.Add([string]$overheardProperty.Value.context)
        }
        foreach ($context in $contexts) {
            if ($names.Add($context)) {
                $contextXml = ConvertTo-DpXmlText $context
                $additions.Add(
                    "    <ScriptContextDatabaseNode Name=`"$contextXml`" Class=`"Entity`" />"
                )
            }
        }
    }
    foreach ($signal in @($Signals)) {
        $context = [string]$signal.read_context
        if (-not [string]::IsNullOrWhiteSpace($context) -and
            $names.Add($context)) {
            $contextXml = ConvertTo-DpXmlText $context
            $additions.Add(
                "    <ScriptContextDatabaseNode Name=`"$contextXml`" Class=`"Entity`" />"
            )
        }
    }
    if ($additions.Count -eq 0) { return $BaseXml }
    $marker = if ($BaseXml.Contains('  </ScriptContexts>')) {
        '  </ScriptContexts>'
    }
    else { '</ScriptContexts>' }
    $index = $BaseXml.LastIndexOf($marker)
    if ($index -lt 0) { throw 'ScriptContext table has no terminator.' }
    return $BaseXml.Insert($index, ($additions -join "`n") + "`n")
}

function ConvertTo-DpItemTableXml {
    param(
        [Parameter(Mandatory)][string]$BaseXml,
        [Parameter(Mandatory)][object[]]$CaseSpecs,
        [Parameter(Mandatory)]$Bindings,
        $CompiledDefinitions
    )

    $knownIds = [ordered]@{}
    $knownNames = [ordered]@{}
    foreach ($match in [regex]::Matches(
        $BaseXml,
        '<[A-Za-z]+\b[^>]*\bId="([^"]+)"[^>]*\bName="([^"]+)"'
    )) {
        $knownIds[[string]$match.Groups[1].Value] =
            [string]$match.Groups[2].Value
        $knownNames[[string]$match.Groups[2].Value] =
            [string]$match.Groups[1].Value
    }

    $additions = [System.Collections.Generic.List[string]]::new()
    foreach ($case in @($CaseSpecs | Sort-Object code, id)) {
        $documentSteps = @($case.evidence | Where-Object kind -eq 'document')
        if ($documentSteps.Count -eq 0) { continue }
        $binding = @($Bindings.settlements | Where-Object {
            [string]$_.region -eq [string]$case.constraints.region -and
            [string]$_.settlement -eq [string]$case.constraints.settlement
        })[0]
        foreach ($step in $documentSteps) {
            $id = [string]$binding.roles.document.documentGuid
            $name = [string]$step.item.name
            if ($knownIds.Contains($id)) {
                if ([string]$knownIds[$id] -ne $name) {
                    throw "Document GUID collision: $id"
                }
                continue
            }
            if ($knownNames.Contains($name)) {
                throw "Document item name collision: $name"
            }
            $knownIds[$id] = $name
            $knownNames[$name] = $id
            $idXml = ConvertTo-DpXmlText $id
            $nameXml = ConvertTo-DpXmlText $name
            $nameKeyXml = ConvertTo-DpXmlText ([string]$step.item.nameKey)
            $infoKeyXml = ConvertTo-DpXmlText ([string]$step.item.infoKey)
            $contentKeyXml = ConvertTo-DpXmlText ([string]$step.item.contentKey)
            $isQuestItem = (
                [string]$step.item.classification -eq 'quest'
            ).ToString().ToLowerInvariant()
            $additions.Add(@"
        <Document Type="5" IconId="letter_simple" UIInfo="$infoKeyXml" UIName="$nameKeyXml" PickpocketInPouch="true" IsQuestItem="$isQuestItem" Model="characters/assets/parchment_folded/parchment_folded.cdf" EntityScript="Book" Weight="0" Price="0" FadeCoef="1.333333" VisibilityCoef="1" Id="$idXml" Name="$nameXml">
            <DocumentContent Parts="$contentKeyXml" />
        </Document>
"@.TrimEnd())
        }
    }
    $compiledVariants = if ($null -eq $CompiledDefinitions) {
        @()
    }
    else { @($CompiledDefinitions.variants) }
    foreach ($variant in @($compiledVariants | Sort-Object variantId)) {
        $trophy = ConvertTo-DpNativeTrophyDefinition -Variant $variant
        if ($null -eq $trophy) { continue }
        $id = [string]$trophy.item_guid
        $name = [string]$trophy.item_name
        if ($knownIds.Contains($id)) {
            if ([string]$knownIds[$id] -ne $name) {
                throw "Trophy GUID collision: $id"
            }
            continue
        }
        if ($knownNames.Contains($name)) {
            throw "Trophy item name collision: $name"
        }
        $knownIds[$id] = $name
        $knownNames[$name] = $id
        $asset = $trophy.asset
        $idXml = ConvertTo-DpXmlText $id
        $nameXml = ConvertTo-DpXmlText $name
        $nameKeyXml = ConvertTo-DpXmlText ([string]$trophy.name_key)
        $infoKeyXml = ConvertTo-DpXmlText ([string]$trophy.info_key)
        $iconXml = ConvertTo-DpXmlText ([string]$asset.icon_id)
        $modelXml = ConvertTo-DpXmlText ([string]$asset.model)
        $isDivisible = ([string]$asset.is_divisible).ToLowerInvariant()
        $isQuestItem = ([string]$asset.is_quest_item).ToLowerInvariant()
        $additions.Add(@"
        <MiscItem Type="$($asset.type)" SubType="$($asset.sub_type)" IconId="$iconXml" UIInfo="$infoKeyXml" UIName="$nameKeyXml" DisplayInShop="false" IsDivisible="$isDivisible" IsQuestItem="$isQuestItem" Model="$modelXml" Weight="$($asset.weight)" Price="$($asset.price)" FadeCoef="$($asset.fade_coef)" VisibilityCoef="$($asset.visibility_coef)" Id="$idXml" Name="$nameXml" />
"@.TrimEnd())
    }
    if ($additions.Count -eq 0) { return $BaseXml }
    $marker = "`t</ItemClasses>"
    $index = $BaseXml.LastIndexOf($marker)
    if ($index -lt 0) { throw 'Item table has no ItemClasses terminator.' }
    return $BaseXml.Insert($index, ($additions -join "`n") + "`n")
}

function ConvertTo-DpDialogueXml {
    param(
        [Parameter(Mandatory)]$Dialogue,
        [Parameter(Mandatory)]$Binding,
        [object[]]$Variants = @()
    )

    $compiledVariants = @($Variants)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('<?xml version="1.0" encoding="utf-8"?>')
    $lines.Add('<Database xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" Name="brambora">')
    $lines.Add('  <Skald>')
    $lines.Add("    <FaderDialog Name=`"$($Dialogue.graphName)`">")
    $lines.Add('      <Ports>')
    $lines.Add('        <Port Name="available" Direction="In" Type="bool">')
    $lines.Add(
        "          <DesignName Text=`"$(ConvertTo-DpXmlText $Dialogue.availableLabel)`" />"
    )
    $lines.Add('        </Port>')
    foreach ($variant in $compiledVariants) {
        $lines.Add(
            "        <Port Name=`"$($variant.port_name)`" Direction=`"In`" Type=`"bool`">"
        )
        $lines.Add(
            "          <DesignName Text=`"$($Dialogue.availableLabel): $($variant.id)`" />"
        )
        $lines.Add('        </Port>')
    }
    $lines.Add('        <Port Name="heard" Direction="Out" Type="trigger">')
    $lines.Add(
        "          <DesignName Text=`"$(ConvertTo-DpXmlText $Dialogue.heardLabel)`" />"
    )
    $lines.Add('        </Port>')
    $lines.Add('      </Ports>')
    $lines.Add("      <Text StringName=`"$($Dialogue.rootKey)`" />")
    $lines.Add('      <Dialogue TechnicalStatus="Enabled" AllowFarewell="false" AllowGreeting="false">')
    $lines.Add("        <Decision Name=`"$($Dialogue.kind)_root`" Priority=`"General`">")
    $lines.Add('          <Sequences>')
    $sequences = if ($compiledVariants.Count -gt 0) {
        $compiledVariants
    }
    else {
        @([ordered]@{
            port_name = $null
            sequence_name = [string]$Dialogue.sequenceName
            prompt_key = [string]$Dialogue.promptKey
            responses = @($Dialogue.responses)
        })
    }
    foreach ($sequence in $sequences) {
        $entryCondition = if (Test-DpTextValue $sequence.port_name) {
            "Port('available') AND Port('$($sequence.port_name)')"
        }
        else { "Port('available')" }
        $lines.Add(
            "            <Sequence EndType=`"EndDialogue`" EntryCondition=`"$entryCondition`" Name=`"$($sequence.sequence_name)`">"
        )
        $lines.Add("              <UiPrompt StringName=`"$($sequence.prompt_key)`" />")
        $lines.Add('              <Triggers>')
        $lines.Add('                <Port Name="heard" />')
        $lines.Add('              </Triggers>')
        $lines.Add('              <Elements>')
        foreach ($response in @($sequence.responses)) {
            $role = [string]$response.role
            if ($role -ne 'HENRY') {
                $roleBinding = $Binding.roles.PSObject.Properties[$role]
                if ($null -eq $roleBinding) {
                    throw "Dialogue '$($Dialogue.graphName)' uses unbound role '$role'."
                }
                $role = [string]$roleBinding.Value.dialogueRole
            }
            $lines.Add("                <Response Role=`"$role`">")
            $lines.Add("                  <Text StringName=`"$($response.key)`" />")
            $lines.Add('                  <Commands><CameraCommand CameraType="CloseUp" /></Commands>')
            $lines.Add('                </Response>')
        }
        $lines.Add('              </Elements>')
        $lines.Add('            </Sequence>')
    }
    $lines.Add('          </Sequences>')
    $lines.Add('        </Decision>')
    $lines.Add('      </Dialogue>')
    $lines.Add('    </FaderDialog>')
    $lines.Add('  </Skald>')
    $lines.Add('</Database>')
    return ($lines -join "`n") + "`n"
}

function ConvertTo-DpOverheardDialogueXml {
    param(
        [Parameter(Mandatory)]$Overheard,
        [Parameter(Mandatory)]$Binding
    )

    $roleMap = @{}
    foreach ($pair in @($Binding.roles.overheard.pairs)) {
        foreach ($speaker in @($pair.speakers)) {
            $semanticRole = [string]$speaker.role
            $dialogueRole = [string]$speaker.dialogueRole
            if ($roleMap.ContainsKey($semanticRole) -and
                [string]$roleMap[$semanticRole] -ne $dialogueRole) {
                throw "Overheard role '$semanticRole' maps to multiple dialogue roles."
            }
            $roleMap[$semanticRole] = $dialogueRole
        }
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('<?xml version="1.0" encoding="utf-8"?>')
    $lines.Add('<Database xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" Name="brambora">')
    $lines.Add('  <Skald>')
    $lines.Add("    <Dialog Name=`"$($Overheard.graph_name)`">")
    $lines.Add('      <Ports>')
    $lines.Add(
        "        <Port Name=`"$($Overheard.clue_port)`" Direction=`"Out`" Type=`"trigger`">"
    )
    $clueLabel = ConvertTo-DpXmlText $Overheard.clue_label
    $lines.Add("          <DesignName Text=`"$clueLabel`" />")
    $lines.Add('        </Port>')
    $lines.Add('      </Ports>')
    $lines.Add("      <Text StringName=`"$($Overheard.root_key)`" />")
    $lines.Add('      <Dialogue Type="ingame" TechnicalStatus="Enabled" Initiator="NonPlayer">')
    $lines.Add(
        "        <Decision Name=`"overheard_root`" Priority=`"General`" Alias=`"$($Overheard.decision_alias)`">"
    )
    $lines.Add('          <Sequences>')
    $lines.Add(
        "            <Sequence EndType=`"EndDialogue`" Name=`"$($Overheard.sequence_name)`">"
    )
    $lines.Add('              <Triggers>')
    $lines.Add("                <Port Name=`"$($Overheard.clue_port)`" />")
    $lines.Add('              </Triggers>')
    $lines.Add('              <Elements>')
    foreach ($response in @($Overheard.responses)) {
        $semanticRole = [string]$response.role
        if (-not $roleMap.ContainsKey($semanticRole)) {
            throw "Overheard dialogue uses unbound role '$semanticRole'."
        }
        $dialogueRole = [string]$roleMap[$semanticRole]
        $lines.Add("                <Response Role=`"$dialogueRole`">")
        $lines.Add("                  <Text StringName=`"$($response.key)`" />")
        $lines.Add('                </Response>')
    }
    $lines.Add('              </Elements>')
    $lines.Add('            </Sequence>')
    $lines.Add('          </Sequences>')
    $lines.Add('        </Decision>')
    $lines.Add('      </Dialogue>')
    $lines.Add('    </Dialog>')
    $lines.Add('  </Skald>')
    $lines.Add('</Database>')
    return ($lines -join "`n") + "`n"
}

function ConvertTo-DpNativeRegionWiring {
    param(
        [Parameter(Mandatory)]$CaseSpec,
        [Parameter(Mandatory)]$Binding
    )

    $native = $CaseSpec.native
    $rumor = @($native.dialogues | Where-Object kind -eq 'rumor')
    $witness = @($native.dialogues | Where-Object kind -eq 'witness')
    if ($rumor.Count -ne 1 -or $witness.Count -ne 1) {
        throw "Case '$($CaseSpec.id)' requires one rumor and one witness dialogue."
    }
    $rumor = $rumor[0]
    $witness = $witness[0]
    $overheard = Get-DpOverheardDefinition `
        -CaseSpec $CaseSpec `
        -Binding $Binding
    $folder = [string]$native.dialogFolder
    $rumorTag = [int]$native.signals.rumorAvailableTag
    $witnessTag = [int]$native.signals.witnessAvailableTag
    $rumorContext = [string]$native.contexts.rumorHeard
    $witnessContext = [string]$native.contexts.witnessHeard
    $objective = $native.witnessObjective
    $objectiveAssetName = [string]$objective.assetName
    $dialogueVariants = @(Get-DpDialogueVariants -CaseSpec $CaseSpec)
    $rumorVariants = @($dialogueVariants | Where-Object {
        [string]$_.dialogue_name -eq [string]$rumor.graphName
    })
    $journalStates = @(Get-DpJournalStates -CaseSpec $CaseSpec)
    $evidenceStateNodes = [System.Collections.Generic.List[string]]::new()
    $evidenceStateEdges = [System.Collections.Generic.List[string]]::new()
    $evidenceTypeEnums = [System.Collections.Generic.List[string]]::new()
    $evidenceLogs = [System.Collections.Generic.List[string]]::new()
    foreach ($journalState in $journalStates) {
        $stateCode = [int]$journalState.code
        $stateName = [string]$journalState.state_name
        $signalTag = [int]$journalState.signal_tag
        $evidenceStateNodes.Add(
            "        <MakeArray Name=`"leadStateTags$stateCode`" TypeT=`"wh::rpgmodule::BuffDefinitionAITags`">"
        )
        $evidenceStateNodes.Add(
            "          <Constant Name=`"A`" Value=`"$signalTag`" />"
        )
        $evidenceStateNodes.Add('        </MakeArray>')
        $evidenceStateNodes.Add(
            "        <BuffTagTrigger Name=`"leadStateTrigger$stateCode`">"
        )
        $evidenceStateNodes.Add('          <Asset Name="Souls" Alias="player" />')
        $evidenceStateNodes.Add(
            "          <Edge From=`"leadStateTags$stateCode.Array`" To=`"BuffTags`" />"
        )
        $evidenceStateNodes.Add('          <Edge From="questProgress.Active" To="IsActive" />')
        $evidenceStateNodes.Add('        </BuffTagTrigger>')
        $evidenceStateEdges.Add(
            "          <Edge From=`"leadStateTrigger$stateCode.OnAdded`" To=`"Set$stateName`" />"
        )
        $objectiveValueType = if ($stateCode -eq 0) { 'None' } else { 'Started' }
        $evidenceTypeEnums.Add(
            "          <StateTypeEnumeration Name=`"$stateName`" ObjectiveValueType=`"$objectiveValueType`" />"
        )
        if ($stateCode -eq 0) {
            $evidenceLogs.Add(
                "            <EnumLog Type=`"None`" Name=`"$stateName`" />"
            )
            continue
        }
        $englishParts = @($journalState.direction_keys | ForEach-Object {
            $property = $CaseSpec.localization.en.PSObject.Properties[
                [string]$_
            ]
            [string]$property.Value
        })
        $fallbackText = ConvertTo-DpXmlText ($englishParts -join ' ')
        $localizationKey = [string]$journalState.localization_key
        $evidenceLogs.Add(
            "            <EnumLog Type=`"Started`" Name=`"$stateName`" IsTracked=`"true`">"
        )
        $evidenceLogs.Add(
            "              <Log StringName=`"$localizationKey`" Text=`"$fallbackText`">"
        )
        $evidenceLogs.Add(
            "                <Localization Text=`"$fallbackText`" Language=`"WHS`" />"
        )
        $evidenceLogs.Add('              </Log>')
        $evidenceLogs.Add('            </EnumLog>')
    }

    $rumorVariantNodes = [System.Collections.Generic.List[string]]::new()
    $rumorVariantPortEdges = [System.Collections.Generic.List[string]]::new()
    foreach ($variant in $rumorVariants) {
        $slot = [int]$variant.signal_tag - 69
        $rumorVariantNodes.Add(
            "        <MakeArray Name=`"rumorVariant${slot}Tags`" TypeT=`"wh::rpgmodule::BuffDefinitionAITags`">"
        )
        $rumorVariantNodes.Add(
            "          <Constant Name=`"A`" Value=`"$($variant.signal_tag)`" />"
        )
        $rumorVariantNodes.Add('        </MakeArray>')
        $rumorVariantNodes.Add(
            "        <BuffTagTrigger Name=`"rumorVariant${slot}Trigger`">"
        )
        $rumorVariantNodes.Add('          <Asset Name="Souls" Alias="player" />')
        $rumorVariantNodes.Add(
            "          <Edge From=`"rumorVariant${slot}Tags.Array`" To=`"BuffTags`" />"
        )
        $rumorVariantNodes.Add('          <Edge From="questProgress.Active" To="IsActive" />')
        $rumorVariantNodes.Add('        </BuffTagTrigger>')
        $rumorVariantNodes.Add(
            "        <State Name=`"rumorVariant${slot}Active`" TypeT=`"bool`">"
        )
        $rumorVariantNodes.Add(
            "          <Edge From=`"rumorVariant${slot}Trigger.OnAdded`" To=`"SetTrue`" />"
        )
        $rumorVariantNodes.Add(
            "          <Edge From=`"rumorVariant${slot}Trigger.OnRemoved`" To=`"SetFalse`" />"
        )
        $rumorVariantNodes.Add('        </State>')
        $rumorVariantPortEdges.Add(
            "          <Edge From=`"rumorVariant${slot}Active.State`" To=`"$($variant.port_name)`" />"
        )
    }
    $rumorVariantNodeXml = $rumorVariantNodes -join "`n"
    $rumorVariantPortEdgeXml = $rumorVariantPortEdges -join "`n"

    $overheardDefinition = if ($null -ne $overheard) {
        "        <Definition File=`"$folder/$($overheard.file_name)`" />"
    }
    else { '' }
    $definitions = @"
      <Definitions>
        <Definition File="$folder/$($rumor.fileName)" />
        <Definition File="$folder/$($witness.fileName)" />
$overheardDefinition
      </Definitions>
"@
    $rumorNodes = @"
        <MakeArray Name="rumorAvailableTags" TypeT="wh::rpgmodule::BuffDefinitionAITags">
          <Constant Name="A" Value="$rumorTag" />
        </MakeArray>
        <BuffTagTrigger Name="rumorAvailableTrigger">
          <Asset Name="Souls" Alias="player" />
          <Edge From="rumorAvailableTags.Array" To="BuffTags" />
          <Edge From="questProgress.Active" To="IsActive" />
        </BuffTagTrigger>
        <State Name="rumorDialogueAvailable" TypeT="bool">
          <Edge From="rumorAvailableTrigger.OnAdded" To="SetTrue" />
          <Edge From="rumorAvailableTrigger.OnRemoved" To="SetFalse" />
          <Edge From="firstLeadTrigger.OnAdded" To="SetFalse" />
          <Edge From="satisfactionTrigger.OnAdded" To="SetFalse" />
          <Edge From="cleanResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="controlledResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="noisyResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="externalResultTrigger.OnAdded" To="SetFalse" />
        </State>
$rumorVariantNodeXml
        <$($rumor.graphName) Name="innkeeperRumorDialog">
          <Edge From="rumorDialogueAvailable.State" To="available" />
$rumorVariantPortEdgeXml
        </$($rumor.graphName)>
        <State Name="rumorDialogueRequestActive" TypeT="bool">
          <Edge From="questProgress.OnActive" To="SetFalse" />
          <Edge From="innkeeperRumorDialog.heard" To="SetTrue" />
          <Edge From="firstLeadTrigger.OnAdded" To="SetFalse" />
          <Edge From="satisfactionTrigger.OnAdded" To="SetFalse" />
          <Edge From="cleanResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="controlledResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="noisyResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="externalResultTrigger.OnAdded" To="SetFalse" />
        </State>
        <SetEntityContext Name="rumorDialogueRequest">
          <Constant Name="Context" Value="$rumorContext" />
          <Asset Name="Souls" Alias="player" />
          <Edge From="rumorDialogueRequestActive.State" To="IsActive" />
        </SetEntityContext>
"@
    $witnessNodes = @"
        <MakeArray Name="witnessAvailableTags" TypeT="wh::rpgmodule::BuffDefinitionAITags">
          <Constant Name="A" Value="$witnessTag" />
        </MakeArray>
        <BuffTagTrigger Name="witnessAvailableTrigger">
          <Asset Name="Souls" Alias="player" />
          <Edge From="witnessAvailableTags.Array" To="BuffTags" />
          <Edge From="questProgress.Active" To="IsActive" />
        </BuffTagTrigger>
        <State Name="witnessDialogueAvailable" TypeT="bool">
          <Edge From="witnessAvailableTrigger.OnAdded" To="SetTrue" />
          <Edge From="witnessAvailableTrigger.OnRemoved" To="SetFalse" />
          <Edge From="revealTagTrigger.OnAdded" To="SetFalse" />
          <Edge From="satisfactionTrigger.OnAdded" To="SetFalse" />
          <Edge From="cleanResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="controlledResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="noisyResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="externalResultTrigger.OnAdded" To="SetFalse" />
        </State>
        <$($witness.graphName) Name="tavernWitnessDialog">
          <Edge From="witnessDialogueAvailable.State" To="available" />
        </$($witness.graphName)>
        <State Name="witnessDialogueRequestActive" TypeT="bool">
          <Edge From="questProgress.OnActive" To="SetFalse" />
          <Edge From="tavernWitnessDialog.heard" To="SetTrue" />
          <Edge From="revealTagTrigger.OnAdded" To="SetFalse" />
          <Edge From="satisfactionTrigger.OnAdded" To="SetFalse" />
          <Edge From="cleanResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="controlledResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="noisyResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="externalResultTrigger.OnAdded" To="SetFalse" />
        </State>
        <SetEntityContext Name="witnessDialogueRequest">
          <Constant Name="Context" Value="$witnessContext" />
          <Asset Name="Souls" Alias="player" />
          <Edge From="witnessDialogueRequestActive.State" To="IsActive" />
        </SetEntityContext>
"@
    $overheardNodes = ''
    $overheardAssets = ''
    $overheardDialogue = $null
    if ($null -ne $overheard) {
        $nodeLines = [System.Collections.Generic.List[string]]::new()
        $assetLines = [System.Collections.Generic.List[string]]::new()
        $nodeLines.Add('        <MakeArray Name="overheardAvailableTags" TypeT="wh::rpgmodule::BuffDefinitionAITags">')
        $nodeLines.Add(
            "          <Constant Name=`"A`" Value=`"$($overheard.available_tag)`" />"
        )
        $nodeLines.Add('        </MakeArray>')
        for ($pairIndex = 0; $pairIndex -lt $overheard.pairs.Count; $pairIndex++) {
            $pair = $overheard.pairs[$pairIndex]
            $speakers = @($pair.speakers)
            $pairName = if ($pairIndex -eq 0) { 'Primary' } else { 'Fallback' }
            $pairNode = "overheard${pairName}Speakers"
            $triggerNode = "overheard${pairName}AvailableTrigger"
            $stateNode = "overheard${pairName}Available"
            $switchNode = "overheardSwitch$pairName"
            $nodeLines.Add(
                "        <MakeArray Name=`"$pairNode`" TypeT=`"wh::rpgmodule::Souls`">"
            )
            for ($speakerIndex = 0; $speakerIndex -lt $speakers.Count; $speakerIndex++) {
                $letter = [char]([int][char]'A' + $speakerIndex)
                $nodeLines.Add(
                    "          <Asset Name=`"$letter`" Alias=`"$($speakers[$speakerIndex].questAlias)`" />"
                )
                $assetLines.Add(
                    "        <SoulAsset Name=`"$($speakers[$speakerIndex].questAlias)`" SharedSoulGuids=`"$($speakers[$speakerIndex].soulGuid)`" />"
                )
            }
            $nodeLines.Add('        </MakeArray>')
            $nodeLines.Add("        <BuffTagTrigger Name=`"$triggerNode`">")
            $nodeLines.Add(
                "          <Asset Name=`"Souls`" Alias=`"$($speakers[0].questAlias)`" />"
            )
            $nodeLines.Add('          <Edge From="overheardAvailableTags.Array" To="BuffTags" />')
            $nodeLines.Add('          <Edge From="questProgress.Active" To="IsActive" />')
            $nodeLines.Add('        </BuffTagTrigger>')
            $nodeLines.Add("        <State Name=`"$stateNode`" TypeT=`"bool`">")
            $nodeLines.Add(
                "          <Edge From=`"$triggerNode.OnAdded`" To=`"SetTrue`" />"
            )
            $nodeLines.Add(
                "          <Edge From=`"$triggerNode.OnRemoved`" To=`"SetFalse`" />"
            )
            foreach ($resultTrigger in @(
                'satisfactionTrigger',
                'cleanResultTrigger',
                'controlledResultTrigger',
                'noisyResultTrigger',
                'externalResultTrigger'
            )) {
                $nodeLines.Add(
                    "          <Edge From=`"$resultTrigger.OnAdded`" To=`"SetFalse`" />"
                )
            }
            $nodeLines.Add('        </State>')
            $nodeLines.Add(
                "        <switchdialog Name=`"$switchNode`" Namespace=`"utils.speech`">"
            )
            $nodeLines.Add(
                "          <Asset Name=`"linksource`" Alias=`"$($speakers[0].questAlias)`" />"
            )
            $nodeLines.Add(
                "          <Constant Name=`"alias`" Value=`"$($overheard.decision_alias)`" />"
            )
            $nodeLines.Add('          <Constant Name="dialogtype" Value="Ingame" />')
            $nodeLines.Add(
                "          <Constant Name=`"repeatafterseconds`" Value=`"$($overheard.repeat_after_seconds)`" />"
            )
            $nodeLines.Add('          <Constant Name="repeataftersecondsvariation" Value="0" />')
            $nodeLines.Add('          <Constant Name="playdialoganimations" Value="false" />')
            $nodeLines.Add('          <Constant Name="maxscheduledpriority" Value="52" />')
            $nodeLines.Add('          <Constant Name="context" Value="-" />')
            $nodeLines.Add('          <Constant Name="perceivingplayer" Value="false" />')
            $nodeLines.Add(
                "          <Constant Name=`"playerdistance`" Value=`"$($overheard.hearing_distance)`" />"
            )
            $nodeLines.Add('          <Constant Name="continuosinitiatorchecks" Value="false" />')
            $nodeLines.Add('          <Constant Name="lookatenabled" Value="false" />')
            $nodeLines.Add('          <Asset Name="lookattarget" Alias="player" />')
            $nodeLines.Add('          <Constant Name="boostperceptionpriority" Value="false" />')
            $nodeLines.Add('          <Constant Name="perceptiondebuff" Value="false" />')
            $nodeLines.Add('          <Constant Name="subtitlesdown" Value="false" />')
            $nodeLines.Add("          <Edge From=`"$pairNode.Array`" To=`"souls`" />")
            $nodeLines.Add("          <Edge From=`"$stateNode.State`" To=`"active`" />")
            $nodeLines.Add('        </switchdialog>')
        }
        $nodeLines.Add(
            "        <$($overheard.graph_name) Name=`"overheardEvidenceDialog`" />"
        )
        $nodeLines.Add('        <State Name="overheardClueRequestActive" TypeT="bool">')
        $nodeLines.Add(
            "          <Edge From=`"overheardEvidenceDialog.$($overheard.clue_port)`" To=`"SetTrue`" />"
        )
        $nodeLines.Add('          <Edge From="overheardCluePulse.OnFinished" To="SetFalse" />')
        $nodeLines.Add('          <Edge From="questProgress.OnActive" To="SetFalse" />')
        $nodeLines.Add('        </State>')
        $nodeLines.Add('        <Timer Name="overheardCluePulse">')
        $nodeLines.Add('          <Constant Name="Duration" Value="3s" />')
        $nodeLines.Add('          <Constant Name="TimeType" Value="GameTime" />')
        $nodeLines.Add(
            "          <Edge From=`"overheardEvidenceDialog.$($overheard.clue_port)`" To=`"SetRunning`" />"
        )
        $nodeLines.Add('        </Timer>')
        $nodeLines.Add('        <SetEntityContext Name="overheardClueRequest">')
        $nodeLines.Add(
            "          <Constant Name=`"Context`" Value=`"$($overheard.context)`" />"
        )
        $nodeLines.Add('          <Asset Name="Souls" Alias="player" />')
        $nodeLines.Add('          <Edge From="overheardClueRequestActive.State" To="IsActive" />')
        $nodeLines.Add('        </SetEntityContext>')
        $overheardNodes = $nodeLines -join "`n"
        $overheardAssets = $assetLines -join "`n"
        $overheardDialogue = [ordered]@{
            fileName = [string]$overheard.file_name
            xml = ConvertTo-DpOverheardDialogueXml `
                -Overheard $overheard `
                -Binding $Binding
        }
    }
    $witnessObjectiveNodes = @"
        <State Name="witnessObjectiveProgress" TypeT="DP_WitnessProgress">
          <Edge From="satisfactionTrigger.OnRemoved" To="SetNone" />
          <Edge From="questProgress.OnActive" To="SetNone" />
          <Edge From="witnessAvailableTrigger.OnAdded" To="SetActive" />
          <Edge From="revealTagTrigger.OnAdded" To="SetDone" />
        </State>
        <$objectiveAssetName Name="witnessVisual">
          <Edge From="witnessObjectiveProgress.State" To="Progress" />
        </$objectiveAssetName>
"@
    $witnessType = @"
        <Type TypeName="DP_WitnessProgress">
          <StateTypeEnumeration Name="None" ObjectiveValueType="None" />
          <StateTypeEnumeration Name="Active" ObjectiveValueType="Started" />
          <StateTypeEnumeration Name="Done" ObjectiveValueType="Completed" />
        </Type>
"@
    $fallbackName = ConvertTo-DpXmlText $objective.fallbackName
    $fallbackActive = ConvertTo-DpXmlText $objective.fallbackActive
    $fallbackDone = ConvertTo-DpXmlText $objective.fallbackDone
    $witnessObjective = @"
        <Objective TypeT="DP_WitnessProgress" Name="$objectiveAssetName">
          <LocalizedName StringName="$($objective.nameKey)" Text="$fallbackName">
            <Localization Text="$fallbackName" Language="WHS" />
          </LocalizedName>
          <Logs>
            <EnumLog Type="None" Name="None" />
            <EnumLog Type="Started" Name="Active" IsTracked="true">
              <Log StringName="$($objective.activeKey)" Text="$fallbackActive">
                <Localization Text="$fallbackActive" Language="WHS" />
              </Log>
            </EnumLog>
            <EnumLog Type="Completed" Name="Done">
              <Log StringName="$($objective.doneKey)" Text="$fallbackDone">
                <Localization Text="$fallbackDone" Language="WHS" />
              </Log>
            </EnumLog>
          </Logs>
        </Objective>
"@

    return [ordered]@{
        caseId = [string]$CaseSpec.id
        region = [string]$CaseSpec.constraints.region
        settlement = [string]$CaseSpec.constraints.settlement
        questName = [string]$native.questName
        dialogFolder = $folder
        dialogDefinitions = $definitions.TrimEnd()
        rumorNodes = $rumorNodes.TrimEnd()
        witnessNodes = $witnessNodes.TrimEnd()
        overheardNodes = $overheardNodes.TrimEnd()
        overheardAssets = $overheardAssets.TrimEnd()
        evidenceStateNodes = $evidenceStateNodes -join "`n"
        evidenceStateEdges = $evidenceStateEdges -join "`n"
        evidenceType = $evidenceTypeEnums -join "`n"
        evidenceLogs = $evidenceLogs -join "`n"
        journalStates = $journalStates
        evidenceWitnessEdge = ''
        witnessObjectiveNodes = ''
        witnessType = ''
        witnessObjective = ''
        dialogues = @($native.dialogues | ForEach-Object {
            $graphName = [string]$_.graphName
            $variants = @($dialogueVariants | Where-Object {
                [string]$_.dialogue_name -eq $graphName
            })
            [ordered]@{
                fileName = [string]$_.fileName
                xml = ConvertTo-DpDialogueXml `
                    -Dialogue $_ `
                    -Binding $Binding `
                    -Variants $variants
            }
        }) + @($overheardDialogue | Where-Object { $null -ne $_ })
    }
}

function Get-DpLeadSignalStates {
    param([Parameter(Mandatory)][object[]]$CaseSpecs)

    $largest = @()
    foreach ($case in $CaseSpecs) {
        $states = @(Get-DpJournalStates -CaseSpec $case)
        if ($states.Count -gt $largest.Count) { $largest = $states }
    }
    return $largest
}

function ConvertTo-DpLeadStateTagXml {
    param(
        [Parameter(Mandatory)][string]$BaseXml,
        [Parameter(Mandatory)][object[]]$CaseSpecs
    )

    $additions = [System.Collections.Generic.List[string]]::new()
    foreach ($state in @(Get-DpLeadSignalStates -CaseSpecs $CaseSpecs)) {
        $tag = [int]$state.signal_tag
        $name = "dp_lead_state_$([int]$state.code)"
        $idMatch = [regex]::Match(
            $BaseXml,
            "<buff_ai_tag\s+[^>]*buff_ai_tag_id=`"$tag`"[^>]*/>"
        )
        if ($idMatch.Success) {
            if (-not $idMatch.Value.Contains(
                "buff_ai_tag_name=`"$name`""
            )) {
                throw "Lead-state buff tag id $tag collides with another tag."
            }
            continue
        }
        if ($BaseXml.Contains("buff_ai_tag_name=`"$name`"")) {
            throw "Lead-state buff tag name '$name' has another id."
        }
        $additions.Add(
            "`t`t<buff_ai_tag buff_ai_tag_id=`"$tag`" " +
            "buff_ai_tag_name=`"$name`" />"
        )
    }
    if ($additions.Count -eq 0) { return $BaseXml }
    $marker = "`t</buff_ai_tags>"
    $index = $BaseXml.LastIndexOf($marker)
    if ($index -lt 0) { throw 'Buff tag table has no closing collection.' }
    return $BaseXml.Insert($index, ($additions -join "`n") + "`n")
}

function ConvertTo-DpLeadStateBuffXml {
    param(
        [Parameter(Mandatory)][string]$BaseXml,
        [Parameter(Mandatory)][object[]]$CaseSpecs
    )

    $additions = [System.Collections.Generic.List[string]]::new()
    foreach ($state in @(Get-DpLeadSignalStates -CaseSpecs $CaseSpecs)) {
        $code = [int]$state.code
        $tag = [int]$state.signal_tag
        $guid = [string]$state.buff_guid
        $name = "dp_lead_state_$code"
        $guidMatch = [regex]::Match(
            $BaseXml,
            "<buff\s+[^>]*buff_id=`"$([regex]::Escape($guid))`"[^>]*/>"
        )
        if ($guidMatch.Success) {
            if (-not $guidMatch.Value.Contains("buff_name=`"$name`"") -or
                -not $guidMatch.Value.Contains("buff_ai_tag_id=`"$tag`"")) {
                throw "Lead-state buff guid $guid collides with another buff."
            }
            continue
        }
        if ($BaseXml.Contains("buff_name=`"$name`"")) {
            throw "Lead-state buff name '$name' has another guid."
        }
        $additions.Add(
            "`t`t<buff buff_ai_tag_id=`"$tag`" buff_class_id=`"1`" " +
            "buff_exclusivity_id=`"0`" buff_id=`"$guid`" " +
            "buff_lifetime_id=`"0`" buff_name=`"$name`" " +
            "buff_ui_visibility_id=`"0`" duration=`"-1`" icon_id=`"0`" " +
            "implementation=`"Cpp:Constant`" is_persistent=`"true`" />"
        )
    }
    if ($additions.Count -eq 0) { return $BaseXml }
    $marker = "`t</buffs>"
    $index = $BaseXml.LastIndexOf($marker)
    if ($index -lt 0) { throw 'Buff table has no closing collection.' }
    return $BaseXml.Insert($index, ($additions -join "`n") + "`n")
}

function Get-DpDialogueVariantSignalStates {
    param([Parameter(Mandatory)][object[]]$CaseSpecs)

    $largest = @()
    foreach ($case in $CaseSpecs) {
        $variants = @(Get-DpDialogueVariants -CaseSpec $case)
        if ($variants.Count -gt $largest.Count) { $largest = $variants }
    }
    return $largest
}

function ConvertTo-DpDialogueVariantTagXml {
    param(
        [Parameter(Mandatory)][string]$BaseXml,
        [Parameter(Mandatory)][object[]]$CaseSpecs
    )

    $additions = [System.Collections.Generic.List[string]]::new()
    foreach ($variant in @(
        Get-DpDialogueVariantSignalStates -CaseSpecs $CaseSpecs
    )) {
        $slot = [int]$variant.signal_tag - 69
        $tag = [int]$variant.signal_tag
        $name = "dp_dialogue_variant_$slot"
        $idMatch = [regex]::Match(
            $BaseXml,
            "<buff_ai_tag\s+[^>]*buff_ai_tag_id=`"$tag`"[^>]*/>"
        )
        if ($idMatch.Success) {
            if (-not $idMatch.Value.Contains(
                "buff_ai_tag_name=`"$name`""
            )) {
                throw "Dialogue-variant buff tag id $tag collides."
            }
            continue
        }
        if ($BaseXml.Contains("buff_ai_tag_name=`"$name`"")) {
            throw "Dialogue-variant buff tag name '$name' has another id."
        }
        $additions.Add(
            "`t`t<buff_ai_tag buff_ai_tag_id=`"$tag`" " +
            "buff_ai_tag_name=`"$name`" />"
        )
    }
    if ($additions.Count -eq 0) { return $BaseXml }
    $marker = "`t</buff_ai_tags>"
    $index = $BaseXml.LastIndexOf($marker)
    if ($index -lt 0) { throw 'Buff tag table has no closing collection.' }
    return $BaseXml.Insert($index, ($additions -join "`n") + "`n")
}

function ConvertTo-DpDialogueVariantBuffXml {
    param(
        [Parameter(Mandatory)][string]$BaseXml,
        [Parameter(Mandatory)][object[]]$CaseSpecs
    )

    $additions = [System.Collections.Generic.List[string]]::new()
    foreach ($variant in @(
        Get-DpDialogueVariantSignalStates -CaseSpecs $CaseSpecs
    )) {
        $slot = [int]$variant.signal_tag - 69
        $tag = [int]$variant.signal_tag
        $guid = [string]$variant.buff_guid
        $name = "dp_dialogue_variant_$slot"
        $guidMatch = [regex]::Match(
            $BaseXml,
            "<buff\s+[^>]*buff_id=`"$([regex]::Escape($guid))`"[^>]*/>"
        )
        if ($guidMatch.Success) {
            if (-not $guidMatch.Value.Contains("buff_name=`"$name`"") -or
                -not $guidMatch.Value.Contains("buff_ai_tag_id=`"$tag`"")) {
                throw "Dialogue-variant buff guid $guid collides."
            }
            continue
        }
        if ($BaseXml.Contains("buff_name=`"$name`"")) {
            throw "Dialogue-variant buff name '$name' has another guid."
        }
        $additions.Add(
            "`t`t<buff buff_ai_tag_id=`"$tag`" buff_class_id=`"1`" " +
            "buff_exclusivity_id=`"0`" buff_id=`"$guid`" " +
            "buff_lifetime_id=`"0`" buff_name=`"$name`" " +
            "buff_ui_visibility_id=`"0`" duration=`"-1`" icon_id=`"0`" " +
            "implementation=`"Cpp:Constant`" is_persistent=`"true`" />"
        )
    }
    if ($additions.Count -eq 0) { return $BaseXml }
    $marker = "`t</buffs>"
    $index = $BaseXml.LastIndexOf($marker)
    if ($index -lt 0) { throw 'Buff table has no closing collection.' }
    return $BaseXml.Insert($index, ($additions -join "`n") + "`n")
}

function Get-DpOverheardSignal {
    param([Parameter(Mandatory)][object[]]$CaseSpecs)

    $tags = @($CaseSpecs | ForEach-Object {
        $property = $_.native.PSObject.Properties['overheard']
        if ($null -ne $property) { [int]$property.Value.availableTag }
    } | Sort-Object -Unique)
    if ($tags.Count -eq 0) { return $null }
    if ($tags.Count -ne 1) {
        throw 'Overheard canaries must share one availability signal tag.'
    }
    return [ordered]@{
        tag = [int]$tags[0]
        name = 'dp_overheard_available'
        guid = Get-DpStableGuid -Seed 'darkpassenger-overheard-available'
    }
}

function ConvertTo-DpOverheardTagXml {
    param(
        [Parameter(Mandatory)][string]$BaseXml,
        [Parameter(Mandatory)][object[]]$CaseSpecs
    )

    $signal = Get-DpOverheardSignal -CaseSpecs $CaseSpecs
    if ($null -eq $signal) { return $BaseXml }
    $tag = [int]$signal.tag
    $name = [string]$signal.name
    $match = [regex]::Match(
        $BaseXml,
        "<buff_ai_tag\s+[^>]*buff_ai_tag_id=`"$tag`"[^>]*/>"
    )
    if ($match.Success) {
        if (-not $match.Value.Contains("buff_ai_tag_name=`"$name`"")) {
            throw "Overheard buff tag id $tag collides."
        }
        return $BaseXml
    }
    if ($BaseXml.Contains("buff_ai_tag_name=`"$name`"")) {
        throw "Overheard buff tag name '$name' has another id."
    }
    $addition =
        "`t`t<buff_ai_tag buff_ai_tag_id=`"$tag`" " +
        "buff_ai_tag_name=`"$name`" />`n"
    $marker = "`t</buff_ai_tags>"
    $index = $BaseXml.LastIndexOf($marker)
    if ($index -lt 0) { throw 'Buff tag table has no closing collection.' }
    return $BaseXml.Insert($index, $addition)
}

function ConvertTo-DpOverheardBuffXml {
    param(
        [Parameter(Mandatory)][string]$BaseXml,
        [Parameter(Mandatory)][object[]]$CaseSpecs
    )

    $signal = Get-DpOverheardSignal -CaseSpecs $CaseSpecs
    if ($null -eq $signal) { return $BaseXml }
    $tag = [int]$signal.tag
    $name = [string]$signal.name
    $guid = [string]$signal.guid
    $match = [regex]::Match(
        $BaseXml,
        "<buff\s+[^>]*buff_id=`"$([regex]::Escape($guid))`"[^>]*/>"
    )
    if ($match.Success) {
        if (-not $match.Value.Contains("buff_name=`"$name`"") -or
            -not $match.Value.Contains("buff_ai_tag_id=`"$tag`"")) {
            throw "Overheard buff guid $guid collides."
        }
        return $BaseXml
    }
    if ($BaseXml.Contains("buff_name=`"$name`"")) {
        throw "Overheard buff name '$name' has another guid."
    }
    $addition =
        "`t`t<buff buff_ai_tag_id=`"$tag`" buff_class_id=`"1`" " +
        "buff_exclusivity_id=`"0`" buff_id=`"$guid`" " +
        "buff_lifetime_id=`"0`" buff_name=`"$name`" " +
        "buff_ui_visibility_id=`"0`" duration=`"-1`" icon_id=`"0`" " +
        "implementation=`"Cpp:Constant`" is_persistent=`"true`" />`n"
    $marker = "`t</buffs>"
    $index = $BaseXml.LastIndexOf($marker)
    if ($index -lt 0) { throw 'Buff table has no closing collection.' }
    return $BaseXml.Insert($index, $addition)
}

function Get-DpEvidenceStashAlias {
    param(
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$Settlement
    )

    foreach ($value in @($Region, $Settlement)) {
        if ($value -notmatch '^[A-Za-z0-9_]+$') {
            throw "Invalid evidence stash identity '$Region/$Settlement'."
        }
    }
    return "DP_EvidenceStash_${Region}_${Settlement}"
}

function Get-DpQuestItemPlacementSignals {
    param(
        [Parameter(Mandatory)][object[]]$CaseSpecs,
        [Parameter(Mandatory)]$Bindings,
        $CompiledDefinitions
    )

    $itemsByGuid = [ordered]@{}
    foreach ($case in @($CaseSpecs | Sort-Object code, id)) {
        $binding = @($Bindings.settlements | Where-Object {
            [string]$_.region -eq [string]$case.constraints.region -and
            [string]$_.settlement -eq [string]$case.constraints.settlement
        })[0]
        foreach ($evidence in @($case.evidence)) {
            $kindProperty = $evidence.PSObject.Properties['kind']
            $isReadableDocument =
                $null -ne $kindProperty -and
                [string]$kindProperty.Value -eq 'document'
            $itemProperty = $evidence.PSObject.Properties['item']
            if ($null -eq $itemProperty -or
                [string]$itemProperty.Value.classification -ne 'quest') {
                continue
            }
            $item = $itemProperty.Value
            $roleName = if (
                $null -ne $evidence.PSObject.Properties['role']
            ) { [string]$evidence.role } else { '' }
            $roleProperty = if ($null -ne $binding) {
                if ([string]::IsNullOrWhiteSpace($roleName)) {
                    $null
                }
                else {
                    $binding.roles.PSObject.Properties[$roleName]
                }
            }
            else { $null }
            $roleBinding = if ($null -ne $roleProperty) {
                $roleProperty.Value
            }
            else { $null }
            $guid = if ($null -ne $item.PSObject.Properties['guid']) {
                [string]$item.guid
            }
            else { '' }
            if ([string]::IsNullOrWhiteSpace($guid)) {
                foreach ($propertyName in 'itemGuid', 'documentGuid') {
                    if ($null -ne $roleBinding -and
                        $null -ne $roleBinding.PSObject.Properties[$propertyName] -and
                        -not [string]::IsNullOrWhiteSpace(
                            [string]$roleBinding.$propertyName
                        )) {
                        $guid = [string]$roleBinding.$propertyName
                        break
                    }
                }
            }
            if ([string]::IsNullOrWhiteSpace($guid)) {
                throw (
                    "Quest evidence '$([string]$evidence.id)' has no " +
                    'concrete KCD2 item GUID.'
                )
            }
            $stashBinding = $null
            if ($isReadableDocument) {
                $containerGuid = if (
                    $null -ne $roleBinding -and
                    $null -ne $roleBinding.PSObject.Properties['containerGuid']
                ) {
                    [string]$roleBinding.containerGuid
                }
                else { '' }
                if ([string]::IsNullOrWhiteSpace($containerGuid)) {
                    throw (
                        "Quest document '$([string]$evidence.id)' has no " +
                        'concrete KCD2 container GUID.'
                    )
                }
                $region = [string]$case.constraints.region
                $settlement = [string]$case.constraints.settlement
                $stashBinding = [ordered]@{
                    region = $region
                    settlement = $settlement
                    container_guid = $containerGuid
                    stash_alias = Get-DpEvidenceStashAlias `
                        -Region $region `
                        -Settlement $settlement
                }
            }
            $key = $guid.ToLowerInvariant()
            if (-not $itemsByGuid.Contains($key)) {
                $itemsByGuid[$key] = [ordered]@{
                    item_guid = $guid
                    classification = 'quest'
                    retention = [string]$item.retention
                    source = "evidence:$([string]$evidence.id)"
                    is_readable_document = $isReadableDocument
                    stash_bindings =
                        [System.Collections.Generic.List[object]]::new()
                }
            }
            elseif ($isReadableDocument) {
                $itemsByGuid[$key].is_readable_document = $true
            }
            if ($null -ne $stashBinding) {
                $signature =
                    "$($stashBinding.region)|$($stashBinding.settlement)|" +
                    "$($stashBinding.container_guid)"
                $existing = @($itemsByGuid[$key].stash_bindings | Where-Object {
                    "$($_.region)|$($_.settlement)|$($_.container_guid)" -eq
                        $signature
                })
                if ($existing.Count -eq 0) {
                    $itemsByGuid[$key].stash_bindings.Add($stashBinding)
                }
            }
        }
    }

    $variants = if ($null -eq $CompiledDefinitions) {
        @()
    }
    else { @($CompiledDefinitions.variants) }
    foreach ($variant in @($variants | Sort-Object variantId)) {
        $trophy = ConvertTo-DpNativeTrophyDefinition -Variant $variant
        if ($null -eq $trophy -or
            [string]$trophy.item.classification -ne 'quest') {
            continue
        }
        $guid = [string]$trophy.item_guid
        $key = $guid.ToLowerInvariant()
        if (-not $itemsByGuid.Contains($key)) {
            $itemsByGuid[$key] = [ordered]@{
                item_guid = $guid
                classification = 'quest'
                retention = [string]$trophy.item.retention
                source = "trophy:$([string]$variant.variantId)"
                is_readable_document = $false
                stash_bindings =
                    [System.Collections.Generic.List[object]]::new()
            }
        }
    }

    $signals = [System.Collections.Generic.List[object]]::new()
    $index = 0
    foreach ($item in @($itemsByGuid.Values | Sort-Object item_guid)) {
        $index++
        $name = 'dp_quest_item_request_{0:d3}' -f $index
        $signals.Add([ordered]@{
            signal_index = $index
            item_guid = [string]$item.item_guid
            classification = [string]$item.classification
            retention = [string]$item.retention
            source = [string]$item.source
            is_readable_document =
                [bool]$item.is_readable_document
            backend = if ([bool]$item.is_readable_document) {
                'quest_effect_stash'
            }
            else { 'player_transfer' }
            stash_bindings = @($item.stash_bindings)
            read_context = if ([bool]$item.is_readable_document) {
                'dp_document_read_' +
                    ([string]$item.item_guid).Replace('-', '').ToLowerInvariant()
            }
            else { '' }
            signal_tag = 129 + $index
            signal_name = $name
            buff_guid = Get-DpStableGuid -Seed (
                "darkpassenger-quest-item-request|$([string]$item.item_guid)"
            )
        })
    }
    return $signals.ToArray()
}

function ConvertTo-DpQuestItemPlacementTagXml {
    param(
        [Parameter(Mandatory)][string]$BaseXml,
        [Parameter(Mandatory)][object[]]$Signals
    )

    $additions = [System.Collections.Generic.List[string]]::new()
    foreach ($signal in @($Signals)) {
        $tag = [int]$signal.signal_tag
        $name = [string]$signal.signal_name
        $match = [regex]::Match(
            $BaseXml,
            "<buff_ai_tag\s+[^>]*buff_ai_tag_id=`"$tag`"[^>]*/>"
        )
        if ($match.Success) {
            if (-not $match.Value.Contains("buff_ai_tag_name=`"$name`"")) {
                throw "Quest-item buff tag id $tag collides."
            }
            continue
        }
        if ($BaseXml.Contains("buff_ai_tag_name=`"$name`"")) {
            throw "Quest-item buff tag name '$name' has another id."
        }
        $additions.Add(
            "`t`t<buff_ai_tag buff_ai_tag_id=`"$tag`" " +
            "buff_ai_tag_name=`"$name`" />"
        )
    }
    if ($additions.Count -eq 0) { return $BaseXml }
    $marker = if ($BaseXml.Contains("`t</buff_ai_tags>")) {
        "`t</buff_ai_tags>"
    }
    else { '</buff_ai_tags>' }
    $index = $BaseXml.LastIndexOf($marker)
    if ($index -lt 0) { throw 'Buff tag table has no closing collection.' }
    return $BaseXml.Insert($index, ($additions -join "`n") + "`n")
}

function ConvertTo-DpQuestItemPlacementBuffXml {
    param(
        [Parameter(Mandatory)][string]$BaseXml,
        [Parameter(Mandatory)][object[]]$Signals
    )

    $additions = [System.Collections.Generic.List[string]]::new()
    foreach ($signal in @($Signals)) {
        $tag = [int]$signal.signal_tag
        $name = [string]$signal.signal_name
        $guid = [string]$signal.buff_guid
        $match = [regex]::Match(
            $BaseXml,
            "<buff\s+[^>]*buff_id=`"$([regex]::Escape($guid))`"[^>]*/>"
        )
        if ($match.Success) {
            if (-not $match.Value.Contains("buff_name=`"$name`"") -or
                -not $match.Value.Contains("buff_ai_tag_id=`"$tag`"")) {
                throw "Quest-item buff guid $guid collides."
            }
            continue
        }
        if ($BaseXml.Contains("buff_name=`"$name`"")) {
            throw "Quest-item buff name '$name' has another guid."
        }
        $additions.Add(
            "`t`t<buff buff_ai_tag_id=`"$tag`" buff_class_id=`"1`" " +
            "buff_exclusivity_id=`"0`" buff_id=`"$guid`" " +
            "buff_lifetime_id=`"0`" buff_name=`"$name`" " +
            "buff_ui_visibility_id=`"0`" duration=`"-1`" icon_id=`"0`" " +
            "implementation=`"Cpp:Constant`" is_persistent=`"false`" />"
        )
    }
    if ($additions.Count -eq 0) { return $BaseXml }
    $marker = if ($BaseXml.Contains("`t</buffs>")) {
        "`t</buffs>"
    }
    else { '</buffs>' }
    $index = $BaseXml.LastIndexOf($marker)
    if ($index -lt 0) { throw 'Buff table has no closing collection.' }
    return $BaseXml.Insert($index, ($additions -join "`n") + "`n")
}

function ConvertTo-DpQuestItemPlacementNodesXml {
    param(
        [Parameter(Mandatory)][object[]]$Signals,
        [string]$Region
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($signal in @($Signals)) {
        $stashBindings = @(
            $signal.stash_bindings |
                Where-Object {
                    [string]::IsNullOrWhiteSpace($Region) -or
                    [string]$_.region -eq $Region
                }
        )
        $isQuestEffectStash =
            [string]$signal.backend -eq 'quest_effect_stash'
        if ($isQuestEffectStash -and $stashBindings.Count -eq 0) {
            continue
        }
        $signalIndex = if (
            $null -ne $signal.PSObject.Properties['signal_index']
        ) { [int]$signal.signal_index } else { [int]$signal.signal_tag - 129 }
        $suffix = '{0:d3}' -f $signalIndex
        $lines.Add("        <MakeArray Name=`"questItemRequestTags$suffix`" TypeT=`"wh::rpgmodule::BuffDefinitionAITags`">")
        $lines.Add("          <Constant Name=`"A`" Value=`"$([int]$signal.signal_tag)`" />")
        $lines.Add('        </MakeArray>')
        $lines.Add("        <BuffTagTrigger Name=`"questItemRequestTrigger$suffix`">")
        $lines.Add('          <Asset Name="Souls" Alias="player" />')
        $lines.Add("          <Edge From=`"questItemRequestTags$suffix.Array`" To=`"BuffTags`" />")
        $lines.Add('          <Edge From="watcherActive.State" To="IsActive" />')
        $lines.Add('        </BuffTagTrigger>')
        if ($isQuestEffectStash) {
            $lines.Add("        <State Name=`"questItemRequestActive$suffix`" TypeT=`"bool`">")
            $lines.Add("          <Edge From=`"questItemRequestTrigger$suffix.OnAdded`" To=`"SetTrue`" />")
            $lines.Add("          <Edge From=`"questItemRequestTrigger$suffix.OnRemoved`" To=`"SetFalse`" />")
            $lines.Add('        </State>')
            $bindingIndex = 0
            foreach ($stashBinding in $stashBindings) {
                $bindingIndex++
                $nodeSuffix = '{0}_{1:d2}' -f $suffix, $bindingIndex
                $lines.Add("        <AddQuestItem Name=`"addQuestItemToStash$nodeSuffix`">")
                $lines.Add("          <Constant Name=`"ItemClassGUID`" Value=`"$([string]$signal.item_guid)`" />")
                $lines.Add("          <Asset Name=`"BackupLocation`" Alias=`"$([string]$stashBinding.stash_alias)`" />")
                $lines.Add("          <Asset Name=`"StartingLocation`" Alias=`"$([string]$stashBinding.stash_alias)`" />")
                $lines.Add("          <Edge From=`"questItemRequestActive$suffix.State`" To=`"IsActive`" />")
                $lines.Add('        </AddQuestItem>')
            }
        }
        else {
            $lines.Add("        <ObjectProperties Name=`"questItemPlayerInventory$suffix`" DeclaringType=`"wh::rpgmodule::I_Soul`">")
            $lines.Add('          <Asset Name="I_Soul" Alias="player" />')
            $lines.Add('        </ObjectProperties>')
            $lines.Add("        <EventMemberFunction Name=`"createQuestItem$suffix`" MethodName=`"CreateItems`" DeclaringType=`"wh::entitymodule::Inventory`">")
            $lines.Add("          <Constant Name=`"ItemClass`" Value=`"$([string]$signal.item_guid)`" />")
            $lines.Add("          <Edge From=`"questItemPlayerInventory$suffix.Inventory`" To=`"Inventory`" />")
            $lines.Add("          <Edge From=`"questItemRequestTrigger$suffix.OnAdded`" To=`"Exec`" />")
            $lines.Add('        </EventMemberFunction>')
        }
        if ([bool]$signal.is_readable_document) {
            $lines.Add("        <UseBookTrigger Name=`"questDocumentReadTrigger$suffix`">")
            $lines.Add("          <Constant Name=`"Book`" Value=`"$([string]$signal.item_guid)`" />")
            $lines.Add('          <Edge From="watcherActive.State" To="IsActive" />')
            $lines.Add('        </UseBookTrigger>')
            $lines.Add("        <State Name=`"questDocumentReadPulse$suffix`" TypeT=`"bool`">")
            $lines.Add("          <Edge From=`"questDocumentReadTrigger$suffix.OnLastPageTurned`" To=`"SetTrue`" />")
            $lines.Add("          <Edge From=`"questDocumentReadTimer$suffix.OnFinished`" To=`"SetFalse`" />")
            $lines.Add('        </State>')
            $lines.Add("        <Timer Name=`"questDocumentReadTimer$suffix`">")
            $lines.Add('          <Constant Name="Duration" Value="3s" />')
            $lines.Add('          <Constant Name="TimeType" Value="GameTime" />')
            $lines.Add("          <Edge From=`"questDocumentReadTrigger$suffix.OnLastPageTurned`" To=`"SetRunning`" />")
            $lines.Add('        </Timer>')
            $lines.Add("        <SetEntityContext Name=`"questDocumentReadRequest$suffix`">")
            $lines.Add("          <Constant Name=`"Context`" Value=`"$([string]$signal.read_context)`" />")
            $lines.Add('          <Asset Name="Souls" Alias="player" />')
            $lines.Add("          <Edge From=`"questDocumentReadPulse$suffix.State`" To=`"IsActive`" />")
            $lines.Add('        </SetEntityContext>')
        }
    }
    return $lines -join "`n"
}

function ConvertTo-DpQuestItemPlacementAssetsXml {
    param(
        [Parameter(Mandatory)][object[]]$Signals,
        [string]$Region
    )

    $aliases = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($signal in @($Signals)) {
        foreach ($stashBinding in @($signal.stash_bindings)) {
            if (
                -not [string]::IsNullOrWhiteSpace($Region) -and
                [string]$stashBinding.region -ne $Region
            ) {
                continue
            }
            [void]$aliases.Add([string]$stashBinding.stash_alias)
        }
    }
    return @(
        $aliases |
            Sort-Object |
            ForEach-Object { "        <StashAsset Name=`"$_`" />" }
    ) -join "`n"
}

function ConvertTo-DpQuestItemPlacementCatalogLua {
    param([Parameter(Mandatory)][object[]]$Signals)

    $entries = [ordered]@{}
    foreach ($signal in @($Signals)) {
        $entries[[string]$signal.item_guid] = [ordered]@{
            item_guid = [string]$signal.item_guid
            buff_guid = [string]$signal.buff_guid
            signal_tag = [int]$signal.signal_tag
            retention = [string]$signal.retention
            backend = [string]$signal.backend
            read_context = [string]$signal.read_context
        }
    }
    return @(
        '-- Generated by Compile-CaseSpecs.ps1. Do not edit.'
        'DarkPassengerQuestItemPlacementCatalog = ' +
            (ConvertTo-DpLuaValue -Value $entries -Indent 0)
        ''
    ) -join "`n"
}

function Merge-DpQuestItemCatalogLua {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$BaseCatalog,
        [Parameter(Mandatory)][object[]]$Signals
    )

    $itemGuids = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($match in [regex]::Matches(
        $BaseCatalog,
        '(?i)\["(?<guid>[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})"\]\s*=\s*true'
    )) {
        $null = $itemGuids.Add(
            $match.Groups['guid'].Value.ToLowerInvariant()
        )
    }
    foreach ($signal in @($Signals)) {
        $itemGuid = ([string]$signal.item_guid).ToLowerInvariant()
        if ($itemGuid -notmatch
            '^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$') {
            throw "Invalid quest-item GUID '$itemGuid'."
        }
        $null = $itemGuids.Add($itemGuid)
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add(
        '-- Generated from authoritative and compiled KCD2 item tables. Do not edit.'
    )
    $lines.Add('DarkPassengerQuestItemCatalog = {')
    foreach ($itemGuid in @($itemGuids) | Sort-Object) {
        $lines.Add("    [`"$itemGuid`"] = true,")
    }
    $lines.Add('}')
    $lines.Add('')
    return $lines -join "`n"
}

function Get-DpCaseSpecValidationErrors {
    param(
        [Parameter(Mandatory)]$CaseSpec,
        [Parameter(Mandatory)]$Bindings,
        [string]$SourceName = '<case>'
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    $prefix = "${SourceName}:"

    if (-not (Test-DpTextValue $CaseSpec.id)) {
        $errors.Add("$prefix id is required")
    }
    if ([int]$CaseSpec.schemaVersion -ne 2) {
        $errors.Add("$prefix schemaVersion must be 2")
    }
    if ([int]$CaseSpec.code -le 0) {
        $errors.Add("$prefix code must be a positive integer")
    }
    if ([double]$CaseSpec.weight -le 0) {
        $errors.Add("$prefix weight must be positive")
    }

    $region = [string]$CaseSpec.constraints.region
    $settlement = [string]$CaseSpec.constraints.settlement
    if (-not (Test-DpTextValue $region)) {
        $errors.Add("$prefix constraints.region is required")
    }
    if (-not (Test-DpTextValue $settlement)) {
        $errors.Add("$prefix constraints.settlement is required")
    }

    $binding = @($Bindings.settlements | Where-Object {
        [string]$_.region -eq $region -and
        [string]$_.settlement -eq $settlement
    })
    if ($binding.Count -ne 1 -and
        (Test-DpTextValue $region) -and
        (Test-DpTextValue $settlement)) {
        $errors.Add("$prefix no settlement binding for '$region/$settlement'")
    }
    if ($binding.Count -eq 1) {
        $registryProperty = $Bindings.PSObject.Properties['dialogueRoles']
        $definitions = if ($null -ne $registryProperty) {
            @($registryProperty.Value)
        }
        else { @() }
        foreach ($roleName in @(Get-DpSettlementDialogueRoleNames `
            -SettlementBinding $binding[0])) {
            if (@($definitions | Where-Object {
                [string]$_.name -eq [string]$roleName
            }).Count -ne 1) {
                $errors.Add(
                    "$prefix dialogue role '$roleName' must have one registry definition"
                )
            }
        }
    }

    foreach ($language in 'ru', 'en') {
        $languageText = $CaseSpec.text.$language
        foreach ($field in 'title', 'description') {
            if (-not (Test-DpTextValue $languageText.$field)) {
                $errors.Add("$prefix text.$language.$field is required")
            }
        }
    }

    $localizationProperty = $CaseSpec.PSObject.Properties['localization']
    if ($null -ne $localizationProperty) {
        $ruLocalization = $CaseSpec.localization.ru
        $enLocalization = $CaseSpec.localization.en
        $ruKeys = if ($null -ne $ruLocalization) {
            @($ruLocalization.PSObject.Properties.Name | Sort-Object)
        }
        else { @() }
        $enKeys = if ($null -ne $enLocalization) {
            @($enLocalization.PSObject.Properties.Name | Sort-Object)
        }
        else { @() }
        if (($ruKeys -join "`n") -ne ($enKeys -join "`n")) {
            $errors.Add(
                "$prefix localization.ru and localization.en key sets must match"
            )
        }
        foreach ($language in 'ru', 'en') {
            $languageLocalization = $CaseSpec.localization.$language
            if ($null -eq $languageLocalization) { continue }
            foreach ($property in $languageLocalization.PSObject.Properties) {
                if (-not (Test-DpTextValue $property.Value)) {
                    $errors.Add(
                        "$prefix localization.$language.$($property.Name) is required"
                    )
                }
            }
        }
    }

    if (-not (Test-DpTextValue $CaseSpec.native.questName)) {
        $errors.Add("$prefix native.questName is required")
    }
    if (-not (Test-DpTextValue $CaseSpec.native.dialogFolder)) {
        $errors.Add("$prefix native.dialogFolder is required")
    }
    foreach ($dialogueKind in 'rumor', 'witness') {
        $dialogues = @($CaseSpec.native.dialogues | Where-Object {
            [string]$_.kind -eq $dialogueKind
        })
        if ($dialogues.Count -ne 1) {
            $errors.Add(
                "$prefix native.dialogues requires one '$dialogueKind' entry"
            )
            continue
        }
        $dialogue = $dialogues[0]
        foreach ($field in 'graphName', 'fileName', 'rootKey',
            'sequenceName', 'promptKey') {
            if (-not (Test-DpTextValue $dialogue.$field)) {
                $errors.Add(
                    "$prefix native dialogue '$dialogueKind' $field is required"
                )
            }
        }
        $variantsProperty = $dialogue.PSObject.Properties['variants']
        $responseGroups = [System.Collections.Generic.List[object]]::new()
        if ($null -ne $variantsProperty) {
            if (-not (Test-DpTextValue $dialogue.evidenceId)) {
                $errors.Add(
                    "$prefix native dialogue '$dialogueKind' evidenceId is required"
                )
            }
            $variantIds = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::Ordinal
            )
            foreach ($variant in @($variantsProperty.Value)) {
                $variantId = [string]$variant.id
                if ($variantId -notmatch '^[a-z][a-z0-9_]*$') {
                    $errors.Add(
                        "$prefix native dialogue '$dialogueKind' variant id " +
                        "'$variantId' is invalid"
                    )
                }
                elseif (-not $variantIds.Add($variantId)) {
                    $errors.Add(
                        "$prefix native dialogue '$dialogueKind' variant " +
                        "'$variantId' is duplicated"
                    )
                }
                if (-not (Test-DpTextValue $variant.promptKey)) {
                    $errors.Add(
                        "$prefix native dialogue '$dialogueKind' variant " +
                        "'$variantId' promptKey is required"
                    )
                }
                $whenProperty = $variant.PSObject.Properties['when']
                if ($null -eq $whenProperty -or
                    $null -eq $whenProperty.Value.PSObject.Properties[
                        'allDiscovered'
                    ] -or
                    $null -eq $whenProperty.Value.PSObject.Properties[
                        'allUndiscovered'
                    ]) {
                    $errors.Add(
                        "$prefix native dialogue '$dialogueKind' variant " +
                        "'$variantId' requires finite when conditions"
                    )
                }
                $responsesProperty = $variant.PSObject.Properties['responses']
                $responses = if ($null -ne $responsesProperty) {
                    @($responsesProperty.Value)
                }
                else { @() }
                if ($responses.Count -eq 0) {
                    $errors.Add(
                        "$prefix native dialogue '$dialogueKind' variant " +
                        "'$variantId' requires responses"
                    )
                }
                $responseGroups.Add($responses)
            }
        }
        else {
            $responsesProperty = $dialogue.PSObject.Properties['responses']
            $responseGroups.Add($(if ($null -ne $responsesProperty) {
                @($responsesProperty.Value)
            }
            else { @() }))
        }
        foreach ($responseGroup in $responseGroups) {
            foreach ($response in @($responseGroup)) {
                $role = [string]$response.role
                if (-not (Test-DpTextValue $response.key)) {
                    $errors.Add(
                        "$prefix native dialogue '$dialogueKind' response key is required"
                    )
                }
                if ($role -ne 'HENRY' -and $binding.Count -eq 1 -and
                    $null -eq $binding[0].roles.PSObject.Properties[$role]) {
                    $errors.Add(
                        "$prefix native dialogue '$dialogueKind' role '$role' is not bound"
                    )
                }
            }
        }
    }
    if ([int]$CaseSpec.native.signals.rumorAvailableTag -le 0 -or
        [int]$CaseSpec.native.signals.witnessAvailableTag -le 0) {
        $errors.Add("$prefix native signal tags must be positive")
    }
    if (-not (Test-DpTextValue $CaseSpec.native.contexts.rumorHeard) -or
        -not (Test-DpTextValue $CaseSpec.native.contexts.witnessHeard)) {
        $errors.Add("$prefix native dialogue contexts are required")
    }
    $overheardProperty = $CaseSpec.native.PSObject.Properties['overheard']
    if ($null -ne $overheardProperty) {
        $overheard = $overheardProperty.Value
        foreach ($field in @(
            'evidenceId',
            'graphName',
            'fileName',
            'rootKey',
            'decisionAlias',
            'sequenceName',
            'cluePort',
            'clueLabel',
            'context'
        )) {
            if (-not (Test-DpTextValue $overheard.$field)) {
                $errors.Add("$prefix native.overheard.$field is required")
            }
        }
        if ([int]$overheard.hearingDistance -le 0 -or
            [int]$overheard.repeatAfterSeconds -lt 0 -or
            [int]$overheard.availableTag -le 0) {
            $errors.Add("$prefix native.overheard scheduler values are invalid")
        }
        $responses = @($overheard.responses)
        if ($responses.Count -eq 0) {
            $errors.Add("$prefix native.overheard requires responses")
        }
        foreach ($response in $responses) {
            if ([string]$response.role -notin @('speakerA', 'speakerB') -or
                -not (Test-DpTextValue $response.key)) {
                $errors.Add("$prefix native.overheard response is invalid")
            }
        }
        if ($binding.Count -eq 1) {
            $bindingProperty =
                $binding[0].roles.PSObject.Properties['overheard']
            $pairs = if ($null -ne $bindingProperty) {
                @($bindingProperty.Value.pairs)
            }
            else { @() }
            if ($pairs.Count -ne 2) {
                $errors.Add(
                    "$prefix overheard binding requires a primary and fallback pair"
                )
            }
            $entityNames = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::Ordinal
            )
            foreach ($pair in $pairs) {
                $speakers = @($pair.speakers)
                if (-not (Test-DpTextValue $pair.id) -or
                    $speakers.Count -ne 2 -or
                    @($speakers.role | Sort-Object -Unique) -join ',' -ne
                        'speakerA,speakerB') {
                    $errors.Add("$prefix overheard pair '$($pair.id)' is invalid")
                    continue
                }
                foreach ($speaker in $speakers) {
                    foreach ($field in @(
                        'entityName',
                        'soulGuid',
                        'questAlias',
                        'dialogueRole'
                    )) {
                        if (-not (Test-DpTextValue $speaker.$field)) {
                            $errors.Add(
                                "$prefix overheard speaker $field is required"
                            )
                        }
                    }
                    if ([string]$speaker.soulGuid -notmatch
                        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
                        $errors.Add(
                            "$prefix overheard speaker soulGuid is invalid"
                        )
                    }
                    if (-not $entityNames.Add([string]$speaker.entityName)) {
                        $errors.Add(
                            "$prefix overheard speaker '$($speaker.entityName)' is duplicated"
                        )
                    }
                }
            }
        }
    }
    if (-not (Test-DpTextValue $CaseSpec.native.witnessObjective.assetName)) {
        $errors.Add("$prefix native.witnessObjective.assetName is required")
    }

    $evidence = @($CaseSpec.evidence)
    if ($evidence.Count -eq 0) {
        $errors.Add("$prefix evidence must contain at least one step")
    }
    $seenEvidence = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $seenEvidenceCodes = [System.Collections.Generic.HashSet[int]]::new()
    $confidenceTotal = 0
    foreach ($step in $evidence) {
        $evidenceId = [string]$step.id
        if (-not (Test-DpTextValue $evidenceId)) {
            $errors.Add("$prefix evidence id is required")
        }
        elseif (-not $seenEvidence.Add($evidenceId)) {
            $errors.Add("$prefix evidence id '$evidenceId' is duplicated")
        }
        $evidenceCode = [int]$step.code
        if ($evidenceCode -le 0) {
            $errors.Add("$prefix evidence '$evidenceId' code must be positive")
        }
        elseif (-not $seenEvidenceCodes.Add($evidenceCode)) {
            $errors.Add("$prefix evidence code '$evidenceCode' is duplicated")
        }
        $kind = [string]$step.kind
        if (-not (Test-DpTextValue $kind)) {
            $errors.Add("$prefix evidence '$evidenceId' kind is required")
        }
        elseif ($kind -notin @('dialogue', 'document')) {
            $errors.Add(
                "$prefix evidence '$evidenceId' kind '$kind' is not supported"
            )
        }
        if ($kind -eq 'document') {
            foreach ($field in 'name', 'nameKey', 'infoKey', 'contentKey') {
                if ($null -eq $step.PSObject.Properties['item'] -or
                    -not (Test-DpTextValue $step.item.$field)) {
                    $errors.Add(
                        "$prefix evidence '$evidenceId' item.$field is required"
                    )
                }
            }
            if (-not (Test-DpTextValue $step.reaction)) {
                $errors.Add(
                    "$prefix evidence '$evidenceId' reaction is required"
                )
            }
        }
        if ([int]$step.confidence -le 0) {
            $errors.Add("$prefix evidence '$evidenceId' confidence must be positive")
        }
        else {
            $confidenceTotal += [int]$step.confidence
        }

        $role = [string]$step.role
        if (-not (Test-DpTextValue $role)) {
            $errors.Add("$prefix evidence '$evidenceId' role is required")
        }
        elseif ($binding.Count -eq 1 -and
            $null -eq $binding[0].roles.PSObject.Properties[$role]) {
            $errors.Add("$prefix semantic role '$role' is not bound")
        }
        if ($role -ne 'innkeeper' -and $role -ne 'overheard') {
            $direction = $step.PSObject.Properties['direction']
            $directionKey = if ($null -ne $direction) {
                [string]$direction.Value.key
            }
            else { '' }
            if (-not (Test-DpTextValue $directionKey)) {
                $errors.Add(
                    "$prefix evidence '$evidenceId' direction.key is required"
                )
            }
            else {
                foreach ($language in 'ru', 'en') {
                    $localizationProperty =
                        $CaseSpec.PSObject.Properties['localization']
                    $languageProperty = if (
                        $null -ne $localizationProperty
                    ) {
                        $localizationProperty.Value.PSObject.Properties[
                            $language
                        ]
                    }
                    else { $null }
                    $languageRoot = if ($null -ne $languageProperty) {
                        $languageProperty.Value
                    }
                    else { $null }
                    $localized = if ($null -ne $languageRoot) {
                        $languageRoot.PSObject.Properties[$directionKey]
                    }
                    else { $null }
                    if ($null -eq $localized -or
                        -not (Test-DpTextValue $localized.Value)) {
                        $errors.Add(
                            "$prefix evidence '$evidenceId' direction key " +
                            "'$directionKey' is missing localization.$language"
                        )
                    }
                }
            }
        }

        $placementProperty = $step.PSObject.Properties['placement']
        $placement = if ($null -ne $placementProperty) {
            [string]$placementProperty.Value
        }
        else { '' }
        if ($placement -notin @('case_start', 'on_event', 'ambient')) {
            $errors.Add(
                "$prefix evidence '$evidenceId' placement must be " +
                "'case_start', 'on_event', or 'ambient'"
            )
        }

        $discoverableProperty =
            $step.PSObject.Properties['discoverableWithoutHint']
        if ($null -eq $discoverableProperty -or
            $discoverableProperty.Value -isnot [bool]) {
            $errors.Add(
                "$prefix evidence '$evidenceId' " +
                'discoverableWithoutHint must be boolean'
            )
        }

        $hintProperty = $step.PSObject.Properties['hintsUnlockedBy']
        if ($null -eq $hintProperty) {
            $errors.Add(
                "$prefix evidence '$evidenceId' hintsUnlockedBy is required"
            )
        }

        $revealsProperty = $step.PSObject.Properties['reveals']
        $revealedFacts = if ($null -ne $revealsProperty) {
            @($revealsProperty.Value | Where-Object {
                Test-DpTextValue $_
            })
        }
        else { @() }
        if (@($revealedFacts).Count -eq 0) {
            $errors.Add(
                "$prefix evidence '$evidenceId' reveals must contain a fact"
            )
        }
    }
    if ($null -ne $overheardProperty -and
        @($evidence | Where-Object {
            [string]$_.id -eq [string]$overheardProperty.Value.evidenceId
        }).Count -ne 1) {
        $errors.Add("$prefix native.overheard evidenceId is unknown")
    }

    $directionCount = @(Get-DpDirectionEvidence -CaseSpec $CaseSpec).Count
    if ($directionCount -gt 5) {
        $errors.Add(
            "$prefix supports at most 5 simultaneous journal directions"
        )
    }

    $evidenceIds = @($evidence | ForEach-Object { [string]$_.id })
    foreach ($dialogue in @($CaseSpec.native.dialogues)) {
        $variantsProperty = $dialogue.PSObject.Properties['variants']
        if ($null -eq $variantsProperty) { continue }
        $dialogueKind = [string]$dialogue.kind
        $dialogueEvidenceId = [string]$dialogue.evidenceId
        if ((Test-DpTextValue $dialogueEvidenceId) -and
            $dialogueEvidenceId -notin $evidenceIds) {
            $errors.Add(
                "$prefix native dialogue '$dialogueKind' references unknown " +
                "reward evidence '$dialogueEvidenceId'"
            )
        }
        foreach ($variant in @($variantsProperty.Value)) {
            $variantId = [string]$variant.id
            $whenProperty = $variant.PSObject.Properties['when']
            if ($null -eq $whenProperty) { continue }
            foreach ($condition in @(
                @{ Field = 'allDiscovered'; Label = 'discovered' },
                @{ Field = 'allUndiscovered'; Label = 'undiscovered' }
            )) {
                $conditionProperty =
                    $whenProperty.Value.PSObject.Properties[$condition.Field]
                if ($null -eq $conditionProperty) { continue }
                foreach ($conditionEvidence in @($conditionProperty.Value)) {
                    $conditionEvidenceId = [string]$conditionEvidence
                    if ((Test-DpTextValue $conditionEvidenceId) -and
                        $conditionEvidenceId -notin $evidenceIds) {
                        $errors.Add(
                            "$prefix native dialogue '$dialogueKind' variant " +
                            "'$variantId' references unknown " +
                            "$($condition.Label) evidence " +
                            "'$conditionEvidenceId'"
                        )
                    }
                }
            }
        }
    }
    foreach ($step in $evidence) {
        $hintProperty = $step.PSObject.Properties['hintsUnlockedBy']
        if ($null -eq $hintProperty) { continue }
        foreach ($hintSource in @($hintProperty.Value)) {
            $hintSourceId = [string]$hintSource
            if ((Test-DpTextValue $hintSourceId) -and
                $hintSourceId -notin $evidenceIds) {
                $errors.Add(
                    "$prefix evidence '$($step.id)' references unknown " +
                    "hint source '$hintSourceId'"
                )
            }
        }
    }

    $threshold = [int]$CaseSpec.revealThreshold
    if ($threshold -le 0) {
        $errors.Add("$prefix revealThreshold must be positive")
    }
    elseif ($confidenceTotal -lt $threshold) {
        $errors.Add(
            "$prefix evidence confidence total $confidenceTotal is below revealThreshold $threshold"
        )
    }

    return $errors.ToArray()
}

function Get-DpValidatedCaseSpecs {
    param(
        [Parameter(Mandatory)][string]$CaseRoot,
        [Parameter(Mandatory)][string]$BindingPath
    )

    $bindings = Read-DpCaseSettlementBindings -LiteralPath $BindingPath
    if ([int]$bindings.schemaVersion -ne 1) {
        throw "Settlement bindings schemaVersion must be 1: $BindingPath"
    }

    $files = @(Get-ChildItem -LiteralPath $CaseRoot -Filter '*.case.json' |
        Sort-Object FullName)
    if ($files.Count -eq 0) {
        throw "No CaseSpec files found in: $CaseRoot"
    }

    $cases = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()
    foreach ($registryError in @(
        Get-DpDialogueRoleRegistryErrors -Bindings $bindings
    )) {
        $errors.Add("$(Split-Path -Leaf $BindingPath): $registryError")
    }
    $ids = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $codes = [System.Collections.Generic.HashSet[int]]::new()

    foreach ($file in $files) {
        $case = Read-DpCaseSpec -LiteralPath $file.FullName
        foreach ($errorMessage in @(Get-DpCaseSpecValidationErrors `
            -CaseSpec $case `
            -Bindings $bindings `
            -SourceName $file.Name)) {
            $errors.Add($errorMessage)
        }
        if ((Test-DpTextValue $case.id) -and
            -not $ids.Add([string]$case.id)) {
            $errors.Add("$($file.Name): case id '$($case.id)' is duplicated")
        }
        if ([int]$case.code -gt 0 -and -not $codes.Add([int]$case.code)) {
            $errors.Add("$($file.Name): case code '$($case.code)' is duplicated")
        }
        $cases.Add($case)
    }

    if ($errors.Count -gt 0) {
        throw "CaseSpec validation failed:`n - $($errors -join "`n - ")"
    }

    return @($cases | Sort-Object code, id)
}

Export-ModuleMember -Function @(
    'Read-DpCaseSpec',
    'Read-DpCaseSettlementBindings',
    'Get-DpCaseSpecValidationErrors',
    'Get-DpValidatedCaseSpecs',
    'ConvertTo-DpLuaString',
    'ConvertTo-DpLuaValue',
    'ConvertTo-DpCaseCatalogLua',
    'Get-DpCaseCleanupManifest',
    'ConvertTo-DpCaseVariantCatalogLua',
    'ConvertTo-DpCaseCompatibilityReport',
    'ConvertTo-DpDialogueXml',
    'ConvertTo-DpOverheardDialogueXml',
    'ConvertTo-DpNativeRegionWiring',
    'Get-DpJournalStates',
    'Get-DpDialogueVariants',
    'ConvertTo-DpLeadStateTagXml',
    'ConvertTo-DpLeadStateBuffXml',
    'ConvertTo-DpDialogueVariantTagXml',
    'ConvertTo-DpDialogueVariantBuffXml',
    'ConvertTo-DpOverheardTagXml',
    'ConvertTo-DpOverheardBuffXml',
    'Get-DpEvidenceStashAlias',
    'Get-DpQuestItemPlacementSignals',
    'ConvertTo-DpQuestItemPlacementTagXml',
    'ConvertTo-DpQuestItemPlacementBuffXml',
    'ConvertTo-DpQuestItemPlacementNodesXml',
    'ConvertTo-DpQuestItemPlacementAssetsXml',
    'ConvertTo-DpQuestItemPlacementCatalogLua',
    'Merge-DpQuestItemCatalogLua',
    'ConvertTo-DpLocalizationXml',
    'ConvertTo-DpStormRoleXml',
    'ConvertTo-DpDialogueRoleTableXml',
    'ConvertTo-DpScriptContextXml',
    'ConvertTo-DpItemTableXml'
)
