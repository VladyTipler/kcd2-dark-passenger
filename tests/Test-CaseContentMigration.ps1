param(
    [string]$DevGameRoot = $env:KCD2_DEV_ROOT
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptRoot = Join-Path $repoRoot 'src\Data\Scripts\mods'
$runtimePath = Join-Path $scriptRoot 'darkpassengertest.lua'
$caseRuntimePath = Join-Path $scriptRoot 'dpcasecontent.lua'
$snapshotPath = Join-Path $scriptRoot 'dpcasesnapshot.lua'
$sceneDirectorPath = Join-Path $scriptRoot 'dpcasescenedirector.lua'
$seederPath = Join-Path $scriptRoot 'dpevidenceseeder.lua'
$caseSpecPath = Join-Path $repoRoot `
    'content\migration\legacy-cases\convenient-accident.case.json'
$generatedCatalogPath = Join-Path $repoRoot `
    'build\mod\Data\Scripts\mods\generated\dp_case_catalog.lua'
$caseKitManifestPath = Join-Path $repoRoot 'casekit\CaseKit.psd1'
$archetypeRoot = Join-Path $repoRoot 'content\archetypes'
$storyRoot = Join-Path $repoRoot 'content\stories'
$evidenceModuleRoot = Join-Path $repoRoot 'content\evidence-modules'
$stableIdRegistryPath = Join-Path $repoRoot `
    'config\casekit-stable-ids.json'

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

$runtime = [System.IO.File]::ReadAllText($runtimePath)
$caseRuntime = [System.IO.File]::ReadAllText($caseRuntimePath)
$snapshot = if (Test-Path -LiteralPath $snapshotPath) {
    [System.IO.File]::ReadAllText($snapshotPath)
}
else { '' }
$seeder = if (Test-Path -LiteralPath $seederPath) {
    [System.IO.File]::ReadAllText($seederPath)
}
else { '' }
$caseSpec = Get-Content -Raw -LiteralPath $caseSpecPath |
    ConvertFrom-Json -Depth 100
$catalog = if (Test-Path -LiteralPath $generatedCatalogPath) {
    [System.IO.File]::ReadAllText($generatedCatalogPath)
}
else { '' }

Add-Result ($caseRuntime.Contains('SCHEMA_VERSION = 4')) `
    'case-content state uses schema v4'
foreach ($token in @(
    'dp_case_content_case_code',
    'dp_case_content_opener_code',
    'dp_case_content_variant_code',
    'dp_case_content_previous_variant_code',
    'dp_case_content_innkeeper_actor_code',
    'dp_case_content_witness_actor_code',
    'caseCode',
    'openerCode',
    'function DarkPassengerCaseContent.MigrateLegacyState',
    '[1] = { caseCode = 1001, openerCode = 1101 }',
    'reason = "legacy_v1"',
    'DarkPassengerCaseCatalogByCode'
)) {
    Add-Result ($caseRuntime.Contains($token)) `
        "schema v4 runtime contains $token"
}

Add-Result (
    $caseRuntime.Contains('legacy.templateSlot') -and
    $caseRuntime.Contains('legacy.rumorSlot') -and
    $caseRuntime.Contains('generation = tonumber(legacy.generation)')
) 'legacy migration preserves investigation generation'
Add-Result (
    $caseRuntime.Contains('if schema == 3 then') -and
    $caseRuntime.Contains('innkeeperActorCode = 0') -and
    $caseRuntime.Contains('witnessActorCode = 0') -and
    $caseRuntime.Contains(
        'actor bindings are resolved from the generated pool'
    )
) 'schema-v3 migration keeps case identity and resolves generated actor bindings'
Add-Result (
    $caseRuntime.Contains('if schema == 2 then') -and
    $caseRuntime.Contains('variantCode = 0') -and
    $caseRuntime.Contains('no variant is rerolled')
) 'schema-v2 migration preserves the active legacy target without reroll'
Add-Result (
    $caseRuntime.Contains('if nextState.generation == generation then') -and
    $caseRuntime.Contains(
        'DarkPassengerCaseContent.Resolve(nextState, catalog) ~= nil'
    ) -and
    $caseRuntime.Contains('reason = "invalid_saved_selection"') -and
    $caseRuntime.Contains('reason = "restored"')
) 'same generation restores stable identity without reroll'
Add-Result (
    $snapshot.Contains('allowBindingMigration') -and
    $snapshot.Contains('reason = "variant_migrated"') -and
    $snapshot.Contains('DarkPassengerCaseVariantCatalogByCode')
) 'snapshot replaces only obsolete generated bindings for the same target'

Add-Result (
    [int]$caseSpec.evidence[0].code -eq 1101 -and
    [int]$caseSpec.evidence[1].code -eq 1102 -and
    [int]$caseSpec.evidence[2].code -eq 1103
) 'all evidence steps have stable codes'
Add-Result (
    $catalog.Contains('code = 1101') -and
    $catalog.Contains('code = 1102') -and
    $catalog.Contains('code = 1103')
) 'generated catalog contains stable evidence codes'

$generatedReload =
    'Script.ReloadScript("Scripts/mods/generated/dp_case_catalog.lua")'
$caseRuntimeReload = 'Script.ReloadScript("Scripts/mods/dpcasecontent.lua")'
$legacyReload =
    'Script.ReloadScript("Scripts/mods/content/dp_case_convenient_accident.lua")'
Add-Result (
    $runtime.IndexOf($generatedReload) -ge 0 -and
    $runtime.IndexOf($caseRuntimeReload) -gt $runtime.IndexOf($generatedReload)
) 'runtime loads generated catalog before case state'
Add-Result (-not $runtime.Contains($legacyReload)) `
    'runtime no longer loads authored Lua case duplicate'

Add-Result (Test-Path -LiteralPath $snapshotPath -PathType Leaf) `
    'immutable case snapshot runtime exists'
foreach ($export in 'Transition', 'Capture', 'Get', 'Restore', 'RunSelfTest') {
    Add-Result (
        $snapshot.Contains("function DarkPassengerCaseSnapshot.$export")
    ) "case snapshot exports $export"
}
foreach ($key in @(
    'dp_case_snapshot_schema_version',
    'dp_case_snapshot_generation',
    'dp_case_snapshot_case_code',
    'dp_case_snapshot_opener_code',
    'dp_case_snapshot_target_slot'
)) {
    Add-Result ($snapshot.Contains($key)) "case snapshot persists $key"
}
Add-Result (
    $snapshot.Contains('candidate.gameRegion') -and
    $snapshot.Contains('candidate.settlement') -and
    $snapshot.Contains('caseTemplate.bindings') -and
    $snapshot.Contains('snapshot_conflict') -and
    -not $snapshot.Contains('containerGuid = ReadScalar')
) 'snapshot derives world bindings from stable numeric references'
Add-Result (
    $caseRuntime.IndexOf('PersistState(nextState)') -lt
        $caseRuntime.IndexOf('DarkPassengerCaseSnapshot.Capture(') -and
    $caseRuntime.IndexOf('DarkPassengerCaseSnapshot.Capture(') -lt
        $caseRuntime.IndexOf('DarkPassengerSceneDirector.Materialize(') -and
    ([System.IO.File]::ReadAllText($sceneDirectorPath)).Contains(
        'DarkPassengerEvidenceSeeder.Seed('
    )
) 'case selection persists snapshot before evidence seeding'

$snapshotReload = 'Script.ReloadScript("Scripts/mods/dpcasesnapshot.lua")'
$sceneDirectorReload =
    'Script.ReloadScript("Scripts/mods/dpcasescenedirector.lua")'
$seederReload = 'Script.ReloadScript("Scripts/mods/dpevidenceseeder.lua")'
Add-Result (
    $runtime.IndexOf($snapshotReload) -gt $runtime.IndexOf($caseRuntimeReload) -and
    $runtime.IndexOf($sceneDirectorReload) -gt $runtime.IndexOf($snapshotReload) -and
    $runtime.IndexOf($seederReload) -gt $runtime.IndexOf($sceneDirectorReload)
) 'runtime loads case state, snapshot, director, then evidence seeder'

try {
    Import-Module $caseKitManifestPath -Force
    $authoredDeck = Read-CaseKitAuthoringDeck `
        -ArchetypeRoot $archetypeRoot `
        -StoryRoot $storyRoot `
        -EvidenceModuleRoot $evidenceModuleRoot
    Add-Result (
        (@($authoredDeck.sourceSchemaVersions) -join ',') -eq '2'
    ) 'production cases use only schema-v2 StoryPack packages'
    Add-Result (
        (@($authoredDeck.stories.id | Sort-Object) -join ',') -eq
            'convenient-accident,missing-traveler'
    ) 'both production cases load from StoryPack packages'

    $storyFiles = @(Get-ChildItem -LiteralPath $storyRoot -Recurse -File)
    $forbiddenNativeContent = @($storyFiles | Where-Object {
        $text = [System.IO.File]::ReadAllText($_.FullName)
        $text -match (
            '"(?:cameraGuid|coordinates|entityGuid|modelPath|' +
            'soulGuid|worldPosition)"'
        )
    })
    Add-Result (
        $forbiddenNativeContent.Count -eq 0
    ) 'StoryPack sources contain no native world or camera identifiers'
}
catch {
    Add-Result $false (
        "production StoryPack deck loads: $($_.Exception.Message)"
    )
    Add-Result $false 'both production cases load from StoryPack packages'
    Add-Result $false 'StoryPack sources contain no native identifiers'
}

if (Test-Path -LiteralPath $stableIdRegistryPath -PathType Leaf) {
    $stableIds = [System.IO.File]::ReadAllText($stableIdRegistryPath) |
        ConvertFrom-Json -Depth 100
    $stableStories = @($stableIds.stories | Sort-Object caseCode)
    Add-Result (
        (@($stableStories.caseCode) -join ',') -eq '1001,2001'
    ) 'stable registry preserves case codes 1001 and 2001'
    Add-Result (
        (@($stableStories.evidence.code) -join ',') -eq
            '1101,1102,1103,2101,2102,2103,2104'
    ) 'stable registry preserves all evidence codes'
}
else {
    Add-Result $false 'stable registry preserves case codes 1001 and 2001'
    Add-Result $false 'stable registry preserves all evidence codes'
}

if (-not [string]::IsNullOrWhiteSpace($DevGameRoot)) {
    $luaCompiler = Join-Path $DevGameRoot `
        'Bin\Win64SharedPrivate\LuaCompiler.exe'
    foreach ($path in @(
        $caseRuntimePath,
        $snapshotPath,
        $seederPath,
        $generatedCatalogPath
    )) {
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
