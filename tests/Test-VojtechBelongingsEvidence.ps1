param(
    [string]$DevGameRoot = $env:KCD2_DEV_ROOT
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptRoot = Join-Path $repoRoot 'src\Data\Scripts\mods'
$belongingsPath = Join-Path $scriptRoot 'dpbelongings.lua'
$seederPath = Join-Path $scriptRoot 'dpevidenceseeder.lua'
$evidencePath = Join-Path $scriptRoot 'dpevidence.lua'
$runtimePath = Join-Path $scriptRoot 'darkpassengertest.lua'
$itemPath = Join-Path $repoRoot `
    'src\Data\Libs\Tables\item\item__darkpassengertest.xml'
$questItemCatalogPath = Join-Path $scriptRoot `
    'generated\dp_quest_item_catalog.lua'
$englishLocalizationPath = Join-Path $repoRoot `
    'localization\English\text__darkpassengertest.xml'
$russianLocalizationPath = Join-Path $repoRoot `
    'localization\Russian\text__darkpassengertest.xml'
$caseSpecPath = Join-Path $repoRoot `
    'content\cases\convenient-accident.case.json'
$bindingPath = Join-Path $repoRoot 'config\case-settlement-bindings.json'

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

$belongings = Read-OptionalText $belongingsPath
$seeder = Read-OptionalText $seederPath
$evidence = Read-OptionalText $evidencePath
$runtime = Read-OptionalText $runtimePath
$itemTable = Read-OptionalText $itemPath
$questItemCatalog = Read-OptionalText $questItemCatalogPath
$englishLocalization = Read-OptionalText $englishLocalizationPath
$russianLocalization = Read-OptionalText $russianLocalizationPath
$caseSpec = Get-Content -Raw -LiteralPath $caseSpecPath |
    ConvertFrom-Json -Depth 100
$bindingManifest = Get-Content -Raw -LiteralPath $bindingPath |
    ConvertFrom-Json -Depth 100
$documentEvidence = @($caseSpec.evidence | Where-Object role -eq 'document')[0]
$documentBinding = @($bindingManifest.settlements | Where-Object {
    $_.region -eq 'kutnohorsko' -and $_.settlement -eq 'pritoky'
})[0].roles.document

Add-Result (Test-Path -LiteralPath $belongingsPath) `
    'Vojtech belongings runtime exists'

foreach ($export in @(
    'Transition',
    'EnsurePlaced',
    'Start',
    'Poll',
    'Status',
    'RunSelfTest'
)) {
    Add-Result (
        $belongings.Contains("function DarkPassengerBelongings.$export")
    ) "belongings runtime exports $export"
}

foreach ($token in
    'DarkPassengerCaseEvidence.ResolveActive("document")',
    'resolved.binding.containerGuid',
    'resolved.binding.documentGuid',
    'resolved.evidence.id',
    'resolved.evidence.confidence',
    'dp_belongings_schema_version',
    'dp_belongings_placed_generation',
    'dp_belongings_read_generation',
    'System.GetEntityByTextGUID(',
    'chest.inventory:CreateItem(',
    'Minigame.WasBookOpened(',
    'Script.SetTimerForFunction(',
    'DarkPassengerInvestigation.AddEvidence('
) {
    Add-Result ($belongings.Contains($token)) `
        "belongings contract contains $token"
}

Add-Result (
    [string]$documentBinding.documentGuid -eq
        '73762008-de9b-4c42-b509-235e63e60840' -and
    [string]$documentEvidence.id -eq 'vojtech_belongings' -and
    [int]$documentEvidence.confidence -eq 30
) 'CaseSpec resolves the custom document and evidence transaction'
Add-Result (
    [string]$documentBinding.legacyDocumentGuid -eq
        '08a31823-a5c6-43f9-9b4b-27b8230a352f'
) 'settlement binding retains the borrowed letter only for canary cleanup'

Add-Result (Test-Path -LiteralPath $itemPath) `
    'custom Vojtech quest-document table exists'
Add-Result (
    -not $questItemCatalog.Contains(
        '73762008-de9b-4c42-b509-235e63e60840'
    )
) 'runtime-created Vojtech document is excluded from the quest-item catalog'

if (Test-Path -LiteralPath $itemPath) {
    try {
        [xml]$itemXml = $itemTable
        $document = $itemXml.SelectSingleNode(
            '//*[local-name()="Document" and @Id="73762008-de9b-4c42-b509-235e63e60840"]'
        )
        Add-Result ($null -ne $document) `
            'custom Vojtech document row is registered'
        Add-Result (
            $null -ne $document -and
            [string]$document.IsQuestItem -ne 'true' -and
            $belongings.Contains('chest.inventory:CreateItem(')
        ) 'runtime-created Vojtech document is not flagged as a quest item'
        Add-Result (
            $null -ne $document -and
            [string]$document.UIName -eq 'dp_vojtech_letter_name' -and
            [string]$document.UIInfo -eq 'dp_vojtech_letter_info' -and
            [string]$document.DocumentContent.Parts -eq
                'dp_vojtech_letter_content'
        ) 'custom Vojtech document owns localized name, info and content'
    }
    catch {
        Add-Result $false 'custom Vojtech document table parses as XML'
    }
}

foreach ($key in
    'dp_vojtech_letter_name',
    'dp_vojtech_letter_info',
    'dp_vojtech_letter_content'
) {
    Add-Result (
        $englishLocalization.Contains("<Cell>$key</Cell>") -and
        $russianLocalization.Contains("<Cell>$key</Cell>")
    ) "quest-document localization parity contains $key"
}

Add-Result (
    $russianLocalization.Contains(
        '<Cell>Неотправленное письмо Войтеха</Cell>'
    ) -and
    $russianLocalization.Contains(
        'с пьяными батраками постоянно случаются несчастья'
    ) -and
    $russianLocalization.Contains(
        'мальчик скребёт ногтями по камням'
    )
) 'Russian localization contains the approved Vojtech letter'

Add-Result (
    $englishLocalization.Contains(
        "<Cell>Vojtech's Unsent Letter</Cell>"
    ) -and
    $englishLocalization.Contains(
        'accidents were always happening to drunken farmhands'
    ) -and
    $englishLocalization.Contains(
        "the boy's fingernails scraping against the stones"
    )
) 'English localization contains the approved Vojtech letter'

Add-Result (
    $belongings.Contains('inventory:DeleteItem(') -and
    $belongings.Contains('resolved.binding.legacyDocumentGuid')
) 'canary cleanup removes old inventory copies through native inventory API'

Add-Result (
    $belongings.Contains('function DarkPassengerBelongings.ResetCanary') -and
    $belongings.Contains('dp_belongings_reset_canary') -and
    $belongings.Contains('DarkPassengerInvestigation.DebugSetConfidence(')
) 'debug canary reset restores the reproducible first-read boundary'

Add-Result (
    -not $belongings.Contains('43e3efd7-6727-0f88')
) 'belongings runtime no longer targets the distant attic chest'

Add-Result (
    $belongings.Contains('state.placedGeneration == generation and exists') -and
    $belongings.Contains('document placement repaired generation=')
) 'persisted placement is repaired when the selected chest has no document'
Add-Result (
    $belongings.Contains('or PlayerInventoryHas(documentGuid)') -and
    $belongings.Contains('if not exists then')
) 'placement never duplicates a document already held by Henry'

Add-Result (
    $belongings -match '(?s)AddEvidence\(\s*resolved\.evidence\.confidence,\s*resolved\.evidence\.id,\s*generation\s*\)'
) 'document read awards the configured evidence transaction'

Add-Result (
    $belongings.Contains('{ generation = generation, timerSerial = timerSerial }') -and
    $belongings.Contains('payload.timerSerial')
) 'poll timers carry generation and serial stale-callback guards'

Add-Result (
    -not $belongings.Contains(':Unlock(') -and
    -not $belongings.Contains('bLocked = false') -and
    -not $belongings.Contains('SetLocked(false)')
) 'runtime preserves vanilla chest access rules'

Add-Result (
    $evidence.Contains('DarkPassengerBelongings.OnRumorAwarded(')
) 'successful rumor starts the belongings step'

Add-Result (Test-Path -LiteralPath $seederPath -PathType Leaf) `
    'generic case-start evidence seeder exists'
Add-Result (
    $seeder.Contains('evidence.placement == "case_start"') -and
    $seeder.Contains('evidence.kind == "document"') -and
    $seeder.Contains('DarkPassengerBelongings.EnsurePlaced(') -and
    $seeder.Contains('DarkPassengerEvidenceRegistry.MarkPlaced(')
) 'case-start seeder places and records compiled document evidence'
Add-Result (
    $seeder.Contains('Script.SetTimerForFunction(') -and
    $seeder.Contains('payload.timerSerial') -and
    $seeder.Contains('payload.generation')
) 'missing streamed containers retry with stale-callback guards'

$restoreMatch = [regex]::Match(
    $evidence,
    '(?s)function DarkPassengerEvidence\.Restore\(investigationState\)(.*?)function DarkPassengerEvidence\.AddRumorAction'
)
Add-Result (
    $restoreMatch.Success -and
    $restoreMatch.Groups[1].Value.Contains(
        'DarkPassengerBelongings.OnRumorAwarded(generation)'
    )
) 'save-load restore repairs belongings for an already-awarded rumor'

$evidenceReload = 'Script.ReloadScript("Scripts/mods/dpevidence.lua")'
$belongingsReload = 'Script.ReloadScript("Scripts/mods/dpbelongings.lua")'
$seederReload = 'Script.ReloadScript("Scripts/mods/dpevidenceseeder.lua")'
$evidenceIndex = $runtime.IndexOf($evidenceReload)
$belongingsIndex = $runtime.IndexOf($belongingsReload)
$seederIndex = $runtime.IndexOf($seederReload)
Add-Result (
    $belongingsIndex -ge 0 -and
    $seederIndex -gt $belongingsIndex -and
    $evidenceIndex -gt $seederIndex
) 'runtime loads document adapter before seeder and rumor producer'

if (-not [string]::IsNullOrWhiteSpace($DevGameRoot)) {
    $compiler = Join-Path $DevGameRoot `
        'Bin\Win64SharedPrivate\LuaCompiler.exe'
    Add-Result (Test-Path -LiteralPath $compiler) 'LuaCompiler is available'
    foreach ($path in $belongingsPath, $seederPath) {
        if ((Test-Path -LiteralPath $compiler) -and
            (Test-Path -LiteralPath $path)) {
            & $compiler -p $path *> $null
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
