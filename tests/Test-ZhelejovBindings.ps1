param(
    [string]$ReferenceDataRoot = $env:KCD2_REFERENCE_DATA_ROOT,
    [string]$DevGameRoot = $env:KCD2_DEV_ROOT
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ReferenceDataRoot)) {
    throw 'Set KCD2_REFERENCE_DATA_ROOT or pass -ReferenceDataRoot.'
}
if ([string]::IsNullOrWhiteSpace($DevGameRoot)) {
    throw 'Set KCD2_DEV_ROOT or pass -DevGameRoot.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$bindingPath = Join-Path $repoRoot 'config\case-settlement-bindings.json'
$candidatePath = Join-Path $repoRoot 'config\victim-candidates.json'
$policyPath = Join-Path $repoRoot 'config\victim-policy.json'
$evidencePath = Join-Path $repoRoot 'evidence\zhelejov-case-bindings.md'
$missionPath = Join-Path $ReferenceDataRoot `
    'trosecko\tros_objects_mission0.xml'
$soulPath = Join-Path $DevGameRoot `
    'Data\Libs\CryHttp\xzar2\table-souls.json'

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

foreach ($path in @(
    $bindingPath,
    $candidatePath,
    $policyPath,
    $missionPath,
    $soulPath
)) {
    Add-Result (Test-Path -LiteralPath $path -PathType Leaf) `
        "binding evidence exists: $path"
}

$bindings = Get-Content -Raw -LiteralPath $bindingPath |
    ConvertFrom-Json -Depth 100
$catalog = Get-Content -Raw -LiteralPath $candidatePath |
    ConvertFrom-Json -Depth 100
$policy = Get-Content -Raw -LiteralPath $policyPath |
    ConvertFrom-Json -Depth 100
$mission = [System.IO.File]::ReadAllText($missionPath)
$souls = Get-Content -Raw -LiteralPath $soulPath |
    ConvertFrom-Json -AsHashtable

$zhelejov = @($bindings.settlements | Where-Object {
    $_.region -eq 'trosecko' -and $_.settlement -eq 'zelejov'
})
Add-Result ($zhelejov.Count -eq 1) `
    'Zhelejov has one settlement binding'

$binding = if ($zhelejov.Count -eq 1) { $zhelejov[0] } else { $null }
Add-Result (
    $null -ne $binding -and
    $binding.roles.innkeeper.entityName -eq 'tzel_vavrinec' -and
    $binding.roles.innkeeper.dialogueRole -eq 'DP_INNKEEPER_RUMOR'
) 'binding selects the native Zhelejov innkeeper'
Add-Result (
    $null -ne $binding -and
    $binding.roles.witness.entityName -eq 'tzel_bretislav' -and
    $binding.roles.witness.dialogueRole -eq 'DP_TAVERN_WITNESS'
) 'binding selects native Zhelejov tavern staff as witness'
Add-Result (
    $null -ne $binding -and
    $binding.roles.document.containerGuid -eq 'aaf89994-e94b-0309' -and
    $binding.roles.document.documentGuid -match `
        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
) 'binding selects the locked upper-floor inn chest and a full item GUID'

$soulRows = @($souls.Values)
$innkeeperSoul = @($soulRows | Where-Object soul_name -eq 'tzel_vavrinec')
$witnessSoul = @($soulRows | Where-Object soul_name -eq 'tzel_bretislav')
Add-Result (
    $innkeeperSoul.Count -eq 1 -and
    $innkeeperSoul[0].character_name -eq 'char_HOSPODSKY_VAVRINEC_TICHOTA' -and
    $innkeeperSoul[0].faction_name -eq `
        'trosecko_settlements_zelejov_commonFolk_tavern_staff'
) 'native soul registry confirms Vavrinec is Zhelejov tavern staff'
Add-Result (
    $witnessSoul.Count -eq 1 -and
    $witnessSoul[0].character_name -eq 'char_PACHOLEK_BRETISLAV' -and
    $witnessSoul[0].faction_name -eq `
        'trosecko_settlements_zelejov_commonFolk_tavern_staff'
) 'native soul registry confirms Bretislav is Zhelejov tavern staff'

Add-Result (
    $mission -match `
        '<Entity Name="tzel_vavrinec"[^>]+EditorLayer="Main/tzel_zelejov/inn/_script/npc/vavrinec"'
) 'world export places Vavrinec in the Zhelejov inn layer'
Add-Result (
    $mission -match `
        '<Entity Name="tzel_bretislav"[^>]+EditorLayer="Main/tzel_zelejov/inn/_script/npc/bretislav"'
) 'world export places Bretislav in the Zhelejov inn layer'
Add-Result (
    $mission -match (
        '<Entity[^>]+Pos="1657\.628,2145\.149,38\.70087"[^>]+' +
        'EntityClass="Stash"[^>]+EntityGuid="aaf89994-e94b-0309"[^>]+' +
        'EditorLayer="Main/tzel_zelejov/inn/_common"'
    ) -and
    $mission -match `
        '<Lock fLockDifficulty="0\.5" bLockDifficultyOverride="1" bLocked="1" />'
) 'world export confirms the selected locked upper-floor stash'

$eligibleTargets = @($catalog.candidates | Where-Object {
    $_.gameRegion -eq 'trosecko' -and
    $_.settlement -eq 'zelejov' -and
    $_.enabled -eq $true -and
    $_.dead -eq $false -and
    $_.killableVerified -eq $true -and
    $_.mainStoryCritical -eq $false -and
    $_.characterName -like 'char_GENERIC_MAN_*'
})
Add-Result ($eligibleTargets.Count -ge 10) `
    'Zhelejov retains a non-empty enabled male target pool'
Add-Result (
    @($eligibleTargets | Where-Object entityName -eq 'tzel_bretislav').Count -eq 0
) 'semantic witness is excluded from the target pool'
Add-Result (Test-Path -LiteralPath $evidencePath -PathType Leaf) `
    'binding discovery is recorded as durable evidence'

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
