Set-StrictMode -Version Latest

$legacyAdapterPath = Join-Path $PSScriptRoot `
    'adapters\kcd2\CaseKit.Legacy.psm1'
Import-Module $legacyAdapterPath -Force
$modelPath = Join-Path $PSScriptRoot 'core\CaseKit.Model.psm1'
Import-Module $modelPath -Force
$worldAdapterPath = Join-Path $PSScriptRoot `
    'adapters\kcd2\CaseKit.Kcd2World.psm1'
Import-Module $worldAdapterPath -Force
$worldIndexPath = Join-Path $PSScriptRoot 'core\CaseKit.WorldIndex.psm1'
Import-Module $worldIndexPath -Force
$authoringPath = Join-Path $PSScriptRoot 'core\CaseKit.Authoring.psm1'
Import-Module $authoringPath -Force

function Read-CaseKitAuthoringDeck {
    [CmdletBinding(DefaultParameterSetName = 'Legacy')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Legacy')]
        [string]$LegacyCaseRoot,
        [Parameter(Mandatory, ParameterSetName = 'Legacy')]
        [string]$LegacyBindingPath,
        [Parameter(Mandatory, ParameterSetName = 'Authored')]
        [string]$ArchetypeRoot,
        [Parameter(Mandatory, ParameterSetName = 'Authored')]
        [string]$StoryRoot,
        [Parameter(Mandatory, ParameterSetName = 'Authored')]
        [string]$EvidenceModuleRoot
    )

    if ($PSCmdlet.ParameterSetName -eq 'Authored') {
        return Read-CaseKitAuthoredDeck `
            -ArchetypeRoot $ArchetypeRoot `
            -StoryRoot $StoryRoot `
            -EvidenceModuleRoot $EvidenceModuleRoot
    }
    return Read-CaseKitLegacyDeck `
        -CaseRoot $LegacyCaseRoot `
        -BindingPath $LegacyBindingPath
}

function Resolve-CaseKitVariants {
    param([Parameter(Mandatory)]$Deck)

    return Resolve-CaseKitDeckVariants -Deck $Deck
}

function New-CaseKitWorldIndex {
    param(
        [Parameter(Mandatory)][string]$RawWorldPath,
        [string]$VictimCatalogPath
    )

    $entities = Read-CaseKitKcd2WorldEntities `
        -RawWorldPath $RawWorldPath `
        -VictimCatalogPath $VictimCatalogPath
    return New-CaseKitSemanticWorldIndex -Entities $entities
}

function ConvertTo-CaseKitBackendInput {
    param([Parameter(Mandatory)][object[]]$Variants)

    return ConvertTo-CaseKitLegacyBackendInput -Variants $Variants
}

Export-ModuleMember -Function @(
    'ConvertTo-CaseKitBackendInput',
    'New-CaseKitWorldIndex',
    'Read-CaseKitAuthoringDeck',
    'Resolve-CaseKitVariants'
)
