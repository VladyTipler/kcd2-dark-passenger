[CmdletBinding(DefaultParameterSetName = 'Legacy')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Legacy')]
    [string]$LegacyCaseRoot,
    [Parameter(Mandatory, ParameterSetName = 'Legacy')]
    [string]$LegacyBindingPath,
    [Parameter(Mandatory, ParameterSetName = 'Authored')]
    [string]$ArchetypeRoot,
    [Parameter(Mandatory, ParameterSetName = 'Authored')]
    [string]$StoryRoot,
    [Parameter(Mandatory, ParameterSetName = 'Authored')]
    [string]$EvidenceModuleRoot,
    [Parameter(Mandatory, ParameterSetName = 'Authored')]
    [string]$WorldIndexPath,
    [Parameter(Mandatory, ParameterSetName = 'Authored')]
    [string]$SettlementProfileRoot,
    [Parameter(Mandatory, ParameterSetName = 'Authored')]
    [string]$StableIdRegistryPath,
    [Parameter(ParameterSetName = 'Authored')]
    [string]$Kcd2AdapterPath,
    [Parameter(Mandatory)]
    [string]$OutputRoot,
    [Parameter(ParameterSetName = 'Authored')]
    [ValidateRange(1, 1024)]
    [int]$MaxVariantsPerCombination = 8
)

$ErrorActionPreference = 'Stop'

$caseKitRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $caseKitRoot 'CaseKit.psd1'
$compatibilityModulePath = Join-Path $caseKitRoot `
    'core\CaseKit.Compatibility.psm1'
$profilesModulePath = Join-Path $caseKitRoot `
    'core\CaseKit.Profiles.psm1'
$materializerModulePath = Join-Path $caseKitRoot `
    'adapters\kcd2\CaseKit.Kcd2Materializer.psm1'
$backendModulePath = Join-Path $caseKitRoot `
    'adapters\kcd2\CaseKit.Kcd2Backend.psm1'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

Import-Module $manifestPath -Force

function Write-CaseKitJson {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)]$Value
    )

    $parent = Split-Path -Parent $LiteralPath
    [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    $json = ($Value | ConvertTo-Json -Depth 100) + "`n"
    [System.IO.File]::WriteAllText($LiteralPath, $json, $utf8NoBom)
}

$resolvedOutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
[System.IO.Directory]::CreateDirectory($resolvedOutputRoot) | Out-Null

