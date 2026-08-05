Set-StrictMode -Version Latest

function Get-CaseKitProfileProperty {
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

function Read-CaseKitSettlementProfile {
    param([Parameter(Mandatory)][string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "Settlement profile not found: $LiteralPath"
    }
    $profile = Get-Content -Raw -LiteralPath $LiteralPath | ConvertFrom-Json
    if ([int]$profile.schemaVersion -ne 1) {
        throw "Unsupported settlement profile schema '$($profile.schemaVersion)'."
    }
    foreach ($field in @('region', 'settlement')) {
        if ([string]::IsNullOrWhiteSpace([string]$profile.$field)) {
            throw "Settlement profile is missing '$field'."
        }
    }
    foreach ($language in @('ru', 'en')) {
        $localized = $profile.localized.PSObject.Properties[$language]
        if ($null -eq $localized -or
            [string]::IsNullOrWhiteSpace(
                [string]$localized.Value.displayName
            )) {
            throw "Settlement profile is missing '$language' displayName."
        }
    }
    $anonymousIdentity = Get-CaseKitProfileProperty `
        -InputObject $profile -Name 'anonymousIdentity'
    if ($null -ne $anonymousIdentity) {
        Test-CaseKitProfileIdentity -Identity $anonymousIdentity `
            -Selector "$($profile.region)/$($profile.settlement)/anonymous"
        if ([string]$anonymousIdentity.mode -ne 'anonymous') {
            throw 'Settlement anonymousIdentity must use anonymous mode.'
        }
    }
    return $profile
}

function Test-CaseKitProfileIdentity {
    param(
        [Parameter(Mandatory)]$Identity,
        [Parameter(Mandatory)][string]$Selector
    )

    $mode = [string]$Identity.mode
    if ($mode -notin @('named', 'titled', 'anonymous')) {
        throw "Profile '$Selector' has unsupported identity mode '$mode'."
    }
    foreach ($language in @('ru', 'en')) {
        $property = $Identity.localized.PSObject.Properties[$language]
        if ($null -eq $property) {
            throw "Profile '$Selector' is missing '$language' identity."
        }
        $copy = $property.Value
        $name = [string](Get-CaseKitProfileProperty `
            -InputObject $copy -Name 'name' -DefaultValue '')
        $title = [string](Get-CaseKitProfileProperty `
            -InputObject $copy -Name 'title' -DefaultValue '')
        $occupation = [string](Get-CaseKitProfileProperty `
            -InputObject $copy -Name 'occupation' -DefaultValue '')
        if ($mode -eq 'named' -and [string]::IsNullOrWhiteSpace($name)) {
            throw "Profile '$Selector' named identity is missing '$language' name."
        }
        if ($mode -eq 'titled' -and [string]::IsNullOrWhiteSpace($title)) {
            throw "Profile '$Selector' titled identity is missing '$language' title."
        }
        if (
            $mode -eq 'anonymous' -and
            [string]::IsNullOrWhiteSpace($occupation)
        ) {
            throw "Profile '$Selector' anonymous identity is missing '$language' occupation."
        }
        if ($mode -ne 'named' -and -not [string]::IsNullOrWhiteSpace($name)) {
            throw "Profile '$Selector' $mode identity must not define a name."
        }
    }
}

function Merge-CaseKitProfileRelations {
    param(
        [Parameter(Mandatory)]$WorldIndex,
        [Parameter(Mandatory)]$Entity,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Relations,
        [Parameter(Mandatory)][string]$Selector,
        [Parameter(Mandatory)]$Profile
    )

    if ($Relations.Count -eq 0) { return }
    if ([string]$Entity.kind -ne 'container') {
        throw "Profile entity '$Selector' relations require a container."
    }
    if (
        @($Entity.capabilities) -contains 'container.shop' -or
        @($Entity.capabilities) -contains 'container.trade'
    ) {
        throw "Profile entity '$Selector' is trade storage and cannot own " +
            'evidence relations.'
    }

    $allowed = @('personal-container-of', 'home-container-of')
    $merged = [System.Collections.Generic.List[object]]::new()
    foreach ($existing in @(Get-CaseKitProfileProperty `
        -InputObject $Entity -Name 'relations' -DefaultValue @())) {
        $merged.Add($existing)
    }
    foreach ($relation in $Relations) {
        $type = [string](Get-CaseKitProfileProperty `
            -InputObject $relation -Name 'type' -DefaultValue '')
        $targetName = [string](Get-CaseKitProfileProperty `
            -InputObject $relation -Name 'targetEntityName' -DefaultValue '')
        if ($allowed -notcontains $type) {
            throw "Profile entity '$Selector' has unsupported relation " +
                "'$type'."
        }
        if ([string]::IsNullOrWhiteSpace($targetName)) {
            throw "Profile entity '$Selector' relation '$type' requires " +
                'targetEntityName.'
        }
        $targets = @($WorldIndex.entities | Where-Object {
            [string]$_.region -eq [string]$Profile.region -and
            [string]$_.settlement -eq [string]$Profile.settlement -and
            [string]$_.kind -eq 'actor' -and
            [string]$_.entityName -eq $targetName
        })
        if ($targets.Count -ne 1) {
            throw "Profile entity '$Selector' relation target " +
                "'$targetName' must match exactly one actor."
        }
        $duplicate = @($merged | Where-Object {
            [string]$_.type -eq $type -and
            [string]$_.targetEntityName -eq $targetName
        }).Count -gt 0
        if (-not $duplicate) {
            $merged.Add([pscustomobject][ordered]@{
                type = $type
                targetEntityName = $targetName
            })
        }
    }
    $Entity | Add-Member -NotePropertyName relations `
        -NotePropertyValue @($merged | Sort-Object type, targetEntityName) `
        -Force
}

function Merge-CaseKitSettlementProfile {
    param(
        [Parameter(Mandatory)]$WorldIndex,
        [Parameter(Mandatory)]$Profile
    )

    if ([int]$Profile.schemaVersion -ne 1) {
        throw "Unsupported settlement profile schema '$($Profile.schemaVersion)'."
    }
    $copy = $WorldIndex | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $titledLabels = @{}

    $settlementMatches = @($copy.settlements | Where-Object {
        $_.region -eq $Profile.region -and
        $_.settlement -eq $Profile.settlement
    })
    if ($settlementMatches.Count -ne 1) {
        throw "Settlement profile '$($Profile.region)/" +
            "$($Profile.settlement)' must match exactly one settlement."
    }
    $localizedSettlement = Get-CaseKitProfileProperty `
        -InputObject $Profile -Name 'localized'
    if ($null -ne $localizedSettlement) {
        $settlementMatches[0] | Add-Member -NotePropertyName localized `
            -NotePropertyValue $localizedSettlement -Force
    }

    $anonymousIdentity = Get-CaseKitProfileProperty `
        -InputObject $Profile -Name 'anonymousIdentity'
    if ($null -ne $anonymousIdentity) {
        foreach ($entity in @($copy.entities | Where-Object {
            $_.region -eq $Profile.region -and
            $_.settlement -eq $Profile.settlement -and
            $_.kind -eq 'actor' -and
            $_.identityMode -eq 'anonymous' -and
            $null -eq $_.PSObject.Properties['identity']
        })) {
            $entity | Add-Member -NotePropertyName identity `
                -NotePropertyValue $anonymousIdentity -Force
        }
    }

    foreach ($override in @($Profile.entities)) {
        $entityName = [string](Get-CaseKitProfileProperty `
            -InputObject $override -Name 'entityName' -DefaultValue '')
        $entityGuid = [string](Get-CaseKitProfileProperty `
            -InputObject $override -Name 'entityGuid' -DefaultValue '')
        if (
            [string]::IsNullOrWhiteSpace($entityName) -eq
            [string]::IsNullOrWhiteSpace($entityGuid)
        ) {
            throw 'Profile entity must define exactly one of entityName or entityGuid.'
        }
        $selector = if ($entityName) { $entityName } else { $entityGuid }
        $matches = @(
            $copy.entities | Where-Object {
                $_.region -eq $Profile.region -and
                $_.settlement -eq $Profile.settlement -and
                (
                    ($entityName -and $_.entityName -eq $entityName) -or
                    ($entityGuid -and $_.entityGuid -eq $entityGuid)
                )
            }
        )
        if ($matches.Count -eq 0) {
            throw "Profile entity '$selector' not found in world index."
        }
        if ($matches.Count -gt 1) {
            throw "Profile entity '$selector' is ambiguous in world index."
        }
        $entity = $matches[0]
        $addCapabilities = @(Get-CaseKitProfileProperty `
            -InputObject $override `
            -Name 'addCapabilities' `
            -DefaultValue @())
        $entity.capabilities = @(
            @($entity.capabilities) + $addCapabilities |
                ForEach-Object { [string]$_ } |
                Sort-Object -Unique
        )

        $identity = Get-CaseKitProfileProperty `
            -InputObject $override `
            -Name 'identity'
        if ($null -ne $identity) {
            Test-CaseKitProfileIdentity `
                -Identity $identity `
                -Selector $selector
            if ($identity.mode -eq 'titled') {
                foreach ($language in @('ru', 'en')) {
                    $title = [string](
                        $identity.localized.PSObject.Properties[$language].Value.title
                    )
                    $key = "$language/$title"
                    if ($titledLabels.ContainsKey($key)) {
                        throw "Ambiguous titled identity '$title' in $($Profile.settlement)."
                    }
                    $titledLabels[$key] = $selector
                }
            }
            $identityCapability = "person.$($identity.mode)"
            $entity.capabilities = @(
                @($entity.capabilities) |
                    Where-Object {
                        $_ -notin @(
                            'person.anonymous',
                            'person.identity_review_required',
                            'person.named',
                            'person.titled'
                        )
                    }
                $identityCapability
            ) | Sort-Object -Unique
            $entity.identityMode = [string]$identity.mode
            $entity | Add-Member `
                -NotePropertyName identity `
                -NotePropertyValue $identity `
                -Force
        }

        $presentation = Get-CaseKitProfileProperty `
            -InputObject $override `
            -Name 'presentation'
        if ($null -ne $presentation) {
            $entity | Add-Member `
                -NotePropertyName presentation `
                -NotePropertyValue $presentation `
                -Force
        }

        Merge-CaseKitProfileRelations -WorldIndex $copy -Entity $entity `
            -Relations @(Get-CaseKitProfileProperty `
                -InputObject $override -Name 'relations' -DefaultValue @()) `
            -Selector $selector -Profile $Profile
    }

    return $copy
}

Export-ModuleMember -Function @(
    'Merge-CaseKitSettlementProfile',
    'Read-CaseKitSettlementProfile'
)
