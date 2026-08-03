Set-StrictMode -Version Latest

function New-CaseKitVariant {
    param(
        [Parameter(Mandatory)]$CaseDefinition,
        [Parameter(Mandatory)]$Binding
    )

    $region = [string]$CaseDefinition.constraints.region
    $settlement = [string]$CaseDefinition.constraints.settlement
    $caseId = [string]$CaseDefinition.case.id

    return [pscustomobject][ordered]@{
        schemaVersion = 1
        variantId = "$caseId--$region--$settlement"
        case = $CaseDefinition.case
        targetPolicy = $CaseDefinition.targetPolicy
        world = [pscustomobject][ordered]@{
            region = $region
            settlement = $settlement
            roles = $Binding.roles
        }
        story = $CaseDefinition.story
        evidence = @($CaseDefinition.evidence)
        presentation = $CaseDefinition.presentation
        source = $CaseDefinition.source
    }
}

function Resolve-CaseKitDeckVariants {
    param([Parameter(Mandatory)]$Deck)

    $variants = [System.Collections.Generic.List[object]]::new()
    foreach ($caseDefinition in @($Deck.cases | Sort-Object `
        @{ Expression = { [int]$_.case.code } }, `
        @{ Expression = { [string]$_.case.id } })) {
        $region = [string]$caseDefinition.constraints.region
        $settlement = [string]$caseDefinition.constraints.settlement
        $matches = @($Deck.settlements | Where-Object {
            [string]$_.region -eq $region -and
            [string]$_.settlement -eq $settlement
        })
        if ($matches.Count -ne 1) {
            throw (
                "Case '$([string]$caseDefinition.case.id)' requires exactly " +
                'one ' +
                "binding for '$region/$settlement'; found $($matches.Count)."
            )
        }
        $variants.Add((New-CaseKitVariant `
            -CaseDefinition $caseDefinition `
            -Binding $matches[0]))
    }
    return $variants.ToArray()
}

Export-ModuleMember -Function 'Resolve-CaseKitDeckVariants'
