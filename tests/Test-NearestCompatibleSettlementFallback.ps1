$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimePath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\darkpassengertest.lua'
$runtime = [System.IO.File]::ReadAllText($runtimePath)

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

function Get-LuaFunction {
    param([Parameter(Mandatory)][string]$Name)
    $escapedName = [regex]::Escape($Name)
    $match = [regex]::Match(
        $runtime,
        "(?ms)^function $escapedName\([^\r\n]*\).*?^end$"
    )
    if (-not $match.Success) {
        throw "Lua function not found: $Name"
    }
    return $match.Value
}

$select = Get-LuaFunction 'DarkPassengerTarget.Select'
$selectNearest = Get-LuaFunction 'DarkPassengerTarget.SelectNearest'

Add-Result (
    $select.Contains('return false, "no_live_candidate"') -and
    $select.Contains('return false, "no_variant"') -and
    $select.Contains('return true, "selected"')
) 'Select reports structured success and retry reasons'

$preflightIndex = $select.IndexOf('PreflightCaseSelection(')
$artifactClearIndex = $select.IndexOf(
    'DarkPassengerCaseLifecycle.ClearCaseArtifacts('
)
$targetClearIndex = $select.IndexOf('DarkPassengerTarget.Clear()')
$commitIndex = $select.IndexOf('DarkPassengerCaseContent.PrepareVariant(')
Add-Result (
    $preflightIndex -ge 0 -and
    $artifactClearIndex -gt $preflightIndex -and
    $targetClearIndex -gt $preflightIndex -and
    $commitIndex -gt $targetClearIndex
) 'selection preflights before destructive cleanup and commits afterward'

Add-Result (
    ([regex]::Matches(
        $select,
        'DarkPassengerCaseContent\.PrepareVariant\('
    )).Count -eq 1
) 'one successful Select commits generation and replay exactly once'

Add-Result (
    $selectNearest.Contains('for _, ranked in ipairs(ordered) do') -and
    $selectNearest.Contains(
        'local selected, reason = DarkPassengerTarget.Select('
    ) -and
    $selectNearest.Contains('if selected then return true, reason end')
) 'nearest selection attempts compatible settlements in distance order'

Add-Result (
    $selectNearest.Contains(
        'reason ~= "no_live_candidate" and reason ~= "no_variant"'
    ) -and
    $selectNearest.Contains('return false, reason')
) 'nearest selection retries only explicitly recoverable failures'

Add-Result (
    -not $selectNearest.Contains('local chosen = ordered[1]') -and
    -not $selectNearest.Substring(
        $selectNearest.IndexOf('for _, ranked in ipairs(ordered) do')
    ).Contains('status = "SELECTING"')
) 'nearest selection does not pin a settlement before Select succeeds'

$compiler =
    'H:\SteamLibrary\steamapps\common\KCD2Mod\Bin\Win64SharedPrivate\LuaCompiler.exe'
if (Test-Path -LiteralPath $compiler -PathType Leaf) {
    & $compiler $runtimePath *> $null
    Add-Result ($LASTEXITCODE -eq 0) 'runtime passes LuaCompiler'
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
