Set-StrictMode -Version Latest

function Merge-LevelMissionObjects {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseObjectsText,
        [Parameter(Mandatory)][string]$MissionObjectBlock,
        [Parameter(Mandatory)][object[]]$WaitingLinks,
        [Parameter(Mandatory)][string]$Region
    )

    $objectsEnd = $BaseObjectsText.LastIndexOf(
        '</Objects>',
        [System.StringComparison]::Ordinal
    )
    if ($objectsEnd -lt 0) {
        throw "Base $Region mission objects have no Objects root terminator."
    }

    $mergedText = $BaseObjectsText.Insert(
        $objectsEnd,
        "`t$($MissionObjectBlock.Trim())`r`n"
    )

    $linkRecords = [System.Collections.Generic.List[object]]::new()
    $requiredGuids = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($waitingLink in $WaitingLinks) {
        $sourceGuid = [string]$waitingLink.SourceId
        $targetGuid = [string]$waitingLink.TargetId
        $linkDefinition = [string]$waitingLink.LinkDefinition
        if (
            [string]::IsNullOrWhiteSpace($sourceGuid) -or
            [string]::IsNullOrWhiteSpace($targetGuid) -or
            [string]::IsNullOrWhiteSpace($linkDefinition)
        ) {
            throw "Dark Passenger $Region waiting link has an empty field."
        }

        $linkRecords.Add([pscustomobject]@{
            SourceGuid = $sourceGuid
            TargetGuid = $targetGuid
            LinkDefinition = $linkDefinition
        })
        $null = $requiredGuids.Add($sourceGuid)
        $null = $requiredGuids.Add($targetGuid)
    }

    $guidAlternation = @(
        $requiredGuids |
            Sort-Object |
            ForEach-Object { [regex]::Escape($_) }
    ) -join '|'
    if ([string]::IsNullOrWhiteSpace($guidAlternation)) {
        throw "Dark Passenger $Region mission-object merge has no links."
    }

    $entityPattern =
        '(?s)<Entity\b(?=[^>]*\bEntityGuid="(?:' +
        $guidAlternation +
        ')")[^>]*>.*?</Entity>'
    $entityMatches = [regex]::Matches(
        $mergedText,
        $entityPattern,
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    )
    $entitiesByGuid =
        [System.Collections.Generic.Dictionary[string, object]]::new(
            [System.StringComparer]::Ordinal
        )
    foreach ($entityMatch in $entityMatches) {
        $openingEnd = $entityMatch.Value.IndexOf('>')
        if ($openingEnd -lt 0) {
            continue
        }

        $openingTag = $entityMatch.Value.Substring(0, $openingEnd + 1)
        $guidMatch = [regex]::Match(
            $openingTag,
            '\bEntityGuid="([^"]+)"',
            [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
        )
        $idMatch = [regex]::Match(
            $openingTag,
            '\bEntityId="([0-9]+)"',
            [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
        )
        if (-not $guidMatch.Success -or -not $idMatch.Success) {
            continue
        }

        $guid = $guidMatch.Groups[1].Value
        if ($entitiesByGuid.ContainsKey($guid)) {
            throw "Unable to resolve unique $Region link entity: guid=$guid count>1"
        }
        $entitiesByGuid.Add($guid, [pscustomobject]@{
            Guid = $guid
            EntityId = $idMatch.Groups[1].Value
            Index = $entityMatch.Index
            Length = $entityMatch.Length
            Text = $entityMatch.Value
        })
    }

    foreach ($requiredGuid in $requiredGuids) {
        if (-not $entitiesByGuid.ContainsKey($requiredGuid)) {
            throw (
                "Unable to resolve unique $Region link entity: " +
                "guid=$requiredGuid count=0"
            )
        }
    }

    $linksBySource =
        [System.Collections.Generic.Dictionary[
            string,
            System.Collections.Generic.List[object]
        ]]::new([System.StringComparer]::Ordinal)
    foreach ($linkRecord in $linkRecords) {
        if (-not $linksBySource.ContainsKey($linkRecord.SourceGuid)) {
            $linksBySource.Add(
                $linkRecord.SourceGuid,
                [System.Collections.Generic.List[object]]::new()
            )
        }
        $linksBySource[$linkRecord.SourceGuid].Add($linkRecord)
    }

    $sourceReplacements = [System.Collections.Generic.List[object]]::new()
    foreach ($sourceGuid in $linksBySource.Keys) {
        $sourceEntity = $entitiesByGuid[$sourceGuid]
        $sourceEntityText = [string]$sourceEntity.Text
        $newLinkLines = [System.Collections.Generic.List[string]]::new()
        foreach ($linkRecord in $linksBySource[$sourceGuid]) {
            $targetEntity = $entitiesByGuid[$linkRecord.TargetGuid]
            $targetEntityId = [string]$targetEntity.EntityId
            $duplicateLinkPattern =
                '<Link\b(?=[^>]*\bTargetId="' +
                [regex]::Escape($targetEntityId) +
                '")(?=[^>]*\bName="' +
                [regex]::Escape($linkRecord.LinkDefinition) +
                '")[^>]*/>'
            if ([regex]::IsMatch(
                $sourceEntityText,
                $duplicateLinkPattern,
                [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
            )) {
                throw (
                    "$Region source '$sourceGuid' already contains " +
                    "'$($linkRecord.LinkDefinition)'."
                )
            }

            $newLinkLines.Add(
                "`t`t`t<Link TargetId=`"$targetEntityId`" " +
                "TargetGuid=`"00000000-0000-0000`" " +
                "Name=`"$($linkRecord.LinkDefinition)`" />"
            )
        }

        $newLinkBlock = $newLinkLines -join "`r`n"
        if ($sourceEntityText -match '<EntityLinks\s*/>') {
            $sourceEntityText = [regex]::Replace(
                $sourceEntityText,
                '<EntityLinks\s*/>',
                "<EntityLinks>`r`n$newLinkBlock`r`n`t`t</EntityLinks>",
                [System.Text.RegularExpressions.RegexOptions]::CultureInvariant,
                [timespan]::FromSeconds(5)
            )
        }
        else {
            $entityLinksEnd = $sourceEntityText.IndexOf(
                '</EntityLinks>',
                [System.StringComparison]::Ordinal
            )
            if ($entityLinksEnd -lt 0) {
                throw "$Region source '$sourceGuid' has no EntityLinks section."
            }
            $sourceEntityText = $sourceEntityText.Insert(
                $entityLinksEnd,
                "$newLinkBlock`r`n`t`t"
            )
        }

        $sourceReplacements.Add([pscustomobject]@{
            Index = [int]$sourceEntity.Index
            Length = [int]$sourceEntity.Length
            Text = $sourceEntityText
        })
    }

    foreach ($replacement in @(
        $sourceReplacements | Sort-Object Index -Descending
    )) {
        $mergedText = $mergedText.Remove(
            $replacement.Index,
            $replacement.Length
        ).Insert($replacement.Index, $replacement.Text)
    }

    return $mergedText
}

Export-ModuleMember -Function Merge-LevelMissionObjects
