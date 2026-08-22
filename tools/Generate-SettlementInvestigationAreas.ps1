[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TriggerAreaCatalogPath,
    [Parameter(Mandatory)][string]$VictimCandidatesPath,
    [Parameter(Mandatory)][string]$OverridePath,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$DiagnosticsPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$selectionModule = Join-Path `
    $PSScriptRoot `
    'VanillaInvestigationAreaSelection.psm1'
$coverageBuilder = Join-Path `
    $PSScriptRoot `
    'build-settlement-area-coverage.mjs'
foreach ($requiredPath in @($selectionModule, $coverageBuilder)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Settlement area generator dependency not found: $requiredPath"
    }
}
Import-Module $selectionModule

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required JSON file not found: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Write-DeterministicJson {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Path
    )

    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $json = $Value | ConvertTo-Json -Depth 14
    [IO.File]::WriteAllText(
        $Path,
        $json + [Environment]::NewLine,
        [Text.UTF8Encoding]::new($false)
    )
}

function Get-PropertyValue {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }
    return $property.Value
}

function ConvertTo-IdentifierSegment {
    param([Parameter(Mandatory)][string]$Value)

    return (@(
        $Value -split '[^A-Za-z0-9]+' |
            Where-Object { $_ } |
            ForEach-Object {
                $_.Substring(0, 1).ToUpperInvariant() +
                    $_.Substring(1).ToLowerInvariant()
            }
    ) -join '')
}

function ConvertTo-CoverageHashtable {
    param([Parameter(Mandatory)]$CoverageObject)

    $result = @{}
    foreach ($property in $CoverageObject.PSObject.Properties) {
        $result[$property.Name.ToLowerInvariant()] = @($property.Value)
    }
    return $result
}

$coveragePath = "$DiagnosticsPath.coverage.json"
& node $coverageBuilder `
    '--catalog' $TriggerAreaCatalogPath `
    '--candidates' $VictimCandidatesPath `
    '--overrides' $OverridePath `
    '--output' $coveragePath
if ($LASTEXITCODE -ne 0) {
    throw "Settlement coverage builder failed with exit code $LASTEXITCODE."
}

$catalog = Read-JsonFile $TriggerAreaCatalogPath
$candidatePolicy = Read-JsonFile $VictimCandidatesPath
$overridePolicy = Read-JsonFile $OverridePath
$coveragePlan = Read-JsonFile $coveragePath
if (
    $catalog.schemaVersion -ne 1 -or
    $candidatePolicy.schemaVersion -ne 2 -or
    $overridePolicy.schemaVersion -ne 1 -or
    $coveragePlan.schemaVersion -ne 1
) {
    throw 'Unsupported settlement investigation input schema.'
}

$areaByGuid = @{}
foreach ($area in @($catalog.areas)) {
    $areaByGuid[[string]$area.guid] = $area
}
$settlementMetadata = @{}
foreach ($settlement in @($candidatePolicy.settlements)) {
    $settlementMetadata[(
        '{0}/{1}' -f $settlement.gameRegion, $settlement.id
    ).ToLowerInvariant()] = $settlement
}
$overrideBySettlement = @{}
foreach ($override in @($overridePolicy.settlements)) {
    $overrideBySettlement[(
        '{0}/{1}' -f $override.gameRegion, $override.settlement
    ).ToLowerInvariant()] = $override
}
$coverageBySettlement = @{}
foreach ($coverage in @($coveragePlan.settlements)) {
    $coverageBySettlement[(
        '{0}/{1}' -f $coverage.gameRegion, $coverage.settlement
    ).ToLowerInvariant()] = $coverage
}

$enabledCandidates = @($candidatePolicy.candidates | Where-Object enabled)
$candidateGroups = @(
    $enabledCandidates |
        Group-Object gameRegion, settlement |
        Sort-Object Name
)
$manifestSettlements = [Collections.Generic.List[object]]::new()
$settlementDiagnostics = [Collections.Generic.List[object]]::new()
$failures = [Collections.Generic.List[object]]::new()

