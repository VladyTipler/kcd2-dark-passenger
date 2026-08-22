Set-StrictMode -Version Latest

$areaSelectionModule = Join-Path $PSScriptRoot `
    'VanillaInvestigationAreaSelection.psm1'
if (-not (Test-Path -LiteralPath $areaSelectionModule -PathType Leaf)) {
    throw "Vanilla area selection module not found: $areaSelectionModule"
}
Import-Module $areaSelectionModule -Force

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

function Get-DpCaseSettlementBindings {
    param(
        [Parameter(Mandatory)]$Bindings,
        [Parameter(Mandatory)][int]$CaseCode,
        [string]$Region,
        [string]$Settlement
    )

    return @($Bindings.settlements | Where-Object {
        $binding = $_
        $caseCodeProperty = $binding.PSObject.Properties['caseCode']
        $caseMatches = $null -eq $caseCodeProperty -or
            [int]$caseCodeProperty.Value -eq $CaseCode
        $regionMatches = [string]::IsNullOrWhiteSpace($Region) -or
            [string]$binding.region -eq $Region
        $settlementMatches = [string]::IsNullOrWhiteSpace($Settlement) -or
            [string]$binding.settlement -eq $Settlement
        $caseMatches -and $regionMatches -and $settlementMatches
    })
}

function Get-DpScopedCaseSettlementBindings {
    param(
        [Parameter(Mandatory)]$Bindings,
        [Parameter(Mandatory)]$CaseSpec,
        [string]$Region = ''
    )

    $caseCodeProperty = $CaseSpec.PSObject.Properties['code']
    $caseCode = if ($null -ne $caseCodeProperty) {
        [int]$caseCodeProperty.Value
    }
    else { 0 }
    $effectiveRegion = if (-not [string]::IsNullOrWhiteSpace($Region)) {
        $Region
    }
    else { [string]$CaseSpec.constraints.region }
    $scoped = @(Get-DpCaseSettlementBindings -Bindings $Bindings `
        -CaseCode $caseCode `
        -Region $effectiveRegion)
    $explicit = @($scoped | Where-Object {
        $null -ne $_.PSObject.Properties['caseCode']
    })
    if ($explicit.Count -gt 0) { return $explicit }
    return @(Get-DpCaseSettlementBindings -Bindings $Bindings `
        -CaseCode $caseCode `
        -Region $effectiveRegion `
        -Settlement ([string]$CaseSpec.constraints.settlement))
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

    $states = [System.Collections.Generic.List[object]]::new()
    $states.Add([ordered]@{
        code = 0
        state_name = 'DirectionsNone'
        signal_tag = 37
        buff_guid = Get-DpStableGuid -Seed 'darkpassenger-lead-state-0'
        localization_key = ''
        fallback = ''
        evidence_code = 0
        entry_id = ''
        all_known_facts = @()
        all_unknown_facts = @()
    })

    foreach ($evidence in @($CaseSpec.evidence)) {
        $journalEntries = if (
            $null -ne $evidence.PSObject.Properties['journalEntries']
        ) {
            @($evidence.journalEntries)
        }
        elseif ($null -ne $evidence.PSObject.Properties['direction'] -and
                -not [string]::IsNullOrWhiteSpace(
                    [string]$evidence.direction.key
                )) {
            $legacyKey = [string]$evidence.direction.key
            $legacyFallback = ''
            if ($null -ne $CaseSpec.localization.en.PSObject.Properties[$legacyKey]) {
                $legacyFallback = [string](
                    $CaseSpec.localization.en.PSObject.Properties[$legacyKey].Value
                )
            }
            @([pscustomobject][ordered]@{
                id = 'default'
                allKnownFacts = @()
                allUnknownFacts = @()
                key = $legacyKey
                fallback = $legacyFallback
            })
        }
        else {
            @()
        }
        foreach ($entry in $journalEntries) {
            if ($states.Count -gt 31) {
                throw (
                    "Case '$($CaseSpec.id)' has more than 31 journal " +
                    'presentations; signal tags 37..68 are exhausted.'
                )
            }
            $entryId = [string]$entry.id
            $entrySuffix = @(
                $entryId -split '[^A-Za-z0-9]+' |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    ForEach-Object {
                        $_.Substring(0, 1).ToUpperInvariant() +
                            $_.Substring(1)
                    }
            ) -join ''
            if ([string]::IsNullOrWhiteSpace($entrySuffix)) {
                $entrySuffix = 'Default'
            }
            $stateCode = $states.Count
            $states.Add([ordered]@{
                code = $stateCode
                state_name = "Evidence$([int]$evidence.code)$entrySuffix"
                signal_tag = 37 + $stateCode
                buff_guid = Get-DpStableGuid `
                    -Seed "darkpassenger-lead-state-$stateCode"
                localization_key = [string]$entry.key
                fallback = [string]$entry.fallback
                evidence_code = [int]$evidence.code
                entry_id = $entryId
                all_known_facts = @($entry.allKnownFacts)
                all_unknown_facts = @($entry.allUnknownFacts)
            })
        }
    }
    return $states.ToArray()
}

function Get-DpCaseActivationSignals {
    param(
        [Parameter(Mandatory)][object[]]$CaseSpecs,
        [int]$StartSignalTag = 122
    )

    $signals = [System.Collections.Generic.List[object]]::new()
    $index = 0
    foreach ($case in @($CaseSpecs | Sort-Object code, id)) {
        $caseCode = [int]$case.code
        $signals.Add([ordered]@{
            case_id = [string]$case.id
            case_code = $caseCode
            signal_tag = $StartSignalTag + $index
            signal_name = "dp_case_active_$caseCode"
            buff_guid = Get-DpStableGuid `
                -Seed "darkpassenger-case-active-$caseCode"
        })
        $index++
    }
    return $signals.ToArray()
}

function Get-DpActorSelectionSignals {
    param(
        [Parameter(Mandatory)][object[]]$CaseSpecs,
        [int]$StartSignalTag = 151,
        [int]$MaxSignalTag = 179
    )

    $signals = [System.Collections.Generic.List[object]]::new()
    $index = 0
    foreach ($case in @($CaseSpecs | Sort-Object code, id)) {
        foreach ($semanticRole in 'innkeeper', 'witness') {
            $tag = $StartSignalTag + $index
            if ($tag -gt $MaxSignalTag) {
                throw "Actor-selection signal tag capacity exceeded at $tag."
            }
            $caseCode = [int]$case.code
            $signalName = "dp_actor_selected_${caseCode}_$semanticRole"
            $signals.Add([ordered]@{
                case_id = [string]$case.id
                case_code = $caseCode
                semantic_role = $semanticRole
                signal_tag = $tag
                signal_name = $signalName
                buff_guid = Get-DpStableGuid -Seed (
                    "darkpassenger-actor-selected-$caseCode-$semanticRole"
                )
            })
            $index++
        }
    }
    return $signals.ToArray()
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
        [Parameter(Mandatory)][object[]]$JournalStates,
        [int]$DirectionCode = 0
    )

    $journalSourceEntries = if (
        $null -ne $Evidence.PSObject.Properties['journalEntries']
    ) {
        @($Evidence.journalEntries)
    }
    else {
        @($JournalStates | Where-Object {
            [int]$_.evidence_code -eq [int]$Evidence.code
        } | ForEach-Object {
            [pscustomobject][ordered]@{
                id = [string]$_.entry_id
                allKnownFacts = @($_.all_known_facts)
                allUnknownFacts = @($_.all_unknown_facts)
                key = [string]$_.localization_key
            }
        })
    }
    $journalEntries = @($journalSourceEntries | ForEach-Object {
        $entry = $_
        $matches = @($JournalStates | Where-Object {
            [int]$_.evidence_code -eq [int]$Evidence.code -and
            [string]$_.entry_id -ceq [string]$entry.id
        })
        if ($matches.Count -ne 1) {
            throw (
                "Evidence '$($Evidence.id)' journal entry '$($entry.id)' " +
                'does not resolve to exactly one journal state.'
            )
        }
        $state = $matches[0]
        [ordered]@{
            id = [string]$entry.id
            all_known_facts = @($entry.allKnownFacts)
            all_unknown_facts = @($entry.allUnknownFacts)
            key = [string]$entry.key
            state_code = [int]$state.code
            state_name = [string]$state.state_name
            signal_tag = [int]$state.signal_tag
            buff_guid = [string]$state.buff_guid
        }
    })

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
        journal_entries = $journalEntries
    }
}

