param(
    [string]$DevGameRoot = $env:KCD2_DEV_ROOT
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptRoot = Join-Path $repoRoot 'src\Data\Scripts\mods'
$belongingsPath = Join-Path $scriptRoot 'dpbelongings.lua'
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
$evidence = Read-OptionalText $evidencePath
$runtime = Read-OptionalText $runtimePath
$itemTable = Read-OptionalText $itemPath
$questItemCatalog = Read-OptionalText $questItemCatalogPath
$englishLocalization = Read-OptionalText $englishLocalizationPath
$russianLocalization = Read-OptionalText $russianLocalizationPath

Add-Result (Test-Path -LiteralPath $belongingsPath) `
    'Vojtech belongings runtime exists'

foreach ($export in 'Transition', 'Start', 'Poll', 'Status', 'RunSelfTest') {
    Add-Result (
        $belongings.Contains("function DarkPassengerBelongings.$export")
    ) "belongings runtime exports $export"
}

foreach ($token in
    'CHEST_GUID = "277db45d-28ac-0286"',
    'EVIDENCE_ID = "vojtech_belongings"',
    'CONFIDENCE_REWARD = 30',
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
    $belongings -match '(?s)DOCUMENT_GUID\s*=\s*"73762008-de9b-4c42-b509-235e63e60840"'
) 'belongings runtime uses the custom quest-document GUID'
Add-Result (
    $belongings -match '(?s)LEGACY_DOCUMENT_GUID\s*=\s*"08a31823-a5c6-43f9-9b4b-27b8230a352f"'
) 'belongings runtime retains the borrowed letter only for canary cleanup'

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
    $belongings.Contains('DarkPassengerBelongings.LEGACY_DOCUMENT_GUID')
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
    $belongings -match '(?s)AddEvidence\(\s*DarkPassengerBelongings.CONFIDENCE_REWARD,\s*DarkPassengerBelongings.EVIDENCE_ID,\s*generation\s*\)'
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
$evidenceIndex = $runtime.IndexOf($evidenceReload)
$belongingsIndex = $runtime.IndexOf($belongingsReload)
Add-Result (
    $belongingsIndex -ge 0 -and $evidenceIndex -gt $belongingsIndex
) 'runtime loads belongings before the rumor producer calls it'

if (-not [string]::IsNullOrWhiteSpace($DevGameRoot)) {
    $compiler = Join-Path $DevGameRoot `
        'Bin\Win64SharedPrivate\LuaCompiler.exe'
    Add-Result (Test-Path -LiteralPath $compiler) 'LuaCompiler is available'
    if ((Test-Path -LiteralPath $compiler) -and
        (Test-Path -LiteralPath $belongingsPath)) {
        & $compiler -p $belongingsPath *> $null
        Add-Result ($LASTEXITCODE -eq 0) `
            'Vojtech belongings runtime passes LuaCompiler'
    }
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
