$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$cliPath = Join-Path $repoRoot 'casekit\cli\Compile-CaseKit.ps1'
$outputRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    "dark-passenger-authored-cli-$([guid]::NewGuid())"

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

try {
    & $cliPath `
        -ArchetypeRoot (Join-Path $repoRoot 'content\archetypes') `
        -StoryRoot (Join-Path $repoRoot 'content\stories') `
        -EvidenceModuleRoot (Join-Path $repoRoot `
            'content\evidence-modules') `
        -WorldIndexPath (Join-Path $repoRoot `
            'config\world-semantic-index.json') `
        -SettlementCatalogPath (Join-Path $repoRoot `
            'config\settlement-investigation-areas.json') `
        -SettlementProfileRoot (Join-Path $repoRoot `
            'config\settlements') `
        -StableIdRegistryPath (Join-Path $repoRoot `
            'config\casekit-stable-ids.json') `
        -Kcd2AdapterPath (Join-Path $repoRoot `
            'config\casekit-kcd2-native.json') `
        -MaxVariantsPerCombination 1 `
        -OutputRoot $outputRoot

    $compiledPath = Join-Path $outputRoot 'compiled-definitions.json'
    $reportPath = Join-Path $outputRoot 'compatibility-report.json'
    $bindingPath = Join-Path $outputRoot 'case-settlement-bindings.json'
    $caseRoot = Join-Path $outputRoot 'cases'
    Add-Result (
        (Test-Path -LiteralPath $compiledPath -PathType Leaf) -and
        (Test-Path -LiteralPath $reportPath -PathType Leaf) -and
        (Test-Path -LiteralPath $bindingPath -PathType Leaf) -and
        (Test-Path -LiteralPath $caseRoot -PathType Container)
    ) 'authored CLI writes compiled definitions and KCD2 backend input'

    if (Test-Path -LiteralPath $compiledPath -PathType Leaf) {
        $compiled = [System.IO.File]::ReadAllText($compiledPath) |
            ConvertFrom-Json -Depth 100
        Add-Result (
            (@($compiled.stories.storyId | Sort-Object) -join ',') -eq
                'convenient-accident,missing-traveler'
        ) 'production StoryPacks compile through the authored CLI'

        $pritoky = @($compiled.variants | Where-Object {
            $_.settlement -eq 'pritoky'
        })[0]
        $zelejov = @($compiled.variants | Where-Object {
            $_.settlement -eq 'zelejov'
        })[0]
        $zelejovTemplate = @($compiled.variants | Where-Object {
            $_.settlement -eq 'zelejov' -and
            $_.storyId -eq 'missing-traveler'
        })[0]
        Add-Result (
            $null -ne $pritoky -and
            $pritoky.bindings.rumorSource.entityName -eq 'kpri_innkeeper' -and
            $pritoky.bindings.witness.entityName -eq 'kpri_woman_10'
        ) 'Pritoky profile resolves its reviewed dialogue actors'
        Add-Result (
            $null -ne $zelejov -and
            $zelejov.bindings.rumorSource.entityName -eq 'tzel_vavrinec' -and
            $zelejov.bindings.witness.entityName -eq 'tzel_bretislav'
        ) 'Zhelejov profile resolves its reviewed dialogue actors'
        Add-Result (
            $zelejovTemplate.renderedAssets.ru.'direction.paper' -match
                'Желе' -and
            $zelejovTemplate.renderedAssets.en.'direction.paper' -match
                'Zhelejov'
        ) 'settlement profiles provide bilingual display names to templates'

        $troskovice = @($compiled.variants | Where-Object {
            $_.settlement -eq 'troskovice' -and
            $_.storyId -eq 'missing-traveler'
        })[0]
        Add-Result (
            $null -ne $troskovice -and
            $troskovice.bindings.rumorSource.entityName -eq 'ttkc_inkeeper' -and
            $troskovice.bindings.evidenceContainer.entityGuid -and
            $troskovice.bindings.witness.entityName -ne ''
        ) 'real authored CLI compiles Troskovice without a manual profile'
        Add-Result (
            $troskovice.renderedAssets.ru.'case.description' -match
                'Тросковице' -and
            $troskovice.renderedAssets.en.'case.description' -match
                'Troskowitz' -and
            $troskovice.renderedAssets.ru.'case.description' -notmatch
                'Желе'
        ) 'portable StoryPack renders the selected settlement instead of Zhelejov'

        $crossRegionConvenientAccident = @($compiled.variants | Where-Object {
            $_.storyId -eq 'convenient-accident' -and
            $_.region -eq 'trosecko' -and
            $_.settlement -eq 'troskovice'
        })[0]
        $crossRegionMissingTraveler = @($compiled.variants | Where-Object {
            $_.storyId -eq 'missing-traveler' -and
            $_.region -eq 'kutnohorsko' -and
            $_.settlement -eq 'pritoky'
        })[0]
        Add-Result (
            $null -ne $crossRegionConvenientAccident -and
            $null -ne $crossRegionMissingTraveler
        ) 'KCD2 adapter does not restrict portable StoryPacks to legacy regions'
    }

    if (Test-Path -LiteralPath $bindingPath -PathType Leaf) {
        $bindings = [System.IO.File]::ReadAllText($bindingPath) |
            ConvertFrom-Json -Depth 100
        Add-Result (
            @($bindings.settlements | Where-Object {
                [int]$_.caseCode -eq 1001 -and
                $_.region -eq 'trosecko' -and
                $_.settlement -eq 'troskovice'
            }).Count -eq 1 -and
            @($bindings.settlements | Where-Object {
                [int]$_.caseCode -eq 2001 -and
                $_.region -eq 'kutnohorsko' -and
                $_.settlement -eq 'pritoky'
            }).Count -eq 1
        ) 'backend emits exact cross-region settlement bindings'
    }

    if (Test-Path -LiteralPath $caseRoot -PathType Container) {
        $caseSpecs = @(Get-ChildItem -LiteralPath $caseRoot `
            -Filter '*.case.json' -File | ForEach-Object {
                [System.IO.File]::ReadAllText($_.FullName) |
                    ConvertFrom-Json -Depth 100
            })
        Add-Result (
            $caseSpecs.Count -eq 2 -and
            @($caseSpecs.code | Sort-Object -Unique).Count -eq 2
        ) 'cross-region backend keeps one logical CaseSpec per case code'
    }

    if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
        $report = [System.IO.File]::ReadAllText($reportPath) |
            ConvertFrom-Json -Depth 100
        Add-Result (
            @($report.rejected | Where-Object {
                $_.storyId -eq 'missing-traveler' -and
                $_.settlement -eq 'pritoky' -and
                @($_.reasons | Where-Object {
                    [string]$_ -like 'binding render failed:*'
                }).Count -gt 0
            }).Count -eq 0
        ) 'optional absent guidance anchors reject cleanly'
    }
}
catch {
    Add-Result $false "authored CLI accepts settlement profiles: $($_.Exception.Message)"
}
finally {
    if (Test-Path -LiteralPath $outputRoot) {
        Remove-Item -LiteralPath $outputRoot -Recurse -Force
    }
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
