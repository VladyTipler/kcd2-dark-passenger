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
    param([Parameter(Mandatory)]$Evidence)

    return [ordered]@{
        id = [string]$Evidence.id
        code = [int]$Evidence.code
        kind = [string]$Evidence.kind
        role = [string]$Evidence.role
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
        next_lead = [string]$Evidence.nextLead
        prompt_key = if (
            $null -ne $Evidence.PSObject.Properties['promptKey']
        ) { [string]$Evidence.promptKey } else { $null }
    }
}

function ConvertTo-DpRuntimeCase {
    param(
        [Parameter(Mandatory)]$CaseSpec,
        [Parameter(Mandatory)]$Binding
    )

    $evidence = @(
        $CaseSpec.evidence | ForEach-Object {
            ConvertTo-DpRuntimeEvidence -Evidence $_
        }
    )
    $rumors = @($evidence | Where-Object {
        $_.kind -eq 'dialogue' -and $_.role -eq 'innkeeper'
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
        rumors = $rumors
        evidence_steps = @($evidence | Select-Object -Skip 1)
        evidence = $evidence
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
    if ([int]$CaseSpec.schemaVersion -ne 1) {
        $errors.Add("$prefix schemaVersion must be 1")
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

    foreach ($language in 'ru', 'en') {
        $languageText = $CaseSpec.text.$language
        foreach ($field in 'title', 'description') {
            if (-not (Test-DpTextValue $languageText.$field)) {
                $errors.Add("$prefix text.$language.$field is required")
            }
        }
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
        if (-not (Test-DpTextValue $step.kind)) {
            $errors.Add("$prefix evidence '$evidenceId' kind is required")
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

        $nextLead = [string]$step.nextLead
        if (-not (Test-DpTextValue $nextLead)) {
            $errors.Add("$prefix evidence '$evidenceId' nextLead is required")
        }
    }

    $evidenceIds = @($evidence | ForEach-Object { [string]$_.id })
    foreach ($step in $evidence) {
        $nextLead = [string]$step.nextLead
        if ((Test-DpTextValue $nextLead) -and
            $nextLead -ne 'reveal_target' -and
            $nextLead -notin $evidenceIds) {
            $errors.Add(
                "$prefix evidence '$($step.id)' references unknown nextLead '$nextLead'"
            )
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
    'ConvertTo-DpCaseCompatibilityReport'
)
