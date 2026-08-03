$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fixtureRoot = Join-Path $PSScriptRoot 'fixtures\world'
$exporterPath = Join-Path $repoRoot 'tools\Export-WorldVictimCandidates.ps1'
$outputPath = Join-Path ([System.IO.Path]::GetTempPath()) `
    'casekit-world-export.json'

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
    & $exporterPath `
        -KuttenbergObjectsPath (Join-Path $fixtureRoot 'objects-kut.xml') `
        -TroskyObjectsPath (Join-Path $fixtureRoot 'objects-tros.xml') `
        -SoulTablePath (Join-Path $fixtureRoot 'souls.json') `
        -OutputPath $outputPath

    $raw = Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json
    Add-Result (
        @($raw.candidates).Count -eq 1 -and
        'fixture_woman' -notin @($raw.candidates.entityName)
    ) 'exporter preserves the legacy victim source without slot drift'
    Add-Result (
        @($raw.actors).Count -eq 2 -and
        'fixture_woman' -in @($raw.actors.entityName)
    ) 'exporter publishes every joined NPC class through the additive actor source'
    Add-Result (
        @($raw.candidates[0].homeLinks).Count -eq 1 -and
        $raw.candidates[0].homeLinks[0].name -eq 'home' -and
        @($raw.candidates[0].workLinks).Count -eq 1 -and
        $raw.candidates[0].workLinks[0].name -eq '_@villager_work'
    ) 'exporter preserves normalized home and work links'
    Add-Result (
        $raw.candidates[0].hasHomeLink -eq $false -and
        $raw.candidates[0].hasVillagerWorkLink -eq $true -and
        $raw.candidates[0].permanentResidentEvidence -eq $false
    ) 'exporter preserves legacy residency booleans for victim catalog parity'
    Add-Result (
        @($raw.containers).Count -eq 1 -and
        $raw.containers[0].entityClass -eq 'Stash' -and
        $raw.containers[0].settlementHint -eq 'fixture'
    ) 'exporter includes settlement stashes as world containers'
}
catch {
    Add-Result $false "KCD2 world exporter runs: $($_.Exception.Message)"
}
finally {
    Remove-Item -LiteralPath $outputPath -Force -ErrorAction SilentlyContinue
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
