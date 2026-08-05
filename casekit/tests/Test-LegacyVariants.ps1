$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$manifestPath = Join-Path $PSScriptRoot '..\CaseKit.psd1'
$caseRoot = Join-Path $repoRoot 'content\migration\legacy-cases'
$bindingPath = Join-Path $repoRoot `
    'content\migration\legacy-case-settlement-bindings.json'

Import-Module $manifestPath -Force

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

function Copy-JsonValue($Value) {
    return $Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
}

$deck = Read-CaseKitAuthoringDeck `
    -LegacyCaseRoot $caseRoot `
    -LegacyBindingPath $bindingPath

try {
    $variants = @(Resolve-CaseKitVariants -Deck $deck)
    Add-Result ($variants.Count -eq 2) `
        'one neutral variant is resolved for each legacy case'
    Add-Result (
        (@($variants | ForEach-Object variantId) -join ',') -eq
            'convenient_accident--kutnohorsko--pritoky,' +
            'missing_traveler--trosecko--zelejov'
    ) 'legacy variant IDs are deterministic'

    $missingTraveler = @($variants | Where-Object {
        [int]$_.case.code -eq 2001
    })[0]
    Add-Result (
        $missingTraveler.story.crimeProfile.innocentVictim -eq 'matej' -and
        $null -eq $missingTraveler.story.PSObject.Properties['roles']
    ) 'authored story is isolated from concrete world roles'
    Add-Result (
        $missingTraveler.world.region -eq 'trosecko' -and
        $missingTraveler.world.settlement -eq 'zelejov' -and
        $missingTraveler.world.roles.innkeeper.entityName -eq 'tzel_vavrinec'
    ) 'variant carries its concrete settlement binding'
}
catch {
    Add-Result $false "legacy variants resolve: $($_.Exception.Message)"
}

$missingBindingDeck = Copy-JsonValue $deck
$missingBindingDeck.settlements = @(
    $missingBindingDeck.settlements | Where-Object settlement -ne 'zelejov'
)
try {
    Resolve-CaseKitVariants -Deck $missingBindingDeck | Out-Null
    Add-Result $false 'missing required settlement binding is rejected'
}
catch {
    Add-Result (
        $_.Exception.Message -eq
            "Case 'missing_traveler' requires exactly one binding for " +
            "'trosecko/zelejov'; found 0."
    ) 'missing required settlement binding is rejected'
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