if ($PSCmdlet.ParameterSetName -eq 'Authored') {
    Import-Module $compatibilityModulePath -Force
    Import-Module $profilesModulePath -Force
    Import-Module $materializerModulePath -Force
    Import-Module $backendModulePath -Force
    $deck = Read-CaseKitAuthoringDeck `
        -ArchetypeRoot $ArchetypeRoot `
        -StoryRoot $StoryRoot `
        -EvidenceModuleRoot $EvidenceModuleRoot
    $worldIndex = [System.IO.File]::ReadAllText($WorldIndexPath) |
        ConvertFrom-Json -Depth 100
    $profilePaths = @(Get-ChildItem -LiteralPath $SettlementProfileRoot `
        -Filter '*.profile.json' -File | Sort-Object FullName)
    if ($profilePaths.Count -eq 0) {
        throw "No settlement profiles found in '$SettlementProfileRoot'."
    }
    $supportedSettlements = [System.Collections.Generic.HashSet[string]]::new()
    $profiles = [System.Collections.Generic.List[object]]::new()
    foreach ($profilePath in $profilePaths) {
        $profile = Read-CaseKitSettlementProfile `
            -LiteralPath $profilePath.FullName
        $profiles.Add($profile)
        $null = $supportedSettlements.Add(
            "$([string]$profile.region)/$([string]$profile.settlement)"
        )
        $worldIndex = Merge-CaseKitSettlementProfile `
            -WorldIndex $worldIndex -Profile $profile
    }
    $worldIndex.settlements = @($worldIndex.settlements | Where-Object {
        $supportedSettlements.Contains(
            "$([string]$_.region)/$([string]$_.settlement)"
        )
    })
    $worldIndex.entities = @($worldIndex.entities | Where-Object {
        $supportedSettlements.Contains(
            "$([string]$_.region)/$([string]$_.settlement)"
        )
    })
    $stableIds = [System.IO.File]::ReadAllText($StableIdRegistryPath) |
        ConvertFrom-Json -Depth 100
    $compatibility = Resolve-CaseKitCompatibility -Deck $deck `
        -WorldIndex $worldIndex `
        -MaxVariantsPerCombination $MaxVariantsPerCombination
    $compiled = ConvertTo-CaseKitCompiledDefinitions -Deck $deck `
        -CompatibilityReport $compatibility `
        -StableIdRegistry $stableIds
    Write-CaseKitJson -LiteralPath (Join-Path $resolvedOutputRoot `
        'compiled-definitions.json') -Value $compiled
    Write-CaseKitJson -LiteralPath (Join-Path $resolvedOutputRoot `
        'compatibility-report.json') -Value $compatibility
    if (-not [string]::IsNullOrWhiteSpace($Kcd2AdapterPath)) {
        $adapter = Read-CaseKitKcd2Adapter -LiteralPath $Kcd2AdapterPath
        $backend = ConvertTo-CaseKitKcd2BackendInput `
            -CompiledDefinitions $compiled -Adapter $adapter `
            -SettlementProfiles $profiles.ToArray()
        $caseOutputRoot = Join-Path $resolvedOutputRoot 'cases'
        if (Test-Path -LiteralPath $caseOutputRoot) {
            Remove-Item -LiteralPath $caseOutputRoot -Recurse -Force
        }
        [System.IO.Directory]::CreateDirectory($caseOutputRoot) | Out-Null
        foreach ($caseSpec in @($backend.caseSpecs | Sort-Object code, id)) {
            $fileName = ([string]$caseSpec.id).Replace('_', '-') +
                '.case.json'
            Write-CaseKitJson -LiteralPath (Join-Path $caseOutputRoot `
                $fileName) -Value $caseSpec
        }
        Write-CaseKitJson -LiteralPath (Join-Path $resolvedOutputRoot `
            'case-settlement-bindings.json') -Value $backend.bindings
        Write-CaseKitJson -LiteralPath (Join-Path $resolvedOutputRoot `
            'casekit-manifest.json') -Value ([pscustomobject][ordered]@{
                schemaVersion = 1
                sourceFormat = 'casekit-kcd2-compiler-input-v1'
                caseIds = @($backend.caseSpecs.id)
                variantIds = @($compiled.variants.variantId)
                caseRoot = 'cases'
                bindingFile = 'case-settlement-bindings.json'
                compiledDefinitionsFile = 'compiled-definitions.json'
                compatibilityReportFile = 'compatibility-report.json'
            })
        Write-Host (
            "Compiled $(@($compiled.stories).Count) StoryPack(s) into " +
            "$(@($compiled.variants).Count) finite variant(s) and " +
            "$(@($backend.caseSpecs).Count) native CaseSpec(s)."
        )
        Write-Host "KCD2 compiler input: $resolvedOutputRoot"
        exit 0
    }
    Write-CaseKitJson -LiteralPath (Join-Path $resolvedOutputRoot `
        'casekit-manifest.json') -Value ([pscustomobject][ordered]@{
            schemaVersion = 1
            sourceFormat = 'casekit-compiled-definitions-v1'
            storyIds = @($compiled.stories.storyId)
            variantIds = @($compiled.variants.variantId)
            compiledDefinitionsFile = 'compiled-definitions.json'
            compatibilityReportFile = 'compatibility-report.json'
        })
    Write-Host (
        "Compiled $(@($compiled.stories).Count) StoryPack(s) into " +
        "$(@($compiled.variants).Count) finite variant(s)."
    )
    Write-Host "CaseKit output: $resolvedOutputRoot"
    exit 0
}

$deck = Read-CaseKitAuthoringDeck `
    -LegacyCaseRoot $LegacyCaseRoot `
    -LegacyBindingPath $LegacyBindingPath
$variants = @(Resolve-CaseKitVariants -Deck $deck)
$backend = ConvertTo-CaseKitBackendInput -Variants $variants
$caseOutputRoot = Join-Path $resolvedOutputRoot 'cases'
if (Test-Path -LiteralPath $caseOutputRoot) {
    Remove-Item -LiteralPath $caseOutputRoot -Recurse -Force
}
[System.IO.Directory]::CreateDirectory($caseOutputRoot) | Out-Null
foreach ($caseSpec in @($backend.caseSpecs | Sort-Object code, id)) {
    $fileName = ([string]$caseSpec.id).Replace('_', '-') + '.case.json'
    Write-CaseKitJson -LiteralPath (Join-Path $caseOutputRoot $fileName) `
        -Value $caseSpec
}
Write-CaseKitJson -LiteralPath (Join-Path $resolvedOutputRoot `
    'case-settlement-bindings.json') -Value $backend.bindings
Write-CaseKitJson -LiteralPath (Join-Path $resolvedOutputRoot `
    'casekit-manifest.json') -Value ([pscustomobject][ordered]@{
        schemaVersion = 1
        sourceFormat = 'casekit-kcd2-compiler-input-v1'
        caseIds = @($backend.caseSpecs.id)
        variantIds = @($variants.variantId)
        caseRoot = 'cases'
        bindingFile = 'case-settlement-bindings.json'
    })

Write-Host "Compiled $(@($backend.caseSpecs).Count) finite CaseVariant(s)."
Write-Host "KCD2 compiler input: $resolvedOutputRoot"
