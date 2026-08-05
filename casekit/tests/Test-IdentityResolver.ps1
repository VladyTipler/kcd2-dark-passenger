$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$worldPath = Join-Path $repoRoot 'config\world-semantic-index.json'
$profileRoot = Join-Path $repoRoot 'config\settlements'
$identityModule = Join-Path $PSScriptRoot '..\core\CaseKit.Identity.psm1'
$profileModule = Join-Path $PSScriptRoot '..\core\CaseKit.Profiles.psm1'

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

try {
    Import-Module $identityModule -Force
    Import-Module $profileModule -Force

    $world = Get-Content -Raw -LiteralPath $worldPath | ConvertFrom-Json
    $pritoky = Read-CaseKitSettlementProfile -LiteralPath (
        Join-Path $profileRoot 'pritoky.profile.json'
    )
    $zelejov = Read-CaseKitSettlementProfile -LiteralPath (
        Join-Path $profileRoot 'zelejov.profile.json'
    )
    $profiled = Merge-CaseKitSettlementProfile `
        -WorldIndex $world `
        -Profile $pritoky
    $profiled = Merge-CaseKitSettlementProfile `
        -WorldIndex $profiled `
        -Profile $zelejov

    $boguslav = $profiled.entities |
        Where-Object entityName -eq 'tzel_bretislav'
    $boguslavRu = Resolve-CaseKitEntityIdentity `
        -Entity $boguslav `
        -Language 'ru'
    $boguslavEn = Resolve-CaseKitEntityIdentity `
        -Entity $boguslav `
        -Language 'en'
    Add-Result (
        $boguslav.entityGuid -eq 'c82f3c48-2fde-4651' -and
        $boguslav.characterName -eq 'char_PACHOLEK_BRETISLAV' -and
        'role.farmhand' -in @($boguslav.capabilities) -and
        'person.named' -in @($boguslav.capabilities) -and
        'person.identity_review_required' -notin @($boguslav.capabilities) -and
        $boguslavRu.displayLabel -eq 'Богуслав' -and
        $boguslavRu.directionLabel -eq 'батрак при желеевской корчме' -and
        $boguslavRu.localizationKey -eq 'char_PACHOLEK_BRETISLAV' -and
        $boguslavEn.displayLabel -eq 'Bretislav'
    ) 'reviewed Zhelejov identity augments semantics without changing engine IDs'

    $tavernMaid = $profiled.entities |
        Where-Object entityName -eq 'kpri_woman_10'
    $tavernMaidIdentity = Resolve-CaseKitEntityIdentity `
        -Entity $tavernMaid `
        -Language 'ru'
    Add-Result (
        $tavernMaid.identityMode -eq 'titled' -and
        'person.titled' -in @($tavernMaid.capabilities) -and
        'person.identity_review_required' -notin @($tavernMaid.capabilities) -and
        [string]::IsNullOrWhiteSpace([string]$tavernMaidIdentity.name) -and
        $tavernMaidIdentity.displayLabel -eq 'служанка из пржитокской корчмы' -and
        $tavernMaidIdentity.directionLabel -eq 'служанку из корчмы в Пржитоках'
    ) 'reviewed unique role becomes a titled identity without an invented name'

    $anonymous = [pscustomobject]@{
        characterName = 'char_GENERIC_MAN_VILLAGER_01'
        identityMode = 'anonymous'
        identity = [pscustomobject]@{
            localized = [pscustomobject]@{
                ru = [pscustomobject]@{
                    occupation = 'батрак'
                    direction = 'батрака, работающего у конюшни'
                }
                en = [pscustomobject]@{
                    occupation = 'farmhand'
                    direction = 'the farmhand working by the stable'
                }
            }
        }
    }
    $anonymousIdentity = Resolve-CaseKitEntityIdentity `
        -Entity $anonymous `
        -Language 'ru'
    Add-Result (
        [string]::IsNullOrWhiteSpace([string]$anonymousIdentity.name) -and
        $anonymousIdentity.displayLabel -eq 'батрак' -and
        $anonymousIdentity.directionLabel -eq 'батрака, работающего у конюшни'
    ) 'anonymous actor gets a precise direction without an invented name'

    $titled = [pscustomobject]@{
        characterName = 'char_TEST_TITLE'
        identityMode = 'titled'
        identity = [pscustomobject]@{
            localized = [pscustomobject]@{
                ru = [pscustomobject]@{ title = 'корчмарь Желеева' }
                en = [pscustomobject]@{ title = 'Zhelejov innkeeper' }
            }
        }
    }
    $titledIdentity = Resolve-CaseKitEntityIdentity `
        -Entity $titled `
        -Language 'ru'
    Add-Result (
        $titledIdentity.displayLabel -eq 'корчмарь Желеева' -and
        $titledIdentity.directionLabel -eq 'корчмарь Желеева'
    ) 'titled identity uses one verified unique title'

    foreach ($guid in @('277db45d-28ac-0286', 'aaf89994-e94b-0309')) {
        $container = $profiled.entities | Where-Object entityGuid -eq $guid
        Add-Result (
            'container.evidence' -in @($container.capabilities) -and
            -not [string]::IsNullOrWhiteSpace(
                [string]$container.presentation.localized.ru.locationHint
            )
        ) "reviewed evidence container $guid is centrally profiled"
    }

    $relationProfile = [pscustomobject]@{
        schemaVersion = 1
        region = 'trosecko'
        settlement = 'zelejov'
        entities = @(
            [pscustomobject]@{
                entityGuid = 'aaf89994-e94b-0309'
                relations = @(
                    [pscustomobject]@{
                        type = 'home-container-of'
                        targetEntityName = 'tzel_vavrinec'
                    }
                )
            }
        )
    }
    $related = Merge-CaseKitSettlementProfile `
        -WorldIndex $profiled -Profile $relationProfile
    $relatedChest = $related.entities |
        Where-Object entityGuid -eq 'aaf89994-e94b-0309'
    Add-Result (
        @($relatedChest.relations).Count -eq 1 -and
        $relatedChest.relations[0].type -eq 'home-container-of' -and
        $relatedChest.relations[0].targetEntityName -eq 'tzel_vavrinec'
    ) 'profile preserves reviewed actor-container relations'

    $missingProfile = [pscustomobject]@{
        schemaVersion = 1
        region = 'trosecko'
        settlement = 'zelejov'
        entities = @(
            [pscustomobject]@{
                entityName = 'does_not_exist'
                addCapabilities = @('role.test')
            }
        )
    }
    try {
        Merge-CaseKitSettlementProfile `
            -WorldIndex $world `
            -Profile $missingProfile | Out-Null
        Add-Result $false 'profile references absent from world index are rejected'
    }
    catch {
        Add-Result (
            $_.Exception.Message -like '*does_not_exist*not found*'
        ) 'profile references absent from world index are rejected'
    }

    $ambiguousProfile = [pscustomobject]@{
        schemaVersion = 1
        region = 'trosecko'
        settlement = 'zelejov'
        entities = @(
            [pscustomobject]@{
                entityName = 'tzel_man_12'
                identity = [pscustomobject]@{
                    mode = 'titled'
                    localized = [pscustomobject]@{
                        ru = [pscustomobject]@{ title = 'местный житель' }
                        en = [pscustomobject]@{ title = 'local resident' }
                    }
                }
            },
            [pscustomobject]@{
                entityName = 'tzel_man_13'
                identity = [pscustomobject]@{
                    mode = 'titled'
                    localized = [pscustomobject]@{
                        ru = [pscustomobject]@{ title = 'местный житель' }
                        en = [pscustomobject]@{ title = 'local resident' }
                    }
                }
            }
        )
    }
    try {
        Merge-CaseKitSettlementProfile `
            -WorldIndex $world `
            -Profile $ambiguousProfile | Out-Null
        Add-Result $false 'ambiguous titled identities are rejected per settlement'
    }
    catch {
        Add-Result (
            $_.Exception.Message -like '*Ambiguous titled identity*'
        ) 'ambiguous titled identities are rejected per settlement'
    }
}
catch {
    Add-Result $false "identity/profile canary runs: $($_.Exception.Message)"
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