foreach ($candidateGroup in $candidateGroups) {
    $firstCandidate = @($candidateGroup.Group)[0]
    $region = [string]$firstCandidate.gameRegion
    $settlementId = [string]$firstCandidate.settlement
    $key = "$region/$settlementId"
    $normalizedKey = $key.ToLowerInvariant()
    if (
        -not $settlementMetadata.ContainsKey($normalizedKey) -or
        -not $coverageBySettlement.ContainsKey($normalizedKey)
    ) {
        $failures.Add([pscustomobject][ordered]@{
            gameRegion = $region
            settlement = $settlementId
            reason = 'generation_input_missing'
            detail = "Missing metadata or coverage plan for $key."
        })
        continue
    }

    $settlement = $settlementMetadata[$normalizedKey]
    $coverage = $coverageBySettlement[$normalizedKey]
    $override = if ($overrideBySettlement.ContainsKey($normalizedKey)) {
        $overrideBySettlement[$normalizedKey]
    }
    else {
        $null
    }
    $candidates = @($candidateGroup.Group | Sort-Object slot)
    $anchors = @(
        $candidates | ForEach-Object {
            [pscustomobject]@{
                id = '{0}:{1}' -f $_.slot, $_.entityName
                position = $_.position
            }
        }
    )
    $relevantAreas = @(
        $coverage.areaGuids | ForEach-Object { $areaByGuid[[string]$_] }
    )
    $coverageHashtable = ConvertTo-CoverageHashtable `
        $coverage.coverageByGuid

    try {
        $selection = Select-SettlementInvestigationAreas `
            -Settlement $settlement `
            -Areas $relevantAreas `
            -Anchors $anchors `
            -Override $override `
            -CoverageByGuid $coverageHashtable
    }
    catch {
        $failures.Add([pscustomobject][ordered]@{
            gameRegion = $region
            settlement = $settlementId
            reason = 'selection_failed'
            detail = $_.Exception.Message
            candidateCount = $candidates.Count
            relevantAreaCount = $relevantAreas.Count
        })
        continue
    }

    $displayNameOverride = Get-PropertyValue $override 'displayName' $null
    $legacyAliases = @(
        Get-PropertyValue $override 'legacyAliases' @() |
            ForEach-Object { [string]$_ }
    )
    foreach ($legacyAlias in $legacyAliases) {
        if ($legacyAlias -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            throw "Settlement '$key' has invalid legacy alias '$legacyAlias'."
        }
    }
    $fallbackName = [string](
        Get-PropertyValue $settlement 'displayName' $settlementId
    )
    $selectedAreas = @($selection.areas)
    $surfaceAreas = @(
        $selectedAreas | ForEach-Object { [double]$_.surfaceArea }
    )
    $manifestSettlements.Add([pscustomobject][ordered]@{
        id = $settlementId
        gameRegion = $region
        alias = (
            'DP_SearchArea_{0}_{1}' -f
                (ConvertTo-IdentifierSegment $region),
                (ConvertTo-IdentifierSegment $settlementId)
        )
        displayName = [pscustomobject][ordered]@{
            english = [string](
                Get-PropertyValue $displayNameOverride 'english' $fallbackName
            )
            russian = [string](
                Get-PropertyValue $displayNameOverride 'russian' $fallbackName
            )
        }
        legacyAliases = @($legacyAliases)
        primaryGuid = [string]$selection.primaryGuid
        areaGuids = @($selection.areaGuids)
        evidenceTerritoryGuids = @($selection.areaGuids)
        candidateCount = $candidates.Count
        candidateSlots = @($candidates.slot)
    })
    $settlementDiagnostics.Add([pscustomobject][ordered]@{
        gameRegion = $region
        settlement = $settlementId
        candidateCount = $candidates.Count
        relevantAreaCount = $relevantAreas.Count
        selectedAreaCount = $selectedAreas.Count
        primaryGuid = [string]$selection.primaryGuid
        areaGuids = @($selection.areaGuids)
        maxSurfaceArea = [double](
            $surfaceAreas | Measure-Object -Maximum
        ).Maximum
        totalSurfaceArea = [double](
            $surfaceAreas | Measure-Object -Sum
        ).Sum
    })
}

$diagnostics = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = if ($failures.Count -eq 0) { 'complete' } else { 'incomplete' }
    enabledCandidateCount = $enabledCandidates.Count
    settlementCount = $candidateGroups.Count
    generatedSettlementCount = $manifestSettlements.Count
    catalogAreaCount = @($catalog.areas).Count
    catalogRejectionCounts = @(
        $catalog.rejections |
            Group-Object reason |
            Sort-Object Name |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    reason = [string]$_.Name
                    count = [int]$_.Count
                }
            }
    )
    settlements = @(
        $settlementDiagnostics | Sort-Object gameRegion, settlement
    )
    failures = @($failures | Sort-Object gameRegion, settlement)
}
Write-DeterministicJson $diagnostics $DiagnosticsPath
if ($failures.Count -gt 0) {
    throw (
        'Settlement investigation coverage failed for {0} settlement(s). See {1}' -f
            $failures.Count,
            $DiagnosticsPath
    )
}

$manifest = [pscustomobject][ordered]@{
    schemaVersion = 1
    regions = @(
        $manifestSettlements |
            Group-Object gameRegion |
            Sort-Object Name |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    id = [string]$_.Name
                    settlements = @($_.Group | Sort-Object id)
                }
            }
    )
}
Write-DeterministicJson $manifest $OutputPath
Write-Host (
    'Generated settlement investigation coverage: settlements={0} candidates={1}' -f
        $manifestSettlements.Count,
        $enabledCandidates.Count
)
