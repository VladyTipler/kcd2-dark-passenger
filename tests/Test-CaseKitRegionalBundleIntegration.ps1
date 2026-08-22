$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$caseKitCli = Join-Path $repoRoot 'casekit\cli\Compile-CaseKit.ps1'
$caseCompiler = Join-Path $repoRoot 'tools\Compile-CaseSpecs.ps1'
$questGenerator = Join-Path $repoRoot 'tools\Generate-VictimArtifacts.ps1'
$areaBindingGenerator = Join-Path $repoRoot `
    'tools\Generate-SettlementAreaBindings.ps1'
$compilerModule = Join-Path $repoRoot 'tools\CaseSpecCompiler.psm1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    "dark-passenger-regional-bundle-$([guid]::NewGuid())"
$caseKitRoot = Join-Path $tempRoot 'casekit'
$buildRoot = Join-Path $tempRoot 'build'

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

function Get-TopLevelNodeNames {
    param([string[]]$Fragments)

    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($fragment in $Fragments) {
        if ([string]::IsNullOrWhiteSpace($fragment)) { continue }
        [xml]$document = "<Root>`n$fragment`n</Root>"
        foreach ($node in @($document.Root.ChildNodes)) {
            if ($node.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
            $name = $node.GetAttribute('Name')
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                $names.Add($name)
            }
        }
    }
    return $names.ToArray()
}

try {
    Import-Module $compilerModule -Force
    & $caseKitCli `
        -ArchetypeRoot (Join-Path $repoRoot 'content\archetypes') `
        -StoryRoot (Join-Path $repoRoot 'content\stories') `
        -EvidenceModuleRoot (Join-Path $repoRoot 'content\evidence-modules') `
        -WorldIndexPath (Join-Path $repoRoot 'config\world-semantic-index.json') `
        -SettlementCatalogPath (Join-Path $repoRoot `
            'config\settlement-investigation-areas.json') `
        -SettlementProfileRoot (Join-Path $repoRoot 'config\settlements') `
        -StableIdRegistryPath (Join-Path $repoRoot `
            'config\casekit-stable-ids.json') `
        -Kcd2AdapterPath (Join-Path $repoRoot `
            'config\casekit-kcd2-native.json') `
        -MaxVariantsPerCombination 1 `
        -OutputRoot $caseKitRoot

    $stagedRpgRoot = Join-Path $buildRoot 'mod\Data\Libs\Tables\rpg'
    $stagedStormRoot = Join-Path $buildRoot `
        'mod\Data\Libs\Storm\roles\quests'
    New-Item -ItemType Directory -Path $stagedRpgRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $stagedStormRoot -Force | Out-Null
    foreach ($fileName in @(
        'buff_ai_tag__darkpassengertest.xml',
        'buff__darkpassengertest.xml',
        'role__darkpassengertest.xml'
    )) {
        Copy-Item -LiteralPath (Join-Path $repoRoot `
            "src\Data\Libs\Tables\rpg\$fileName") `
            -Destination (Join-Path $stagedRpgRoot $fileName)
    }
    Copy-Item -LiteralPath (Join-Path $repoRoot `
        'src\Data\Libs\Storm\roles\quests\darkpassengertest.xml') `
        -Destination (Join-Path $stagedStormRoot 'darkpassengertest.xml')

    & $caseCompiler `
        -CaseVariantRoot $caseKitRoot `
        -LocalizationRoot (Join-Path $repoRoot 'localization') `
        -BuildRoot $buildRoot

    $generatedLevelRoot = Join-Path $buildRoot 'mod\Data\Levels'
    & $areaBindingGenerator `
        -OutputRoot $generatedLevelRoot `
        -LuaOutputPath (Join-Path $buildRoot `
            'mod\Data\Scripts\mods\generated\dp_investigation_area_catalog.lua') `
        -CompiledDefinitionsPath (Join-Path $caseKitRoot `
            'compiled-definitions.json') `
        -SettlementBindingsPath (Join-Path $caseKitRoot `
            'case-settlement-bindings.json')

    $generatedKuttenbergQuest = Join-Path $buildRoot `
        'mod\Data\Quests\Final\Barbora\kutnohorsko\dark_within_k.xml'
    $generatedTroskyQuest = Join-Path $buildRoot `
        'mod\Data\Quests\Final\Barbora\trosecko\dark_within_t.xml'
    & $questGenerator `
        -NativeWiringPath (Join-Path $buildRoot `
            'generated\cases\native-wiring.json') `
        -KuttenbergQuestOutputPath $generatedKuttenbergQuest `
        -TroskyQuestOutputPath $generatedTroskyQuest `
        -LuaOutputPath (Join-Path $buildRoot `
            'mod\Data\Scripts\mods\generated\dp_candidate_catalog.lua')

    $generatedBindings = [System.IO.File]::ReadAllText((Join-Path `
        $caseKitRoot 'case-settlement-bindings.json')) |
        ConvertFrom-Json -Depth 100
    $generatedZhelejov = @($generatedBindings.settlements | Where-Object {
        [int]$_.caseCode -eq 2001 -and
        [string]$_.region -eq 'trosecko' -and
        [string]$_.settlement -eq 'zelejov'
    })[0]
    $placementCatalog = [System.IO.File]::ReadAllText((Join-Path $buildRoot `
        'mod\Data\Scripts\mods\generated\dp_quest_item_placement_catalog.lua'))
    $troskyWaitingLinks = [xml][System.IO.File]::ReadAllText((Join-Path `
        $generatedLevelRoot 'trosecko\waitinglinks.xml'))
    $zhelejovStashLinks = @(
        $troskyWaitingLinks.StaticLinksInfo.WaitingLinks.WaitingLink |
            Where-Object {
                [string]$_.TargetId -eq '02f9f209-a91a-0267' -and
                [string]$_.LinkDefinition -eq
                    "asset['DP_EvidenceStash_trosecko_zelejov']"
            }
    )
    $troskyQuestXml = [System.IO.File]::ReadAllText($generatedTroskyQuest)
    Add-Result (
        [string]$generatedZhelejov.roles.document.containerGuid -eq
            '02f9f209-a91a-0267' -and
        $placementCatalog.Contains('["02f9f209-a91a-0267"]') -and
        $zhelejovStashLinks.Count -eq 1 -and
        $troskyQuestXml.Contains(
            'Value="d5833fd4-f7bf-4957-86f5-d661db38bcf3"'
        ) -and
        $troskyQuestXml.Contains(
            'Alias="DP_EvidenceStash_trosecko_zelejov"'
        )
    ) 'materialized Zhelejov evidence destination crosses binding, Lua, graph, and waiting-link boundaries'

    $manifestPath = Join-Path $buildRoot `
        'generated\cases\native-wiring.json'
    $manifest = [System.IO.File]::ReadAllText($manifestPath) |
        ConvertFrom-Json -Depth 100
    $stormRolePath = Join-Path $buildRoot `
        'mod\Data\Libs\Storm\roles\quests\darkpassengertest.xml'
    $dialogueRoleTablePath = Join-Path $buildRoot `
        'mod\Data\Libs\Tables\rpg\role__darkpassengertest.xml'
    $stormRoleXml = [System.IO.File]::ReadAllText($stormRolePath)
    $dialogueRoleTableXml = [System.IO.File]::ReadAllText(
        $dialogueRoleTablePath
    )
    $stormRoleNames = @([regex]::Matches(
        $stormRoleXml,
        '<addRole\s+name="(?<name>[^"]+)"\s*/>'
    ) | ForEach-Object { [string]$_.Groups['name'].Value })
    $stormRules = @([regex]::Matches(
        $stormRoleXml,
        '(?s)<rule\b.*?</rule>'
    ))
    $registeredRoleNames = @([regex]::Matches(
        $dialogueRoleTableXml,
        '<role\b[^>]*\brole_name="(?<name>[^"]+)"[^>]*/>'
    ) | ForEach-Object { [string]$_.Groups['name'].Value })
    $invalidStormRoles = @($stormRoleNames | Sort-Object -Unique |
        Where-Object {
            $stormRoleName = [string]$_
            @($registeredRoleNames | Where-Object {
                [string]$_ -ceq $stormRoleName
            }).Count -ne 1
    })
    Add-Result (
        $invalidStormRoles.Count -eq 0
    ) ('every generated Storm addRole has one RPG role definition' +
        $(if ($invalidStormRoles.Count -gt 0) {
            ': ' + ($invalidStormRoles -join ', ')
        } else { '' }))
    $missingStormAssignments = [System.Collections.Generic.List[string]]::new()
    foreach ($settlementBinding in @($generatedBindings.settlements)) {
        foreach ($role in 'innkeeper', 'witness') {
            $roleProperty = $settlementBinding.roles.PSObject.Properties[$role]
            $poolProperty =
                $settlementBinding.actorPools.PSObject.Properties[$role]
            if ($null -eq $roleProperty -or $null -eq $poolProperty) { continue }
            $dialogueRole = [string]$roleProperty.Value.dialogueRole
            foreach ($actor in @($poolProperty.Value)) {
                $entityName = [string]$actor.entityName
                $hasAssignment = @($stormRules | Where-Object {
                    $_.Value.Contains(
                        "<hasName name=`"$entityName`" />"
                    ) -and $_.Value.Contains(
                        "<addRole name=`"$dialogueRole`" />"
                    )
                }).Count -eq 1
                if (-not $hasAssignment) {
                    $missingStormAssignments.Add(
                        "$($settlementBinding.caseCode)/" +
                        "$($settlementBinding.region)/" +
                        "$($settlementBinding.settlement)/$role/" +
                        "$entityName->$dialogueRole"
                    )
                }
            }
        }
    }
    Add-Result (
        $missingStormAssignments.Count -eq 0
    ) ('every generated dialogue actor crosses the Storm assignment boundary' +
        $(if ($missingStormAssignments.Count -gt 0) {
            ': ' + ($missingStormAssignments -join ', ')
        } else { '' }))
    Add-Result (
        @($manifest.regions).Count -eq 2 -and
        (@($manifest.regions.region | Sort-Object -Unique) -join ',') -eq
            'kutnohorsko,trosecko'
    ) 'compiler emits one native bundle per physical region'

    Add-Result (
        @($manifest.regions | Where-Object {
            (@($_.caseIds | Sort-Object) -join ',') -eq
                'convenient_accident,missing_traveler'
        }).Count -eq 2
    ) 'each regional bundle contains every compatible StoryPack module'

    Add-Result (
        @($manifest.regions | Where-Object {
            ([regex]::Matches(
                [string]$_.dialogDefinitions,
                '<Definitions>'
            )).Count -eq 1 -and
            ([string]$_.rumorNodes).Contains('case1001Active') -and
            ([string]$_.rumorNodes).Contains('case2001Active')
        }).Count -eq 2
    ) 'regional bundle merges definitions and case-gates story nodes'

    Add-Result (
        @($manifest.regions | Where-Object {
            -not ([string]$_.dialogDefinitions).Contains('System.Object[]')
        }).Count -eq 2
    ) 'regional bundle serializes dialogue definitions as XML'

    Add-Result (
        @($manifest.regions | Where-Object {
            $names = @(Get-TopLevelNodeNames -Fragments @(
                [string]$_.rumorNodes,
                [string]$_.witnessNodes,
                [string]$_.evidenceStateNodes
            ))
            @($names | Group-Object | Where-Object Count -gt 1).Count -eq 0
        }).Count -eq 2
    ) 'regional bundle has no duplicate story node names'

    Add-Result (
        @($manifest.regions | Where-Object {
            ([string]$_.evidenceStateNodes) -notmatch 'Name="leadState' -and
            ([string]$_.evidenceStateNodes).Contains(
                'Name="case1001_leadStateTrigger0"'
            ) -and
            ([string]$_.evidenceStateNodes).Contains(
                'Name="case2001_leadStateTrigger0"'
            )
        }).Count -eq 2
    ) 'evidence nodes are fully case-namespaced'

    Add-Result (
        @($manifest.regions | Where-Object {
            @($_.caseActivationSignals).Count -eq 2 -and
            (@($_.caseActivationSignals.case_code | Sort-Object) -join ',') -eq
                '1001,2001'
        }).Count -eq 2
    ) 'each regional bundle declares every active-case signal'

    Add-Result (
        @($manifest.regions | Where-Object {
            $caseActiveTriggers = @([regex]::Matches(
                [string]$_.rumorNodes,
                '(?s)<BuffTagTrigger Name="case\d+ActiveTrigger">.*?</BuffTagTrigger>'
            ))
            $caseActiveTriggers.Count -ne 2 -or
            @($caseActiveTriggers | Where-Object {
                -not $_.Value.Contains(
                    '<Edge From="questProgress.Active" To="IsActive" />'
                ) -or $_.Value.Contains(
                    '<Edge From="watcherActive.State" To="IsActive" />'
                )
            }).Count -gt 0
        }).Count -eq 0
    ) 'case activation follows the live quest lifecycle used by native scenes'

    Add-Result (
        @($manifest.regions | Where-Object {
            $guidanceNodes = [string]$_.guidanceNodes
            $guidanceTriggers = @([regex]::Matches(
                $guidanceNodes,
                '(?s)<BuffTagTrigger Name="guidance[^"]+Trigger">.*?</BuffTagTrigger>'
            ))
            $guidanceStates = @([regex]::Matches(
                $guidanceNodes,
                '(?s)<State Name="guidance[^"]+Progress".*?</State>'
            ))
            $guidanceTriggers.Count -eq 0 -or
            $guidanceStates.Count -ne $guidanceTriggers.Count -or
            @($guidanceTriggers | Where-Object {
                -not $_.Value.Contains(
                    '<Edge From="watcherActive.State" To="IsActive" />'
                ) -or $_.Value.Contains(
                    '<Edge From="questProgress.Active" To="IsActive" />'
                )
            }).Count -gt 0 -or
            @($guidanceStates | Where-Object {
                $_.Value.Contains(
                    '<Edge From="questProgress.OnActive" To="SetNone" />'
                )
            }).Count -gt 0
        }).Count -eq 0
    ) 'guidance survives signals published before quest activation'

    foreach ($questPath in @(
        $generatedKuttenbergQuest,
        $generatedTroskyQuest
    )) {
        $questXml = [System.IO.File]::ReadAllText($questPath)
        $caseSearchStates = @([regex]::Matches(
            $questXml,
            '(?s)<State Name="(?:case\d+SearchProgress|objectiveProgress)".*?</State>'
        ))
        Add-Result (
            $caseSearchStates.Count -gt 0 -and
            @($caseSearchStates | Where-Object {
                $_.Value.Contains(
                    '<Edge From="questProgress.OnActive" To="SetNone" />'
                )
            }).Count -eq 0
        ) "$(Split-Path -Leaf $questPath) does not reactivate an already presented case search objective"
        $caseSearchCleanupFailures = @($caseSearchStates |
            Where-Object {
                $stateName = [regex]::Match(
                    $_.Value,
                    '<State Name="(?<name>[^"]+)"'
                ).Groups['name'].Value
                $caseCode = if ($stateName -eq 'objectiveProgress') {
                    '1001'
                }
                else {
                    [regex]::Match(
                        $stateName,
                        '^case(?<case>\d+)SearchProgress$'
                    ).Groups['case'].Value
                }
                [string]::IsNullOrWhiteSpace($caseCode) -or
                    -not $_.Value.Contains(
                        '<Edge From="case' + $caseCode +
                        'ActiveTrigger.OnRemoved" To="SetNone" />'
                    )
            })
        Add-Result (
            $caseSearchStates.Count -gt 0 -and
            $caseSearchCleanupFailures.Count -eq 0
        ) "$(Split-Path -Leaf $questPath) clears each Case search area when clearCaseArtifacts removes its activation buff"
        $caseCodes = @([regex]::Matches(
            $questXml,
            '<BuffTagTrigger Name="case(?<case>\d+)ActiveTrigger">'
        ) | ForEach-Object { [string]$_.Groups['case'].Value } |
            Sort-Object -Unique)
        $crossCaseSearchResetFailures = @($caseSearchStates |
            Where-Object {
                $stateXml = $_.Value
                $stateName = [regex]::Match(
                    $stateXml,
                    '<State Name="(?<name>[^"]+)"'
                ).Groups['name'].Value
                $ownerCase = if ($stateName -eq 'objectiveProgress') {
                    '1001'
                }
                else {
                    [regex]::Match(
                        $stateName,
                        '^case(?<case>\d+)SearchProgress$'
                    ).Groups['case'].Value
                }
                @($caseCodes | Where-Object {
                    $_ -ne $ownerCase -and
                    -not $stateXml.Contains(
                        '<Edge From="case' + $_ +
                        'ActiveTrigger.OnAdded" To="SetNone" />'
                    )
                }).Count -gt 0
            })
        Add-Result (
            $caseCodes.Count -gt 1 -and
            $crossCaseSearchResetFailures.Count -eq 0
        ) "$(Split-Path -Leaf $questPath) explicitly clears every other Case search area when a new Case activates"
        $guidanceProgressStates = @([regex]::Matches(
            $questXml,
            '(?s)<State Name="guidance[^\"]+Progress".*?</State>'
        ))
        $guidanceAreaStates = @([regex]::Matches(
            $questXml,
            '(?s)<State Name="guidance[^\"]+Inside".*?</State>'
        ))
        $staleGuidanceResetFailures = @(
            @($guidanceProgressStates | Where-Object {
                $stateXml = $_.Value
                @($caseCodes | Where-Object {
                    -not $stateXml.Contains(
                        '<Edge From="case' + $_ +
                        'ActiveTrigger.OnAdded" To="SetNone" />'
                    )
                }).Count -gt 0
            }) +
            @($guidanceAreaStates | Where-Object {
                $stateXml = $_.Value
                @($caseCodes | Where-Object {
                    -not $stateXml.Contains(
                        '<Edge From="case' + $_ +
                        'ActiveTrigger.OnAdded" To="SetFalse" />'
                    )
                }).Count -gt 0
            })
        )
        Add-Result (
            $guidanceProgressStates.Count -gt 0 -and
            $guidanceAreaStates.Count -gt 0 -and
            $staleGuidanceResetFailures.Count -eq 0
        ) "$(Split-Path -Leaf $questPath) resets every stale guidance objective and area on fresh Case activation"
        $casePresentationStates = @([regex]::Matches(
            $questXml,
            '(?s)<State Name="(?<name>' +
                '(?:objectiveProgress|evidenceProgress|' +
                'targetObjectiveProgress|cleanupProgress|' +
                'case(?<case>\d+)(?:Search|Evidence|Target|Cleanup)Progress)' +
                ')".*?</State>'
        ))
        $casePresentationCleanupFailures = @($casePresentationStates |
            Where-Object {
                $caseCode = if ([string]::IsNullOrWhiteSpace(
                    [string]$_.Groups['case'].Value
                )) { '1001' } else { [string]$_.Groups['case'].Value }
                $_.Value -notmatch (
                    '<Edge From="case' + $caseCode +
                    'ActiveTrigger\.OnRemoved" To="Set[^\"]+" />'
                )
            })
        Add-Result (
            $casePresentationStates.Count -ge 8 -and
            $casePresentationCleanupFailures.Count -eq 0
        ) "$(Split-Path -Leaf $questPath) clears all Case-owned journal presentation when clearCaseArtifacts removes its activation buff"

        $targetSlotSoulArrays = @([regex]::Matches(
            $questXml,
            '(?s)<MakeArray Name="targetSlot(?<slot>\d{3})Souls".*?</MakeArray>'
        ))
        $targetSlotTriggers = @([regex]::Matches(
            $questXml,
            '(?s)<BuffTagTrigger Name="targetSlot(?<slot>\d{3})TagTrigger">' +
                '(?<body>.*?)</BuffTagTrigger>'
        ))
        $targetSlotStates = @([regex]::Matches(
            $questXml,
            '(?s)<State Name="targetSlot(?<slot>\d{3})TagState" TypeT="bool">' +
                '(?<body>.*?)</State>'
        ))
        $targetSlotChecks = @([regex]::Matches(
            $questXml,
            '(?s)<If Name="targetSlot(?<slot>\d{3})Tagged">' +
                '(?<body>.*?)</If>'
        ))
        Add-Result (
            $targetSlotSoulArrays.Count -gt 0 -and
            $targetSlotTriggers.Count -eq $targetSlotSoulArrays.Count -and
            $targetSlotStates.Count -eq $targetSlotSoulArrays.Count -and
            $targetSlotChecks.Count -eq $targetSlotSoulArrays.Count -and
            @($targetSlotTriggers | Where-Object {
                $slot = [string]$_.Groups['slot'].Value
                $body = [string]$_.Groups['body'].Value
                $body -notmatch
                    '<Asset Name="Souls" Alias="[A-Za-z_][A-Za-z0-9_]*" />' -or
                -not $body.Contains(
                    '<Edge From="targetTags.Array" To="BuffTags" />'
                ) -or
                -not $body.Contains(
                    '<Edge From="watcherActive.State" To="IsActive" />'
                )
            }).Count -eq 0 -and
            @($targetSlotStates | Where-Object {
                $slot = [string]$_.Groups['slot'].Value
                $body = [string]$_.Groups['body'].Value
                -not $body.Contains(
                    '<Edge From="targetSlot' + $slot +
                    'TagTrigger.OnAdded" To="SetTrue" />'
                ) -or
                -not $body.Contains(
                    '<Edge From="targetSlot' + $slot +
                    'TagTrigger.OnRemoved" To="SetFalse" />'
                )
            }).Count -eq 0 -and
            @($targetSlotChecks | Where-Object {
                $slot = [string]$_.Groups['slot'].Value
                -not $_.Groups['body'].Value.Contains(
                    '<Edge From="targetSlot' + $slot +
                    'TagState.State" To="Condition" />'
                )
            }).Count -eq 0 -and
            $questXml -notmatch
                '<Function Name="targetSlot\d{3}TagCheck"'
        ) "$(Split-Path -Leaf $questPath) tracks the current target tag through per-slot add/remove events"

        $validationTimers = @([regex]::Matches(
            $questXml,
            '(?s)<Timer Name="targetSlot\d{3}ValidationDelay">.*?</Timer>'
        ))
        Add-Result (
            $validationTimers.Count -gt 0 -and
            @($validationTimers | Where-Object {
                -not $_.Value.Contains(
                    '<Edge From="case1001ActiveTrigger.OnAdded" To="SetRunning" />'
                ) -or
                -not $_.Value.Contains(
                    '<Edge From="case1001ActivePhaseGate.True" To="SetRunning" />'
                ) -or
                -not $_.Value.Contains(
                    '<Edge From="case2001ActiveTrigger.OnAdded" To="SetRunning" />'
                ) -or
                -not $_.Value.Contains(
                    '<Edge From="case2001ActivePhaseGate.True" To="SetRunning" />'
                )
            }).Count -eq 0
        ) "$(Split-Path -Leaf $questPath) revalidates every target after any Case activation"

        $bindingPhaseGates = @([regex]::Matches(
            $questXml,
            '(?s)<If Name="case(?<case>\d+)_[^"]+BindingPhaseGate\d+">' +
                '(?<body>.*?)</If>'
        ))
        Add-Result (
            $bindingPhaseGates.Count -gt 0 -and
            @($bindingPhaseGates | Where-Object {
                $caseCode = [string]$_.Groups['case'].Value
                $body = [string]$_.Groups['body'].Value
                -not $body.Contains(
                    '<Edge From="case' + $caseCode +
                    'ActiveTrigger.OnAdded" To="Exec" />'
                ) -or
                -not $body.Contains(
                    '<Edge From="case' + $caseCode +
                    'ActivePhaseGate.True" To="Exec" />'
                )
            }).Count -eq 0
        ) "$(Split-Path -Leaf $questPath) restores settlement binding after late quest activation"

        $searchTargetGates = @([regex]::Matches(
            $questXml,
            '(?s)<If Name="(?<name>(?<stem>primarySearch|case\d+Search)' +
                'Gate\d+)">\s*' +
                '<Edge From="case(?<case>\d+)Active\.State" To="Condition" />\s*' +
                '<Edge From="targetSlot(?<slot>\d{3})Tagged\.True" To="Exec" />\s*' +
                '</If>'
        ))
        $searchTargetRecoveryFailures = @($searchTargetGates | Where-Object {
            $gateName = [string]$_.Groups['name'].Value
            $stem = [string]$_.Groups['stem'].Value
            $caseCode = [string]$_.Groups['case'].Value
            $slot = [string]$_.Groups['slot'].Value
            $destination = [regex]::Match(
                $questXml,
                '<Edge From="' + [regex]::Escape($gateName) +
                    '\.True" To="(?<destination>[^\"]+)" />'
            ).Groups['destination'].Value
            $phaseGate = [regex]::Match(
                $questXml,
                '(?s)<If Name="(?<name>' + [regex]::Escape($stem) +
                    'PhaseGate\d+)">\s*' +
                    '<Edge From="targetSlot' + $slot +
                    'TagState\.State" To="Condition" />' +
                    '(?<body>.*?)</If>'
            )
            -not $phaseGate.Success -or
                -not $phaseGate.Groups['body'].Value.Contains(
                    '<Edge From="case' + $caseCode +
                    'ActiveTrigger.OnAdded" To="Exec" />'
                ) -or
                -not $phaseGate.Groups['body'].Value.Contains(
                    '<Edge From="case' + $caseCode +
                    'ActivePhaseGate.True" To="Exec" />'
                ) -or
                [string]::IsNullOrWhiteSpace($destination) -or
                -not $questXml.Contains(
                    '<Edge From="' +
                    $phaseGate.Groups['name'].Value +
                    '.True" To="' + $destination + '" />'
                )
        })
        Add-Result (
            $searchTargetGates.Count -gt 0 -and
            $searchTargetRecoveryFailures.Count -eq 0
        ) "$(Split-Path -Leaf $questPath) restores settlement search after Case activation arrives after target tag"

        $caseActivationStates = @([regex]::Matches(
            $questXml,
            '(?s)<MakeArray Name="case(?<case>\d+)ActiveTags".*?' +
                '<Constant Name="A" Value="(?<tag>\d+)".*?' +
                '<State Name="case\k<case>Active" TypeT="bool">.*?</State>'
        ))
        $caseActivationRecoveryFailures = @($caseActivationStates |
            Where-Object {
                $caseCode = [string]$_.Groups['case'].Value
                $tag = [string]$_.Groups['tag'].Value
                -not $questXml.Contains(
                    '<MakeArray Name="case' + $caseCode +
                    'ActiveSouls" TypeT="wh::rpgmodule::Souls">'
                ) -or
                -not $questXml.Contains(
                    '<Function Name="case' + $caseCode +
                    'ActiveTagCheck" MethodName="wh::rpgmodule::BuffTagCheck"'
                ) -or
                -not $questXml.Contains(
                    '<Constant Name="BuffTag" Value="' + $tag + '" />'
                ) -or
                -not $questXml.Contains(
                    '<If Name="case' + $caseCode +
                    'ActivePhaseGate">'
                ) -or
                -not $questXml.Contains(
                    '<Edge From="case' + $caseCode +
                    'ActiveTagCheck.HaveBuffTag" To="Condition" />'
                ) -or
                -not $questXml.Contains(
                    '<Edge From="questProgress.OnActive" To="Exec" />'
                ) -or
                -not $_.Value.Contains(
                    '<Edge From="case' + $caseCode +
                    'ActivePhaseGate.True" To="SetTrue" />'
                )
            })
        Add-Result (
            $caseActivationStates.Count -gt 0 -and
            $caseActivationRecoveryFailures.Count -eq 0
        ) "$(Split-Path -Leaf $questPath) restores Case activation when its buff predates quest activation"
    }

    $variantCatalogPath = Join-Path $buildRoot `
        'mod\Data\Scripts\mods\generated\dp_case_variant_catalog.lua'
    $variantCatalog = [System.IO.File]::ReadAllText($variantCatalogPath)
    $compiled = [System.IO.File]::ReadAllText((Join-Path $caseKitRoot `
        'compiled-definitions.json')) | ConvertFrom-Json -Depth 100
    Add-Result (
        @($compiled.variants | Where-Object {
            @($_.bindings.evidenceContainer.capabilities) -contains
                'container.trade'
        }).Count -eq 0
    ) 'compiled cases never place evidence in trade storage'
    $foreignVariants = @(
        @($compiled.variants | Where-Object {
            $_.storyId -eq 'convenient-accident' -and
            $_.region -eq 'trosecko' -and
            $_.settlement -eq 'troskovice'
        })[0],
        @($compiled.variants | Where-Object {
            $_.storyId -eq 'missing-traveler' -and
            $_.region -eq 'kutnohorsko' -and
            $_.settlement -eq 'pritoky'
        })[0]
    )
    Add-Result (
        @($foreignVariants | Where-Object {
            $variant = $_
            $block = [regex]::Match(
                $variantCatalog,
                '(?s)DarkPassengerCaseVariantCatalog\[' +
                    [regex]::Escape('"' + [string]$variant.variantId + '"') +
                    '\].*?(?=DarkPassengerCaseVariantCatalogByCode)'
            ).Value
            $block.Contains('native_ready = true')
        }).Count -eq 2
    ) 'cross-region control variants remain native-ready after bundling'

    Add-Result (
        @($foreignVariants | Where-Object {
            $variant = $_
            $block = [regex]::Match(
                $variantCatalog,
                '(?s)DarkPassengerCaseVariantCatalog\[' +
                    [regex]::Escape('"' + [string]$variant.variantId + '"') +
                    '\].*?(?=DarkPassengerCaseVariantCatalogByCode)'
            ).Value
            $block -match 'case_activation_buff_guid\s*=\s*"[0-9a-f-]{36}"'
        }).Count -eq 2
    ) 'runtime variants carry their active-case buff guid'

    $buffTagPath = Join-Path $buildRoot `
        'mod\Data\Libs\Tables\rpg\buff_ai_tag__darkpassengertest.xml'
    $buffPath = Join-Path $buildRoot `
        'mod\Data\Libs\Tables\rpg\buff__darkpassengertest.xml'
    $buffTags = [System.IO.File]::ReadAllText($buffTagPath)
    $buffs = [System.IO.File]::ReadAllText($buffPath)
    Add-Result (
        $buffTags.Contains('dp_case_active_1001') -and
        $buffTags.Contains('dp_case_active_2001') -and
        $buffs.Contains('dp_case_active_1001') -and
        $buffs.Contains('dp_case_active_2001')
    ) 'active-case signals are registered in RPG tables'
    Add-Result (
        $buffTags.Contains('dp_actor_selected_2001_innkeeper') -and
        $buffTags.Contains('dp_actor_selected_2001_witness') -and
        $buffs.Contains('dp_actor_selected_2001_innkeeper') -and
        $buffs.Contains('is_persistent="false"')
    ) 'actor-selection signals cross the compiler boundary into RPG tables'

    $troseckoBundle = @($manifest.regions | Where-Object {
        [string]$_.region -eq 'trosecko'
    })[0]
    $missingTravelerModule = @($troseckoBundle.storyModules |
        Where-Object { [string]$_.caseId -eq 'missing_traveler' })[0]
    $settlementModules = @($missingTravelerModule.settlementModules)
    Add-Result (
        $settlementModules.Count -eq 2 -and
        (@($settlementModules.settlement | Sort-Object) -join ',') -eq
            'troskovice,zelejov' -and
        @($settlementModules | Where-Object {
            @($_.targetCandidateSlots).Count -gt 0 -and
            @($_.dialogues).Count -ge 2
        }).Count -eq 2 -and
        @($settlementModules.dialogues.fileName | Group-Object |
            Where-Object Count -gt 1).Count -eq 0
    ) 'regional StoryPack emits isolated dialogue modules per settlement'
    $compiledDialogs = @(
        $troseckoBundle.storyModules.settlementModules.dialogues
    )
    Add-Result (
        $compiledDialogs.Count -gt 0 -and
        @($compiledDialogs | Where-Object {
            [xml]$dialogueDocument = [string]$_.xml
            $dialogueNode = @(
                $dialogueDocument.Database.Skald.ChildNodes |
                    Where-Object {
                        $_.NodeType -eq [System.Xml.XmlNodeType]::Element
                    }
            )[0]
            [System.IO.Path]::GetFileNameWithoutExtension(
                [string]$_.fileName
            ) -ne [string]$dialogueNode.GetAttribute('Name')
        }).Count -eq 0
    ) 'regional dialogue filename matches its registered Skald type name'
    Add-Result (
        $compiledDialogs.Count -gt 0 -and
        @($compiledDialogs | Where-Object {
            [xml]$dialogueDocument = [string]$_.xml
            $dialogueNode = @(
                $dialogueDocument.Database.Skald.ChildNodes |
                    Where-Object {
                        $_.NodeType -eq [System.Xml.XmlNodeType]::Element
                    }
            )[0]
            $registeredName = [string]$dialogueNode.GetAttribute('Name')
            $registeredName -cne $registeredName.ToLowerInvariant()
        }).Count -eq 0
    ) 'regional dialogue registered type names follow lowercase Skald convention'
    Add-Result (
        $compiledDialogs.Count -gt 0 -and
        @($compiledDialogs | Where-Object {
            $xml = [string]$_.xml
            -not $xml.Contains(
                '<Port Name="actor_selected" Direction="In" Type="bool">'
            ) -or
            $xml -notmatch
                'EntryCondition="[^"]*Port\(''actor_selected''\)[^"]*"'
        }).Count -eq 0 -and
        ([string]$missingTravelerModule.rumorNodes).Contains(
            'MethodName="wh::rpgmodule::BuffTagCheck"'
        ) -and
        ([string]$missingTravelerModule.rumorNodes).Contains(
            'To="actor_selected"'
        )
    ) 'dialogue graph gates every runtime speaker through its actor-selection tag'
    Add-Result (
        ([string]$missingTravelerModule.rumorNodes).Contains(
            'case2001_troskoviceBindingActive'
        ) -and
        ([string]$missingTravelerModule.rumorNodes).Contains(
            'case2001_zelejovBindingActive'
        ) -and
        ([string]$missingTravelerModule.rumorNodes) -match
            'From="targetSlot\d{3}Tagged\.True"'
    ) 'settlement dialogue availability is gated by the selected target slot'

    foreach ($nodeProperty in @('rumorNodes', 'witnessNodes')) {
        $availabilityNodes = [string]$missingTravelerModule.$nodeProperty
        $targetGateBlocks = @([regex]::Matches(
            $availabilityNodes,
            '(?s)<If Name="case2001_(?<settlement>[A-Za-z0-9_]+)' +
                '(?:Rumor|Witness)TargetGate(?<slot>\d+)">.*?</If>'
        ))
        Add-Result (
            $targetGateBlocks.Count -gt 0 -and
            @($targetGateBlocks | Where-Object {
                $settlement = $_.Groups['settlement'].Value
                $slot = $_.Groups['slot'].Value
                -not $_.Value.Contains(
                    ('From="case2001_{0}BindingGate{1}.True" To="Exec"' -f
                        $settlement, $slot)
                ) -or
                $_.Value -match
                    'From="targetSlot\d+Tagged\.True" To="Exec"'
            }).Count -eq 0
        ) "$nodeProperty availability converges after the active binding gate"
    }

    $rumorNodes = [string]$missingTravelerModule.rumorNodes
    $bindingPhaseGates = @([regex]::Matches(
        $rumorNodes,
        '(?s)<If Name="case2001_(?<settlement>[A-Za-z0-9_]+)' +
            'BindingPhaseGate(?<slot>\d+)">.*?</If>'
    ))
    $expectedBindingGateCount = @($settlementModules | ForEach-Object {
        @($_.targetCandidateSlots).Count
    } | Measure-Object -Sum).Sum
    Add-Result (
        $bindingPhaseGates.Count -eq $expectedBindingGateCount -and
        @($bindingPhaseGates | Where-Object {
            $slot = [int]$_.Groups['slot'].Value
            -not $_.Value.Contains(
                ('From="targetSlot{0:D3}TagState.State" To="Condition"' -f
                    $slot)
            ) -or
            -not $_.Value.Contains(
                'From="case2001ActiveTrigger.OnAdded" To="Exec"'
            )
        }).Count -eq 0
    ) 'binding availability converges when active-case arrives after target tag'

    $bindingActiveBlocks = @([regex]::Matches(
        $rumorNodes,
        '(?s)<State Name="case2001_[A-Za-z0-9_]+' +
            'BindingActive" TypeT="bool">.*?</State>'
    ))
    Add-Result (
        $bindingActiveBlocks.Count -gt 0 -and
        @($bindingActiveBlocks | Where-Object {
            $_.Value.Contains(
                '<Edge From="questProgress.OnActive" To="SetFalse" />'
            )
        }).Count -eq 0
    ) 'quest activation cannot erase an already-established dialogue binding'

    foreach ($nodeProperty in @('rumorNodes', 'witnessNodes')) {
        $availabilityNodes = [string]$missingTravelerModule.$nodeProperty
        $targetGateBlocks = @([regex]::Matches(
            $availabilityNodes,
            '(?s)<If Name="case2001_(?<settlement>[A-Za-z0-9_]+)' +
                '(?:Rumor|Witness)TargetGate(?<slot>\d+)">.*?</If>'
        ))
        Add-Result (
            $targetGateBlocks.Count -gt 0 -and
            @($targetGateBlocks | Where-Object {
                $settlement = $_.Groups['settlement'].Value
                $slot = $_.Groups['slot'].Value
                -not $_.Value.Contains(
                    ('BindingPhaseGate{0}.True" To="Exec"' -f $slot)
                )
            }).Count -eq 0
        ) "$nodeProperty availability converges when active-case arrives last"
    }

    $collisionModules = @($troseckoBundle.storyModules |
        Select-Object -First 2 | ForEach-Object {
            $_ | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
        })
    $collisionModules[0].dialogues = @([pscustomobject]@{
        fileName = 'collision.xml'
        xml = '<first />'
    })
    $collisionModules[1].dialogues = @([pscustomobject]@{
        fileName = 'collision.xml'
        xml = '<second />'
    })
    $collisionRejected = $false
    try {
        $null = ConvertTo-DpNativeRegionBundle -Modules $collisionModules
    }
    catch {
        $collisionRejected = $_.Exception.Message -like
            "*dialogue file 'collision.xml'*conflicts*"
    }
    Add-Result $collisionRejected `
        'regional bundle rejects conflicting dialogue file payloads'
}
catch {
    Write-Host $_.ScriptStackTrace
    Add-Result $false "regional bundle pipeline completes: $($_.Exception.Message)"
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