function ConvertTo-DpRuntimeCase {
    param(
        [Parameter(Mandatory)]$CaseSpec,
        [Parameter(Mandatory)]$Binding
    )

    $journalStates = @(Get-DpJournalStates -CaseSpec $CaseSpec)
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
            -JournalStates $journalStates `
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
        identity_requirement = if ($null -ne (
            $CaseSpec.PSObject.Properties['identityRequirement']
        )) {
            $CaseSpec.identityRequirement
        }
        else { $null }
        rumors = $rumors
        evidence_steps = @($evidence | Select-Object -Skip 1)
        evidence = $evidence.ToArray()
        journal_states = $journalStates
        dialogue_variants = $dialogueVariants
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
        $binding = @(Get-DpCaseSettlementBindings -Bindings $Bindings `
            -CaseCode ([int]$case.code) `
            -Region ([string]$case.constraints.region) `
            -Settlement ([string]$case.constraints.settlement))[0]
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
                activation_mode = if (
                    $null -ne $step.action.PSObject.Properties['activation']
                ) { [string]$step.action.activation.mode } else { $null }
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
        [object[]]$GuidanceSignals = @(),
        $CaseActivationSignal,
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
            Where-Object { $_ -in @('innkeeper', 'witness') } |
            Sort-Object -Unique
    )

    $signalBuffGuids = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $CaseActivationSignal -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$CaseActivationSignal.buff_guid
        )) {
        $signalBuffGuids.Add([string]$CaseActivationSignal.buff_guid)
    }
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
    foreach ($guidanceSignal in @($GuidanceSignals)) {
        if (-not [string]::IsNullOrWhiteSpace(
            [string]$guidanceSignal.buff_guid
        )) {
            $signalBuffGuids.Add([string]$guidanceSignal.buff_guid)
        }
    }

    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($evidence in @($CaseSpec.evidence)) {
        $itemProperty = $evidence.PSObject.Properties['item']
        if ($null -eq $itemProperty -or $null -eq $itemProperty.Value) {
            continue
        }
        $source = "evidence:$([string]$evidence.id)"
        $signals = @($QuestItemPlacementSignals | Where-Object {
            [string]$_.source -eq $source
        })
        $bindingContainerGuid = if ($null -ne $Binding -and
            $null -ne $Binding.roles.PSObject.Properties['document']) {
            [string]$Binding.roles.document.containerGuid
        }
        else { '' }
        $signal = if (-not [string]::IsNullOrWhiteSpace(
            $bindingContainerGuid
        )) {
            @($signals | Where-Object {
                [string]$_.request_key -eq
                    $bindingContainerGuid.ToLowerInvariant()
            } | Select-Object -First 1)
        }
        else { @($signals | Select-Object -First 1) }
        if ($signal -is [array]) { $signal = $signal | Select-Object -First 1 }
        if ($null -eq $signal) { continue }
        $scene = @($RuntimeScenes | Where-Object {
            [int]$_.evidence_code -eq [int]$evidence.code
        } | Select-Object -First 1)
        if ($scene -is [array]) { $scene = $scene | Select-Object -First 1 }
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
        [object[]]$QuestItemPlacementSignals = @(),
        [object[]]$GuidanceSignals = @(),
        [object[]]$CaseActivationSignals = @(),
        [object[]]$ActorSelectionSignals = @()
    )

    if (@($ActorSelectionSignals).Count -eq 0) {
        $ActorSelectionSignals = @(Get-DpActorSelectionSignals `
            -CaseSpecs $CaseSpecs -StartSignalTag 151 -MaxSignalTag 179)
    }

    $storyById = @{}
    foreach ($story in @($CompiledDefinitions.stories)) {
        $storyById[[string]$story.storyId] = $story
    }
    $caseByCode = @{}
    foreach ($caseSpec in @($CaseSpecs)) {
        $caseByCode[[int]$caseSpec.code] = $caseSpec
    }
    $caseActivationByCode = @{}
    foreach ($signal in @($CaseActivationSignals)) {
        $caseActivationByCode[[int]$signal.case_code] = $signal
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
        $caseBindings = @()
        if ($null -ne $Bindings -and $null -ne $caseSpec) {
            $caseBindings = @(Get-DpCaseSettlementBindings -Bindings $Bindings `
                -CaseCode ([int]$variant.caseCode) `
                -Region ([string]$variant.region) `
                -Settlement ([string]$variant.settlement))
        }
        $caseBinding = if (@($caseBindings).Count -eq 1) {
            $caseBindings[0]
        }
        else { $null }
        $runtimeActorPools = [ordered]@{}
        $runtimeActorSelection = [ordered]@{}
        if ($null -ne $caseBinding) {
            foreach ($roleMap in @(
                @{ Semantic = 'rumorSource'; Native = 'innkeeper' },
                @{ Semantic = 'witness'; Native = 'witness' }
            )) {
                $semanticBinding = $runtimeBindings[$roleMap.Semantic]
                $nativeRoleProperty =
                    $caseBinding.roles.PSObject.Properties[$roleMap.Native]
                if ($null -eq $semanticBinding -or
                    $null -eq $nativeRoleProperty) {
                    continue
                }
                $dialogueRoleProperty =
                    $nativeRoleProperty.Value.PSObject.Properties[
                        'dialogueRole'
                    ]
                if ($null -ne $dialogueRoleProperty -and
                    -not [string]::IsNullOrWhiteSpace(
                        [string]$dialogueRoleProperty.Value
                    )) {
                    $semanticBinding['dialogue_role'] =
                        [string]$dialogueRoleProperty.Value
                }
                $actorPoolsProperty =
                    $caseBinding.PSObject.Properties['actorPools']
                $poolProperty = if ($null -ne $actorPoolsProperty) {
                    $actorPoolsProperty.Value.PSObject.Properties[$roleMap.Native]
                }
                else { $null }
                if ($null -ne $poolProperty) {
                    $runtimeActorPools[$roleMap.Native] = @(
                        $poolProperty.Value |
                            Sort-Object candidateOrder, entityName |
                            ForEach-Object {
                                [ordered]@{
                                    actor_code = Get-DpStableRuntimeCode `
                                        -Value ([string]$_.entityName)
                                    candidate_order = [int]$_.candidateOrder
                                    entity_name = [string]$_.entityName
                                    entity_guid = [string]$_.entityGuid
                                    soul_guid = [string]$_.soulGuid
                                    dialogue_role = [string]$_.dialogueRole
                                }
                            }
                    )
                    $selectionSignal = @($ActorSelectionSignals | Where-Object {
                        [int]$_.case_code -eq [int]$variant.caseCode -and
                        [string]$_.semantic_role -ceq [string]$roleMap.Native
                    })
                    if ($selectionSignal.Count -ne 1) {
                        throw "Variant '$($variant.variantId)' has no unique " +
                            "actor-selection signal for '$($roleMap.Native)'."
                    }
                    $runtimeActorSelection[$roleMap.Native] = [ordered]@{
                        signal_tag = [int]$selectionSignal[0].signal_tag
                        buff_guid = [string]$selectionSignal[0].buff_guid
                    }
                }
            }
        }
        $bindingCoversVariant = $false
        if ($null -ne $caseBinding) {
            $variantIdsProperty =
                $caseBinding.PSObject.Properties['nativeVariantIds']
            $bindingCoversVariant = $null -eq $variantIdsProperty -or
                @($variantIdsProperty.Value) -contains [string]$variant.variantId
        }
        $supportedRegions = if (
            $null -ne $caseSpec -and
            $null -ne $caseSpec.constraints.PSObject.Properties['regions']
        ) { @($caseSpec.constraints.regions) } elseif ($null -ne $caseSpec) {
            @([string]$caseSpec.constraints.region)
        } else { @() }
        $nativeRegionAvailable = $false
        if ($null -ne $caseSpec -and
            $null -ne $caseSpec.native.PSObject.Properties['regions']) {
            $nativeRegionAvailable = $null -ne
                $caseSpec.native.regions.PSObject.Properties[
                    [string]$variant.region
                ]
        }
        elseif ($null -ne $caseSpec) {
            $nativeRegionAvailable =
                [string]$caseSpec.constraints.region -eq [string]$variant.region
        }
        $nativeReady = $null -ne $caseSpec -and
            $supportedRegions -contains [string]$variant.region -and
            $nativeRegionAvailable -and
            $null -ne $caseBinding -and $bindingCoversVariant -and
            [int]$target.candidate_slot -gt 0
        $runtimeScenes = @(ConvertTo-DpRuntimeSceneDefinitions `
            -Story $story -VariantBindings $variant.bindings `
            -CandidateByEntityName $candidateByEntityName)
        $trophy = ConvertTo-DpNativeTrophyDefinition -Variant $variant
        $variantGuidanceSignals = @($GuidanceSignals | Where-Object {
            [string]$_.variant_id -eq [string]$variant.variantId
        } | Sort-Object signal_tag, qualified_id)
        $runtimeGuidance = @($variantGuidanceSignals | ForEach-Object {
            [ordered]@{
                id = [string]$_.qualified_id
                evidence_code = [int]$_.step_evidence_code
                visibility_mode = [string]$_.visibility_mode
                requires_fact_ids = @($_.requires_fact_ids | ForEach-Object {
                    [string]$_
                })
                lifetime = [string]$_.lifetime
                buff_guid = [string]$_.buff_guid
                signal_tag = [int]$_.signal_tag
                alias = [string]$_.alias
                asset_kind = [string]$_.asset_kind
            }
        })
        $timedAreaActions = [System.Collections.Generic.List[object]]::new()
        if ($nativeReady) {
            foreach ($signal in @($variantGuidanceSignals | Where-Object {
                $null -ne $_.timed_area_action
            })) {
                $timedAreaActions.Add([ordered]@{
                    id = [string]$signal.timed_area_action.id
                    evidence_code = [int]$signal.step_evidence_code
                    area_context = [string]$signal.timed_area_action.area_context
                    prompt_key = [string]$signal.timed_area_action.prompt_key
                    progress_key = [string]$signal.timed_area_action.progress_key
                    unavailable_key =
                        [string]$signal.timed_area_action.unavailable_key
                    available_from_hour =
                        [int]$signal.timed_area_action.available_from_hour
                    available_until_hour =
                        [int]$signal.timed_area_action.available_until_hour
                    duration_hours =
                        [int]$signal.timed_area_action.duration_hours
                })
            }
        }
        $cleanupManifest = if ($nativeReady) {
            Get-DpCaseCleanupManifest `
                -CaseSpec $caseSpec `
                -Variant $variant `
                -RuntimeScenes $runtimeScenes `
                -Binding $caseBinding `
                -QuestItemPlacementSignals $QuestItemPlacementSignals `
                -GuidanceSignals $variantGuidanceSignals `
                -CaseActivationSignal $caseActivationByCode[
                    [int]$variant.caseCode
                ] `
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
            case_activation_buff_guid = if (
                $caseActivationByCode.ContainsKey([int]$variant.caseCode)
            ) {
                [string]$caseActivationByCode[[int]$variant.caseCode].buff_guid
            }
            else { '' }
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
            actor_pools = $runtimeActorPools
            actor_selection = $runtimeActorSelection
            scenes = $runtimeScenes
            timed_area_actions = $timedAreaActions.ToArray()
            guidance = $runtimeGuidance
            cleanup_manifest = $cleanupManifest
        })
    }

    $catalogRevisionSeed = ConvertTo-Json `
        -InputObject $runtimeVariants.ToArray() `
        -Depth 100 `
        -Compress
    $catalogRevision = Get-DpStableRuntimeCode `
        -Value $catalogRevisionSeed
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('-- Generated by Compile-CaseSpecs.ps1. Do not edit.')
    $lines.Add(
        "DarkPassengerCaseVariantCatalogRevision = $catalogRevision"
    )
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
        $CompiledDefinitions,
        [AllowEmptyCollection()][object[]]$GuidanceSignals = @()
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
            if (-not $values.Contains($key)) {
                throw (
                    "Authored journal localization key '$key' is absent " +
                    "from $Language localization."
                )
            }
        }
    }

    foreach ($signal in @($GuidanceSignals | Sort-Object `
        objective_name_key, objective_active_key -Unique)) {
        if (-not [bool]$signal.objective_authored) { continue }
        foreach ($entry in @(
            [ordered]@{
                key = [string]$signal.objective_name_key
                value = [string]$signal.objective_name_localization.$Language
            },
            [ordered]@{
                key = [string]$signal.objective_active_key
                value = [string]$signal.objective_active_localization.$Language
            }
        )) {
            if ($values.Contains($entry.key)) {
                if ([string]$values[$entry.key] -ne $entry.value) {
                    throw "Generated guidance localization key " +
                        "'$($entry.key)' conflicts."
                }
                continue
            }
            $values[$entry.key] = $entry.value
            $rows.Add($entry)
        }
    }
    foreach ($signal in @($GuidanceSignals | Where-Object {
        $null -ne $_.timed_area_action
    } | Sort-Object { [string]$_.timed_area_action.id } -Unique)) {
        foreach ($entry in @(
            [ordered]@{
                key = [string]$signal.timed_area_action.prompt_key
                value = [string]$signal.timed_area_action.prompt_localization.$Language
            },
            [ordered]@{
                key = [string]$signal.timed_area_action.progress_key
                value = [string]$signal.timed_area_action.progress_localization.$Language
            },
            [ordered]@{
                key = [string]$signal.timed_area_action.unavailable_key
                value = [string]$signal.timed_area_action.unavailable_localization.$Language
            }
        )) {
            if ($values.Contains($entry.key)) {
                if ([string]$values[$entry.key] -ne $entry.value) {
                    throw "Generated timed area localization key " +
                        "'$($entry.key)' conflicts."
                }
                continue
            }
            $values[$entry.key] = $entry.value
            $rows.Add($entry)
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

    $unresolved = @($rows | Where-Object {
        [string]$_.value -match '\{\{[^{}]+\}\}'
    } | Select-Object -First 1)
    if ($unresolved.Count -gt 0) {
        throw "Localization key '$([string]$unresolved[0].key)' contains " +
            'an unresolved authored template token.'
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
    $generatedAssignments = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($case in @($CaseSpecs | Sort-Object code, id)) {
        $allCaseBindings = @(Get-DpCaseSettlementBindings `
            -Bindings $Bindings -CaseCode ([int]$case.code))
        $explicitCaseBindings = @($allCaseBindings | Where-Object {
            $null -ne $_.PSObject.Properties['caseCode']
        })
        $stormBindings = if ($explicitCaseBindings.Count -gt 0) {
            $explicitCaseBindings
        }
        else {
            @(Get-DpScopedCaseSettlementBindings `
                -Bindings $Bindings -CaseSpec $case)
        }
        foreach ($binding in @($stormBindings)) {
            $roleBindings = [System.Collections.Generic.List[object]]::new()
            foreach ($role in 'innkeeper', 'witness') {
                $property = $binding.roles.PSObject.Properties[$role]
                if ($null -eq $property) { continue }
                $poolProperty = $binding.PSObject.Properties['actorPools']
                $pool = if ($null -ne $poolProperty) {
                    $poolProperty.Value.PSObject.Properties[$role]
                }
                else { $null }
                $actors = if ($null -ne $pool) {
                    @($pool.Value)
                }
                else { @($property.Value) }
                foreach ($actor in @($actors | Sort-Object entityName)) {
                    $roleBindings.Add([ordered]@{
                        suffix = $role
                        entityName = [string]$actor.entityName
                        dialogueRole = [string]$property.Value.dialogueRole
                    })
                }
            }
            foreach ($entry in $roleBindings) {
                $entityName = [string]$entry.entityName
                $dialogueRole = [string]$entry.dialogueRole
                $assignment = "$entityName|$dialogueRole"
                if (-not $generatedAssignments.Add($assignment)) { continue }
                $existing = @($rules | Where-Object {
                    $_.Value.Contains("<hasName name=`"$entityName`" />") -and
                    $_.Value.Contains("<addRole name=`"$dialogueRole`" />")
                })
                if ($existing.Count -gt 0) { continue }

                $ruleName = 'darkpassenger_' + [int]$case.code + '_' +
                    ([string]$binding.settlement -replace '[^A-Za-z0-9_]', '_') +
                    '_' + ([string]$entry.suffix -replace '[^A-Za-z0-9_]', '_') +
                    '_' + (Get-DpStableRuntimeCode -Value $entityName)
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
        $matchingBindings = @(Get-DpScopedCaseSettlementBindings `
            -Bindings $Bindings -CaseSpec $case)
        if ($matchingBindings.Count -eq 0) {
            throw "Case '$($case.id)' requires at least one settlement binding."
        }
        foreach ($matchingBinding in $matchingBindings) {
            foreach ($roleName in @(Get-DpSettlementDialogueRoleNames `
                -SettlementBinding $matchingBinding)) {
                [void]$requiredNames.Add([string]$roleName)
            }
        }
    }

    $knownNames = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::Ordinal
    )
    $knownIds = [System.Collections.Generic.Dictionary[string, string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
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
        $knownName = [string]$nameMatch.Groups[1].Value
        $knownId = [string]$idMatch.Groups[1].Value
        if ($knownNames.ContainsKey($knownName)) {
            throw "Duplicate RPG role name '$knownName' in the base RPG table."
        }
        if ($knownIds.ContainsKey($knownId)) {
            throw "Duplicate RPG role id '$knownId' in the base RPG table."
        }
        $knownNames[$knownName] = [ordered]@{
            roleId = [string]$idMatch.Groups[1].Value
            metaRole = [string]$metaRoleMatch.Groups[1].Value
        }
        $knownIds[$knownId] = $knownName
    }

    foreach ($roleName in @($requiredNames | Sort-Object)) {
        $matches = @($definitions | Where-Object {
            [string]$_.name -ceq $roleName
        })
        if ($matches.Count -ne 1) {
            throw "Dialogue role '$roleName' requires exactly one registry definition."
        }
    }

    $additions = [System.Collections.Generic.List[string]]::new()
    foreach ($definition in @($definitions | Sort-Object name)) {
        $roleName = [string]$definition.name
        $roleId = [string]$definition.roleId
        $metaRole = [string]$definition.metaRole

        if ($knownNames.ContainsKey($roleName)) {
            $known = $knownNames[$roleName]
            if ([string]$known.roleId -ne $roleId -or
                [string]$known.metaRole -ne $metaRole) {
                throw "Dialogue role '$roleName' conflicts with the base RPG table."
            }
            continue
        }
        if ($knownIds.ContainsKey($roleId)) {
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
        [object[]]$Signals = @(),
        [object[]]$GuidanceSignals = @()
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
    foreach ($signal in @($GuidanceSignals)) {
        $timedActionProperty = $signal.PSObject.Properties[
            'timed_area_action'
        ]
        if ($null -eq $timedActionProperty -or
            $null -eq $timedActionProperty.Value) {
            continue
        }
        $context = [string]$timedActionProperty.Value.area_context
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
        $binding = @(Get-DpCaseSettlementBindings -Bindings $Bindings `
            -CaseCode ([int]$case.code) `
            -Region ([string]$case.constraints.region) `
            -Settlement ([string]$case.constraints.settlement))[0]
        foreach ($step in $documentSteps) {
            $id = if ($null -ne $step.item.PSObject.Properties['guid']) {
                [string]$step.item.guid
            }
            elseif ($null -ne $binding) {
                [string]$binding.roles.document.documentGuid
            }
            else { '' }
            if ([string]::IsNullOrWhiteSpace($id)) {
                throw "Document '$([string]$step.id)' has no item GUID."
            }
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

function Get-DpDialogueVoiceLine {
    param(
        $VoiceAssignment,
        [Parameter(Mandatory)][string]$StringName
    )

    if ($null -eq $VoiceAssignment) { return $null }
    $matches = @($VoiceAssignment.lines | Where-Object {
        [string]$_.stringName -ceq $StringName
    })
    if ($matches.Count -ne 1) {
        throw "Dialogue voice assignment has no unique line for '$StringName'."
    }
    return $matches[0]
}

function Add-DpDialogueResponseXml {
    param(
        [Parameter(Mandatory)]$Lines,
        [Parameter(Mandatory)]$Response,
        [Parameter(Mandatory)]$Binding,
        $VoiceAssignment,
        [Parameter(Mandatory)][string]$Indent
    )

    $role = [string]$Response.role
    if ($role -ne 'HENRY') {
        $roleBinding = $Binding.roles.PSObject.Properties[$role]
        if ($null -eq $roleBinding) {
            throw "Dialogue response uses unbound role '$role'."
        }
        $role = [string]$roleBinding.Value.dialogueRole
    }
    $responseAttributes = "Role=`"$role`""
    if ($null -ne $VoiceAssignment) {
        $voiceLine = Get-DpDialogueVoiceLine `
            -VoiceAssignment $VoiceAssignment `
            -StringName ([string]$Response.key)
        $responseAttributes += ' StartDelay="0.3' +
            '" ReferenceLength="' +
            [string]$voiceLine.referenceLength + '"'
    }
    $Lines.Add("$Indent<Response $responseAttributes>")
    $Lines.Add(
        "$Indent  <Text StringName=`"$($Response.key)`" />"
    )
    $Lines.Add(
        "$Indent  <Commands><CameraCommand CameraType=`"CloseUp`" /></Commands>"
    )
    $Lines.Add("$Indent</Response>")
}

function Add-DpDialogueSequenceXml {
    param(
        [Parameter(Mandatory)]$Lines,
        [Parameter(Mandatory)][object[]]$Responses,
        [Parameter(Mandatory)][int]$StartIndex,
        [Parameter(Mandatory)][string]$SequenceName,
        [AllowEmptyString()][string]$EntryCondition,
        [AllowEmptyString()][string]$PromptKey,
        [Parameter(Mandatory)]$Binding,
        $VoiceAssignment,
        [Parameter(Mandatory)][string]$Indent,
        [switch]$Root
    )

    if ($StartIndex -lt 0 -or $StartIndex -ge $Responses.Count) {
        throw "Dialogue sequence '$SequenceName' has no response at $StartIndex."
    }
    $entryAttribute = if (Test-DpTextValue $EntryCondition) {
        " EntryCondition=`"$EntryCondition`""
    } else { '' }
    $Lines.Add(
        "$Indent<Sequence EndType=`"EndDialogue`"$entryAttribute Name=`"$SequenceName`">"
    )
    if ($Root -and (Test-DpTextValue $PromptKey)) {
        $Lines.Add("$Indent  <UiPrompt StringName=`"$PromptKey`" />")
    }
    if ($Root) {
        $Lines.Add("$Indent  <Triggers>")
        $Lines.Add("$Indent    <Port Name=`"heard`" />")
        $Lines.Add("$Indent  </Triggers>")
    }
    $Lines.Add("$Indent  <Elements>")
    for ($index = $StartIndex; $index -lt $Responses.Count; $index++) {
        Add-DpDialogueResponseXml `
            -Lines $Lines -Response $Responses[$index] -Binding $Binding `
            -VoiceAssignment $VoiceAssignment -Indent "$Indent    "
    }
    $Lines.Add("$Indent  </Elements>")
    $Lines.Add("$Indent</Sequence>")
}

function ConvertTo-DpDialogueXml {
    param(
        [Parameter(Mandatory)]$Dialogue,
        [Parameter(Mandatory)]$Binding,
        [object[]]$Variants = @(),
        $VoiceAssignment
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
    $lines.Add('        <Port Name="actor_selected" Direction="In" Type="bool">')
    $lines.Add('          <DesignName Text="Selected case actor" />')
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
    if ($null -ne $VoiceAssignment -and
        @($VoiceAssignment.selectedSouls).Count -gt 0) {
        $lines.Add('        <SelectedSouls>')
        foreach ($selectedSoul in @($VoiceAssignment.selectedSouls)) {
            $attributes = [System.Collections.Generic.List[string]]::new()
            $attributes.Add(
                'Role="' +
                (ConvertTo-DpXmlText ([string]$selectedSoul.role)) + '"'
            )
            $attributes.Add(
                'Voice="' +
                (ConvertTo-DpXmlText ([string]$selectedSoul.voice)) + '"'
            )
            if (Test-DpTextValue $selectedSoul.soul) {
                $attributes.Add(
                    'Soul="' +
                    (ConvertTo-DpXmlText ([string]$selectedSoul.soul)) + '"'
                )
            }
            $attributes.Add(
                'Type="' +
                (ConvertTo-DpXmlText ([string]$selectedSoul.type)) + '"'
            )
            $attributes.Add(
                'Language="' +
                (ConvertTo-DpXmlText ([string]$selectedSoul.language)) + '"'
            )
            $lines.Add(
                '          <SelectedSoul ' + ($attributes -join ' ') + ' />'
            )
        }
        $lines.Add('        </SelectedSouls>')
    }
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
            "Port('available') AND Port('actor_selected') AND Port('$($sequence.port_name)')"
        }
        else { "Port('available') AND Port('actor_selected')" }
        Add-DpDialogueSequenceXml `
            -Lines $lines -Responses @($sequence.responses) -StartIndex 0 `
            -SequenceName ([string]$sequence.sequence_name) `
            -EntryCondition $entryCondition `
            -PromptKey ([string]$sequence.prompt_key) `
            -Binding $Binding -VoiceAssignment $VoiceAssignment `
            -Indent '            ' -Root
    }
    $lines.Add('          </Sequences>')
    $lines.Add('        </Decision>')
    $lines.Add('      </Dialogue>')
    $lines.Add('    </FaderDialog>')
    $lines.Add('  </Skald>')
    $lines.Add('</Database>')
    return ($lines -join "`n") + "`n"
}

function Read-DpDialogueVoiceRegistry {
    param([Parameter(Mandatory)][string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "Dialogue voice registry not found: $LiteralPath"
    }
    $registry = [System.IO.File]::ReadAllText($LiteralPath) |
        ConvertFrom-Json -Depth 100
    if ([int]$registry.schemaVersion -ne 1) {
        throw "Dialogue voice registry schemaVersion must be 1: $LiteralPath"
    }

    $profileIds = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($profile in @($registry.voiceProfiles)) {
        $profileId = [string]$profile.id
        if (-not (Test-DpTextValue $profileId) -or
            -not $profileIds.Add($profileId)) {
            throw "Dialogue voice profile id is empty or duplicated: '$profileId'."
        }
        foreach ($field in @(
            'voice', 'assetPrefix', 'rig', 'type', 'language'
        )) {
            if (-not (Test-DpTextValue $profile.$field)) {
                throw "Dialogue voice profile '$profileId' has no '$field'."
            }
        }
        if ([string]$profile.rig -cnotin @(
            'human_male', 'human_female'
        )) {
            throw "Dialogue voice profile '$profileId' has unsupported rig " +
                "'$($profile.rig)'."
        }
        $actorRoleProperty = $profile.actor.PSObject.Properties['role']
        $entityNameProperty =
            $profile.actor.PSObject.Properties['entityName']
        $actorRole = if ($null -ne $actorRoleProperty) {
            [string]$actorRoleProperty.Value
        } else { '' }
        $entityName = if ($null -ne $entityNameProperty) {
            [string]$entityNameProperty.Value
        } else { '' }
        if ((Test-DpTextValue $actorRole) -eq
            (Test-DpTextValue $entityName)) {
            throw "Dialogue voice profile '$profileId' must select exactly " +
                'one actor role or entityName.'
        }
    }

    $assignmentKeys = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($assignment in @($registry.dialogueAssignments)) {
        foreach ($field in @(
            'storyId', 'region', 'settlement', 'dialogueKind',
            'packageLanguage'
        )) {
            if (-not (Test-DpTextValue $assignment.$field)) {
                throw "Dialogue voice assignment has no '$field'."
            }
        }
        $assignmentKey = @(
            [string]$assignment.storyId,
            [string]$assignment.region,
            [string]$assignment.settlement,
            [string]$assignment.dialogueKind
        ) -join '|'
        if (-not $assignmentKeys.Add($assignmentKey)) {
            throw "Dialogue voice assignment is duplicated: $assignmentKey."
        }
        foreach ($speaker in $assignment.speakers.PSObject.Properties) {
            if (-not $profileIds.Contains([string]$speaker.Value)) {
                throw "Dialogue voice assignment '$assignmentKey' uses " +
                    "unknown profile '$($speaker.Value)'."
            }
        }
        if ([string]$assignment.packageLanguage -cne 'english' -or
            [string]$assignment.media.voice -cne 'native' -or
            [bool]$assignment.media.lipSync -ne $true) {
            throw "Dialogue voice assignment '$assignmentKey' must request " +
                'English native voice with lipSync enabled.'
        }
    }
    return $registry
}

function Read-DpDialogueMediaReferenceLengths {
    param(
        [Parameter(Mandatory)][string]$JobsManifestPath,
        [Parameter(Mandatory)][string]$ResultsManifestPath
    )

    foreach ($path in @($JobsManifestPath, $ResultsManifestPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Dialogue media manifest not found: $path"
        }
    }
    $jobsManifest = [System.IO.File]::ReadAllText($JobsManifestPath) |
        ConvertFrom-Json -Depth 100
    $resultsManifest = [System.IO.File]::ReadAllText($ResultsManifestPath) |
        ConvertFrom-Json -Depth 100
    if ([int]$jobsManifest.schemaVersion -ne 1 -or
        [string]$jobsManifest.game -cne 'kcd2' -or
        [string]$jobsManifest.packageLanguage -cne 'english') {
        throw 'Dialogue media jobs manifest must be KCD2 schema 1 in English.'
    }
    if ([int]$resultsManifest.schemaVersion -ne 1 -or
        [string]$resultsManifest.status -cne 'complete') {
        throw 'Dialogue media results manifest is not complete.'
    }

    $jobsById = @{}
    foreach ($job in @($jobsManifest.jobs)) {
        $jobId = [string]$job.jobId
        if (-not (Test-DpTextValue $jobId) -or $jobsById.ContainsKey($jobId)) {
            throw "Dialogue media jobs contain duplicate id '$jobId'."
        }
        $jobsById[$jobId] = $job
    }
    $resultsById = @{}
    foreach ($result in @($resultsManifest.jobs)) {
        $jobId = [string]$result.jobId
        if (-not (Test-DpTextValue $jobId) -or
            $resultsById.ContainsKey($jobId)) {
            throw "Dialogue media results contain duplicate id '$jobId'."
        }
        $resultsById[$jobId] = $result
    }
    $jobIds = @($jobsById.Keys | Sort-Object)
    $resultIds = @($resultsById.Keys | Sort-Object)
    if (($jobIds -join "`n") -cne ($resultIds -join "`n")) {
        throw 'Dialogue media result coverage differs from resolved jobs.'
    }

    $lengths = @{}
    foreach ($jobId in $jobIds) {
        $job = $jobsById[$jobId]
        $result = $resultsById[$jobId]
        $duration = [decimal]$result.durationSeconds
        if ([string]$result.status -cne 'complete' -or $duration -le 0) {
            throw "Dialogue media result '$jobId' has no positive duration."
        }
        $folder = ([string]$job.audioFolder).Replace('\', '/').Trim('/')
        $stringName = [string]$job.stringName
        if ($folder -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or
            $stringName -notmatch '^[A-Za-z0-9_.-]+$') {
            throw "Dialogue media job '$jobId' has unsafe duration key."
        }
        $key = "$folder|$stringName"
        if (-not $lengths.ContainsKey($key) -or
            [decimal]$lengths[$key] -lt $duration) {
            $lengths[$key] = $duration
        }
    }
    return $lengths
}

function Get-DpDialogueMediaDemands {
    param(
        [Parameter(Mandatory)]$CaseSpec,
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$Settlement,
        [Parameter(Mandatory)]$Dialogue,
        [Parameter(Mandatory)]$Binding
    )

    $mediaProperty = $Dialogue.PSObject.Properties['media']
    if ($null -eq $mediaProperty) {
        throw "Dialogue '$($Dialogue.graphName)' must declare native voice " +
            'with lipSync enabled.'
    }
    $media = $mediaProperty.Value
    if ([string]$media.voice -cne 'native' -or
        [bool]$media.lipSync -ne $true) {
        throw "Dialogue '$($Dialogue.graphName)' media must request " +
            'native voice with lipSync enabled.'
    }
    $questName = [string]$CaseSpec.native.questName
    $regionsProperty = $CaseSpec.native.PSObject.Properties['regions']
    if ($null -ne $regionsProperty) {
        $regionProperty = $regionsProperty.Value.PSObject.Properties[$Region]
        if ($null -ne $regionProperty) {
            $questName = [string]$regionProperty.Value.questName
        }
    }
    if ($Region -notmatch '^[A-Za-z0-9_-]+$' -or
        $questName -notmatch '^[A-Za-z0-9_-]+$') {
        throw "Case '$($CaseSpec.id)' has invalid dialogue audio folder " +
            "'$Region/$questName'."
    }
    $audioFolder = "$Region/$questName"
    $responseRows = if (
        $null -ne $Dialogue.PSObject.Properties['variants']
    ) {
        @($Dialogue.variants | ForEach-Object { @($_.responses) })
    }
    else { @($Dialogue.responses) }
    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $demands = [System.Collections.Generic.List[object]]::new()
    foreach ($response in $responseRows) {
        $stringName = [string]$response.key
        $speakerRole = [string]$response.role
        $lineKey = "$speakerRole|$stringName"
        if (-not $seen.Add($lineKey)) { continue }
        $englishText = if (
            $CaseSpec.localization.en -is [System.Collections.IDictionary]
        ) {
            if ($CaseSpec.localization.en.Contains($stringName)) {
                [string]$CaseSpec.localization.en[$stringName]
            }
            else { '' }
        }
        else {
            $englishTextProperty =
                $CaseSpec.localization.en.PSObject.Properties[$stringName]
            if ($null -eq $englishTextProperty) { '' }
            else { [string]$englishTextProperty.Value }
        }
        if (-not (Test-DpTextValue $englishText)) {
            throw "Voice line '$stringName' has no English localization text."
        }

        $candidates = [System.Collections.Generic.List[object]]::new()
        if ($speakerRole -ceq 'HENRY') {
            $candidates.Add([pscustomobject][ordered]@{
                candidateOrder = 0
                actor = [pscustomobject][ordered]@{ role = 'HENRY' }
                dialogueRole = 'HENRY'
                actorKey = 'role-HENRY'
            })
        }
        else {
            $poolProperty = $null
            if ($null -ne $Binding.PSObject.Properties['actorPools']) {
                $poolProperty =
                    $Binding.actorPools.PSObject.Properties[$speakerRole]
            }
            $actorRows = if ($null -ne $poolProperty) {
                @($poolProperty.Value)
            }
            else {
                $roleProperty = $Binding.roles.PSObject.Properties[$speakerRole]
                if ($null -eq $roleProperty) { @() }
                else { @($roleProperty.Value) }
            }
            foreach ($actorRow in @($actorRows | Sort-Object `
                candidateOrder, entityName)) {
                $entityName = [string]$actorRow.entityName
                if (-not (Test-DpTextValue $entityName)) { continue }
                $orderProperty = $actorRow.PSObject.Properties['candidateOrder']
                $candidateOrder = if ($null -eq $orderProperty) {
                    0
                }
                else { [int]$orderProperty.Value }
                $candidates.Add([pscustomobject][ordered]@{
                    candidateOrder = $candidateOrder
                    actor = [pscustomobject][ordered]@{
                        entityName = $entityName
                    }
                    dialogueRole = [string]$actorRow.dialogueRole
                    actorKey = "entity-$entityName"
                })
            }
        }
        if ($candidates.Count -eq 0) {
            throw "Dialogue '$($Dialogue.graphName)' has no eligible actor " +
                "for speaker '$speakerRole' in $Region/$Settlement."
        }
        foreach ($candidate in $candidates) {
            $demands.Add([pscustomobject][ordered]@{
                demandId = @(
                    [string]$CaseSpec.id,
                    $Region,
                    $Settlement,
                    [string]$Dialogue.graphName,
                    $stringName,
                    [string]$candidate.actorKey
                ) -join '.'
                storyId = [string]$CaseSpec.id
                region = $Region
                settlement = $Settlement
                dialogueGraph = [string]$Dialogue.graphName
                stringName = $stringName
                text = $englishText
                speakerRole = $speakerRole
                candidateOrder = [int]$candidate.candidateOrder
                actor = $candidate.actor
                dialogueRole = [string]$candidate.dialogueRole
                audioFolder = $audioFolder
                media = [pscustomobject][ordered]@{
                    voice = 'native'
                    lipSync = $true
                }
            })
        }
    }
    return $demands.ToArray()
}

function Get-DpResolvedDialogueVoiceAssignment {
    param(
        $Registry,
        [Parameter(Mandatory)]$CaseSpec,
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$Settlement,
        [Parameter(Mandatory)]$Dialogue,
        [Parameter(Mandatory)]$Binding,
        $MediaReferenceLengths
    )

    $questName = [string]$CaseSpec.native.questName
    if ($Region -notmatch '^[A-Za-z0-9_-]+$' -or
        $questName -notmatch '^[A-Za-z0-9_-]+$') {
        throw "Case '$($CaseSpec.id)' has invalid dialogue audio folder " +
            "'$Region/$questName'."
    }
    $audioFolder = "$Region/$questName"

    if ($null -ne $MediaReferenceLengths -and
        $null -ne $Dialogue.PSObject.Properties['media']) {
        $responseRows = if (
            $null -ne $Dialogue.PSObject.Properties['variants']
        ) {
            @($Dialogue.variants | ForEach-Object { @($_.responses) })
        }
        else { @($Dialogue.responses) }
        $lines = [System.Collections.Generic.List[object]]::new()
        $seen = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        foreach ($response in $responseRows) {
            $stringName = [string]$response.key
            if (-not $seen.Add($stringName)) { continue }
            $key = "$audioFolder|$stringName"
            if (-not $MediaReferenceLengths.ContainsKey($key)) {
                throw "Dialogue media results have no duration for '$key'."
            }
            $duration = [decimal]$MediaReferenceLengths[$key]
            $lines.Add([ordered]@{
                stringName = $stringName
                referenceLength = $duration.ToString(
                    '0.###',
                    [System.Globalization.CultureInfo]::InvariantCulture
                )
            })
        }
        return [ordered]@{
            selectedSouls = @()
            lines = $lines.ToArray()
            assets = @()
            facialAssets = @()
            mediaJobs = @()
        }
    }

    if ($null -eq $Registry) { return $null }
    $matches = @($Registry.dialogueAssignments | Where-Object {
        [string]$_.storyId -ceq [string]$CaseSpec.id -and
        [string]$_.region -ceq $Region -and
        [string]$_.settlement -ceq $Settlement -and
        [string]$_.dialogueKind -ceq [string]$Dialogue.kind
    })
    if ($matches.Count -eq 0) { return $null }
    if ($matches.Count -ne 1) {
        throw "Dialogue '$($Dialogue.graphName)' has multiple voice assignments."
    }
    $assignment = $matches[0]

    $profiles = @{}
    foreach ($profile in @($Registry.voiceProfiles)) {
        $profiles[[string]$profile.id] = $profile
    }
    $responseRows = if (
        $null -ne $Dialogue.PSObject.Properties['variants']
    ) {
        @($Dialogue.variants | ForEach-Object { @($_.responses) })
    }
    else { @($Dialogue.responses) }
    $responseKeys = @($responseRows | ForEach-Object {
        [string]$_.key
    } | Sort-Object -Unique)
    $responseRoles = @($responseRows | ForEach-Object {
        [string]$_.role
    } | Sort-Object -Unique)
    $speakerNames = @($assignment.speakers.PSObject.Properties.Name)
    $missingSpeaker = @($responseRoles | Where-Object {
        [string]$_ -cnotin $speakerNames
    } | Select-Object -First 1)
    if ($missingSpeaker.Count -gt 0) {
        throw "Dialogue '$($Dialogue.graphName)' has no voice profile for " +
            "speaker '$($missingSpeaker[0])'."
    }

    $selectedSouls = [System.Collections.Generic.List[object]]::new()
    $resolvedProfiles = @{}
    foreach ($speaker in $assignment.speakers.PSObject.Properties) {
        $semanticRole = [string]$speaker.Name
        if ($semanticRole -cnotin $responseRoles) { continue }
        $profile = $profiles[[string]$speaker.Value]
        $resolvedRole = $semanticRole
        $actorRoleProperty = $profile.actor.PSObject.Properties['role']
        $entityNameProperty =
            $profile.actor.PSObject.Properties['entityName']
        $actorRole = if ($null -ne $actorRoleProperty) {
            [string]$actorRoleProperty.Value
        } else { '' }
        $entityName = if ($null -ne $entityNameProperty) {
            [string]$entityNameProperty.Value
        } else { '' }
        if (Test-DpTextValue $actorRole) {
            if ($actorRole -cne $semanticRole) {
                throw "Voice profile '$($profile.id)' selects role " +
                    "'$actorRole', not '$semanticRole'."
            }
        }
        else {
            $roleBinding = $Binding.roles.PSObject.Properties[$semanticRole]
            if ($null -eq $roleBinding -or
                [string]$roleBinding.Value.entityName -cne $entityName) {
                throw "Voice profile '$($profile.id)' actor '$entityName' " +
                    "does not match '$semanticRole' in $Region/$Settlement."
            }
            $resolvedRole = [string]$roleBinding.Value.dialogueRole
        }
        $resolvedProfiles[$semanticRole] = $profile
        $soulProperty = $profile.PSObject.Properties['soul']
        $selectedSouls.Add([ordered]@{
            role = $resolvedRole
            voice = [string]$profile.voice
            soul = if ($null -ne $soulProperty) {
                [string]$soulProperty.Value
            } else { '' }
            type = [string]$profile.type
            language = [string]$profile.language
        })
    }

    $registeredLines = @($assignment.lines)
    $registeredKeys = @($registeredLines | ForEach-Object {
        [string]$_.stringName
    })
    $duplicateLine = $registeredKeys | Group-Object | Where-Object {
        $_.Count -gt 1
    } | Select-Object -First 1
    if ($null -ne $duplicateLine) {
        throw "Dialogue '$($Dialogue.graphName)' voice line " +
            "'$($duplicateLine.Name)' is duplicated."
    }
    $missingLine = @($responseKeys | Where-Object {
        [string]$_ -cnotin $registeredKeys
    } | Select-Object -First 1)
    $extraLine = @($registeredKeys | Where-Object {
        [string]$_ -cnotin $responseKeys
    } | Select-Object -First 1)
    if ($missingLine.Count -gt 0 -or $extraLine.Count -gt 0) {
        throw "Dialogue '$($Dialogue.graphName)' voice line coverage differs " +
            'from its response keys.'
    }

    $lines = [System.Collections.Generic.List[object]]::new()
    $assets = [System.Collections.Generic.List[object]]::new()
    $facialAssets = [System.Collections.Generic.List[object]]::new()
    $mediaJobs = [System.Collections.Generic.List[object]]::new()
    foreach ($response in $responseRows) {
        $stringName = [string]$response.key
        $line = @($registeredLines | Where-Object {
            [string]$_.stringName -ceq $stringName
        })[0]
        $semanticRole = [string]$response.role
        $profile = $resolvedProfiles[$semanticRole]
        $sourceAsset = ([string]$line.asset).Replace('\', '/')
        if (-not (Test-DpTextValue $sourceAsset) -or
            [System.IO.Path]::IsPathRooted($sourceAsset) -or
            $sourceAsset -match '(^|/)\.\.(/|$)') {
            throw "Voice line '$stringName' has an unsafe asset path."
        }
        $expectedFileName =
            [string]$profile.assetPrefix + '_' + $stringName + '.ogg'
        $actualFileName = [System.IO.Path]::GetFileName(
            $sourceAsset.Replace('/', '\')
        )
        if ($actualFileName -cne $expectedFileName) {
            throw "Voice line '$stringName' asset must be named " +
                "'$expectedFileName'."
        }
        $referenceLength = [decimal]$line.referenceLength
        if ($referenceLength -le 0) {
            throw "Voice line '$stringName' referenceLength must be positive."
        }
        $formattedLength = $referenceLength.ToString(
            '0.##',
            [System.Globalization.CultureInfo]::InvariantCulture
        )
        $resolvedLine = [ordered]@{
            stringName = $stringName
            referenceLength = $formattedLength
        }
        $lines.Add($resolvedLine)
        $assets.Add([ordered]@{
            storyId = [string]$CaseSpec.id
            region = $Region
            settlement = $Settlement
            dialogueGraph = [string]$Dialogue.graphName
            audioFolder = $audioFolder
            stringName = $stringName
            voiceProfile = [string]$profile.id
            packageLanguage = [string]$assignment.packageLanguage
            sourceAsset = $sourceAsset
            destination = (
                'dialog/' + $audioFolder + '/' +
                $expectedFileName
            )
        })
        $englishTextProperty =
            $CaseSpec.localization.en.PSObject.Properties[$stringName]
        if ($null -eq $englishTextProperty -or
            -not (Test-DpTextValue ([string]$englishTextProperty.Value))) {
            throw "Voice line '$stringName' has no English localization text."
        }
        $mediaJobs.Add([ordered]@{
            jobId = @(
                [string]$CaseSpec.id,
                $Settlement,
                $stringName,
                [string]$profile.assetPrefix
            ) -join '.'
            storyId = [string]$CaseSpec.id
            dialogueGraph = [string]$Dialogue.graphName
            stringName = $stringName
            text = [string]$englishTextProperty.Value
            voiceProfile = [string]$profile.id
            assetPrefix = [string]$profile.assetPrefix
            rig = [string]$profile.rig
            audioFolder = $audioFolder
            media = [ordered]@{
                voice = [string]$assignment.media.voice
                lipSync = [bool]$assignment.media.lipSync
            }
        })
    }
    return [ordered]@{
        selectedSouls = $selectedSouls.ToArray()
        lines = $lines.ToArray()
        assets = $assets.ToArray()
        facialAssets = $facialAssets.ToArray()
        mediaJobs = $mediaJobs.ToArray()
    }
}

function ConvertTo-DpCaseNamespacedNodeFragment {
    param(
        [AllowEmptyString()][string]$Xml,
        [Parameter(Mandatory)][string]$Prefix
    )

    if ([string]::IsNullOrWhiteSpace($Xml)) { return $Xml }
    $document = [System.Xml.XmlDocument]::new()
    $document.PreserveWhitespace = $true
    $document.LoadXml("<Root>`n$Xml`n</Root>")
    $names = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($node in @($document.DocumentElement.ChildNodes)) {
        if ($node.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
        $name = $node.GetAttribute('Name')
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $null = $names.Add($name)
        }
    }
    $result = $Xml
    foreach ($name in @($names | Sort-Object Length -Descending)) {
        $qualified = $Prefix + '_' + $name
        $result = $result.Replace("Name=`"$name`"", "Name=`"$qualified`"")
        $result = $result.Replace("From=`"$name.", "From=`"$qualified.")
        $result = $result.Replace("To=`"$name.", "To=`"$qualified.")
    }
    return $result
}

function Get-DpNativeSettlementToken {
    param([Parameter(Mandatory)][string]$Settlement)

    $token = $Settlement -replace '[^A-Za-z0-9_]', '_'
    if ($token -match '^[0-9]') { $token = "s_$token" }
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "Native settlement id '$Settlement' has no usable token."
    }
    return $token
}

function Copy-DpSettlementScopedDialogue {
    param(
        [Parameter(Mandatory)]$Dialogue,
        [Parameter(Mandatory)][int]$CaseCode,
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$Settlement,
        [string]$ScopeSuffix = ''
    )

    $copy = $Dialogue | ConvertTo-Json -Depth 100 |
        ConvertFrom-Json -Depth 100
    $regionToken = Get-DpNativeSettlementToken -Settlement $Region
    $settlementToken = Get-DpNativeSettlementToken -Settlement $Settlement
    $suffixToken = if ([string]::IsNullOrWhiteSpace($ScopeSuffix)) { '' } else {
        '_' + (Get-DpNativeSettlementToken -Settlement $ScopeSuffix)
    }
    $prefix = "dpcase${CaseCode}_${regionToken}_${settlementToken}${suffixToken}_"
    $copy.graphName = $prefix + [string]$copy.graphName
    $copy.fileName = $prefix + [string]$copy.fileName
    return $copy
}

function ConvertTo-DpNativeRegionWiring {
    param(
        [Parameter(Mandatory)]$CaseSpec,
        [Parameter(Mandatory)]
        [Alias('Binding')]
        [object[]]$Bindings,
        [string]$Region = '',
        $NativeRegion,
        $CaseActivationSignal,
        [object[]]$ActorSelectionSignals = @(),
        $VoiceRegistry,
        $MediaReferenceLengths
    )

    $Bindings = @($Bindings | Sort-Object settlement)
    if ($Bindings.Count -eq 0) {
        throw "Case '$($CaseSpec.id)' has no native binding for region '$Region'."
    }
    $primaryBinding = $Bindings[0]
    $CaseSpec = $CaseSpec | ConvertTo-Json -Depth 100 |
        ConvertFrom-Json -Depth 100
    if ([string]::IsNullOrWhiteSpace($Region)) {
        $Region = [string]$CaseSpec.constraints.region
    }
    $CaseSpec.constraints.region = $Region
    $CaseSpec.constraints.settlement = [string]$primaryBinding.settlement
    if ($null -eq $NativeRegion -and
        $null -ne $CaseSpec.native.PSObject.Properties['regions']) {
        $NativeRegion = $CaseSpec.native.regions.PSObject.Properties[
            $Region
        ].Value
    }
    if ($null -ne $NativeRegion) {
        $CaseSpec.native.questName = [string]$NativeRegion.questName
        $CaseSpec.native.dialogFolder = [string]$NativeRegion.dialogFolder
    }
    foreach ($property in $CaseSpec.native.contexts.PSObject.Properties) {
        $property.Value = ([string]$property.Value) -replace
            '_(kutnohorsko|trosecko)$', "_$Region"
    }
    $native = $CaseSpec.native
    $rumor = @($native.dialogues | Where-Object kind -eq 'rumor')
    $witness = @($native.dialogues | Where-Object kind -eq 'witness')
    if ($rumor.Count -ne 1 -or $witness.Count -ne 1) {
        throw "Case '$($CaseSpec.id)' requires one rumor and one witness dialogue."
    }
    $rumor = $rumor[0]
    $witness = $witness[0]
    $folder = [string]$native.dialogFolder
    $caseCode = [int]$CaseSpec.code
    $nodePrefix = "case$caseCode"
    if ($null -eq $CaseActivationSignal) {
        $CaseActivationSignal = [pscustomobject][ordered]@{
            case_id = [string]$CaseSpec.id
            case_code = $caseCode
            signal_tag = 122
            signal_name = "dp_case_active_$caseCode"
            buff_guid = Get-DpStableGuid `
                -Seed "darkpassenger-case-active-$caseCode"
        }
    }
    if (@($ActorSelectionSignals).Count -eq 0) {
        $ActorSelectionSignals = @(Get-DpActorSelectionSignals `
            -CaseSpecs @($CaseSpec) -StartSignalTag 151 -MaxSignalTag 179)
    }
    $actorSelectionByRole = @{}
    foreach ($semanticRole in 'innkeeper', 'witness') {
        $matches = @($ActorSelectionSignals | Where-Object {
            [int]$_.case_code -eq $caseCode -and
            [string]$_.semantic_role -eq $semanticRole
        })
        if ($matches.Count -ne 1) {
            throw "Case '$($CaseSpec.id)' requires exactly one actor-selection signal for '$semanticRole'."
        }
        $actorSelectionByRole[$semanticRole] = $matches[0]
    }
    $caseActiveNodes = @"
        <MakeArray Name="${nodePrefix}ActiveTags" TypeT="wh::rpgmodule::BuffDefinitionAITags">
          <Constant Name="A" Value="$([int]$CaseActivationSignal.signal_tag)" />
        </MakeArray>
        <MakeArray Name="${nodePrefix}ActiveSouls" TypeT="wh::rpgmodule::Souls">
          <Asset Name="A" Alias="player" />
        </MakeArray>
        <Function Name="${nodePrefix}ActiveTagCheck" MethodName="wh::rpgmodule::BuffTagCheck" DeclaringType="wh::rpgmodule">
          <Constant Name="BuffTag" Value="$([int]$CaseActivationSignal.signal_tag)" />
          <Edge From="${nodePrefix}ActiveSouls.Array" To="Souls" />
        </Function>
        <If Name="${nodePrefix}ActivePhaseGate">
          <Edge From="${nodePrefix}ActiveTagCheck.HaveBuffTag" To="Condition" />
          <Edge From="questProgress.OnActive" To="Exec" />
        </If>
        <BuffTagTrigger Name="${nodePrefix}ActiveTrigger">
          <Asset Name="Souls" Alias="player" />
          <Edge From="${nodePrefix}ActiveTags.Array" To="BuffTags" />
          <Edge From="questProgress.Active" To="IsActive" />
        </BuffTagTrigger>
        <State Name="${nodePrefix}Active" TypeT="bool">
          <Edge From="${nodePrefix}ActiveTrigger.OnAdded" To="SetTrue" />
          <Edge From="${nodePrefix}ActivePhaseGate.True" To="SetTrue" />
          <Edge From="${nodePrefix}ActiveTrigger.OnRemoved" To="SetFalse" />
          <Edge From="satisfactionTrigger.OnAdded" To="SetFalse" />
        </State>
"@
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
        $fallbackText = ConvertTo-DpXmlText ([string]$journalState.fallback)
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

    $definitionFiles = [System.Collections.Generic.List[string]]::new()
    $compiledDialogues = [System.Collections.Generic.List[object]]::new()
    $settlementModules = [System.Collections.Generic.List[object]]::new()
    $rumorBindingNodes = [System.Collections.Generic.List[string]]::new()
    $witnessBindingNodes = [System.Collections.Generic.List[string]]::new()
    $rumorHeardEdges = [System.Collections.Generic.List[string]]::new()
    $witnessHeardEdges = [System.Collections.Generic.List[string]]::new()

    foreach ($binding in $Bindings) {
        $settlement = [string]$binding.settlement
        $bindingToken = Get-DpNativeSettlementToken -Settlement $settlement
        $targetSlotValues = if (
            $null -ne $binding.PSObject.Properties['targetCandidateSlots']
        ) {
            @($binding.targetCandidateSlots)
        } else {
            @()
        }
        $targetSlots = @($targetSlotValues | ForEach-Object {
            [int]$_
        } | Sort-Object -Unique)

        $scopedRumor = Copy-DpSettlementScopedDialogue `
            -Dialogue $rumor -CaseCode $caseCode -Region $Region `
            -Settlement $settlement
        $scopedWitness = Copy-DpSettlementScopedDialogue `
            -Dialogue $witness -CaseCode $caseCode -Region $Region `
            -Settlement $settlement
        $rumorVoice = Get-DpResolvedDialogueVoiceAssignment `
            -Registry $VoiceRegistry -CaseSpec $CaseSpec -Region $Region `
            -Settlement $settlement -Dialogue $scopedRumor -Binding $binding `
            -MediaReferenceLengths $MediaReferenceLengths
        $witnessVoice = Get-DpResolvedDialogueVoiceAssignment `
            -Registry $VoiceRegistry -CaseSpec $CaseSpec -Region $Region `
            -Settlement $settlement -Dialogue $scopedWitness -Binding $binding `
            -MediaReferenceLengths $MediaReferenceLengths
        foreach ($dialogue in @($scopedRumor, $scopedWitness)) {
            $definitionFiles.Add("$folder/$([string]$dialogue.fileName)")
        }
        $compiledDialogues.Add([ordered]@{
            settlement = $settlement
            graphName = [string]$scopedRumor.graphName
            fileName = [string]$scopedRumor.fileName
            voiceAssets = if ($null -ne $rumorVoice) {
                @($rumorVoice.assets)
            } else { @() }
            facialAssets = if ($null -ne $rumorVoice) {
                @($rumorVoice.facialAssets)
            } else { @() }
            mediaJobs = if ($null -ne $rumorVoice) {
                @($rumorVoice.mediaJobs)
            } else { @() }
            xml = ConvertTo-DpDialogueXml -Dialogue $scopedRumor `
                -Binding $binding -Variants $rumorVariants `
                -VoiceAssignment $rumorVoice
        })
        $compiledDialogues.Add([ordered]@{
            settlement = $settlement
            graphName = [string]$scopedWitness.graphName
            fileName = [string]$scopedWitness.fileName
            voiceAssets = if ($null -ne $witnessVoice) {
                @($witnessVoice.assets)
            } else { @() }
            facialAssets = if ($null -ne $witnessVoice) {
                @($witnessVoice.facialAssets)
            } else { @() }
            mediaJobs = if ($null -ne $witnessVoice) {
                @($witnessVoice.mediaJobs)
            } else { @() }
            xml = ConvertTo-DpDialogueXml -Dialogue $scopedWitness `
                -Binding $binding -VoiceAssignment $witnessVoice
        })

        $rumorDialogueRole = ConvertTo-DpXmlText (
            [string]$binding.roles.innkeeper.dialogueRole
        )
        $witnessDialogueRole = ConvertTo-DpXmlText (
            [string]$binding.roles.witness.dialogueRole
        )
        $rumorSelectionTag = [int]$actorSelectionByRole['innkeeper'].signal_tag
        $witnessSelectionTag = [int]$actorSelectionByRole['witness'].signal_tag

        $bindingActiveEdges = [System.Collections.Generic.List[string]]::new()
        $rumorTargetGates = [System.Collections.Generic.List[string]]::new()
        $rumorTargetEdges = [System.Collections.Generic.List[string]]::new()
        $witnessTargetGates = [System.Collections.Generic.List[string]]::new()
        $witnessTargetEdges = [System.Collections.Generic.List[string]]::new()
        if ($targetSlots.Count -eq 0) {
            $bindingActiveEdges.Add(
                "          <Edge From=`"${nodePrefix}ActiveTrigger.OnAdded`" To=`"SetTrue`" />"
            )
            $bindingActiveEdges.Add(
                "          <Edge From=`"${nodePrefix}ActivePhaseGate.True`" To=`"SetTrue`" />"
            )
        }
        foreach ($targetSlot in $targetSlots) {
            $slotNode = 'targetSlot{0:D3}' -f $targetSlot
            $bindingGate = "${bindingToken}BindingGate$targetSlot"
            $bindingPhaseGate =
                "${bindingToken}BindingPhaseGate$targetSlot"
            $rumorGate = "${bindingToken}RumorTargetGate$targetSlot"
            $witnessGate = "${bindingToken}WitnessTargetGate$targetSlot"
            $rumorBindingNodes.Add(@"
        <If Name="$bindingGate">
          <Edge From="${nodePrefix}Active.State" To="Condition" />
          <Edge From="${slotNode}Tagged.True" To="Exec" />
        </If>
        <If Name="$bindingPhaseGate">
          <Edge From="${slotNode}TagState.State" To="Condition" />
          <Edge From="${nodePrefix}ActiveTrigger.OnAdded" To="Exec" />
          <Edge From="${nodePrefix}ActivePhaseGate.True" To="Exec" />
        </If>
"@.TrimEnd())
            $bindingActiveEdges.Add(
                "          <Edge From=`"$bindingGate.True`" To=`"SetTrue`" />"
            )
            $bindingActiveEdges.Add(
                "          <Edge From=`"$bindingPhaseGate.True`" To=`"SetTrue`" />"
            )
            $rumorTargetGates.Add(@"
        <If Name="$rumorGate">
          <Edge From="rumorDialogueAvailable.State" To="Condition" />
          <Edge From="$bindingGate.True" To="Exec" />
          <Edge From="$bindingPhaseGate.True" To="Exec" />
        </If>
"@.TrimEnd())
            $rumorTargetEdges.Add(
                "          <Edge From=`"$rumorGate.True`" To=`"SetTrue`" />"
            )
            $witnessTargetGates.Add(@"
        <If Name="$witnessGate">
          <Edge From="witnessDialogueAvailable.State" To="Condition" />
          <Edge From="${nodePrefix}_$bindingGate.True" To="Exec" />
          <Edge From="${nodePrefix}_$bindingPhaseGate.True" To="Exec" />
        </If>
"@.TrimEnd())
            $witnessTargetEdges.Add(
                "          <Edge From=`"$witnessGate.True`" To=`"SetTrue`" />"
            )
        }

        $rumorBindingNodes.Add(@"
        <State Name="${bindingToken}BindingActive" TypeT="bool">
$($bindingActiveEdges -join "`n")
          <Edge From="${nodePrefix}ActiveTrigger.OnRemoved" To="SetFalse" />
          <Edge From="satisfactionTrigger.OnAdded" To="SetFalse" />
        </State>
$($rumorTargetGates -join "`n")
        <If Name="${bindingToken}RumorPhaseGate">
          <Edge From="${bindingToken}BindingActive.State" To="Condition" />
          <Edge From="rumorAvailableTrigger.OnAdded" To="Exec" />
        </If>
        <State Name="${bindingToken}RumorAvailable" TypeT="bool">
$($rumorTargetEdges -join "`n")
          <Edge From="${bindingToken}RumorPhaseGate.True" To="SetTrue" />
          <Edge From="rumorAvailableTrigger.OnRemoved" To="SetFalse" />
          <Edge From="firstLeadTrigger.OnAdded" To="SetFalse" />
          <Edge From="satisfactionTrigger.OnAdded" To="SetFalse" />
          <Edge From="cleanResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="controlledResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="noisyResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="externalResultTrigger.OnAdded" To="SetFalse" />
        </State>
        <$($scopedRumor.graphName) Name="${bindingToken}InnkeeperRumorDialog">
          <Edge From="${bindingToken}RumorAvailable.State" To="available" />
          <Edge From="${bindingToken}InnkeeperSelectionCheck.HaveBuffTag" To="actor_selected" />
$rumorVariantPortEdgeXml
        </$($scopedRumor.graphName)>
        <MakeArray Name="${bindingToken}InnkeeperSelectedSouls" TypeT="wh::rpgmodule::Souls">
          <Edge From="${bindingToken}InnkeeperRumorDialog.$rumorDialogueRole" To="A" />
        </MakeArray>
        <Function Name="${bindingToken}InnkeeperSelectionCheck" MethodName="wh::rpgmodule::BuffTagCheck" DeclaringType="wh::rpgmodule">
          <Constant Name="BuffTag" Value="$rumorSelectionTag" />
          <Edge From="${bindingToken}InnkeeperSelectedSouls.Array" To="Souls" />
        </Function>
"@.TrimEnd())
        $rumorHeardEdges.Add(
            "          <Edge From=`"${bindingToken}InnkeeperRumorDialog.heard`" To=`"SetTrue`" />"
        )

        $witnessBindingNodes.Add(@"
$($witnessTargetGates -join "`n")
        <If Name="${bindingToken}WitnessPhaseGate">
          <Edge From="${nodePrefix}_${bindingToken}BindingActive.State" To="Condition" />
          <Edge From="witnessAvailableTrigger.OnAdded" To="Exec" />
        </If>
        <State Name="${bindingToken}WitnessAvailable" TypeT="bool">
$($witnessTargetEdges -join "`n")
          <Edge From="${bindingToken}WitnessPhaseGate.True" To="SetTrue" />
          <Edge From="witnessAvailableTrigger.OnRemoved" To="SetFalse" />
          <Edge From="revealTagTrigger.OnAdded" To="SetFalse" />
          <Edge From="satisfactionTrigger.OnAdded" To="SetFalse" />
          <Edge From="cleanResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="controlledResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="noisyResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="externalResultTrigger.OnAdded" To="SetFalse" />
        </State>
        <$($scopedWitness.graphName) Name="${bindingToken}TavernWitnessDialog">
          <Edge From="${bindingToken}WitnessAvailable.State" To="available" />
          <Edge From="${bindingToken}WitnessSelectionCheck.HaveBuffTag" To="actor_selected" />
        </$($scopedWitness.graphName)>
        <MakeArray Name="${bindingToken}WitnessSelectedSouls" TypeT="wh::rpgmodule::Souls">
          <Edge From="${bindingToken}TavernWitnessDialog.$witnessDialogueRole" To="A" />
        </MakeArray>
        <Function Name="${bindingToken}WitnessSelectionCheck" MethodName="wh::rpgmodule::BuffTagCheck" DeclaringType="wh::rpgmodule">
          <Constant Name="BuffTag" Value="$witnessSelectionTag" />
          <Edge From="${bindingToken}WitnessSelectedSouls.Array" To="Souls" />
        </Function>
"@.TrimEnd())
        $witnessHeardEdges.Add(
            "          <Edge From=`"${bindingToken}TavernWitnessDialog.heard`" To=`"SetTrue`" />"
        )

        $settlementModules.Add([ordered]@{
            settlement = $settlement
            targetCandidateSlots = $targetSlots
            roles = $binding.roles
            dialogues = @($compiledDialogues | Where-Object {
                [string]$_.settlement -eq $settlement
            })
        })
    }

    $definitionLines = @($definitionFiles | Sort-Object -Unique |
        ForEach-Object { "        <Definition File=`"$_`" />" })
    $definitions = @(
        '      <Definitions>',
        ($definitionLines -join "`n"),
        '      </Definitions>'
    ) -join "`n"
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
$($rumorBindingNodes -join "`n")
        <State Name="rumorDialogueRequestActive" TypeT="bool">
          <Edge From="questProgress.OnActive" To="SetFalse" />
$($rumorHeardEdges -join "`n")
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
$($witnessBindingNodes -join "`n")
        <State Name="witnessDialogueRequestActive" TypeT="bool">
          <Edge From="questProgress.OnActive" To="SetFalse" />
$($witnessHeardEdges -join "`n")
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

    $evidenceStateEdges = $evidenceStateEdges -join "`n"
    foreach ($fragmentName in @(
        'rumorNodes', 'witnessNodes', 'evidenceStateNodes'
    )) {
        $value = Get-Variable -Name $fragmentName -ValueOnly
        $value = ConvertTo-DpCaseNamespacedNodeFragment `
            -Xml ([string]$value) -Prefix $nodePrefix
        $value = $value.Replace(
            'From="questProgress.Active" To="IsActive"',
            "From=`"${nodePrefix}Active.State`" To=`"IsActive`""
        )
        Set-Variable -Name $fragmentName -Value $value
    }
    foreach ($journalState in $journalStates) {
        $triggerName = 'leadStateTrigger' + [int]$journalState.code
        $evidenceStateEdges = $evidenceStateEdges.Replace(
            "From=`"$triggerName.",
            "From=`"${nodePrefix}_$triggerName."
        )
    }
    $rumorNodes = $caseActiveNodes.TrimEnd() + "`n" + $rumorNodes

    return [ordered]@{
        caseId = [string]$CaseSpec.id
        caseCode = $caseCode
        region = $Region
        settlement = [string]$CaseSpec.constraints.settlement
        questName = [string]$native.questName
        dialogFolder = $folder
        dialogDefinitions = $definitions.TrimEnd()
        rumorNodes = $rumorNodes.TrimEnd()
        witnessNodes = $witnessNodes.TrimEnd()
        evidenceStateNodes = $evidenceStateNodes -join "`n"
        evidenceStateEdges = $evidenceStateEdges
        evidenceType = $evidenceTypeEnums -join "`n"
        evidenceLogs = $evidenceLogs -join "`n"
        journalStates = $journalStates
        journalObjectives = if (
            $null -ne $native.PSObject.Properties['journal']
        ) { $native.journal.objectives } else { $null }
        caseActivationSignal = $CaseActivationSignal
        evidenceWitnessEdge = ''
        witnessObjectiveNodes = ''
        witnessType = ''
        witnessObjective = ''
        settlementModules = $settlementModules.ToArray()
        dialogues = $compiledDialogues.ToArray()
    }
}

function ConvertTo-DpNativeRegionBundle {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Modules
    )

    if ($Modules.Count -lt 1) {
        throw 'Native regional bundle requires at least one story module.'
    }
    $Modules = @($Modules | Sort-Object caseCode, caseId)
    $region = [string]$Modules[0].region
    $questName = [string]$Modules[0].questName
    $dialogFolder = [string]$Modules[0].dialogFolder
    foreach ($module in $Modules) {
        if ([string]$module.region -ne $region -or
            [string]$module.questName -ne $questName -or
            [string]$module.dialogFolder -ne $dialogFolder) {
            throw "Native story module '$($module.caseId)' does not belong to " +
                "regional shell '$region/$questName/$dialogFolder'."
        }
    }
    $duplicateCase = $Modules | Group-Object { [string]$_.caseId } |
        Where-Object Count -gt 1 | Select-Object -First 1
    if ($null -ne $duplicateCase) {
        throw "Region '$region' contains duplicate case '$($duplicateCase.Name)'."
    }

    $dialogueCandidates = @($Modules | ForEach-Object { @($_.dialogues) })
    $bundleDialogues = [System.Collections.Generic.List[object]]::new()
    foreach ($group in @($dialogueCandidates | Group-Object {
        [string]$_.fileName
    })) {
        $fileName = [string]$group.Name
        $payloads = @($group.Group | Group-Object { [string]$_.xml })
        if ($payloads.Count -gt 1) {
            throw "Regional dialogue file '$fileName' conflicts between " +
                "StoryPack modules in '$region'."
        }
        $bundleDialogues.Add($group.Group[0])
    }
    foreach ($group in @($bundleDialogues | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.graphName)
    } | Group-Object { [string]$_.graphName })) {
        if ($group.Count -gt 1) {
            throw "Regional dialogue graph '$($group.Name)' conflicts between " +
                "StoryPack modules in '$region'."
        }
    }

    $definitionFiles = @($Modules | ForEach-Object {
        [regex]::Matches(
            [string]$_.dialogDefinitions,
            '<Definition\s+File="([^"]+)"\s*/>'
        ) | ForEach-Object { [string]$_.Groups[1].Value }
    } | Sort-Object -Unique)
    $definitionLines = @($definitionFiles | ForEach-Object {
        "        <Definition File=`"$_`" />"
    })
    $definitions = @(
        '      <Definitions>',
        ($definitionLines -join "`n"),
        '      </Definitions>'
    ) -join "`n"

    return [ordered]@{
        caseIds = @($Modules | ForEach-Object { [string]$_.caseId })
        region = $region
        settlement = [string]$Modules[0].settlement
        questName = $questName
        dialogFolder = $dialogFolder
        dialogDefinitions = $definitions
        rumorNodes = @($Modules | ForEach-Object {
            [string]$_.rumorNodes
        }) -join "`n"
        witnessNodes = @($Modules | ForEach-Object {
            [string]$_.witnessNodes
        }) -join "`n"
        evidenceStateNodes = @($Modules | ForEach-Object {
            [string]$_.evidenceStateNodes
        }) -join "`n"
        evidenceStateEdges = [string]$Modules[0].evidenceStateEdges
        evidenceType = [string]$Modules[0].evidenceType
        evidenceLogs = [string]$Modules[0].evidenceLogs
        journalStates = @($Modules[0].journalStates)
        journalObjectives = $Modules[0].journalObjectives
        storyModules = $Modules
        caseActivationSignals = @($Modules | ForEach-Object {
            $_.caseActivationSignal
        })
        evidenceWitnessEdge = ''
        witnessObjectiveNodes = ''
        witnessType = ''
        witnessObjective = ''
        dialogues = $bundleDialogues.ToArray()
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
        $name = "dp_journal_state_$([int]$state.code)"
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
        $name = "dp_journal_state_$code"
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

function ConvertTo-DpCaseActivationTagXml {
    param(
        [Parameter(Mandatory)][string]$BaseXml,
        [Parameter(Mandatory)][object[]]$Signals
    )

    $additions = [System.Collections.Generic.List[string]]::new()
    foreach ($signal in @($Signals | Sort-Object case_code)) {
        $tag = [int]$signal.signal_tag
        $name = [string]$signal.signal_name
        $idMatch = [regex]::Match(
            $BaseXml,
            "<buff_ai_tag\s+[^>]*buff_ai_tag_id=`"$tag`"[^>]*/>"
        )
        if ($idMatch.Success) {
            if (-not $idMatch.Value.Contains(
                "buff_ai_tag_name=`"$name`""
            )) {
                throw "Case-activation buff tag id $tag collides."
            }
            continue
        }
        if ($BaseXml.Contains("buff_ai_tag_name=`"$name`"")) {
            throw "Case-activation buff tag name '$name' has another id."
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

function ConvertTo-DpCaseActivationBuffXml {
    param(
        [Parameter(Mandatory)][string]$BaseXml,
        [Parameter(Mandatory)][object[]]$Signals
    )

    $additions = [System.Collections.Generic.List[string]]::new()
    foreach ($signal in @($Signals | Sort-Object case_code)) {
        $tag = [int]$signal.signal_tag
        $guid = [string]$signal.buff_guid
        $name = [string]$signal.signal_name
        $guidMatch = [regex]::Match(
            $BaseXml,
            "<buff\s+[^>]*buff_id=`"$([regex]::Escape($guid))`"[^>]*/>"
        )
        if ($guidMatch.Success) {
            if (-not $guidMatch.Value.Contains("buff_name=`"$name`"") -or
                -not $guidMatch.Value.Contains("buff_ai_tag_id=`"$tag`"")) {
                throw "Case-activation buff guid $guid collides."
            }
            continue
        }
        if ($BaseXml.Contains("buff_name=`"$name`"")) {
            throw "Case-activation buff name '$name' has another guid."
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

function ConvertTo-DpActorSelectionTagXml {
    param(
        [Parameter(Mandatory)][string]$BaseXml,
        [Parameter(Mandatory)][object[]]$Signals
    )

    $additions = [System.Collections.Generic.List[string]]::new()
    foreach ($signal in @($Signals | Sort-Object signal_tag)) {
        $tag = [int]$signal.signal_tag
        $name = [string]$signal.signal_name
        $idMatch = [regex]::Match(
            $BaseXml,
            "<buff_ai_tag\s+[^>]*buff_ai_tag_id=`"$tag`"[^>]*/>"
        )
        if ($idMatch.Success) {
            if (-not $idMatch.Value.Contains("buff_ai_tag_name=`"$name`"")) {
                throw "Actor-selection buff tag id $tag collides."
            }
            continue
        }
        if ($BaseXml.Contains("buff_ai_tag_name=`"$name`"")) {
            throw "Actor-selection buff tag name '$name' has another id."
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

function ConvertTo-DpActorSelectionBuffXml {
    param(
        [Parameter(Mandatory)][string]$BaseXml,
        [Parameter(Mandatory)][object[]]$Signals
    )

    $additions = [System.Collections.Generic.List[string]]::new()
    foreach ($signal in @($Signals | Sort-Object signal_tag)) {
        $tag = [int]$signal.signal_tag
        $guid = [string]$signal.buff_guid
        $name = [string]$signal.signal_name
        $guidMatch = [regex]::Match(
            $BaseXml,
            "<buff\s+[^>]*buff_id=`"$([regex]::Escape($guid))`"[^>]*/>"
        )
        if ($guidMatch.Success) {
            if (-not $guidMatch.Value.Contains("buff_name=`"$name`"") -or
                -not $guidMatch.Value.Contains("buff_ai_tag_id=`"$tag`"")) {
                throw "Actor-selection buff guid $guid collides."
            }
            continue
        }
        if ($BaseXml.Contains("buff_name=`"$name`"")) {
            throw "Actor-selection buff name '$name' has another guid."
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
        $CompiledDefinitions,
        [ValidateRange(1, 2147483647)]
        [int]$StartSignalTag = 130
    )

    $requestsByKey = [ordered]@{}
    foreach ($case in @($CaseSpecs | Sort-Object code, id)) {
        $supportedRegions = if (
            $null -ne $case.constraints.PSObject.Properties['regions']
        ) {
            @($case.constraints.regions | ForEach-Object { [string]$_ })
        }
        elseif ($null -ne $case.PSObject.Properties['native'] -and
            $null -ne $case.native.PSObject.Properties['regions']) {
            @($case.native.regions.PSObject.Properties.Name)
        }
        else { @([string]$case.constraints.region) }
        $caseBindings = @(
            foreach ($supportedRegion in @(
                $supportedRegions |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    Sort-Object -Unique
            )) {
                Get-DpScopedCaseSettlementBindings `
                    -Bindings $Bindings `
                    -CaseSpec $case `
                    -Region $supportedRegion
            }
        )
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
            $guid = if ($null -ne $item.PSObject.Properties['guid']) {
                [string]$item.guid
            }
            else { '' }
            if ([string]::IsNullOrWhiteSpace($guid)) {
                foreach ($caseBinding in $caseBindings) {
                    $roleProperty = if (
                        [string]::IsNullOrWhiteSpace($roleName)
                    ) { $null } else {
                        $caseBinding.roles.PSObject.Properties[$roleName]
                    }
                    if ($null -eq $roleProperty) { continue }
                    foreach ($propertyName in 'itemGuid', 'documentGuid') {
                        $valueProperty =
                            $roleProperty.Value.PSObject.Properties[$propertyName]
                        if ($null -ne $valueProperty -and
                            -not [string]::IsNullOrWhiteSpace(
                                [string]$valueProperty.Value
                            )) {
                            $guid = [string]$valueProperty.Value
                            break
                        }
                    }
                    if (-not [string]::IsNullOrWhiteSpace($guid)) { break }
                }
            }
            if ([string]::IsNullOrWhiteSpace($guid)) {
                throw (
                    "Quest evidence '$([string]$evidence.id)' has no " +
                    'concrete KCD2 item GUID.'
                )
            }
            if ($isReadableDocument) {
                foreach ($caseBinding in $caseBindings) {
                    $roleProperty = if (
                        [string]::IsNullOrWhiteSpace($roleName)
                    ) { $null } else {
                        $caseBinding.roles.PSObject.Properties[$roleName]
                    }
                    $roleBinding = if ($null -ne $roleProperty) {
                        $roleProperty.Value
                    }
                    else { $null }
                    $containerGuid = if ($null -ne $roleBinding -and
                        $null -ne $roleBinding.PSObject.Properties['containerGuid']) {
                        [string]$roleBinding.containerGuid
                    }
                    else { '' }
                    if ([string]::IsNullOrWhiteSpace($containerGuid)) {
                        throw (
                            "Quest document '$([string]$evidence.id)' has no " +
                            "container in '$([string]$caseBinding.region)/" +
                            "$([string]$caseBinding.settlement)'."
                        )
                    }
                    $requestKey = $containerGuid.ToLowerInvariant()
                    $key = $guid.ToLowerInvariant() + '|' + $requestKey
                    if ($requestsByKey.Contains($key)) { continue }
                    $region = [string]$caseBinding.region
                    $settlement = [string]$caseBinding.settlement
                    $requestsByKey[$key] = [ordered]@{
                        item_guid = $guid
                        request_key = $requestKey
                        classification = 'quest'
                        retention = [string]$item.retention
                        source = "evidence:$([string]$evidence.id)"
                        is_readable_document = $true
                        stash_bindings = @([ordered]@{
                            region = $region
                            settlement = $settlement
                            container_guid = $containerGuid
                            stash_alias = Get-DpEvidenceStashAlias `
                                -Region $region -Settlement $settlement
                        })
                    }
                }
            }
            else {
                $key = $guid.ToLowerInvariant() + '|'
                if (-not $requestsByKey.Contains($key)) {
                    $requestsByKey[$key] = [ordered]@{
                        item_guid = $guid
                        request_key = ''
                        classification = 'quest'
                        retention = [string]$item.retention
                        source = "evidence:$([string]$evidence.id)"
                        is_readable_document = $false
                        stash_bindings = @()
                    }
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
        $key = $guid.ToLowerInvariant() + '|'
        if (-not $requestsByKey.Contains($key)) {
            $requestsByKey[$key] = [ordered]@{
                item_guid = $guid
                request_key = ''
                classification = 'quest'
                retention = [string]$trophy.item.retention
                source = "trophy:$([string]$variant.variantId)"
                is_readable_document = $false
                stash_bindings = @()
            }
        }
    }

    $signals = [System.Collections.Generic.List[object]]::new()
    $index = 0
    foreach ($item in @($requestsByKey.Values |
        Sort-Object item_guid, request_key)) {
        $index++
        $name = 'dp_quest_item_request_{0:d3}' -f $index
        $signals.Add([ordered]@{
            signal_index = $index
            item_guid = [string]$item.item_guid
            request_key = [string]$item.request_key
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
            signal_tag = $StartSignalTag + $index - 1
            signal_name = $name
            buff_guid = Get-DpStableGuid -Seed (
                "darkpassenger-quest-item-request|$([string]$item.item_guid)|" +
                [string]$item.request_key
            )
        })
    }
    return $signals.ToArray()
}

function Get-DpGuidanceToken {
    param([Parameter(Mandatory)][string]$Seed)

    return (Get-DpStableGuid -Seed $Seed).Replace('-', '').Substring(0, 16)
}

function Get-DpCaseAssetLocalizationKey {
    param(
        [Parameter(Mandatory)][int]$CaseCode,
        [Parameter(Mandatory)][string]$Asset,
        [AllowNull()]$KeyOrigins = $null
    )

    $suffix = $Asset.ToLowerInvariant() -replace '[^a-z0-9]+', '_'
    $suffix = $suffix.Trim('_')
    if ([string]::IsNullOrWhiteSpace($suffix)) {
        throw "Cannot generate a native localization key for asset '$Asset'."
    }
    $key = 'dp_case_{0}_{1}' -f $CaseCode, $suffix
    if ($null -ne $KeyOrigins) {
        if ($KeyOrigins.Contains($key) -and
            [string]$KeyOrigins[$key] -ne $Asset) {
            throw "Generated localization key '$key' collides between " +
                "assets '$([string]$KeyOrigins[$key])' and '$Asset'."
        }
        $KeyOrigins[$key] = $Asset
    }
    return $key
}

function Get-DpCompiledStoryAssetValue {
    param(
        [Parameter(Mandatory)]$Story,
        [Parameter(Mandatory)][ValidateSet('ru', 'en')][string]$Language,
        [Parameter(Mandatory)][string]$Asset
    )

    $languageProperty = $Story.localization.PSObject.Properties[$Language]
    $assetProperty = $languageProperty.Value.PSObject.Properties[$Asset]
    if ($null -eq $assetProperty) {
        throw "Story '$($Story.storyId)' is missing $Language asset '$Asset'."
    }
    return [string]$assetProperty.Value
}

function Get-DpGuidanceSignals {
    param(
        [Parameter(Mandatory)]$CompiledDefinitions,
        [Parameter(Mandatory)]$AreaManifest,
        [AllowNull()]$AreaInventory = $null,
        [ValidateRange(1, 2147483647)]
        [int]$StartSignalTag = 193,
        [ValidateRange(1, 2147483647)]
        [int]$MaxSignalTag = [int]::MaxValue
    )

    if ($StartSignalTag -gt $MaxSignalTag) {
        throw "Guidance signal range starts after its maximum: " +
            "$StartSignalTag..$MaxSignalTag."
    }

    $stories = @{}
    $localizationKeyOrigins = @{}
    foreach ($story in @($CompiledDefinitions.stories)) {
        $storyId = [string]$story.storyId
        $stories[$storyId] = $story
        $origins = [ordered]@{}
        $journal = if ($null -eq $story.PSObject.Properties['journal']) {
            $null
        }
        else { $story.journal }
        if ($null -ne $journal -and
            $null -ne $journal.PSObject.Properties['objectives']) {
            foreach ($objective in $journal.objectives.PSObject.Properties) {
                $presentation = $objective.Value
                if ($null -eq $presentation) { continue }
                Get-DpCaseAssetLocalizationKey `
                    -CaseCode ([int]$story.caseCode) `
                    -Asset ([string]$presentation.nameAsset) `
                    -KeyOrigins $origins | Out-Null
                if ($null -eq $presentation.PSObject.Properties['states']) {
                    continue
                }
                foreach ($state in $presentation.states.PSObject.Properties) {
                    Get-DpCaseAssetLocalizationKey `
                        -CaseCode ([int]$story.caseCode) `
                        -Asset ([string]$state.Value) `
                        -KeyOrigins $origins | Out-Null
                }
            }
        }
        $localizationKeyOrigins[$storyId] = $origins
    }
    $areaAliases = @{}
    foreach ($settlement in @(
        $AreaManifest.regions | ForEach-Object { @($_.settlements) }
    )) {
        $areaAliases[
            "$([string]$settlement.gameRegion)/$([string]$settlement.id)"
        ] = [string]$settlement.alias
    }
    $inventoryAreas = if ($null -eq $AreaInventory) {
        @()
    }
    elseif ($null -ne $AreaInventory.PSObject.Properties['areas']) {
        @($AreaInventory.areas)
    }
    else {
        @($AreaInventory)
    }
    $inventoryAreas = @($inventoryAreas)

    $signals = [System.Collections.Generic.List[object]]::new()
    $nativeSignals = @{}
    $signalTag = $StartSignalTag
    foreach ($variant in @(
        $CompiledDefinitions.variants | Sort-Object variantId
    )) {
        $storyId = [string]$variant.storyId
        if (-not $stories.ContainsKey($storyId)) {
            throw "Guidance variant '$($variant.variantId)' references unknown story."
        }
        $story = $stories[$storyId]
        $timedAreaActionsByGuidance = @{}
        foreach ($action in @($story.timedAreaActions)) {
            $guidanceId = [string]$action.guidanceQualifiedId
            if ([string]::IsNullOrWhiteSpace($guidanceId)) {
                throw "Timed area action '$($action.qualifiedId)' has no " +
                    'GuidanceTarget.'
            }
            $timedAreaActionsByGuidance[$guidanceId] = $action
        }
        $evidenceByQualifiedId = @{}
        foreach ($evidence in @($story.evidence)) {
            $evidenceByQualifiedId[[string]$evidence.qualifiedId] = $evidence
        }
        foreach ($guidance in @(
            $variant.guidanceBindings | Sort-Object qualifiedId
        )) {
            $binding = $guidance.binding
            $assetKind = ''
            $alias = ''
            $sharedSoulGuid = ''
            $entityGuid = ''
            $areaSelection = if (
                $null -ne $guidance.PSObject.Properties['areaSelection']
            ) {
                [string]$guidance.areaSelection
            }
            else { '' }
            $targetKind = [string]$guidance.targetKind
            $precision = [string]$guidance.precision
            $usesGeneratedAlias = $false
            if ($null -ne $binding -and $targetKind -eq 'actor' -and
                $precision -in @('exact', 'point') -and
                -not [string]::IsNullOrWhiteSpace(
                    [string]$binding.soulGuid
                )) {
                $assetKind = 'SoulAsset'
                $usesGeneratedAlias = $true
                $sharedSoulGuid = [string]$binding.soulGuid
            }
            elseif ($null -ne $binding -and
                $targetKind -in @('entity', 'place') -and
                $precision -in @('exact', 'point') -and
                [string]$binding.kind -eq 'container' -and
                -not [string]::IsNullOrWhiteSpace(
                    [string]$binding.entityGuid
                )) {
                $assetKind = 'InteractionTriggerAsset'
                $usesGeneratedAlias = $true
                $entityGuid = [string]$binding.entityGuid
            }
            elseif ($null -ne $binding -and
                $targetKind -in @('area', 'place') -and
                $precision -eq 'area' -and
                [string]$binding.kind -eq 'settlement') {
                if ($areaSelection -eq 'smallest-common') {
                    $anchors = if (
                        $null -ne $guidance.PSObject.Properties['anchorBindings']
                    ) {
                        @($guidance.anchorBindings)
                    }
                    else { @() }
                    if ($inventoryAreas.Count -eq 0) {
                        throw "GuidanceTarget '$($guidance.qualifiedId)' " +
                            'requires the vanilla TriggerArea inventory.'
                    }
                    $selectedArea = Select-CommonInvestigationArea `
                        -Region ([string]$binding.region) `
                        -Areas $inventoryAreas `
                        -Anchors $anchors
                    $assetKind = 'TriggerAreaAsset'
                    $usesGeneratedAlias = $true
                    $entityGuid = [string]$selectedArea.guid
                }
                else {
                    $areaKey = "$([string]$binding.region)/" +
                        [string]$binding.settlement
                    if ($areaAliases.ContainsKey($areaKey)) {
                        $assetKind = 'TriggerAreaAsset'
                        $alias = [string]$areaAliases[$areaKey]
                    }
                }
            }

            $objective = if (
                $null -ne $guidance.PSObject.Properties['objective']
            ) { $guidance.objective } else { $null }
            if ([string]::IsNullOrWhiteSpace($assetKind)) {
                if ([string]$guidance.fallback -eq 'reject-variant') {
                    throw "KCD2 cannot materialize GuidanceTarget '$($guidance.qualifiedId)' for variant '$($variant.variantId)'."
                }
                if ($null -eq $objective) { continue }
            }
            $stepQualifiedId = "$([string]$guidance.threadId)/" +
                [string]$guidance.stepId
            if (-not $evidenceByQualifiedId.ContainsKey($stepQualifiedId)) {
                throw "GuidanceTarget '$($guidance.qualifiedId)' has no compiled evidence step '$stepQualifiedId'."
            }
            $evidence = $evidenceByQualifiedId[$stepQualifiedId]
            $timedAreaAction = $timedAreaActionsByGuidance[
                [string]$guidance.qualifiedId
            ]
            if ($null -ne $timedAreaAction -and
                $assetKind -ne 'TriggerAreaAsset') {
                throw "Timed area action '$($timedAreaAction.qualifiedId)' " +
                    "requires a resolved TriggerAreaAsset."
            }
            $objectiveAuthored = $null -ne $objective
            if ($objectiveAuthored) {
                $nameAsset = [string]$objective.nameAsset
                $activeAsset = [string]$objective.states.active
                $objectiveNameKey = Get-DpCaseAssetLocalizationKey `
                    -CaseCode ([int]$story.caseCode) -Asset $nameAsset `
                    -KeyOrigins $localizationKeyOrigins[$storyId]
                $objectiveActiveKey = Get-DpCaseAssetLocalizationKey `
                    -CaseCode ([int]$story.caseCode) -Asset $activeAsset `
                    -KeyOrigins $localizationKeyOrigins[$storyId]
                $objectiveNameLocalization = [pscustomobject][ordered]@{
                    ru = Get-DpCompiledStoryAssetValue -Story $story `
                        -Language ru -Asset $nameAsset
                    en = Get-DpCompiledStoryAssetValue -Story $story `
                        -Language en -Asset $nameAsset
                }
                $objectiveActiveLocalization = [pscustomobject][ordered]@{
                    ru = Get-DpCompiledStoryAssetValue -Story $story `
                        -Language ru -Asset $activeAsset
                    en = Get-DpCompiledStoryAssetValue -Story $story `
                        -Language en -Asset $activeAsset
                }
            }
            else {
                $objectiveNameKey = 'dark_within_evidence_name'
                $objectiveActiveKey = 'dark_within_guidance'
                $objectiveNameLocalization = [pscustomobject][ordered]@{
                    ru = 'Собрать доказательства вины'
                    en = 'Gather proof of guilt'
                }
                $objectiveActiveLocalization = [pscustomobject][ordered]@{
                    ru = 'Следовать зацепке, отмеченной на карте.'
                    en = 'Follow the lead marked on the map.'
                }
            }

            $nativeSeed = [ordered]@{
                region = [string]$variant.region
                asset_kind = $assetKind
                alias = $alias
                shared_soul_guid = $sharedSoulGuid
                entity_guid = $entityGuid
                objective_authored = $objectiveAuthored
                objective_name_key = $objectiveNameKey
                objective_name_ru = [string]$objectiveNameLocalization.ru
                objective_name_en = [string]$objectiveNameLocalization.en
                objective_active_key = $objectiveActiveKey
                objective_active_ru = [string]$objectiveActiveLocalization.ru
                objective_active_en = [string]$objectiveActiveLocalization.en
                timed_area_action_id = if ($null -eq $timedAreaAction) {
                    ''
                }
                else { [string]$timedAreaAction.qualifiedId }
            } | ConvertTo-Json -Depth 10 -Compress
            $native = $nativeSignals[$nativeSeed]
            if ($null -eq $native) {
                if ($signalTag -gt $MaxSignalTag) {
                    throw "Guidance signals exhausted safe native signal " +
                        "range $StartSignalTag..$MaxSignalTag."
                }
                $token = Get-DpGuidanceToken -Seed (
                    "darkpassenger-guidance-native|$nativeSeed"
                )
                $nativeAlias = if ($usesGeneratedAlias) {
                    "DP_Guidance_$token"
                }
                else { $alias }
                $native = [pscustomobject][ordered]@{
                    native_key = $nativeSeed
                    signal_tag = $signalTag
                    signal_name = "dp_guidance_$token"
                    buff_guid = Get-DpStableGuid -Seed (
                        "darkpassenger-guidance-native|$nativeSeed|signal"
                    )
                    objective_type = "DP_GuidanceProgress_$token"
                    objective_name = "dp_guidance_objective_$token"
                    alias = $nativeAlias
                }
                $nativeSignals[$nativeSeed] = $native
                $signalTag++
            }
            $timedAreaRuntime = if ($null -eq $timedAreaAction) {
                $null
            }
            else {
                # The runtime context belongs to the resolved native area, not
                # merely to the authored action. The same StoryPack action can
                # be materialized in several settlements; sharing its context
                # would make entering any of those areas activate the selected
                # case action.
                $actionToken = Get-DpGuidanceToken -Seed (
                    "darkpassenger-timed-area|" + [string]$native.native_key
                )
                $promptAsset = [string]$timedAreaAction.content.prompt
                $progressAsset = [string]$timedAreaAction.content.progress
                $unavailableAsset = [string]$timedAreaAction.content.unavailable
                [pscustomobject][ordered]@{
                    id = [string]$timedAreaAction.qualifiedId
                    mode = [string]$timedAreaAction.activation.mode
                    available_from_hour = [int]$timedAreaAction.activation.availableFromHour
                    available_until_hour = [int]$timedAreaAction.activation.availableUntilHour
                    duration_hours = [int]$timedAreaAction.activation.durationHours
                    area_context = "dp_timed_area_$actionToken"
                    prompt_key = Get-DpCaseAssetLocalizationKey `
                        -CaseCode ([int]$story.caseCode) `
                        -Asset $promptAsset `
                        -KeyOrigins $localizationKeyOrigins[$storyId]
                    prompt_localization = [pscustomobject][ordered]@{
                        ru = Get-DpCompiledStoryAssetValue -Story $story `
                            -Language ru -Asset $promptAsset
                        en = Get-DpCompiledStoryAssetValue -Story $story `
                            -Language en -Asset $promptAsset
                    }
                    progress_key = Get-DpCaseAssetLocalizationKey `
                        -CaseCode ([int]$story.caseCode) `
                        -Asset $progressAsset `
                        -KeyOrigins $localizationKeyOrigins[$storyId]
                    progress_localization = [pscustomobject][ordered]@{
                        ru = Get-DpCompiledStoryAssetValue -Story $story `
                            -Language ru -Asset $progressAsset
                        en = Get-DpCompiledStoryAssetValue -Story $story `
                            -Language en -Asset $progressAsset
                    }
                    unavailable_key = Get-DpCaseAssetLocalizationKey `
                        -CaseCode ([int]$story.caseCode) `
                        -Asset $unavailableAsset `
                        -KeyOrigins $localizationKeyOrigins[$storyId]
                    unavailable_localization = [pscustomobject][ordered]@{
                        ru = Get-DpCompiledStoryAssetValue -Story $story `
                            -Language ru -Asset $unavailableAsset
                        en = Get-DpCompiledStoryAssetValue -Story $story `
                            -Language en -Asset $unavailableAsset
                    }
                }
            }
            $signals.Add([pscustomobject][ordered]@{
                variant_id = [string]$variant.variantId
                variant_code = Get-DpStableRuntimeCode `
                    -Value ([string]$variant.variantId)
                story_id = $storyId
                region = [string]$variant.region
                settlement = [string]$variant.settlement
                qualified_id = [string]$guidance.qualifiedId
                step_evidence_id = [string]$evidence.qualifiedId
                step_evidence_code = [int]$evidence.code
                visibility_mode = [string]$guidance.visibility.mode
                requires_fact_ids = @($guidance.visibility.requiresFacts)
                lifetime = [string]$guidance.lifetime
                fallback = [string]$guidance.fallback
                native_key = [string]$native.native_key
                signal_tag = [int]$native.signal_tag
                signal_name = [string]$native.signal_name
                buff_guid = [string]$native.buff_guid
                objective_type = [string]$native.objective_type
                objective_name = [string]$native.objective_name
                objective_authored = $objectiveAuthored
                objective_name_key = $objectiveNameKey
                objective_name_text = [string]$objectiveNameLocalization.en
                objective_name_localization = $objectiveNameLocalization
                objective_active_key = $objectiveActiveKey
                objective_active_text = [string]$objectiveActiveLocalization.en
                objective_active_localization = $objectiveActiveLocalization
                alias = [string]$native.alias
                asset_kind = $assetKind
                shared_soul_guid = $sharedSoulGuid
                entity_guid = $entityGuid
                area_selection = $areaSelection
                timed_area_action = $timedAreaRuntime
            })
        }
    }
    return $signals.ToArray()
}

function Get-DpUniqueGuidanceNativeSignals {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Signals
    )

    $unique = [System.Collections.Generic.List[object]]::new()
    $byTag = @{}
    foreach ($signal in @($Signals | Sort-Object signal_tag, signal_name)) {
        $tag = [int]$signal.signal_tag
        if (-not $byTag.ContainsKey($tag)) {
            $byTag[$tag] = $signal
            $unique.Add($signal)
            continue
        }
        $existing = $byTag[$tag]
        $existingContract = [ordered]@{
            native_key = [string]$existing.native_key
            signal_name = [string]$existing.signal_name
            buff_guid = [string]$existing.buff_guid
            objective_type = [string]$existing.objective_type
            objective_name = [string]$existing.objective_name
            alias = [string]$existing.alias
            asset_kind = [string]$existing.asset_kind
            shared_soul_guid = [string]$existing.shared_soul_guid
            entity_guid = [string]$existing.entity_guid
        } | ConvertTo-Json -Compress
        $currentContract = [ordered]@{
            native_key = [string]$signal.native_key
            signal_name = [string]$signal.signal_name
            buff_guid = [string]$signal.buff_guid
            objective_type = [string]$signal.objective_type
            objective_name = [string]$signal.objective_name
            alias = [string]$signal.alias
            asset_kind = [string]$signal.asset_kind
            shared_soul_guid = [string]$signal.shared_soul_guid
            entity_guid = [string]$signal.entity_guid
        } | ConvertTo-Json -Compress
        if ($currentContract -cne $existingContract) {
            throw "Guidance native signal tag '$tag' has conflicting contracts."
        }
    }
    return $unique.ToArray()
}

function ConvertTo-DpGuidanceNativeWiring {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Signals,
        [Parameter(Mandatory)][string]$Region,
        [AllowEmptyCollection()][object[]]$CaseActivationSignals = @()
    )

    $regionalSignals = @(Get-DpUniqueGuidanceNativeSignals -Signals @(
        $Signals | Where-Object {
        [string]$_.region -eq $Region
        }
    ))
    $nodes = [System.Collections.Generic.List[string]]::new()
    $types = [System.Collections.Generic.List[string]]::new()
    $assets = [System.Collections.Generic.List[string]]::new()
    $objectives = [System.Collections.Generic.List[string]]::new()
    $assetDefinitions = @{}
    $caseActivationCodes = @(
        $CaseActivationSignals |
            ForEach-Object { [int]$_.case_code } |
            Where-Object { $_ -gt 0 } |
            Sort-Object -Unique
    )
    foreach ($signal in $regionalSignals) {
        $token = Get-DpGuidanceToken -Seed ([string]$signal.signal_name)
        $nodeSuffix = "guidance$token"
        $nodes.Add("        <MakeArray Name=`"${nodeSuffix}Tags`" TypeT=`"wh::rpgmodule::BuffDefinitionAITags`">")
        $nodes.Add("          <Constant Name=`"A`" Value=`"$([int]$signal.signal_tag)`" />")
        $nodes.Add('        </MakeArray>')
        $nodes.Add("        <BuffTagTrigger Name=`"${nodeSuffix}Trigger`">")
        $nodes.Add('          <Asset Name="Souls" Alias="player" />')
        $nodes.Add("          <Edge From=`"${nodeSuffix}Tags.Array`" To=`"BuffTags`" />")
        $nodes.Add('          <Edge From="watcherActive.State" To="IsActive" />')
        $nodes.Add('        </BuffTagTrigger>')
        $nodes.Add("        <State Name=`"${nodeSuffix}Progress`" TypeT=`"$([string]$signal.objective_type)`">")
        $nodes.Add("          <Edge From=`"${nodeSuffix}Trigger.OnAdded`" To=`"SetActive`" />")
        $nodes.Add("          <Edge From=`"${nodeSuffix}Trigger.OnRemoved`" To=`"SetNone`" />")
        foreach ($caseCode in $caseActivationCodes) {
            $nodes.Add(
                "          <Edge From=`"case${caseCode}ActiveTrigger.OnAdded`" To=`"SetNone`" />"
            )
        }
        $nodes.Add('        </State>')
        $nodes.Add("        <$([string]$signal.objective_name) Name=`"${nodeSuffix}Visual`">")
        $nodes.Add("          <Edge From=`"${nodeSuffix}Progress.State`" To=`"Progress`" />")
        $nodes.Add("        </$([string]$signal.objective_name)>")
        if ($null -ne $signal.timed_area_action) {
            $areaNode = "${nodeSuffix}Area"
            $insideNode = "${nodeSuffix}Inside"
            $contextNode = "${nodeSuffix}AreaContext"
            $nodes.Add("        <AreaTrigger Name=`"$areaNode`">")
            $nodes.Add('          <Asset Name="Souls" Alias="player" />')
            $nodes.Add("          <Asset Name=`"Areas`" Alias=`"$([string]$signal.alias)`" />")
            $nodes.Add("          <Edge From=`"${nodeSuffix}Progress.Active`" To=`"IsActive`" />")
            $nodes.Add('        </AreaTrigger>')
            $nodes.Add("        <State Name=`"$insideNode`" TypeT=`"bool`">")
            $nodes.Add("          <Edge From=`"$areaNode.OnEnter`" To=`"SetTrue`" />")
            $nodes.Add("          <Edge From=`"$areaNode.OnLeave`" To=`"SetFalse`" />")
            $nodes.Add("          <Edge From=`"${nodeSuffix}Trigger.OnRemoved`" To=`"SetFalse`" />")
            foreach ($caseCode in $caseActivationCodes) {
                $nodes.Add(
                    "          <Edge From=`"case${caseCode}ActiveTrigger.OnAdded`" To=`"SetFalse`" />"
                )
            }
            $nodes.Add('        </State>')
            $nodes.Add("        <SetEntityContext Name=`"$contextNode`">")
            $nodes.Add("          <Constant Name=`"Context`" Value=`"$([string]$signal.timed_area_action.area_context)`" />")
            $nodes.Add('          <Asset Name="Souls" Alias="player" />')
            $nodes.Add("          <Edge From=`"$insideNode.State`" To=`"IsActive`" />")
            $nodes.Add('        </SetEntityContext>')
        }

        $types.Add("        <Type TypeName=`"$([string]$signal.objective_type)`">")
        $types.Add('          <StateTypeEnumeration Name="None" ObjectiveValueType="None" />')
        $types.Add('          <StateTypeEnumeration Name="Active" ObjectiveValueType="Started" />')
        $types.Add('        </Type>')

        $alias = [string]$signal.alias
        $assetDefinition = switch ([string]$signal.asset_kind) {
            '' { $null }
            'SoulAsset' {
                "        <SoulAsset Name=`"$alias`" SharedSoulGuids=`"$([string]$signal.shared_soul_guid)`" />"
            }
            'InteractionTriggerAsset' {
                "        <InteractionTriggerAsset Name=`"$alias`" />"
            }
            'TriggerAreaAsset' {
                if ([string]::IsNullOrWhiteSpace(
                    [string]$signal.entity_guid
                )) {
                    $null
                }
                else {
                    "        <TriggerAreaAsset Name=`"$alias`" />"
                }
            }
            default {
                throw "Unsupported guidance asset kind '$([string]$signal.asset_kind)'."
            }
        }
        if ($null -ne $assetDefinition) {
            if ($assetDefinitions.ContainsKey($alias) -and
                [string]$assetDefinitions[$alias] -ne $assetDefinition) {
                throw "Guidance asset alias '$alias' has conflicting definitions."
            }
            if (-not $assetDefinitions.ContainsKey($alias)) {
                $assetDefinitions[$alias] = $assetDefinition
                $assets.Add($assetDefinition)
            }
        }

        $objectiveNameKey = ConvertTo-DpXmlText `
            ([string]$signal.objective_name_key)
        $objectiveNameText = ConvertTo-DpXmlText `
            ([string]$signal.objective_name_text)
        $objectiveActiveKey = ConvertTo-DpXmlText `
            ([string]$signal.objective_active_key)
        $objectiveActiveText = ConvertTo-DpXmlText `
            ([string]$signal.objective_active_text)
        $objectives.Add("        <Objective TypeT=`"$([string]$signal.objective_type)`" Name=`"$([string]$signal.objective_name)`">")
        $objectives.Add("          <LocalizedName StringName=`"$objectiveNameKey`" Text=`"$objectiveNameText`">")
        $objectives.Add("            <Localization Text=`"$objectiveNameText`" Language=`"WHS`" />")
        $objectives.Add('          </LocalizedName>')
        $objectives.Add('          <Logs>')
        $objectives.Add('            <EnumLog Type="None" Name="None" />')
        $markerAttribute = if ([string]::IsNullOrWhiteSpace($alias)) {
            ''
        }
        else { " Marker=`"$alias`"" }
        $objectives.Add("            <EnumLog Type=`"Started`" Name=`"Active`" IsTracked=`"true`"$markerAttribute>")
        $objectives.Add("              <Log StringName=`"$objectiveActiveKey`" Text=`"$objectiveActiveText`">")
        $objectives.Add("                <Localization Text=`"$objectiveActiveText`" Language=`"WHS`" />")
        $objectives.Add('              </Log>')
        $objectives.Add('            </EnumLog>')
        $objectives.Add('          </Logs>')
        $objectives.Add('        </Objective>')
    }

    return [pscustomobject][ordered]@{
        nodes = $nodes -join "`n"
        types = $types -join "`n"
        assets = $assets -join "`n"
        objectives = $objectives -join "`n"
    }
}

function Get-DpGuidanceWaitingLinks {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Signals,
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$QuestHolderGuid
    )

    $nativeSignals = @(Get-DpUniqueGuidanceNativeSignals -Signals $Signals)
    return @($nativeSignals | Where-Object {
        [string]$_.region -eq $Region -and
        [string]$_.asset_kind -in @(
            'InteractionTriggerAsset',
            'TriggerAreaAsset'
        ) -and
        -not [string]::IsNullOrWhiteSpace([string]$_.entity_guid)
    } | Sort-Object alias | ForEach-Object {
        [pscustomobject][ordered]@{
            sourceGuid = $QuestHolderGuid
            targetGuid = [string]$_.entity_guid
            linkDefinition = "asset['$([string]$_.alias)']"
        }
    })
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

function ConvertTo-DpGuidanceTagXml {
    param(
        [Parameter(Mandatory)][string]$BaseXml,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Signals
    )

    if ($Signals.Count -eq 0) { return $BaseXml }
    $nativeSignals = @(Get-DpUniqueGuidanceNativeSignals -Signals $Signals)
    return ConvertTo-DpQuestItemPlacementTagXml `
        -BaseXml $BaseXml `
        -Signals $nativeSignals
}

function ConvertTo-DpGuidanceBuffXml {
    param(
        [Parameter(Mandatory)][string]$BaseXml,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Signals
    )

    if ($Signals.Count -eq 0) { return $BaseXml }
    $nativeSignals = @(Get-DpUniqueGuidanceNativeSignals -Signals $Signals)
    return ConvertTo-DpQuestItemPlacementBuffXml `
        -BaseXml $BaseXml `
        -Signals $nativeSignals
}

function ConvertTo-DpQuestItemPlacementNodesXml {
    param(
        [Parameter(Mandatory)][object[]]$Signals,
        [string]$Region
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $readTriggers = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
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
        if ([bool]$signal.is_readable_document -and
            $readTriggers.Add([string]$signal.item_guid)) {
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
    foreach ($group in @($Signals | Group-Object { [string]$_.item_guid } |
        Sort-Object Name)) {
        $signals = @($group.Group | Sort-Object request_key, signal_tag)
        $first = $signals[0]
        $requests = [ordered]@{}
        foreach ($signal in $signals) {
            $requestKey = if ([string]::IsNullOrWhiteSpace(
                [string]$signal.request_key
            )) { '__default' } else { [string]$signal.request_key }
            $requests[$requestKey] = [ordered]@{
                buff_guid = [string]$signal.buff_guid
                signal_tag = [int]$signal.signal_tag
                request_key = [string]$signal.request_key
            }
        }
        $entries[([string]$first.item_guid).ToLowerInvariant()] = [ordered]@{
            item_guid = [string]$first.item_guid
            buff_guid = [string]$first.buff_guid
            signal_tag = [int]$first.signal_tag
            retention = [string]$first.retention
            backend = [string]$first.backend
            read_context = [string]$first.read_context
            default_request_key = if ($signals.Count -eq 1) {
                if ([string]::IsNullOrWhiteSpace(
                    [string]$first.request_key
                )) { '__default' } else { [string]$first.request_key }
            }
            else { '' }
            requests = $requests
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

    $binding = @(Get-DpCaseSettlementBindings -Bindings $Bindings `
        -CaseCode ([int]$CaseSpec.code) `
        -Region $region -Settlement $settlement)
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
                [string]$_.name -ceq [string]$roleName
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
    $revealedFactIds = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
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
        elseif ($kind -notin @('dialogue', 'document', 'area_action')) {
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
        elseif ($role -ne 'area_action' -and $binding.Count -eq 1 -and
            $null -eq $binding[0].roles.PSObject.Properties[$role]) {
            $errors.Add("$prefix semantic role '$role' is not bound")
        }
        if ($role -notin @('innkeeper', 'overheard', 'area_action')) {
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
        foreach ($revealedFact in @($revealedFacts)) {
            $null = $revealedFactIds.Add([string]$revealedFact)
        }
    }
    $identityProperty = $CaseSpec.PSObject.Properties['identityRequirement']
    if ($null -ne $identityProperty) {
        $identityModes = @(
            $identityProperty.Value.PSObject.Properties.Name |
                Where-Object { $_ -in @('allOf', 'anyOf') }
        )
        if ($identityModes.Count -ne 1 -or
            @($identityProperty.Value.PSObject.Properties).Count -ne 1) {
            $errors.Add(
                "$prefix identityRequirement must define exactly one of " +
                "'allOf' or 'anyOf'"
            )
        }
        else {
            $mode = [string]$identityModes[0]
            $facts = @($identityProperty.Value.$mode | ForEach-Object {
                [string]$_
            })
            if ($facts.Count -eq 0) {
                $errors.Add(
                    "$prefix identityRequirement.$mode must contain a fact"
                )
            }
            foreach ($fact in $facts) {
                if (-not $revealedFactIds.Contains($fact)) {
                    $errors.Add(
                        "$prefix identityRequirement references unknown " +
                        "fact '$fact'"
                    )
                }
            }
        }
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
    'Get-DpCaseSettlementBindings',
    'Get-DpScopedCaseSettlementBindings',
    'Get-DpCaseSpecValidationErrors',
    'Get-DpValidatedCaseSpecs',
    'ConvertTo-DpLuaString',
    'ConvertTo-DpLuaValue',
    'ConvertTo-DpCaseCatalogLua',
    'Get-DpCaseCleanupManifest',
    'ConvertTo-DpCaseVariantCatalogLua',
    'ConvertTo-DpCaseCompatibilityReport',
    'ConvertTo-DpDialogueXml',
    'Read-DpDialogueVoiceRegistry',
    'Read-DpDialogueMediaReferenceLengths',
    'Get-DpDialogueMediaDemands',
    'Get-DpResolvedDialogueVoiceAssignment',
    'ConvertTo-DpNativeRegionWiring',
    'ConvertTo-DpNativeRegionBundle',
    'Get-DpJournalStates',
    'Get-DpCaseActivationSignals',
    'Get-DpActorSelectionSignals',
    'Get-DpDialogueVariants',
    'ConvertTo-DpLeadStateTagXml',
    'ConvertTo-DpLeadStateBuffXml',
    'ConvertTo-DpCaseActivationTagXml',
    'ConvertTo-DpCaseActivationBuffXml',
    'ConvertTo-DpActorSelectionTagXml',
    'ConvertTo-DpActorSelectionBuffXml',
    'ConvertTo-DpDialogueVariantTagXml',
    'ConvertTo-DpDialogueVariantBuffXml',
    'Get-DpGuidanceSignals',
    'Get-DpUniqueGuidanceNativeSignals',
    'ConvertTo-DpGuidanceNativeWiring',
    'Get-DpGuidanceWaitingLinks',
    'ConvertTo-DpGuidanceTagXml',
    'ConvertTo-DpGuidanceBuffXml',
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
