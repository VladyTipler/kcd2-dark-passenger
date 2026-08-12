$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$caseKitRoot = Join-Path $repoRoot 'casekit'
$adapterModulePath = Join-Path $caseKitRoot `
    'adapters\kcd2\CaseKit.Kcd2Backend.psm1'
$nativeCompilerModulePath = Join-Path $repoRoot 'tools\CaseSpecCompiler.psm1'

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

function ConvertTo-TestJson($Value) {
    return $Value | ConvertTo-Json -Depth 100 -Compress
}

if (-not (Test-Path -LiteralPath $adapterModulePath -PathType Leaf)) {
    Add-Result $false 'KCD2 backend adapter module exists'
}
else {
    Import-Module (Join-Path $caseKitRoot 'CaseKit.psd1') -Force
    Import-Module (Join-Path $caseKitRoot `
        'core\CaseKit.Profiles.psm1') -Force
    Import-Module (Join-Path $caseKitRoot `
        'core\CaseKit.Compatibility.psm1') -Force
    Import-Module (Join-Path $caseKitRoot `
        'adapters\kcd2\CaseKit.Kcd2Materializer.psm1') -Force
    Import-Module $nativeCompilerModulePath -Force
    $backendModule = Import-Module $adapterModulePath -Force -PassThru

    try {
        $actorGuidance = ConvertTo-CaseKitKcd2GuidancePresentation `
            -GuidanceBinding ([pscustomobject]@{
                qualifiedId = 'thread/step/actor'
                targetKind = 'actor'
                precision = 'exact'
                fallback = 'journal-direction'
                binding = [pscustomobject]@{
                    kind = 'actor'
                    entityName = 'test_actor'
                    entityGuid = '11111111-1111-1111-1111-111111111111'
                    soulGuid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
                }
            })
        Add-Result (
            $actorGuidance.mode -eq 'native-marker' -and
            $actorGuidance.assetKind -eq 'SoulAsset' -and
            $actorGuidance.alias -eq 'DpGuidance_thread_step_actor'
        ) 'KCD2 adapter maps actor guidance to SoulAsset'
        $actorWithoutSoulGuid = ConvertTo-CaseKitKcd2GuidancePresentation `
            -GuidanceBinding ([pscustomobject]@{
                qualifiedId = 'thread/step/actor-without-soul'
                targetKind = 'actor'
                precision = 'exact'
                fallback = 'journal-direction'
                binding = [pscustomobject]@{
                    kind = 'actor'
                    entityName = 'test_actor'
                    entityGuid = '11111111-1111-1111-1111-111111111111'
                    soulGuid = ''
                }
            })
        Add-Result (
            $actorWithoutSoulGuid.mode -eq 'journal-direction' -and
            $null -eq $actorWithoutSoulGuid.assetKind
        ) 'KCD2 adapter refuses a native actor marker without soul GUID'
        $entityGuidance = ConvertTo-CaseKitKcd2GuidancePresentation `
            -GuidanceBinding ([pscustomobject]@{
                qualifiedId = 'thread/step/entity'
                targetKind = 'entity'
                precision = 'exact'
                fallback = 'journal-direction'
                binding = [pscustomobject]@{
                    kind = 'container'
                    entityName = 'test_chest'
                    entityGuid = '22222222-2222-2222-2222-222222222222'
                }
            })
        Add-Result (
            $entityGuidance.mode -eq 'native-marker' -and
            $entityGuidance.assetKind -eq 'InteractionTriggerAsset'
        ) 'KCD2 adapter maps entity guidance to InteractionTriggerAsset'
        $areaGuidance = ConvertTo-CaseKitKcd2GuidancePresentation `
            -GuidanceBinding ([pscustomobject]@{
                qualifiedId = 'thread/step/area'
                targetKind = 'area'
                precision = 'area'
                fallback = 'journal-direction'
                binding = [pscustomobject]@{
                    kind = 'settlement'
                    region = 'trosecko'
                    settlement = 'zelejov'
                }
            })
        Add-Result (
            $areaGuidance.mode -eq 'native-marker' -and
            $areaGuidance.assetKind -eq 'TriggerAreaAsset' -and
            $areaGuidance.catalogKey -eq 'trosecko/zelejov'
        ) 'KCD2 adapter maps area guidance to TriggerAreaAsset catalog lookup'
        $fallbackGuidance = ConvertTo-CaseKitKcd2GuidancePresentation `
            -GuidanceBinding ([pscustomobject]@{
                qualifiedId = 'thread/step/place'
                targetKind = 'place'
                precision = 'point'
                fallback = 'journal-direction'
                binding = $null
            })
        Add-Result (
            $fallbackGuidance.mode -eq 'journal-direction' -and
            $null -eq $fallbackGuidance.assetKind
        ) 'KCD2 adapter emits explicit journal fallback when no point exists'

        $collisionStory = [pscustomobject]@{
            storyId = 'localization-collision-probe'
            caseCode = 9901
            localization = [pscustomobject]@{
                ru = [pscustomobject][ordered]@{
                    'objective.probe-name' = 'Первая строка'
                    'objective.probe_name' = 'Вторая строка'
                }
                en = [pscustomobject][ordered]@{
                    'objective.probe-name' = 'First line'
                    'objective.probe_name' = 'Second line'
                }
            }
        }
        $collisionLocalization = [ordered]@{
            ru = [ordered]@{}
            en = [ordered]@{}
        }
        $collisionOrigins = [ordered]@{}
        $firstPresentation = [pscustomobject]@{
            nameAsset = 'objective.probe-name'
            states = [pscustomobject]@{}
        }
        $secondPresentation = [pscustomobject]@{
            nameAsset = 'objective.probe_name'
            states = [pscustomobject]@{}
        }
        $null = & $backendModule {
            param($Story, $Presentation, $Localization, $Origins)
            ConvertTo-CaseKitKcd2ObjectivePresentation `
                -CompiledStory $Story `
                -Presentation $Presentation `
                -Localization $Localization `
                -GeneratedKeyOrigins $Origins
        } $collisionStory $firstPresentation $collisionLocalization `
            $collisionOrigins
        $collisionRejected = $false
        try {
            $null = & $backendModule {
                param($Story, $Presentation, $Localization, $Origins)
                ConvertTo-CaseKitKcd2ObjectivePresentation `
                    -CompiledStory $Story `
                    -Presentation $Presentation `
                    -Localization $Localization `
                    -GeneratedKeyOrigins $Origins
            } $collisionStory $secondPresentation $collisionLocalization `
                $collisionOrigins
        }
        catch {
            $collisionRejected = $_.Exception.Message -like
                "*generated localization key*dp_case_9901_objective_probe_name*" +
                "*objective.probe-name*objective.probe_name*"
        }
        Add-Result $collisionRejected `
            'backend rejects deterministic localization-key collisions'

        $deck = Read-CaseKitAuthoringDeck `
            -ArchetypeRoot (Join-Path $repoRoot 'content\archetypes') `
            -StoryRoot (Join-Path $repoRoot 'content\stories') `
            -EvidenceModuleRoot (Join-Path $repoRoot `
                'content\evidence-modules')
        $world = [System.IO.File]::ReadAllText((Join-Path $repoRoot `
            'config\world-semantic-index.json')) |
                ConvertFrom-Json -Depth 100
        $settlementCatalog = Read-CaseKitSettlementCatalog -LiteralPath (
            Join-Path $repoRoot 'config\settlement-investigation-areas.json'
        )
        $world = Add-CaseKitInferredSettlementSemantics `
            -WorldIndex $world -SettlementCatalog $settlementCatalog
        $profiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot `
            'config\settlements') -Filter '*.profile.json' -File |
            Sort-Object FullName | ForEach-Object {
                Read-CaseKitSettlementProfile -LiteralPath $_.FullName
            })
        foreach ($profile in $profiles) {
            $world = Merge-CaseKitSettlementProfile -WorldIndex $world `
                -Profile $profile
        }
        $supported = @(
            'kutnohorsko/pritoky',
            'trosecko/zelejov',
            'trosecko/troskovice'
        )
        $world.settlements = @($world.settlements | Where-Object {
            "$($_.region)/$($_.settlement)" -in $supported
        })
        $world.entities = @($world.entities | Where-Object {
            "$($_.region)/$($_.settlement)" -in $supported
        })
        $compatibility = Resolve-CaseKitCompatibility -Deck $deck `
            -WorldIndex $world -MaxVariantsPerCombination 1
        $stableIds = [System.IO.File]::ReadAllText((Join-Path $repoRoot `
            'config\casekit-stable-ids.json')) |
                ConvertFrom-Json -Depth 100
        $compiled = ConvertTo-CaseKitCompiledDefinitions -Deck $deck `
            -CompatibilityReport $compatibility `
            -StableIdRegistry $stableIds
        $adapter = Read-CaseKitKcd2Adapter -LiteralPath (Join-Path $repoRoot `
            'config\casekit-kcd2-native.json')
        $backend = ConvertTo-CaseKitKcd2BackendInput `
            -CompiledDefinitions $compiled `
            -Adapter $adapter `
            -SettlementProfiles $profiles

        $missingStory = @($compiled.stories | Where-Object {
            $_.storyId -eq 'missing-traveler'
        })[0]
        $missingVariant = @($compiled.variants | Where-Object {
            $_.storyId -eq 'missing-traveler' -and
            $_.region -eq 'trosecko' -and $_.settlement -eq 'zelejov'
        } | Sort-Object rank)[0]
        $missingAdapter = @($adapter.stories | Where-Object {
            $_.storyId -eq 'missing-traveler'
        })[0]
        $nullObjectiveStory = $missingStory |
            ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
        $nullObjectiveStory.journal.objectives.investigation = $null
        $nullObjectiveCase = $null
        try {
            $nullObjectiveCase = & $backendModule {
                param($Story, $Variant, $Adapter)
                ConvertTo-CaseKitKcd2CaseSpec -CompiledStory $Story `
                    -Variant $Variant -StoryAdapter $Adapter
            } $nullObjectiveStory $missingVariant $missingAdapter
        }
        catch {
            Write-Host $_.Exception.Message
        }
        Add-Result (
            $null -ne $nullObjectiveCase -and
            $null -eq $nullObjectiveCase.native.journal.objectives.
                PSObject.Properties['investigation']
        ) 'backend treats a null lifecycle objective as an omitted override'
        $configuredSceneProperty =
            $missingAdapter.native.PSObject.Properties['overheardScenes']
        $configuredScene = if ($null -ne $configuredSceneProperty) {
            @($configuredSceneProperty.Value)[0]
        }
        else {
            $missingAdapter.native.overheard
        }
        $sceneAdapterA = $configuredScene |
            ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
        $sceneAdapterA | Add-Member -NotePropertyName evidenceQualifiedId `
            -NotePropertyValue 'courtyard-gossip/overhear-argument' -Force
        $sceneAdapterA | Add-Member -NotePropertyName qualifiedId `
            -NotePropertyValue 'courtyard-gossip/proximity-probe' -Force
        $sceneAdapterB = $configuredScene |
            ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
        $sceneAdapterB | Add-Member -NotePropertyName evidenceQualifiedId `
            -NotePropertyValue 'courtyard-gossip/overhear-argument' -Force
        $sceneAdapterB | Add-Member -NotePropertyName qualifiedId `
            -NotePropertyValue 'courtyard-gossip/interaction-probe' -Force
        $sceneAdapterB.graphName = 'overheard_interaction_probe_dialog_t'
        $sceneAdapterB.fileName = 'overheard_interaction_probe_dialog_t.xml'
        $sceneAdapterB.decisionAlias = 'darkPassenger_interactionProbe'
        $sceneAdapterB.sequenceName = 'interaction_probe'
        $sceneAdapterB.context = 'dp_overheard_interaction_probe'
        $compiledSceneA = [pscustomobject]@{
            qualifiedId = 'courtyard-gossip/proximity-probe'
            evidenceId = 'zelejov_inn_yard_whisper'
            activation = [pscustomobject]@{ mode = 'proximity' }
        }
        $compiledSceneB = [pscustomobject]@{
            qualifiedId = 'courtyard-gossip/interaction-probe'
            evidenceId = 'zelejov_inn_yard_whisper'
            activation = [pscustomobject]@{ mode = 'interaction' }
        }
        $variantSceneA = [pscustomobject]@{
            qualifiedId = $compiledSceneA.qualifiedId
            activation = $compiledSceneA.activation
            speakers = $missingVariant.overheardScenes[0].speakers
        }
        $variantSceneB = [pscustomobject]@{
            qualifiedId = $compiledSceneB.qualifiedId
            activation = $compiledSceneB.activation
            speakers = $missingVariant.overheardScenes[0].speakers
        }
        $nativeScenes = @(ConvertTo-CaseKitKcd2OverheardScenes `
            -SceneAdapters @($sceneAdapterA, $sceneAdapterB) `
            -CompiledScenes @($compiledSceneA, $compiledSceneB) `
            -VariantScenes @($variantSceneA, $variantSceneB) `
            -CompiledStory $missingStory `
            -StoryAdapter $missingAdapter)
        Add-Result (
            $nativeScenes.Count -eq 2 -and
            $nativeScenes[0].activation.mode -eq 'proximity' -and
            $nativeScenes[1].activation.mode -eq 'interaction' -and
            $nativeScenes[0].speakers.speakerA.entityName -eq
                $missingVariant.bindings.gossipSourceA.entityName -and
            $nativeScenes[1].graphName -eq
                'overheard_interaction_probe_dialog_t'
        ) 'KCD2 adapter emits finite native overheard scenes with concrete speakers'

        Add-Result $true 'KCD2 backend adapter module exists'
        Add-Result (
            (@($backend.caseSpecs.id) -join ',') -eq
                'convenient_accident,missing_traveler'
        ) 'adapter emits both stable runtime case IDs'
        Add-Result (
            @($backend.caseSpecs | Where-Object {
                (@($_.constraints.regions | Sort-Object) -join ',') -eq
                    'kutnohorsko,trosecko' -and
                @($_.native.regions.PSObject.Properties.Name).Count -eq 2 -and
                $_.native.regions.kutnohorsko.questName -eq 'dark_within_k' -and
                $_.native.regions.trosecko.questName -eq 'dark_within_t'
            }).Count -eq 2
        ) 'logical CaseSpecs expose both physical regional shells'
        $productionCase = @($backend.caseSpecs | Where-Object {
            $_.id -eq 'missing_traveler'
        })[0]
        $productionScenesProperty =
            $productionCase.native.PSObject.Properties['overheardScenes']
        $productionScenes = if ($null -ne $productionScenesProperty) {
            @($productionScenesProperty.Value)
        }
        else {
            @()
        }
        $legacySceneProperty =
            $productionCase.native.PSObject.Properties['overheard']
        $productionGuidance = @($productionCase.native.guidance)
        Add-Result (
            $productionScenes.Count -eq 1 -and
            $null -eq $legacySceneProperty -and
            $productionScenes[0].qualifiedId -eq
                'courtyard-gossip/overhear-argument' -and
            $productionScenes[0].activation.mode -eq 'interaction' -and
            @($productionGuidance | Where-Object {
                $_.qualifiedId -eq
                    'courtyard-gossip/overhear-argument/listen-area' -and
                $_.assetKind -eq 'TriggerAreaAsset' -and
                $_.catalogKey -eq 'trosecko/zelejov' -and
                $_.lifetime -eq 'step' -and
                $_.objective.nameKey -eq
                    'dp_case_2001_objective_guidance_listen_name' -and
                $_.objective.states.active.key -eq
                    'dp_case_2001_objective_guidance_listen_active'
            }).Count -eq 1
        ) 'production Missing Traveler emits an interactive scene with area guidance'
        Add-Result (
            $productionCase.native.journal.objectives.investigation.nameKey -eq
                'dp_case_2001_objective_investigation_name' -and
            $productionCase.native.journal.objectives.cleanup.states.witnessed.key -eq
                'dp_case_2001_objective_cleanup_witnessed' -and
            $productionCase.localization.ru.
                'dp_case_2001_objective_investigation_name' -eq
                'Раскрыть судьбу Матея'
        ) 'backend materializes StoryPack lifecycle objectives and localization'
        Add-Result (
            @($backend.caseSpecs | Where-Object {
                @($_.identityRequirement.allOf).Count -eq 1
            }).Count -eq 2 -and
            $backend.caseSpecs[0].identityRequirement.allOf[0] -eq
                'suspect_identified' -and
            $backend.caseSpecs[1].identityRequirement.allOf[0] -eq
                'horse_returner_identified'
        ) 'adapter carries compiled identity requirements into CaseSpecs'

        $documentEvidence = @($backend.caseSpecs.evidence |
            ForEach-Object { @($_) } | Where-Object {
                $null -ne $_.PSObject.Properties['item']
            })
        Add-Result (
            $documentEvidence.Count -eq 2 -and
            @($documentEvidence | Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_.item.guid) -and
                $_.destination.mode -eq 'world-container' -and
                -not [string]::IsNullOrWhiteSpace(
                    [string]$_.destination.containerEntityGuid
                )
            }).Count -eq 2
        ) 'backend receives concrete non-shop evidence destinations'

        $troskoviceBinding = @($backend.bindings.settlements |
            Where-Object {
                [int]$_.caseCode -eq 2001 -and
                $_.region -eq 'trosecko' -and
                $_.settlement -eq 'troskovice'
            })[0]
        Add-Result (
            $null -ne $troskoviceBinding -and
            $troskoviceBinding.roles.innkeeper.entityName -eq
                'ttkc_inkeeper' -and
            $troskoviceBinding.roles.witness.entityName -ne '' -and
            $troskoviceBinding.roles.document.containerGuid -ne '' -and
            @($troskoviceBinding.roles.overheard.pairs).Count -gt 0 -and
            @($troskoviceBinding.nativeVariantIds).Count -gt 0
        ) 'backend emits a complete Troskovice binding without a profile'

        $candidateConfig = [System.IO.File]::ReadAllText((Join-Path $repoRoot `
            'config\victim-candidates.json')) | ConvertFrom-Json -Depth 100
        $variantCatalog = ConvertTo-DpCaseVariantCatalogLua `
            -CompiledDefinitions $compiled `
            -CaseSpecs @($backend.caseSpecs) `
            -Candidates @($candidateConfig.candidates) `
            -Bindings $backend.bindings
        $troskoviceVariant = @($compiled.variants | Where-Object {
            $_.storyId -eq 'missing-traveler' -and
            $_.settlement -eq 'troskovice'
        } | Sort-Object rank)[0]
        $variantBlock = [regex]::Match(
            $variantCatalog,
            '(?s)DarkPassengerCaseVariantCatalog\[' +
                [regex]::Escape('"' + [string]$troskoviceVariant.variantId + '"') +
                '\].*?(?=DarkPassengerCaseVariantCatalogByCode)'
        ).Value
        Add-Result (
            -not [string]::IsNullOrWhiteSpace($variantBlock) -and
            $variantBlock.Contains('native_ready = true') -and
            $variantBlock.Contains('ttkc_inkeeper') -and
            $variantBlock.Contains(
                [string]$troskoviceBinding.roles.overheard.pairs[0].speakers[0].entityName
            )
        ) 'native compiler accepts and scopes the generated Troskovice variant'

        $crossRegionControls = @(
            [pscustomobject]@{
                storyId = 'convenient-accident'
                region = 'trosecko'
                settlement = 'troskovice'
            },
            [pscustomobject]@{
                storyId = 'missing-traveler'
                region = 'kutnohorsko'
                settlement = 'pritoky'
            }
        )
        $crossRegionReady = $true
        foreach ($control in $crossRegionControls) {
            $controlVariant = @($compiled.variants | Where-Object {
                $_.storyId -eq $control.storyId -and
                $_.region -eq $control.region -and
                $_.settlement -eq $control.settlement
            } | Sort-Object rank)[0]
            $controlBlock = if ($null -eq $controlVariant) { '' } else {
                [regex]::Match(
                    $variantCatalog,
                    '(?s)DarkPassengerCaseVariantCatalog\[' +
                        [regex]::Escape(
                            '"' + [string]$controlVariant.variantId + '"'
                        ) +
                        '\].*?(?=DarkPassengerCaseVariantCatalogByCode)'
                ).Value
            }
            $crossRegionReady = $crossRegionReady -and
                $null -ne $controlVariant -and
                $controlBlock.Contains('native_ready = true')
        }
        Add-Result $crossRegionReady `
            'cross-region variants are native-ready in their physical shell'

        $stormXml = ConvertTo-DpStormRoleXml `
            -BaseXml "<database>`n  <rules>`n  </rules>`n</database>`n" `
            -CaseSpecs @($backend.caseSpecs) -Bindings $backend.bindings
        Add-Result (
            $stormXml.Contains('<hasName name="ttkc_inkeeper" />') -and
            $stormXml.Contains(
                '<addRole name="' +
                [string]$troskoviceBinding.roles.innkeeper.dialogueRole +
                '" />'
            )
        ) 'native role graph registers auto-discovered Troskovice actors'

        Add-Result (
            @($backend.bindings.settlements | Where-Object {
                [int]$_.caseCode -eq 1001 -and
                $_.settlement -eq 'pritoky'
            }).Count -eq 1 -and
            @($backend.bindings.settlements | Where-Object {
                [int]$_.caseCode -eq 2001 -and
                $_.settlement -eq 'zelejov'
            }).Count -eq 1
        ) 'reviewed settlements remain native bindings beside auto discovery'
        $reviewedZhelejov = @($backend.bindings.settlements |
            Where-Object {
                [int]$_.caseCode -eq 2001 -and
                $_.settlement -eq 'zelejov'
            })[0]
        Add-Result (
            $reviewedZhelejov.roles.innkeeper.entityName -eq
                'tzel_vavrinec' -and
            $reviewedZhelejov.roles.document.containerGuid -eq
                'aaf89994-e94b-0309'
        ) 'reviewed native profile overrides inferred binding values'
        Add-Result (
            [string]$troskoviceBinding.roles.innkeeper.dialogueRole -match
                '^DP_ACTOR_[0-9A-F]{24}$' -and
            [string]$reviewedZhelejov.roles.innkeeper.dialogueRole -match
                '^DP_ACTOR_[0-9A-F]{24}$' -and
            [string]$troskoviceBinding.roles.innkeeper.dialogueRole -ne
                [string]$reviewedZhelejov.roles.innkeeper.dialogueRole -and
            @($backend.bindings.dialogueRoles | Where-Object {
                [string]$_.name -eq
                    [string]$troskoviceBinding.roles.innkeeper.dialogueRole
            }).Count -eq 1 -and
            @($backend.bindings.dialogueRoles | Where-Object {
                [string]$_.name -eq
                    [string]$reviewedZhelejov.roles.innkeeper.dialogueRole
            }).Count -eq 1
        ) 'backend gives each concrete dialogue actor a stable isolated role'

        $divergentCompiled = $compiled | ConvertTo-Json -Depth 100 |
            ConvertFrom-Json -Depth 100
        $sourceVariant = @($divergentCompiled.variants | Where-Object {
            $_.storyId -eq 'missing-traveler' -and
            $_.settlement -eq 'troskovice'
        } | Sort-Object rank, variantId)[0]
        $divergentVariant = $sourceVariant | ConvertTo-Json -Depth 100 |
            ConvertFrom-Json -Depth 100
        $divergentVariant.variantId =
            [string]$sourceVariant.variantId + '--different-native-role'
        $divergentVariant.rank = [int]$sourceVariant.rank + 100
        $divergentVariant.bindings.witness.entityName =
            'casekit_different_witness'
        $divergentCompiled.variants = @($divergentCompiled.variants) +
            $divergentVariant
        $divergentBackend = ConvertTo-CaseKitKcd2BackendInput `
            -CompiledDefinitions $divergentCompiled `
            -Adapter $adapter
        $divergentBinding = @($divergentBackend.bindings.settlements |
            Where-Object {
                [int]$_.caseCode -eq 2001 -and
                $_.settlement -eq 'troskovice'
            })[0]
        Add-Result (
            (@($divergentBinding.nativeVariantIds) -notcontains
                [string]$divergentVariant.variantId) -and
            $divergentBinding.roles.witness.entityName -ne
                'casekit_different_witness'
        ) 'native binding covers only variants with the same concrete roles'
    }
    catch {
        Write-Host $_.ScriptStackTrace
        Add-Result $false "KCD2 backend adapter runs: $($_.Exception.Message)"
    }
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
