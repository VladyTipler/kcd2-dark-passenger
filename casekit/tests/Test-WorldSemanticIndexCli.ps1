$ErrorActionPreference = 'Stop'

$caseKitRoot = Split-Path -Parent $PSScriptRoot
$cliPath = Join-Path $caseKitRoot 'cli\Build-WorldSemanticIndex.ps1'
$worldPath = Join-Path $PSScriptRoot 'fixtures\world\actors.json'
$victimPath = Join-Path $PSScriptRoot 'fixtures\world\victim-catalog.json'
$outputPath = Join-Path ([System.IO.Path]::GetTempPath()) `
    'casekit-world-index.json'

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
        -RawWorldPath $worldPath `
        -VictimCatalogPath $victimPath `
        -OutputPath $outputPath
    $first = [System.IO.File]::ReadAllBytes($outputPath)
    & $cliPath `
        -RawWorldPath $worldPath `
        -VictimCatalogPath $victimPath `
        -OutputPath $outputPath
    $second = [System.IO.File]::ReadAllBytes($outputPath)

    Add-Result (
        [Convert]::ToHexString($first) -ceq [Convert]::ToHexString($second)
    ) 'CLI output is byte-identical across repeated builds'
    Add-Result (
        -not (
            $second.Length -ge 3 -and
            $second[0] -eq 0xEF -and
            $second[1] -eq 0xBB -and
            $second[2] -eq 0xBF
        )
    ) 'CLI writes UTF-8 without BOM'
    $index = Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json
    Add-Result (@($index.entities).Count -eq 4) `
        'CLI crosses JSON input to semantic output boundary'
}
catch {
    Add-Result $false "world index CLI runs: $($_.Exception.Message)"
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
