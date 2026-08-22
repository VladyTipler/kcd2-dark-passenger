$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$rawPath = Join-Path $repoRoot 'evidence\world-candidates.raw.json'
$indexPath = Join-Path $repoRoot 'config\world-semantic-index.json'
$compiledPath = Join-Path $repoRoot `
    'build\generated\casekit\compiler-input\compiled-definitions.json'
$buildScriptPath = Join-Path $repoRoot 'tools\Build-Mod.ps1'
$tradeChestGuid = '042bf770-1c46-03bf'

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

$raw = Get-Content -Raw -LiteralPath $rawPath | ConvertFrom-Json -Depth 20
$index = Get-Content -Raw -LiteralPath $indexPath |
    ConvertFrom-Json -Depth 20
$compiled = Get-Content -Raw -LiteralPath $compiledPath |
    ConvertFrom-Json -Depth 100
$buildScript = [System.IO.File]::ReadAllText($buildScriptPath)

$rawChest = @($raw.containers | Where-Object {
    [string]$_.entityGuid -eq $tradeChestGuid
})
Add-Result (
    $rawChest.Count -eq 1 -and
    [string]$rawChest[0].entityId -eq '23442' -and
    $rawChest[0].shopStash -eq $true
) 'raw world snapshot preserves the native Troskovice shopStash link'

$indexedChest = @($index.entities | Where-Object {
    [string]$_.entityGuid -eq $tradeChestGuid
})
Add-Result (
    $indexedChest.Count -eq 1 -and
    @($indexedChest[0].capabilities) -contains 'container.trade' -and
    @($indexedChest[0].capabilities) -contains 'container.shop' -and
    @($indexedChest[0].capabilities) -notcontains 'container.evidence'
) 'semantic index excludes native trade storage from evidence placement'

Add-Result (
    @($compiled.variants | Where-Object {
        [string]$_.bindings.evidenceContainer.entityGuid -eq $tradeChestGuid -or
        @($_.bindings.evidenceContainer.capabilities) -contains
            'container.trade'
    }).Count -eq 0
) 'compiled variants never bind evidence to trade storage'

$worldIndexBuilderDeclaration = $buildScript.IndexOf(
    "'casekit\cli\Build-WorldSemanticIndex.ps1'"
)
$worldIndexBuild = $buildScript.IndexOf('& $worldIndexBuilderPath')
$caseKitCompile = $buildScript.IndexOf('& $caseKitCompilerPath')
Add-Result (
    $worldIndexBuilderDeclaration -ge 0 -and
    $worldIndexBuild -ge 0 -and
    $caseKitCompile -ge 0 -and
    $worldIndexBuild -lt $caseKitCompile
) 'build refreshes the semantic index before compiling CaseKit'

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
