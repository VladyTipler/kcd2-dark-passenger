param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot 'tools\CaseSpecCompiler.psm1'
$casePath = Join-Path $repoRoot `
    'content\migration\legacy-cases\convenient-accident.case.json'
$missingTravelerPath = Join-Path $repoRoot `
    'content\migration\legacy-cases\missing-traveler.case.json'
$bindingPath = Join-Path $repoRoot `
    'content\migration\legacy-case-settlement-bindings.json'

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

function Get-ThrownMessage {
    param([Parameter(Mandatory)][scriptblock]$Action)

    try {
        & $Action
        return ''
    }
    catch {
        return [string]$_.Exception.Message
    }
}

Add-Result (Test-Path -LiteralPath $modulePath) 'CaseSpec compiler module exists'
Add-Result (Test-Path -LiteralPath $casePath) `
    'convenient-accident CaseSpec exists'
Add-Result (Test-Path -LiteralPath $missingTravelerPath) `
    'missing-traveler CaseSpec exists'
Add-Result (Test-Path -LiteralPath $bindingPath) `
    'settlement binding source exists'

if (Test-Path -LiteralPath $modulePath) {
    Import-Module $modulePath -Force
}

$requiredCommands = @(
    'Read-DpCaseSpec',
    'Read-DpCaseSettlementBindings',
    'Get-DpCaseSpecValidationErrors',
    'Get-DpValidatedCaseSpecs',
    'ConvertTo-DpLocalizationXml',
    'ConvertTo-DpDialogueXml',
    'Get-DpDialogueVariants',
    'ConvertTo-DpDialogueVariantTagXml',
    'ConvertTo-DpDialogueVariantBuffXml',
    'Get-DpActorSelectionSignals',
    'ConvertTo-DpActorSelectionTagXml',
    'ConvertTo-DpActorSelectionBuffXml',
    'ConvertTo-DpStormRoleXml',
    'ConvertTo-DpDialogueRoleTableXml',
    'ConvertTo-DpScriptContextXml',
    'ConvertTo-DpItemTableXml'
)
foreach ($command in $requiredCommands) {
    Add-Result ($null -ne (Get-Command $command -ErrorAction SilentlyContinue)) `
        "compiler exports $command"
}

if ((Test-Path -LiteralPath $modulePath) -and
    (Test-Path -LiteralPath $casePath) -and
    (Test-Path -LiteralPath $bindingPath)) {
    $case = Read-DpCaseSpec -LiteralPath $casePath
    $bindings = Read-DpCaseSettlementBindings -LiteralPath $bindingPath
    $errors = @(Get-DpCaseSpecValidationErrors `
        -CaseSpec $case `
        -Bindings $bindings `
        -SourceName (Split-Path -Leaf $casePath))

    Add-Result ($errors.Count -eq 0) 'authored Pritoky CaseSpec validates'
    Add-Result ([int]$case.schemaVersion -eq 2) `
        'CaseSpec uses nonlinear evidence schema version 2'
    Add-Result ($case.id -eq 'convenient_accident') `
        'CaseSpec preserves stable case id'
    Add-Result ([int]$case.code -eq 1001) `
        'CaseSpec has stable numeric code'
    Add-Result (
        $case.constraints.region -eq 'kutnohorsko' -and
        $case.constraints.settlement -eq 'pritoky'
    ) 'CaseSpec is constrained to Pritoky'
    Add-Result (@($case.evidence).Count -eq 3) `
        'CaseSpec contains three evidence steps'
    Add-Result (
        (@($case.evidence | ForEach-Object { [int]$_.confidence }) |
            Measure-Object -Sum).Sum -eq 70
    ) 'CaseSpec evidence reaches reveal threshold'
    Add-Result (
        -not [string]::IsNullOrWhiteSpace([string]$case.text.ru.title) -and
        -not [string]::IsNullOrWhiteSpace([string]$case.text.en.title)
    ) 'CaseSpec contains Russian and English text'

    $binding = @($bindings.settlements | Where-Object {
        $_.region -eq 'kutnohorsko' -and $_.settlement -eq 'pritoky'
    })
    Add-Result ($binding.Count -eq 1) 'Pritoky has one binding record'
    Add-Result (
        -not [string]::IsNullOrWhiteSpace(
            [string]$binding[0].roles.innkeeper.entityName
        ) -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$binding[0].roles.document.containerGuid
        ) -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$binding[0].roles.witness.entityName
        )
    ) 'Pritoky resolves all semantic roles'

    function Copy-JsonObject($Value) {
        return $Value | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    }

    $missingRoleBindings = Copy-JsonObject $bindings
    $missingRoleBindings.dialogueRoles = @(
        $missingRoleBindings.dialogueRoles | Where-Object {
            [string]$_.name -ne 'DP_INNKEEPER_RUMOR'
        }
    )
    $missingRoleErrors = @(Get-DpCaseSpecValidationErrors `
        -CaseSpec $case `
        -Bindings $missingRoleBindings `
        -SourceName 'missing-dialogue-role.json')
    Add-Result (
        $missingRoleErrors -contains (
            "missing-dialogue-role.json: dialogue role 'DP_INNKEEPER_RUMOR' " +
            'must have one registry definition'
        )
    ) 'missing RPG dialogue role definition is rejected'

    $caseMismatchBindings = Copy-JsonObject $bindings
    $caseMismatchBinding = @($caseMismatchBindings.settlements |
        Where-Object {
            [string]$_.region -eq 'kutnohorsko' -and
            [string]$_.settlement -eq 'pritoky'
        })[0]
    $caseMismatchBinding.roles.innkeeper.dialogueRole =
        'dp_innkeeper_rumor'
    $caseMismatchErrors = @(Get-DpCaseSpecValidationErrors `
        -CaseSpec $case `
        -Bindings $caseMismatchBindings `
        -SourceName 'case-mismatch-dialogue-role.json')
    Add-Result (
        $caseMismatchErrors -contains (
            "case-mismatch-dialogue-role.json: dialogue role " +
            "'dp_innkeeper_rumor' must have one registry definition"
        )
    ) 'dialogue role binding requires exact registry name casing'

    $registryOwnedBindings = Copy-JsonObject $bindings
    $registryOwnedBinding = @($registryOwnedBindings.settlements |
        Where-Object {
            [string]$_.region -eq 'kutnohorsko' -and
            [string]$_.settlement -eq 'pritoky'
        })[0]
    $registryOwnedBinding.roles.innkeeper.dialogueRole =
        'DP_ACTOR_REGISTRY_TEST'
    $registryOwnedBindings.dialogueRoles = @(
        @($registryOwnedBindings.dialogueRoles) +
        [pscustomobject]@{
            name = 'DP_ACTOR_REGISTRY_TEST'
            roleId = '271d1f8b-1848-44b6-a29a-583ac023ee84'
            metaRole = 'NPC'
        }
    )
    $registryOwnedRoleXml = ConvertTo-DpDialogueRoleTableXml `
        -BaseXml "<database>`n  <roles>`n  </roles>`n</database>`n" `
        -CaseSpecs @($case) `
        -Bindings $registryOwnedBindings
    [xml]$registryOwnedRoleDocument = $registryOwnedRoleXml
    $materializedRegistryRows = @(
        $registryOwnedRoleDocument.database.roles.role
    )
    $unmaterializedRegistryRoles = @(
        $registryOwnedBindings.dialogueRoles | Where-Object {
            $definition = $_
            @($materializedRegistryRows | Where-Object {
                [string]$_.role_name -ceq [string]$definition.name -and
                [string]$_.role_id -ieq [string]$definition.roleId -and
                [string]$_.metarole_name -ceq [string]$definition.metaRole
            }).Count -ne 1
        }
    )
    Add-Result (
        $unmaterializedRegistryRoles.Count -eq 0
    ) 'RPG role table materializes the complete dialogue-role registry'

    $crossRegionBindings = [pscustomobject]@{
        settlements = @(
            [pscustomobject]@{
                caseCode = 1001
                region = 'kutnohorsko'
                settlement = 'pritoky'
                roles = [pscustomobject]@{
                    innkeeper = [pscustomobject]@{
                        entityName = 'kpri_innkeeper'
                        dialogueRole = 'DP_TEST_KUTNO_INNKEEPER'
                    }
                }
                actorPools = [pscustomobject]@{
                    innkeeper = @([pscustomobject]@{
                        entityName = 'kpri_innkeeper'
                    })
                }
            },
            [pscustomobject]@{
                caseCode = 1001
                region = 'trosecko'
                settlement = 'zelejov'
                roles = [pscustomobject]@{
                    innkeeper = [pscustomobject]@{
                        entityName = 'tzel_vavrinec'
                        dialogueRole = 'DP_TEST_TROSECKO_INNKEEPER'
                    }
                }
                actorPools = [pscustomobject]@{
                    innkeeper = @([pscustomobject]@{
                        entityName = 'tzel_vavrinec'
                    })
                }
            }
        )
    }
    $crossRegionStormXml = ConvertTo-DpStormRoleXml `
        -BaseXml "<storm>`n  <rules>`n  </rules>`n</storm>`n" `
        -CaseSpecs @($case) `
        -Bindings $crossRegionBindings
    Add-Result (
        $crossRegionStormXml.Contains(
            '<addRole name="DP_TEST_KUTNO_INNKEEPER" />'
        ) -and
        $crossRegionStormXml.Contains(
            '<addRole name="DP_TEST_TROSECKO_INNKEEPER" />'
        )
    ) 'Storm transform assigns one StoryPack across every explicit region binding'

    $registryRole = @($bindings.dialogueRoles | Where-Object {
        [string]$_.name -eq 'DP_INNKEEPER_RUMOR'
    })[0]
    $registryRoleRow =
        '    <role role_id="' + [string]$registryRole.roleId +
        '" metarole_name="' + [string]$registryRole.metaRole +
        '" role_name="' + [string]$registryRole.name + '" />'
    $duplicateNameBaseXml =
        "<database>`n  <roles>`n$registryRoleRow`n" +
        "$registryRoleRow`n  </roles>`n</database>`n"
    $duplicateNameMessage = Get-ThrownMessage -Action {
        ConvertTo-DpDialogueRoleTableXml `
            -BaseXml $duplicateNameBaseXml `
            -CaseSpecs @($case) `
            -Bindings $bindings | Out-Null
    }
    Add-Result (
        $duplicateNameMessage -like
            "*duplicate RPG role name 'DP_INNKEEPER_RUMOR'*"
    ) 'duplicate RPG role name is rejected'

    $duplicateGuidRow =
        '    <role role_id="' + [string]$registryRole.roleId +
        '" metarole_name="NPC" role_name="DP_STALE_ROLE" />'
    $duplicateGuidBaseXml =
        "<database>`n  <roles>`n$duplicateGuidRow`n" +
        "$registryRoleRow`n  </roles>`n</database>`n"
    $duplicateGuidMessage = Get-ThrownMessage -Action {
        ConvertTo-DpDialogueRoleTableXml `
            -BaseXml $duplicateGuidBaseXml `
            -CaseSpecs @($case) `
            -Bindings $bindings | Out-Null
    }
    Add-Result (
        $duplicateGuidMessage -like
            "*duplicate RPG role id '$([string]$registryRole.roleId)'*"
    ) 'duplicate RPG role GUID is rejected'

    $withoutId = Copy-JsonObject $case
    $withoutId.id = ''
    $idErrors = @(Get-DpCaseSpecValidationErrors `
        -CaseSpec $withoutId -Bindings $bindings -SourceName 'missing-id.json')
    Add-Result (
        $idErrors -contains 'missing-id.json: id is required'
    ) 'missing identity error is deterministic'

    $duplicateEvidence = Copy-JsonObject $case
    $duplicateEvidence.evidence[1].id = $duplicateEvidence.evidence[0].id
    $duplicateErrors = @(Get-DpCaseSpecValidationErrors `
        -CaseSpec $duplicateEvidence `
        -Bindings $bindings `
        -SourceName 'duplicate-evidence.json')
    Add-Result (
        $duplicateErrors -contains (
            'duplicate-evidence.json: evidence id ' +
            "'$($duplicateEvidence.evidence[0].id)' is duplicated"
        )
    ) 'duplicate evidence IDs are rejected'

    $missingEnglish = Copy-JsonObject $case
    $missingEnglish.text.en.title = ''
    $languageErrors = @(Get-DpCaseSpecValidationErrors `
        -CaseSpec $missingEnglish `
        -Bindings $bindings `
        -SourceName 'missing-english.json')
    Add-Result (
        $languageErrors -contains `
            'missing-english.json: text.en.title is required'
    ) 'missing bilingual text is rejected'

    $unknownSettlement = Copy-JsonObject $case
    $unknownSettlement.constraints.settlement = 'unknown_village'
    $settlementErrors = @(Get-DpCaseSpecValidationErrors `
        -CaseSpec $unknownSettlement `
        -Bindings $bindings `
        -SourceName 'unknown-settlement.json')
    Add-Result (
        $settlementErrors -contains (
            "unknown-settlement.json: no settlement binding for " +
            "'kutnohorsko/unknown_village'"
        )
    ) 'unsupported settlement is rejected'

    $missingTraveler = Read-DpCaseSpec -LiteralPath $missingTravelerPath
    $actorSelectionSignals = @(Get-DpActorSelectionSignals `
        -CaseSpecs @($missingTraveler) -StartSignalTag 151)
    Add-Result (
        $actorSelectionSignals.Count -eq 2 -and
        (@($actorSelectionSignals.semantic_role) -join ',') -eq
            'innkeeper,witness' -and
        (@($actorSelectionSignals.signal_tag) -join ',') -eq '151,152' -and
        @($actorSelectionSignals | Where-Object {
            [string]::IsNullOrWhiteSpace([string]$_.buff_guid)
        }).Count -eq 0
    ) 'actor selection allocates one hidden signal per dynamic dialogue slot'
    $actorSelectionTagXml = ConvertTo-DpActorSelectionTagXml `
        -BaseXml "<database>`n`t<buff_ai_tags>`n`t</buff_ai_tags>`n</database>`n" `
        -Signals $actorSelectionSignals
    $actorSelectionBuffXml = ConvertTo-DpActorSelectionBuffXml `
        -BaseXml "<database>`n`t<buffs>`n`t</buffs>`n</database>`n" `
        -Signals $actorSelectionSignals
    Add-Result (
        $actorSelectionTagXml.Contains('buff_ai_tag_id="151"') -and
        $actorSelectionTagXml.Contains(
            'buff_ai_tag_name="dp_actor_selected_2001_innkeeper"'
        ) -and
        $actorSelectionBuffXml.Contains(
            'buff_name="dp_actor_selected_2001_witness"'
        ) -and
        $actorSelectionBuffXml.Contains('is_persistent="false"')
    ) 'actor selection emits non-persistent native buff tags and buffs'
    Add-Result (
        @($missingTraveler.identityRequirement.allOf).Count -eq 1 -and
        $missingTraveler.identityRequirement.allOf[0] -eq
            'horse_returner_identified'
    ) 'CaseSpec declares one hard identity requirement'
    $unknownIdentityFact = Copy-JsonObject $missingTraveler
    $unknownIdentityFact.identityRequirement.allOf = @('unknown_identity')
    $identityErrors = @(Get-DpCaseSpecValidationErrors `
        -CaseSpec $unknownIdentityFact -Bindings $bindings `
        -SourceName 'unknown-identity.json')
    Add-Result (
        $identityErrors -contains (
            "unknown-identity.json: identityRequirement references " +
            "unknown fact 'unknown_identity'"
        )
    ) 'CaseSpec rejects identity facts no evidence can reveal'
    $alternativeIdentity = Copy-JsonObject $missingTraveler
    $alternativeIdentity.identityRequirement.PSObject.Properties.Remove(
        'allOf'
    )
    $alternativeIdentity.identityRequirement | Add-Member `
        -NotePropertyName anyOf `
        -NotePropertyValue @(
            'horse_returner_identified',
            'culprit_dismissed_widow_claim'
        )
    $alternativeIdentityErrors = @(Get-DpCaseSpecValidationErrors `
        -CaseSpec $alternativeIdentity -Bindings $bindings `
        -SourceName 'alternative-identity.json')
    Add-Result ($alternativeIdentityErrors.Count -eq 0) `
        'CaseSpec accepts reachable anyOf identity alternatives'

    $missingTravelerRuntimeCatalog = ConvertTo-DpCaseCatalogLua `
        -CaseSpecs @($missingTraveler) `
        -Bindings $bindings
    Add-Result (
        $missingTravelerRuntimeCatalog -match (
            '(?s)id = "matej_guest_ledger",.*?item = \{.*?' +
            'name = "dp_matej_guest_ledger",.*?' +
            'classification = "quest",.*?' +
            'retention = "case",.*?' +
            'contentKey = "dp_mt_ledger_content",'
        )
    ) 'runtime catalog preserves document item metadata'

    $missingTravelerRumor = @($missingTraveler.native.dialogues |
        Where-Object kind -eq 'rumor')[0]
    $rumorVariants = @($missingTravelerRumor.variants)
    Add-Result (
        [string]$missingTravelerRumor.evidenceId -eq
            'zelejov_innkeeper_missing_traveler' -and
        $rumorVariants.Count -eq 2 -and
        (@($rumorVariants | ForEach-Object id) -join ',') -eq
            'unread_ledger,ledger_discovered'
    ) 'missing-traveler rumor authors two variants over one evidence reward'
    if ($rumorVariants.Count -eq 2) {
        Add-Result (
            (@($rumorVariants[0].when.allUndiscovered) -join ',') -eq
                'matej_guest_ledger,zelejov_innkeeper_missing_traveler' -and
            (@($rumorVariants[1].when.allDiscovered) -join ',') -eq
                'matej_guest_ledger' -and
            (@($rumorVariants[1].when.allUndiscovered) -join ',') -eq
                'zelejov_innkeeper_missing_traveler'
        ) 'dialogue variants declare finite evidence knowledge conditions'

        $unknownVariantEvidence = Copy-JsonObject $missingTraveler
        $unknownVariantEvidence.native.dialogues[0].variants[1].when.allDiscovered =
            @('missing_evidence')
        $variantErrors = @(Get-DpCaseSpecValidationErrors `
            -CaseSpec $unknownVariantEvidence `
            -Bindings $bindings `
            -SourceName 'unknown-dialogue-condition.json')
        Add-Result (
            $variantErrors -contains (
                "unknown-dialogue-condition.json: native dialogue 'rumor' " +
                "variant 'ledger_discovered' references unknown discovered " +
                "evidence 'missing_evidence'"
            )
        ) 'dialogue variants reject unknown evidence conditions'
    }
    else {
        Add-Result $false `
            'dialogue variants declare finite evidence knowledge conditions'
        Add-Result $false `
            'dialogue variants reject unknown evidence conditions'
    }

    Add-Result (
        @($missingTraveler.evidence | Where-Object {
            [string]::IsNullOrWhiteSpace([string]$_.placement) -or
            $null -eq $_.PSObject.Properties['discoverableWithoutHint'] -or
            $null -eq $_.PSObject.Properties['hintsUnlockedBy'] -or
            $null -eq $_.PSObject.Properties['reveals']
        }).Count -eq 0
    ) 'every evidence source declares nonlinear discovery metadata'

    $invalidPlacement = Copy-JsonObject $missingTraveler
    $invalidPlacement.evidence[1] | Add-Member `
        -NotePropertyName placement `
        -NotePropertyValue 'runtime_magic' `
        -Force
    $placementErrors = @(Get-DpCaseSpecValidationErrors `
        -CaseSpec $invalidPlacement `
        -Bindings $bindings `
        -SourceName 'invalid-placement.json')
    Add-Result (
        $placementErrors -contains (
            "invalid-placement.json: evidence 'matej_guest_ledger' " +
            "placement must be 'case_start', 'on_event', or 'ambient'"
        )
    ) 'unknown evidence placement is rejected'

    $missingPlacement = Copy-JsonObject $missingTraveler
    $missingPlacement.evidence[1].PSObject.Properties.Remove('placement')
    $missingPlacementErrors = @(Get-DpCaseSpecValidationErrors `
        -CaseSpec $missingPlacement `
        -Bindings $bindings `
        -SourceName 'missing-placement.json')
    Add-Result (
        $missingPlacementErrors -contains (
            "missing-placement.json: evidence 'matej_guest_ledger' " +
            "placement must be 'case_start', 'on_event', or 'ambient'"
        )
    ) 'missing evidence placement returns a validation error'

    $unknownKind = Copy-JsonObject $missingTraveler
    $unknownKind.evidence[1].kind = 'telepathy'
    $kindErrors = @(Get-DpCaseSpecValidationErrors `
        -CaseSpec $unknownKind `
        -Bindings $bindings `
        -SourceName 'unknown-kind.json')
    Add-Result (
        $kindErrors -contains (
            "unknown-kind.json: evidence 'matej_guest_ledger' " +
            "kind 'telepathy' is not supported"
        )
    ) 'unknown evidence kind is rejected'

    $unknownHint = Copy-JsonObject $missingTraveler
    $unknownHint.evidence[1] | Add-Member `
        -NotePropertyName hintsUnlockedBy `
        -NotePropertyValue @('missing_clue') `
        -Force
    $hintErrors = @(Get-DpCaseSpecValidationErrors `
        -CaseSpec $unknownHint `
        -Bindings $bindings `
        -SourceName 'unknown-hint.json')
    Add-Result (
        $hintErrors -contains (
            "unknown-hint.json: evidence 'matej_guest_ledger' " +
            "references unknown hint source 'missing_clue'"
        )
    ) 'unknown hint source is rejected'

    $mismatchedLocalization = Copy-JsonObject $missingTraveler
    $mismatchedLocalization.localization.en.PSObject.Properties.Remove(
        'dp_mt_ledger_content'
    )
    $localizationErrors = @(Get-DpCaseSpecValidationErrors `
        -CaseSpec $mismatchedLocalization `
        -Bindings $bindings `
        -SourceName 'mismatched-localization.json')
    Add-Result (
        $localizationErrors -contains (
            'mismatched-localization.json: localization.ru and ' +
            'localization.en key sets must match'
        )
    ) 'localization key mismatch is rejected'

    $missingDocumentItem = Copy-JsonObject $missingTraveler
    $missingDocumentItem.evidence[1].item.name = ''
    $documentErrors = @(Get-DpCaseSpecValidationErrors `
        -CaseSpec $missingDocumentItem `
        -Bindings $bindings `
        -SourceName 'missing-document-item.json')
    Add-Result (
        $documentErrors -contains (
            "missing-document-item.json: evidence 'matej_guest_ledger' " +
            'item.name is required'
        )
    ) 'document item metadata is required'

    $validated = @(Get-DpValidatedCaseSpecs `
        -CaseRoot (Split-Path -Parent $casePath) `
        -BindingPath $bindingPath)
    Add-Result (
        $validated.Count -eq 2 -and
        $validated[0].id -eq 'convenient_accident' -and
        $validated[1].id -eq 'missing_traveler'
    ) 'validated loader returns authored cases'
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
