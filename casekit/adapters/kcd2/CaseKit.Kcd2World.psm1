Set-StrictMode -Version Latest

function Read-CaseKitKcd2Json {
    param([Parameter(Mandatory)][string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "Required JSON file not found: $LiteralPath"
    }
    return Get-Content -Raw -LiteralPath $LiteralPath | ConvertFrom-Json
}

function Get-CaseKitPropertyValue {
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

function Get-CaseKitSortedStrings {
    param([object[]]$Value)

    return @(
        $Value |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
}

function ConvertTo-CaseKitWorldLinks {
    param([object[]]$Links)

    return @(
        $Links |
            ForEach-Object {
                [ordered]@{
                    name = [string]$_.name
                    targetId = [string]$_.targetId
                    targetGuid = [string]$_.targetGuid
                }
            } |
            Sort-Object name, targetId, targetGuid
    )
}

function Test-CaseKitAnonymousCharacter {
    param([string]$CharacterName)

    return (
        [string]::IsNullOrWhiteSpace($CharacterName) -or
        $CharacterName -like 'char_GENERIC_*'
    )
}

function Test-CaseKitTavernMetadata {
    param(
        [string]$FactionName,
        [string]$EditorLayer
    )

    $value = "$FactionName/$EditorLayer"
    return $value -match '(?i)(?:^|[/_])(inn|tavern)(?:[/_]|$)'
}

function Test-CaseKitInnkeeperMetadata {
    param(
        [string]$EntityName,
        [string]$CharacterName,
        [string]$EditorLayer
    )

    return (
        $EntityName -match '(?i)(?:^|_)(?:innkeeper|inkeeper)$' -or
        $EditorLayer -match '(?i)/(?:innkeeper|inkeeper|vavrinec)(?:/|$)' -or
        $CharacterName -match '(?i)^char_HOSPODSK[AY]_'
    )
}

function Test-CaseKitTavernWorkerMetadata {
    param(
        [string]$FactionName,
        [string]$CharacterName,
        [bool]$IsInnkeeper
    )

    return (
        $IsInnkeeper -or
        $FactionName -match '(?i)(?:inn|tavern)_staff(?:_|$)' -or
        $CharacterName -match '(?i)^char_(?:HOSPODSK[AY]|SENKYR|DEVECKA_.*HOSPOD)'
    )
}

function Get-CaseKitActorSemantics {
    param(
        [Parameter(Mandatory)]$Actor,
        $VictimCandidate
    )

    $capabilities = [System.Collections.Generic.List[string]]::new()
    $policyFlags = [System.Collections.Generic.List[string]]::new()
    $capabilities.Add('actor.npc')
    $capabilities.Add('person')
    $capabilities.Add('resident.settlement')

    $characterName = [string]$Actor.characterName
    if (Test-CaseKitAnonymousCharacter -CharacterName $characterName) {
        $capabilities.Add('person.anonymous')
    }
    else {
        $capabilities.Add('person.identity_review_required')
    }

    $faction = [string]$Actor.factionName
    $layer = [string]$Actor.editorLayer
    $entityName = [string]$Actor.entityName
    $isTavern = Test-CaseKitTavernMetadata `
        -FactionName $faction -EditorLayer $layer
    $isInnkeeper = Test-CaseKitInnkeeperMetadata `
        -EntityName $entityName -CharacterName $characterName `
        -EditorLayer $layer
    $isTavernWorker = Test-CaseKitTavernWorkerMetadata `
        -FactionName $faction -CharacterName $characterName `
        -IsInnkeeper $isInnkeeper
    if ($isTavernWorker) {
        $capabilities.Add('role.tavern_worker')
        $capabilities.Add('interaction.dialogue')
    }
    if ($isInnkeeper) {
        $capabilities.Add('role.innkeeper')
    }
    if ($isTavern) {
        $capabilities.Add('place.inn')
        $capabilities.Add('workplace.inn')
    }
    $hasHome = @(
        Get-CaseKitPropertyValue -InputObject $Actor -Name 'homeLinks' @()
    ).Count -gt 0 -or (
        Get-CaseKitPropertyValue -InputObject $Actor -Name 'hasHomeLink' $false
    ) -eq $true
    $hasWork = @(
        Get-CaseKitPropertyValue -InputObject $Actor -Name 'workLinks' @()
    ).Count -gt 0 -or (
        Get-CaseKitPropertyValue `
            -InputObject $Actor `
            -Name 'hasVillagerWorkLink' `
            -DefaultValue $false
    ) -eq $true
    if ($hasHome) { $capabilities.Add('schedule.home') }
    if ($hasWork) { $capabilities.Add('schedule.work') }

    $sourceStoryCritical = (Get-CaseKitPropertyValue `
        -InputObject $Actor -Name 'storyCritical' -DefaultValue $false
    ) -eq $true
    $sourceQuestCritical = (Get-CaseKitPropertyValue `
        -InputObject $Actor -Name 'questCritical' -DefaultValue $false
    ) -eq $true
    $sourceImmortal = (Get-CaseKitPropertyValue `
        -InputObject $Actor -Name 'immortal' -DefaultValue $false
    ) -eq $true
    $sourceDead = (Get-CaseKitPropertyValue `
        -InputObject $Actor -Name 'dead' -DefaultValue $false
    ) -eq $true -or $faction -eq 'deadBodies'
    if ($sourceStoryCritical) { $policyFlags.Add('story.critical') }
    if ($sourceQuestCritical) { $policyFlags.Add('quest.critical') }
    if ($sourceImmortal) { $policyFlags.Add('actor.immortal') }
    if ($sourceDead) { $policyFlags.Add('actor.dead_template') }

    $eligible = (
        $null -ne $VictimCandidate -and
        $VictimCandidate.enabled -eq $true -and
        $VictimCandidate.killableVerified -eq $true -and
        $VictimCandidate.storyCritical -ne $true -and
        $VictimCandidate.questCritical -ne $true -and
        $VictimCandidate.immortal -ne $true -and
        $VictimCandidate.dead -ne $true -and
        -not $sourceStoryCritical -and
        -not $sourceQuestCritical -and
        -not $sourceImmortal -and
        -not $sourceDead
    )
    if ($eligible) {
        $policyFlags.Add('victim.eligible')
        $capabilities.Add('person.killable')
    }
    else {
        $policyFlags.Add('victim.review_required')
    }

    return [ordered]@{
        capabilities = Get-CaseKitSortedStrings -Value $capabilities
        policyFlags = Get-CaseKitSortedStrings -Value $policyFlags
    }
}

function ConvertTo-CaseKitWorldActor {
    param(
        [Parameter(Mandatory)]$Actor,
        $VictimCandidate
    )

    $semantics = Get-CaseKitActorSemantics `
        -Actor $Actor `
        -VictimCandidate $VictimCandidate
    $characterName = [string]$Actor.characterName
    return [ordered]@{
        kind = 'actor'
        entityName = [string]$Actor.entityName
        entityGuid = [string]$Actor.entityGuid
        soulGuid = [string]$Actor.soulGuid
        characterName = $characterName
        factionName = [string]$Actor.factionName
        entityClass = 'NPC'
        region = [string]$Actor.gameRegion
        settlement = [string]$Actor.settlementHint
        position = $Actor.position
        editorLayer = [string]$Actor.editorLayer
        homeLinks = @(
            ConvertTo-CaseKitWorldLinks -Links @(
                Get-CaseKitPropertyValue `
                    -InputObject $Actor `
                    -Name 'homeLinks' `
                    -DefaultValue @()
            )
        )
        workLinks = @(
            ConvertTo-CaseKitWorldLinks -Links @(
                Get-CaseKitPropertyValue `
                    -InputObject $Actor `
                    -Name 'workLinks' `
                    -DefaultValue @()
            )
        )
        identityMode = if (
            Test-CaseKitAnonymousCharacter -CharacterName $characterName
        ) { 'anonymous' } else { 'unresolved' }
        capabilities = @($semantics.capabilities)
        policyFlags = @($semantics.policyFlags)
    }
}

function ConvertTo-CaseKitWorldContainer {
    param([Parameter(Mandatory)]$Container)

    $capabilities = [System.Collections.Generic.List[string]]::new()
    $capabilities.Add('container')
    $capabilities.Add('container.stash')
    if ((Get-CaseKitPropertyValue `
        -InputObject $Container -Name 'shopStash' -DefaultValue $false
    ) -eq $true) {
        $capabilities.Add('container.shop')
        $capabilities.Add('container.trade')
    }
    $layer = [string]$Container.editorLayer
    $isTavern = Test-CaseKitTavernMetadata -EditorLayer $layer
    if ($isTavern) {
        $capabilities.Add('place.inn')
    }
    $isTrade = $capabilities.Contains('container.trade')
    $isChest = [string]$Container.entityName -match '(?i)chest(?:[._/]|$)'
    if ($isTavern -and $isChest -and -not $isTrade) {
        $capabilities.Add('container.evidence')
    }

    return [ordered]@{
        kind = 'container'
        entityName = [string]$Container.entityName
        entityId = [string](Get-CaseKitPropertyValue `
            -InputObject $Container -Name 'entityId' -DefaultValue '')
        entityGuid = [string]$Container.entityGuid
        soulGuid = ''
        characterName = ''
        factionName = ''
        entityClass = [string]$Container.entityClass
        region = [string]$Container.gameRegion
        settlement = [string]$Container.settlementHint
        position = $Container.position
        editorLayer = $layer
        homeLinks = @()
        workLinks = @()
        identityMode = 'not_applicable'
        capabilities = @(Get-CaseKitSortedStrings -Value $capabilities)
        policyFlags = @()
        relations = @()
    }
}

function Read-CaseKitKcd2WorldEntities {
    param(
        [Parameter(Mandatory)][string]$RawWorldPath,
        [string]$VictimCatalogPath
    )

    $raw = Read-CaseKitKcd2Json -LiteralPath $RawWorldPath
    if ([int]$raw.schemaVersion -ne 1) {
        throw "Unsupported raw world schema '$($raw.schemaVersion)'."
    }

    $victimByName = @{}
    if (-not [string]::IsNullOrWhiteSpace($VictimCatalogPath)) {
        $victimCatalog = Read-CaseKitKcd2Json `
            -LiteralPath $VictimCatalogPath
        if ([int]$victimCatalog.schemaVersion -ne 2) {
            throw "Unsupported victim catalog schema '$($victimCatalog.schemaVersion)'."
        }
        foreach ($candidate in @($victimCatalog.candidates)) {
            $victimByName[[string]$candidate.entityName] = $candidate
        }
    }

    $entities = [System.Collections.Generic.List[object]]::new()
    $actorSource = Get-CaseKitPropertyValue `
        -InputObject $raw `
        -Name 'actors' `
        -DefaultValue $raw.candidates
    foreach ($actor in @($actorSource)) {
        $candidate = $null
        if ($victimByName.ContainsKey([string]$actor.entityName)) {
            $candidate = $victimByName[[string]$actor.entityName]
        }
        $entities.Add((ConvertTo-CaseKitWorldActor `
            -Actor $actor `
            -VictimCandidate $candidate))
    }
    foreach ($container in @(
        Get-CaseKitPropertyValue -InputObject $raw -Name 'containers' @()
    )) {
        if ($null -eq $container.PSObject.Properties['shopStash']) {
            throw (
                "Raw world container '$([string]$container.entityName)' is " +
                'missing shopStash classification. Regenerate the world ' +
                'snapshot before compiling cases.'
            )
        }
        $entities.Add((ConvertTo-CaseKitWorldContainer -Container $container))
    }
    return @($entities)
}

Export-ModuleMember -Function 'Read-CaseKitKcd2WorldEntities'
