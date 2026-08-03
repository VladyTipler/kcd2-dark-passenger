Set-StrictMode -Version Latest

$legacyAdapterPath = Join-Path $PSScriptRoot `
    'adapters\kcd2\CaseKit.Legacy.psm1'
Import-Module $legacyAdapterPath -Force
$modelPath = Join-Path $PSScriptRoot 'core\CaseKit.Model.psm1'
Import-Module $modelPath -Force

function Read-CaseKitAuthoringDeck {
    param(
        [Parameter(Mandatory)][string]$LegacyCaseRoot,
        [Parameter(Mandatory)][string]$LegacyBindingPath
    )

    return Read-CaseKitLegacyDeck `
        -CaseRoot $LegacyCaseRoot `
        -BindingPath $LegacyBindingPath
}

function Resolve-CaseKitVariants {
    param([Parameter(Mandatory)]$Deck)

    return Resolve-CaseKitDeckVariants -Deck $Deck
}

function ConvertTo-CaseKitBackendInput {
    param([Parameter(Mandatory)][object[]]$Variants)

    return ConvertTo-CaseKitLegacyBackendInput -Variants $Variants
}

Export-ModuleMember -Function @(
    'ConvertTo-CaseKitBackendInput',
    'Read-CaseKitAuthoringDeck',
    'Resolve-CaseKitVariants'
)
