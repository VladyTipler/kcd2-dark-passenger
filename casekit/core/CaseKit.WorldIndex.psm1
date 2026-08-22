Set-StrictMode -Version Latest

function New-CaseKitSemanticWorldIndex {
    param([Parameter(Mandatory)][object[]]$Entities)

    $duplicateGuids = @(
        $Entities |
            Group-Object { [string]$_.entityGuid } |
            Where-Object Count -gt 1
    )
    if ($duplicateGuids.Count -gt 0) {
        $duplicates = @($duplicateGuids | ForEach-Object Name) -join ', '
        throw "Duplicate entity GUID: $duplicates"
    }

    $orderedEntities = @(
        $Entities |
            Sort-Object `
                @{ Expression = { [string]$_.region } },
                @{ Expression = { [string]$_.settlement } },
                @{ Expression = { [string]$_.kind } },
                @{ Expression = { [string]$_.entityName } },
                @{ Expression = { [string]$_.entityGuid } }
    )

    $regions = @(
        $orderedEntities |
            ForEach-Object { [string]$_.region } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
    $settlementCounts = [ordered]@{}
    foreach ($entity in $orderedEntities) {
        $region = [string]$entity.region
        $settlement = [string]$entity.settlement
        if ([string]::IsNullOrWhiteSpace($settlement)) { continue }
        $key = "$region/$settlement"
        if (-not $settlementCounts.Contains($key)) {
            $settlementCounts[$key] = [ordered]@{
                region = $region
                settlement = $settlement
                actorCount = 0
                containerCount = 0
            }
        }
        if ($entity.kind -eq 'actor') {
            $settlementCounts[$key].actorCount++
        }
        elseif ($entity.kind -eq 'container') {
            $settlementCounts[$key].containerCount++
        }
    }
    $settlements = @($settlementCounts.Values)

    return [ordered]@{
        schemaVersion = 1
        regions = $regions
        settlements = $settlements
        entities = $orderedEntities
    }
}

Export-ModuleMember -Function 'New-CaseKitSemanticWorldIndex'
