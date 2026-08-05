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
        -SettlementProfileRoot (Join-Path $repoRoot `
            'config\settlements') `
        -StableIdRegistryPath (Join-Path $repoRoot `
            'config\casekit-stable-ids.json') `
        -MaxVariantsPerCombination 1 `
        -OutputRoot $outputRoot

    $compiledPath = Join-Path $outputRoot 'compiled-definitions.json'
    $reportPath = Join-Path $outputRoot 'compatibility-report.json'
    Add-Result (
        (Test-Path -LiteralPath $compiledPath -PathType Leaf) -and
        (Test-Path -LiteralPath $reportPath -PathType Leaf)
    ) 'authored CLI writes compiled definitions and compatibility report'

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
        $pritokyTemplate = @($compiled.variants | Where-Object {
            $_.settlement -eq 'pritoky' -and
            $_.storyId -eq 'missing-traveler'
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
            $pritokyTemplate.renderedAssets.ru.'direction.paper' -match
                'Пржиток' -and
            $zelejovTemplate.renderedAssets.en.'direction.paper' -match
                'Zhelejov'
        ) 'settlement profiles provide bilingual display names to templates'
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
