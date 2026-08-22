Set-StrictMode -Version Latest

function Test-CaseKitBindingContains {
    param(
        [Parameter(Mandatory)]$Bindings,
        [Parameter(Mandatory)][string]$Name
    )

    if ($Bindings -is [System.Collections.IDictionary]) {
        return $Bindings.Contains($Name)
    }
    return $null -ne $Bindings.PSObject.Properties[$Name]
}

function Get-CaseKitBindingValue {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Field
    )

    if ($Value -is [System.Collections.IDictionary]) {
        if (-not $Value.Contains($Field)) {
            return $null
        }
        return $Value[$Field]
    }
    $property = $Value.PSObject.Properties[$Field]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function Expand-CaseKitTemplate {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)]$Bindings
    )

    return [regex]::Replace(
        $Text,
        '\{\{(?<slot>[A-Za-z][A-Za-z0-9_]*)\.(?<field>[A-Za-z][A-Za-z0-9_]*)\}\}',
        {
            param($match)

            $slot = $match.Groups['slot'].Value
            $field = $match.Groups['field'].Value
            if (-not (Test-CaseKitBindingContains `
                -Bindings $Bindings -Name $slot)) {
                throw "Unknown template slot '$slot'."
            }
            $binding = if ($Bindings -is [System.Collections.IDictionary]) {
                $Bindings[$slot]
            }
            else {
                $Bindings.PSObject.Properties[$slot].Value
            }
            $identityMode = Get-CaseKitBindingValue `
                -Value $binding -Field 'identityMode'
            if ($field -eq 'name' -and $identityMode -eq 'anonymous') {
                throw "Anonymous binding '$slot' has no name."
            }
            $value = Get-CaseKitBindingValue -Value $binding -Field $field
            if ([string]::IsNullOrWhiteSpace([string]$value)) {
                throw "Template value '$slot.$field' is unavailable."
            }
            return [string]$value
        }
    )
}

function Get-CaseKitTemplateTokens {
    param([Parameter(Mandatory)][string]$Text)

    return @([regex]::Matches(
        $Text,
        '\{\{(?<slot>[A-Za-z][A-Za-z0-9_]*)\.(?<field>[A-Za-z][A-Za-z0-9_]*)\}\}'
    ) | ForEach-Object {
        [pscustomobject][ordered]@{
            slot = $_.Groups['slot'].Value
            field = $_.Groups['field'].Value
        }
    })
}

Export-ModuleMember -Function @(
    'Expand-CaseKitTemplate',
    'Get-CaseKitTemplateTokens'
)
