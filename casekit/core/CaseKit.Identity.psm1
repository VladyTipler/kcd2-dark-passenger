Set-StrictMode -Version Latest

function Get-CaseKitIdentityProperty {
    param(
        $InputObject,
        [Parameter(Mandatory)][string]$Name,
        $DefaultValue = $null
    )

    if ($null -eq $InputObject) { return $DefaultValue }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $DefaultValue }
    return $property.Value
}

function Resolve-CaseKitEntityIdentity {
    param(
        [Parameter(Mandatory)]$Entity,
        [Parameter(Mandatory)]
        [ValidateSet('ru', 'en')]
        [string]$Language
    )

    $mode = [string](Get-CaseKitIdentityProperty `
        -InputObject $Entity `
        -Name 'identityMode')
    if ($mode -notin @('named', 'titled', 'anonymous')) {
        throw "Entity identity mode '$mode' is not resolved."
    }
    $identity = Get-CaseKitIdentityProperty `
        -InputObject $Entity `
        -Name 'identity'
    $localized = Get-CaseKitIdentityProperty `
        -InputObject $identity `
        -Name 'localized'
    $localizedProperty = if ($null -eq $localized) {
        $null
    }
    else {
        $localized.PSObject.Properties[$Language]
    }
    if ($null -eq $localizedProperty) {
        throw "Identity is missing '$Language' localization."
    }
    $copy = $localizedProperty.Value
    $name = [string](Get-CaseKitIdentityProperty `
        -InputObject $copy -Name 'name' -DefaultValue '')
    $title = [string](Get-CaseKitIdentityProperty `
        -InputObject $copy -Name 'title' -DefaultValue '')
    $occupation = [string](Get-CaseKitIdentityProperty `
        -InputObject $copy -Name 'occupation' -DefaultValue '')
    $direction = [string](Get-CaseKitIdentityProperty `
        -InputObject $copy -Name 'direction' -DefaultValue '')

    switch ($mode) {
        'named' {
            if ([string]::IsNullOrWhiteSpace($name)) {
                throw "Named identity is missing '$Language' name."
            }
            $displayLabel = $name
            if ([string]::IsNullOrWhiteSpace($direction)) {
                $direction = if (
                    [string]::IsNullOrWhiteSpace($occupation)
                ) { $name } else { "$name, $occupation" }
            }
        }
        'titled' {
            if ([string]::IsNullOrWhiteSpace($title)) {
                throw "Titled identity is missing '$Language' title."
            }
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                throw 'Titled identity must not define a personal name.'
            }
            $displayLabel = $title
            if ([string]::IsNullOrWhiteSpace($direction)) {
                $direction = $title
            }
        }
        'anonymous' {
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                throw 'Anonymous identity must not define a personal name.'
            }
            if ([string]::IsNullOrWhiteSpace($occupation)) {
                throw "Anonymous identity is missing '$Language' occupation."
            }
            $displayLabel = $occupation
            if ([string]::IsNullOrWhiteSpace($direction)) {
                $direction = $occupation
            }
        }
    }

    return [ordered]@{
        mode = $mode
        name = $name
        displayLabel = $displayLabel
        directionLabel = $direction
        occupation = $occupation
        localizationKey = [string](Get-CaseKitIdentityProperty `
            -InputObject $Entity `
            -Name 'characterName' `
            -DefaultValue '')
    }
}

Export-ModuleMember -Function 'Resolve-CaseKitEntityIdentity'
