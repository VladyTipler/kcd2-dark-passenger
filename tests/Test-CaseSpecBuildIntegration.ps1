param(
    [string]$DevGameRoot = $env:KCD2_DEV_ROOT
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($DevGameRoot)) {
    throw 'Set KCD2_DEV_ROOT or pass -DevGameRoot.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$buildScriptPath = Join-Path $repoRoot 'tools\Build-Mod.ps1'
$catalogPath = Join-Path $repoRoot `
    'build\mod\Data\Scripts\mods\generated\dp_case_catalog.lua'
$reportPath = Join-Path $repoRoot `
    'build\generated\cases\case-compatibility.json'
$compilerPath = Join-Path $repoRoot 'tools\Compile-CaseSpecs.ps1'
$belongingsRuntimePath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dpbelongings.lua'

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

& $buildScriptPath -DevGameRoot $DevGameRoot
Add-Result ($?) 'real Build-Mod completes'
Add-Result (Test-Path -LiteralPath $catalogPath) `
    'real build emits compiled case catalog'
Add-Result (Test-Path -LiteralPath $reportPath) `
    'real build emits case compatibility report'

$buildScript = [System.IO.File]::ReadAllText($buildScriptPath)
Add-Result (
    $buildScript.Contains('Compile-CaseSpecs.ps1') -and
    $buildScript.Contains('& $caseCompilerPath')
) 'Build-Mod invokes the CaseSpec compiler'

$catalog = if (Test-Path -LiteralPath $catalogPath) {
    [System.IO.File]::ReadAllText($catalogPath)
}
else { '' }
Add-Result ($catalog.Contains('id = "convenient_accident"')) `
    'staged runtime catalog contains convenient accident'
Add-Result (
    $catalog -match (
        '(?s)id = "matej_guest_ledger",.*?item = \{.*?' +
        'name = "dp_matej_guest_ledger",.*?' +
        'classification = "quest",.*?' +
        'retention = "case",.*?' +
        'contentKey = "dp_mt_ledger_content",'
    )
) 'real build preserves quest-item metadata in the runtime catalog'

$belongingsRuntime = if (Test-Path -LiteralPath $belongingsRuntimePath) {
    [System.IO.File]::ReadAllText($belongingsRuntimePath)
}
else { '' }
Add-Result (
    $belongingsRuntime.Contains(
        'local function IsQuestItemDefinition(resolved, documentGuid)'
    ) -and
    $belongingsRuntime.Contains(
        'DarkPassengerQuestItemCatalog[documentGuid] == true'
    ) -and
    $belongingsRuntime -match (
        '(?s)if IsQuestItemDefinition\(resolved, documentGuid\) then.*?' +
        'DarkPassengerQuestItemPlacement\.Request\(.*?else.*?' +
        'chest\.inventory:CreateItem\(documentGuid, 1, 1\)'
    )
) 'runtime dispatches compiled quest evidence through AddQuestItem bridge'

if (Test-Path -LiteralPath $catalogPath) {
    $luaCompiler = Join-Path $DevGameRoot `
        'Bin\Win64SharedPrivate\LuaCompiler.exe'
    & $luaCompiler -p $catalogPath *> $null
    Add-Result ($LASTEXITCODE -eq 0) `
        'real staged catalog passes LuaCompiler'
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
