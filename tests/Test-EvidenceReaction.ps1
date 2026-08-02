param(
    [string]$DevGameRoot = $env:KCD2_DEV_ROOT
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimePath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dpevidencereaction.lua'
$belongingsPath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dpbelongings.lua'
$initPath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\darkpassengertest.lua'
$tagPath = Join-Path $repoRoot `
    'src\Data\Libs\Tables\rpg\buff_ai_tag__darkpassengertest.xml'
$buffPath = Join-Path $repoRoot `
    'src\Data\Libs\Tables\rpg\buff__darkpassengertest.xml'
$templatePath = Join-Path $repoRoot `
    'src\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml.template'
$generatorPath = Join-Path $repoRoot 'tools\Generate-VictimArtifacts.ps1'
$dialogRoot = Join-Path $repoRoot `
    'src\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k'

$script:checks = 0
$script:failures = [System.Collections.Generic.List[string]]::new()

function Read-OptionalText {
    param([string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath)) { return '' }
    return Get-Content -Raw -LiteralPath $LiteralPath
}

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

$runtime = Read-OptionalText $runtimePath
$belongings = Read-OptionalText $belongingsPath
$init = Read-OptionalText $initPath
$tags = Read-OptionalText $tagPath
$buffs = Read-OptionalText $buffPath
$template = Read-OptionalText $templatePath
$generator = Read-OptionalText $generatorPath

Add-Result (Test-Path -LiteralPath $runtimePath) `
    'reusable evidence-reaction runtime exists'

foreach ($token in @(
    'function DarkPassengerEvidenceReaction.Dispatch(',
    'function DarkPassengerEvidenceReaction.Restore(',
    'function DarkPassengerEvidenceReaction.Reset(',
    'DarkPassengerEvidenceReaction.METAROLE = "HRAC_VYPNUL_PHOTOMODE"',
    'DialogUtils.RequestPlayerMonologByMetarole(',
    'dispatchedGeneration'
)) {
    Add-Result ($runtime.Contains($token)) `
        "direct reaction runtime contains $token"
}

$dispatchStart = $runtime.IndexOf(
    'function DarkPassengerEvidenceReaction.Dispatch('
)
$restoreStart = $runtime.IndexOf(
    'function DarkPassengerEvidenceReaction.Restore('
)
$dispatchBody = if ($dispatchStart -ge 0 -and $restoreStart -gt $dispatchStart) {
    $runtime.Substring($dispatchStart, $restoreStart - $dispatchStart)
} else {
    ''
}
Add-Result (
    $dispatchBody.Contains('DialogUtils.RequestPlayerMonologByMetarole(')
) 'reaction dispatch calls the live-proven vanilla metarole route'
Add-Result (
    -not $dispatchBody.Contains(':AddBuff(')
) 'reaction dispatch has no buff bridge'

Add-Result (
    $init.Contains(
        'Script.ReloadScript("Scripts/mods/dpevidencereaction.lua")'
    )
) 'mod init loads reaction runtime before evidence producers'

$persistIndex = $belongings.IndexOf('PersistState(nextState)')
$dispatchIndex = $belongings.IndexOf(
    'DarkPassengerEvidenceReaction.Dispatch('
)
Add-Result (
    $persistIndex -ge 0 -and $dispatchIndex -gt $persistIndex
) 'belongings persist the accepted read before reaction dispatch'

$obsoleteTokens = @(
    'dp_evidence_reaction_interesting',
    'dp_evidence_reaction_useful',
    'dp_evidence_reaction_hmm',
    '882e2544-63d3-400a-b28c-bff3d5afd6cb',
    '066bdb65-b78d-4a1b-80e7-e23110fc77c3',
    'c1c4877a-6f8b-49d9-819f-740d910dbc34',
    'dark_within_k_evidenceInteresting',
    'dark_within_k_evidenceUseful',
    'dark_within_k_evidenceHmm',
    '{{DP_EVIDENCE_REACTION_NODES}}'
)
$obsoleteSurface = @($runtime, $tags, $buffs, $template, $generator) -join "`n"
foreach ($token in $obsoleteTokens) {
    Add-Result (-not $obsoleteSurface.Contains($token)) `
        "obsolete reaction artifact is absent: $token"
}

foreach ($dialogName in @(
    'evidence_reaction_interesting.xml',
    'evidence_reaction_useful.xml',
    'evidence_reaction_hmm.xml'
)) {
    Add-Result (
        -not (Test-Path -LiteralPath (Join-Path $dialogRoot $dialogName))
    ) "obsolete reaction dialog is absent: $dialogName"
}

foreach ($token in @(
    'DarkPassengerEvidenceReaction.REACTIONS',
    'function DarkPassengerEvidenceReaction.Choose(',
    'function DarkPassengerEvidenceReaction.ClearSignal(',
    'selectedGeneration',
    'selectedIndex',
    'RemoveAllSignals('
)) {
    Add-Result (-not $runtime.Contains($token)) `
        "runtime no longer contains $token"
}

if (-not [string]::IsNullOrWhiteSpace($DevGameRoot)) {
    $compiler = Join-Path $DevGameRoot `
        'Bin\Win64SharedPrivate\LuaCompiler.exe'
    Add-Result (Test-Path -LiteralPath $compiler) 'LuaCompiler is available'
    if ((Test-Path -LiteralPath $compiler) -and
        (Test-Path -LiteralPath $runtimePath)) {
        & $compiler -p $runtimePath *> $null
        Add-Result ($LASTEXITCODE -eq 0) `
            'evidence-reaction runtime passes LuaCompiler'
    }
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
