param(
    [string]$DevGameRoot = $env:KCD2_DEV_ROOT
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptRoot = Join-Path $repoRoot 'src\Data\Scripts\mods'
$resolverPath = Join-Path $scriptRoot 'dpcaseevidence.lua'
$initPath = Join-Path $scriptRoot 'darkpassengertest.lua'
$rumorPath = Join-Path $scriptRoot 'dpevidence.lua'
$documentPath = Join-Path $scriptRoot 'dpbelongings.lua'
$witnessPath = Join-Path $scriptRoot 'dpwitnesslead.lua'
$catalogPath = Join-Path $repoRoot `
    'build\mod\Data\Scripts\mods\generated\dp_case_catalog.lua'

$script:checks = 0
$script:failures = [System.Collections.Generic.List[string]]::new()

function Read-OptionalText([string]$LiteralPath) {
    if (-not (Test-Path -LiteralPath $LiteralPath)) { return '' }
    return [System.IO.File]::ReadAllText($LiteralPath)
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

$resolver = Read-OptionalText $resolverPath
$init = Read-OptionalText $initPath
$rumor = Read-OptionalText $rumorPath
$document = Read-OptionalText $documentPath
$witness = Read-OptionalText $witnessPath
$catalog = Read-OptionalText $catalogPath

Add-Result (Test-Path -LiteralPath $resolverPath) `
    'generic case-evidence resolver exists'
foreach ($export in 'Resolve', 'ResolveActive', 'RunSelfTest') {
    Add-Result (
        $resolver.Contains("function DarkPassengerCaseEvidence.$export")
    ) "case-evidence resolver exports $export"
}
Add-Result (
    $resolver.Contains('local caseTemplate = selected.caseTemplate') -and
    $resolver.Contains('FindEvidence(caseTemplate, role)') -and
    $resolver.Contains('caseTemplate.bindings[role]') -and
    $resolver.Contains('evidence.role == role')
) 'resolver joins selected evidence with semantic binding'
Add-Result (
    $resolver.Contains('candidate.gameRegion') -and
    $resolver.Contains('candidate.settlement') -and
    $resolver.Contains('constraints.region') -and
    $resolver.Contains('constraints.settlement')
) 'resolver rejects a selected case outside the active candidate context'

$catalogIndex = $init.IndexOf(
    'Script.ReloadScript("Scripts/mods/generated/dp_case_catalog.lua")'
)
$caseIndex = $init.IndexOf(
    'Script.ReloadScript("Scripts/mods/dpcasecontent.lua")'
)
$resolverIndex = $init.IndexOf(
    'Script.ReloadScript("Scripts/mods/dpcaseevidence.lua")'
)
$consumerIndex = $init.IndexOf(
    'Script.ReloadScript("Scripts/mods/dpwitnesslead.lua")'
)
Add-Result (
    $catalogIndex -ge 0 -and $caseIndex -gt $catalogIndex -and
    $resolverIndex -gt $caseIndex -and $consumerIndex -gt $resolverIndex
) 'runtime loads catalog, case state, resolver, then consumers'

Add-Result (
    $catalog.Contains('bindings = {') -and
    $catalog.Contains('entityName = "kpri_innkeeper"') -and
    $catalog.Contains('containerGuid = "277db45d-28ac-0286"')
) 'compiled catalog carries semantic world bindings'

Add-Result (
    $rumor.Contains('DarkPassengerCaseEvidence.ResolveActive("innkeeper")') -and
    $rumor.Contains('resolved.binding.entityName') -and
    -not $rumor.Contains('SOURCE_ENTITY_NAME = "kpri_innkeeper"') -and
    -not $rumor.Contains('SOURCE_SETTLEMENT = "pritoky"')
) 'rumor handler resolves the active innkeeper dynamically'
Add-Result (
    $document.Contains('DarkPassengerCaseEvidence.ResolveActive("document")') -and
    $document.Contains('resolved.binding.containerGuid') -and
    $document.Contains('resolved.binding.documentGuid') -and
    $document.Contains('resolved.evidence.code') -and
    $document.Contains('resolved.evidence.id') -and
    $document.Contains('DarkPassengerEvidenceRegistry.Discover(') -and
    -not $document.Contains('EVIDENCE_ID = "vojtech_belongings"')
) 'document handler resolves item, container, reward, and ID dynamically'
Add-Result (
    $witness.Contains('DarkPassengerCaseEvidence.ResolveActive("witness")') -and
    $witness.Contains('resolved.evidence.code') -and
    $witness.Contains('resolved.evidence.confidence') -and
    $witness.Contains('DarkPassengerEvidenceRegistry.Discover(') -and
    $witness.Contains('IsDiscovered(generation, resolved)') -and
    -not $witness.Contains('WITNESS_ENTITY_NAME = "kpri_woman_10"') -and
    -not $witness.Contains('SOURCE_SETTLEMENT = "pritoky"')
) 'witness handler resolves the active witness evidence dynamically'

foreach ($source in @(
    @{ Name = 'rumor'; Text = $rumor; Guard = 'already_awarded' },
    @{ Name = 'document'; Text = $document; Guard = 'already_read' },
    @{ Name = 'witness'; Text = $witness; Guard = 'already_discovered' }
)) {
    Add-Result (
        $source.Text.Contains($source.Guard) -and
        $source.Text.Contains('generation')
    ) "$($source.Name) remains generation-scoped and one-shot"
}

if (-not [string]::IsNullOrWhiteSpace($DevGameRoot)) {
    $luaCompiler = Join-Path $DevGameRoot `
        'Bin\Win64SharedPrivate\LuaCompiler.exe'
    foreach ($path in $resolverPath, $rumorPath, $documentPath, $witnessPath) {
        if (Test-Path -LiteralPath $path) {
            & $luaCompiler -p $path *> $null
            Add-Result ($LASTEXITCODE -eq 0) `
                "LuaCompiler accepts $(Split-Path -Leaf $path)"
        }
    }
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
