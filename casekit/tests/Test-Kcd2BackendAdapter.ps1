$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$caseKitRoot = Join-Path $repoRoot 'casekit'
$adapterModulePath = Join-Path $caseKitRoot `
    'adapters\kcd2\CaseKit.Kcd2Backend.psm1'

$script:checks = 0
$script:failures = [System.Collections.Generic.List[string]]::new()

function Add-Result {
    param([bool]$Condition, [string]$Label)

    $script:checks++
    if ($Condition) {
        Write-Host "PASS: $Label"
        return
    }
    $script:failures.Add($Label)
    Write-Host "FAIL: $Label"
}

function ConvertTo-TestJson($Value) {
    return $Value | ConvertTo-Json -Depth 100 -Compress
}

if (-not (Test-Path -LiteralPath $adapterModulePath -PathType Leaf)) {
    Add-Result $false 'KCD2 backend adapter module exists'
}
else {
    Import-Module (Join-Path $caseKitRoot 'CaseKit.psd1') -Force
    Import-Module (Join-Path $caseKitRoot `
        'core\CaseKit.Profiles.psm1') -Force
    Import-Module (Join-Path $caseKitRoot `
        'core\CaseKit.Compatibility.psm1') -Force
    Import-Module (Join-Path $caseKitRoot `
        'adapters\kcd2\CaseKit.Kcd2Materializer.psm1') -Force
    Import-Module $adapterModulePath -Force

    try {
        $deck = Read-CaseKitAuthoringDeck `
            -ArchetypeRoot (Join-Path $repoRoot 'content\archetypes') `
            -StoryRoot (Join-Path $repoRoot 'content\stories') `
            -EvidenceModuleRoot (Join-Path $repoRoot `
                'content\evidence-modules')
        $world = [System.IO.File]::ReadAllText((Join-Path $repoRoot `
            'config\world-semantic-index.json')) |
                ConvertFrom-Json -Depth 100
        $profiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot `
            'config\settlements') -Filter '*.profile.json' -File |
            Sort-Object FullName | ForEach-Object {
                Read-CaseKitSettlementProfile -LiteralPath $_.FullName
            })
        foreach ($profile in $profiles) {
            $world = Merge-CaseKitSettlementProfile -WorldIndex $world `
                -Profile $profile
        }
        $supported = @($profiles | ForEach-Object {
            "$($_.region)/$($_.settlement)"
        })
        $world.settlements = @($world.settlements | Where-Object {
            "$($_.region)/$($_.settlement)" -in $supported
        })
        $world.entities = @($world.entities | Where-Object {
            "$($_.region)/$($_.settlement)" -in $supported
        })
        $compatibility = Resolve-CaseKitCompatibility -Deck $deck `
            -WorldIndex $world -MaxVariantsPerCombination 1
        $stableIds = [System.IO.File]::ReadAllText((Join-Path $repoRoot `
            'config\casekit-stable-ids.json')) |
                ConvertFrom-Json -Depth 100
        $compiled = ConvertTo-CaseKitCompiledDefinitions -Deck $deck `
            -CompatibilityReport $compatibility `
            -StableIdRegistry $stableIds
        $adapter = Read-CaseKitKcd2Adapter -LiteralPath (Join-Path $repoRoot `
            'config\casekit-kcd2-native.json')
        $backend = ConvertTo-CaseKitKcd2BackendInput `
            -CompiledDefinitions $compiled `
            -Adapter $adapter `
            -SettlementProfiles $profiles

        Add-Result $true 'KCD2 backend adapter module exists'
        Add-Result (
            (@($backend.caseSpecs.id) -join ',') -eq
                'convenient_accident,missing_traveler'
        ) 'adapter emits both stable runtime case IDs'

        $documentEvidence = @($backend.caseSpecs.evidence |
            ForEach-Object { @($_) } | Where-Object {
                $null -ne $_.PSObject.Properties['item']
            })
        Add-Result (
            $documentEvidence.Count -eq 2 -and
            @($documentEvidence | Where-Object {
                $_.destination.mode -eq 'world-container' -and
                -not [string]::IsNullOrWhiteSpace(
                    [string]$_.destination.containerEntityGuid
                )
            }).Count -eq 2
        ) 'backend receives concrete non-shop evidence destinations'

        $legacyCases = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot `
            'content\migration\legacy-cases') -Filter '*.case.json' -File |
            ForEach-Object {
                [System.IO.File]::ReadAllText($_.FullName) |
                    ConvertFrom-Json -Depth 100
            } | Sort-Object code)
        Add-Result (
            (ConvertTo-TestJson $backend.caseSpecs) -ceq
            (ConvertTo-TestJson $legacyCases)
        ) 'authored stories reconstruct the proven CaseSpecs exactly'

        $legacyBindings = [System.IO.File]::ReadAllText((Join-Path $repoRoot `
            'content\migration\legacy-case-settlement-bindings.json')) |
                ConvertFrom-Json -Depth 100
        Add-Result (
            (ConvertTo-TestJson $backend.bindings) -ceq
            (ConvertTo-TestJson $legacyBindings)
        ) 'central profiles reconstruct the proven settlement bindings exactly'
    }
    catch {
        Add-Result $false "KCD2 backend adapter runs: $($_.Exception.Message)"
    }
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
