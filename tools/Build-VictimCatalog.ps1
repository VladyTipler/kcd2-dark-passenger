param(
    [string]$RawCandidatesPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'evidence\world-candidates.raw.json'),
    [string]$PolicyPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\victim-policy.json'),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\victim-candidates.json')
)

$ErrorActionPreference = 'Stop'

function Write-Utf8NoBom {
    param(
        [string]$LiteralPath,
        [string]$Content
    )

    [System.IO.File]::WriteAllText(
        $LiteralPath,
        $Content,
        [System.Text.UTF8Encoding]::new($false)
    )
}

$raw = Get-Content -Raw -LiteralPath $RawCandidatesPath | ConvertFrom-Json
$policy = Get-Content -Raw -LiteralPath $PolicyPath | ConvertFrom-Json
if ($raw.schemaVersion -ne 1 -or $policy.schemaVersion -ne 1) {
    throw 'Unsupported raw candidate or policy schema.'
}

$manualExclusions = @(
    $policy.manualExclude | ForEach-Object { [string]$_.entityName }
)
$mainStoryDeny = @($policy.mainStoryDeny | ForEach-Object { [string]$_ })
$manualIncludes = @(
    $policy.manualInclude |
        ForEach-Object {
            if ($_ -is [string]) { [string]$_ }
            else { [string]$_.entityName }
        }
)
$candidates = [System.Collections.Generic.List[object]]::new()
$slot = 0

$settlements = @(
    $raw.candidates |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.settlementHint) } |
        Group-Object gameRegion, settlementHint |
        ForEach-Object {
            $first = $_.Group[0]
            [ordered]@{
                id = [string]$first.settlementHint
                gameRegion = [string]$first.gameRegion
                displayName = [string]$first.settlementHint
                center = [ordered]@{
                    x = [math]::Round(
                        [double](($_.Group | Measure-Object -Property { [double]$_.position.x } -Average).Average),
                        3
                    )
                    y = [math]::Round(
                        [double](($_.Group | Measure-Object -Property { [double]$_.position.y } -Average).Average),
                        3
                    )
                    z = [math]::Round(
                        [double](($_.Group | Measure-Object -Property { [double]$_.position.z } -Average).Average),
                        3
                    )
                }
            }
        } |
        Sort-Object gameRegion, id
)

foreach ($settlement in $settlements) {
    $includeGeneric = $policy.defaults.includeGenericSettlementActors -eq $true

    $residents = @(
        $raw.candidates |
            Where-Object {
                $_.gameRegion -eq $settlement.gameRegion -and
                $_.settlementHint -eq $settlement.id -and
                (
                    ($includeGeneric -and $_.characterName -like 'char_GENERIC_*') -or
                    $_.entityName -in $manualIncludes
                ) -and
                $_.entityName -notin $manualExclusions -and
                $_.entityName -notin $mainStoryDeny
            } |
            Sort-Object entityName
    )

    foreach ($resident in $residents) {
        $slot++
        $aliasPrefix = (
            (Get-Culture).TextInfo.ToTitleCase(
                "$($settlement.gameRegion)_$($settlement.id)"
            )
        ) -replace '[^A-Za-z0-9]', ''
        $roleTag = if ($resident.factionName -like '*tradersAndCraftmans*') {
            'merchant'
        }
        else {
            'commoner'
        }

        $candidates.Add([ordered]@{
            slot = $slot
            gameRegion = [string]$settlement.gameRegion
            settlement = [string]$settlement.id
            alias = "$($aliasPrefix)Resident$('{0:D3}' -f $slot)"
            guid = [string]$resident.soulGuid
            entityName = [string]$resident.entityName
            position = $resident.position
            factionName = [string]$resident.factionName
            characterName = [string]$resident.characterName
            tags = @('resident', $roleTag)
            weight = 1
            enabled = $true
            killableVerified = $true
            permanentResident = $true
            mainStoryCritical = $false
            sideQuestRisk = $true
            storyCritical = $false
            questCritical = $false
            immortal = $false
            dead = $false
            sourceEvidence = [ordered]@{
                settlement = 'objects_mission0:regional settlement EditorLayer'
                resident = if ($resident.permanentResidentEvidence) {
                    'objects_mission0:_!home+_@villager_work'
                }
                else {
                    'objects_mission0:regional settlement actor'
                }
                sharedSoul = 'table-souls.json:soul_name'
                narrativePolicy = if ($resident.entityName -in $manualIncludes) {
                    'manually included named actor; side-quest risk allowed'
                }
                else {
                    'generic settlement actor; side-quest risk allowed'
                }
            }
        })
    }
}

$catalog = [ordered]@{
    schemaVersion = 2
    regions = @($policy.regions)
    settlements = @($settlements)
    candidates = @($candidates)
}

Write-Utf8NoBom -LiteralPath $OutputPath -Content (
    ($catalog | ConvertTo-Json -Depth 10) + "`n"
)
Write-Host "Built shipping catalogue with $($candidates.Count) candidates."
