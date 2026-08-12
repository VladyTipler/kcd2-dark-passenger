$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$caseKitCli = Join-Path $repoRoot 'casekit\cli\Compile-CaseKit.ps1'
$caseCompiler = Join-Path $repoRoot 'tools\Compile-CaseSpecs.ps1'
$questGenerator = Join-Path $repoRoot 'tools\Generate-VictimArtifacts.ps1'
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
                [string]$_.overheardNodes,
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

    foreach ($questPath in @(
        $generatedKuttenbergQuest,
        $generatedTroskyQuest
    )) {
        $questXml = [System.IO.File]::ReadAllText($questPath)
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
                    '<Edge From="case2001ActiveTrigger.OnAdded" To="SetRunning" />'
                )
            }).Count -eq 0
        ) "$(Split-Path -Leaf $questPath) revalidates every target after any Case activation"
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
                ('From="targetSlot{0:D3}TagCheck.HaveBuffTag" To="Condition"' -f
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
