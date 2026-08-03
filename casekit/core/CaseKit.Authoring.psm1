Set-StrictMode -Version Latest

$templateModulePath = Join-Path $PSScriptRoot 'CaseKit.Templates.psm1'
Import-Module $templateModulePath -Force

function Read-CaseKitAuthoringJson {
    param([Parameter(Mandatory)][string]$LiteralPath)

    try {
        return [System.IO.File]::ReadAllText($LiteralPath) |
            ConvertFrom-Json -Depth 100
    }
    catch {
        throw "Invalid CaseKit JSON in '$LiteralPath': $($_.Exception.Message)"
    }
}

function Get-CaseKitAuthoringFiles {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][string]$Filter
    )

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Container)) {
        throw "CaseKit authoring root not found: $LiteralPath"
    }
    return @(Get-ChildItem -LiteralPath $LiteralPath -Filter $Filter -File |
        Sort-Object FullName)
}

function Get-CaseKitProperty {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Name
    )

    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function Get-CaseKitPropertyNames {
    param([Parameter(Mandatory)]$Value)

    return @($Value.PSObject.Properties.Name)
}

function New-CaseKitEntryMap {
    param(
        [Parameter(Mandatory)][object[]]$Entries,
        [Parameter(Mandatory)][string]$Kind
    )

    $map = [ordered]@{}
    foreach ($entry in $Entries) {
        $id = [string]$entry.value.id
        if ([string]::IsNullOrWhiteSpace($id)) {
            throw "$Kind in '$($entry.path)' has no id."
        }
        if ($map.Contains($id)) {
            throw "Duplicate $Kind id '$id' in '$($entry.path)'."
        }
        $map[$id] = $entry
    }
    return $map
}

function Assert-CaseKitFactsExist {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$FactIds,
        [Parameter(Mandatory)]$FactMap,
        [Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][string]$SourcePath
    )

    foreach ($factId in $FactIds) {
        if (-not $FactMap.Contains([string]$factId)) {
            throw "$Context references unknown fact '$factId' in '$SourcePath'."
        }
    }
}

function Assert-CaseKitAssetReference {
    param(
        [Parameter(Mandatory)][string]$AssetKey,
        [Parameter(Mandatory)]$AssetKeys,
        [Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][string]$SourcePath
    )

    if (-not $AssetKeys.Contains($AssetKey)) {
        throw "$Context references unknown asset '$AssetKey' in '$SourcePath'."
    }
}

function Get-CaseKitContentAssetKeys {
    param([Parameter(Mandatory)]$Content)

    $keys = [System.Collections.Generic.List[string]]::new()
    foreach ($property in $Content.PSObject.Properties) {
        if ($property.Value -is [string]) {
            $keys.Add([string]$property.Value)
            continue
        }
        foreach ($value in @($property.Value)) {
            $keys.Add([string]$value)
        }
    }
    return $keys.ToArray()
}

function Assert-CaseKitTemplateContract {
    param(
        [Parameter(Mandatory)]$Story,
        [Parameter(Mandatory)]$Archetype,
        [Parameter(Mandatory)][string]$SourcePath
    )

    foreach ($language in @('ru', 'en')) {
        $assets = Get-CaseKitProperty -Value $Story.assets -Name $language
        foreach ($asset in $assets.PSObject.Properties) {
            foreach ($token in @(Get-CaseKitTemplateTokens `
                -Text ([string]$asset.Value))) {
                $slotProperty = $Archetype.slots.PSObject.Properties[$token.slot]
                if ($null -eq $slotProperty) {
                    throw "Unknown template slot '$($token.slot)' in asset " +
                        "'$($asset.Name)' in '$SourcePath'."
                }
                $slot = $slotProperty.Value
                if (@($slot.templateFields) -notcontains $token.field) {
                    throw "Template field '$($token.slot).$($token.field)' is " +
                        "not declared in '$SourcePath'."
                }
                if ($token.field -eq 'name' -and
                    @($slot.identityModes) -contains 'anonymous') {
                    throw "Template slot '$($token.slot)' may resolve to " +
                        "anonymous and cannot use field 'name' in '$SourcePath'."
                }
            }
        }
    }
}

function Assert-CaseKitLanguageAssets {
    param(
        [Parameter(Mandatory)]$Story,
        [Parameter(Mandatory)][string]$SourcePath
    )

    $ruKeys = @(Get-CaseKitPropertyNames -Value $Story.assets.ru | Sort-Object)
    $enKeys = @(Get-CaseKitPropertyNames -Value $Story.assets.en | Sort-Object)
    foreach ($key in $ruKeys) {
        if ($enKeys -notcontains $key) {
            throw "Story '$($Story.id)' in '$SourcePath' is missing English " +
                "asset key '$key'."
        }
    }
    foreach ($key in $enKeys) {
        if ($ruKeys -notcontains $key) {
            throw "Story '$($Story.id)' in '$SourcePath' is missing Russian " +
                "asset key '$key'."
        }
    }
}

function Assert-CaseKitEvidenceModules {
    param([Parameter(Mandatory)]$ModuleMap)

    foreach ($entry in $ModuleMap.Values) {
        $module = $entry.value
        if ($module.confidence.mode -ne 'one_shot') {
            throw "Evidence module '$($module.id)' in '$($entry.path)' must " +
                "use one_shot confidence."
        }
        if ([int]$module.confidence.minimum -gt
            [int]$module.confidence.maximum) {
            throw "Evidence module '$($module.id)' in '$($entry.path)' has " +
                'an invalid confidence range.'
        }
    }
}

function Get-CaseKitReachableConfidence {
    param(
        [Parameter(Mandatory)]$Story,
        [Parameter(Mandatory)]$Archetype
    )

    $knownFacts = [System.Collections.Generic.HashSet[string]]::new()
    $scoredSteps = [System.Collections.Generic.HashSet[string]]::new()
    $changed = $true
    $total = 0
    while ($changed) {
        $changed = $false
        foreach ($thread in @($Story.threads)) {
            $leadFacts = @($thread.lead.requiresFacts)
            foreach ($step in @($thread.steps)) {
                $stepKey = "$($thread.id)/$($step.id)"
                if ($scoredSteps.Contains($stepKey)) {
                    continue
                }
                $requirements = @($leadFacts) + @($step.requiresFacts)
                $canRun = $true
                foreach ($factId in $requirements) {
                    if (-not $knownFacts.Contains([string]$factId)) {
                        $canRun = $false
                        break
                    }
                }
                if (-not $canRun) {
                    continue
                }
                $null = $scoredSteps.Add($stepKey)
                $rule = $Archetype.evidenceRules.PSObject.Properties[
                    [string]$step.action.evidenceModule
                ]
                $total += [int]$rule.Value.confidence
                foreach ($factId in @($step.result.revealsFacts)) {
                    $null = $knownFacts.Add([string]$factId)
                }
                $changed = $true
            }
        }
    }
    return $total
}

function Assert-CaseKitStoryContract {
    param(
        [Parameter(Mandatory)]$StoryEntry,
        [Parameter(Mandatory)]$ArchetypeMap,
        [Parameter(Mandatory)]$ModuleMap
    )

    $story = $StoryEntry.value
    $sourcePath = [string]$StoryEntry.path
    Assert-CaseKitLanguageAssets -Story $story -SourcePath $sourcePath

    $factMap = [ordered]@{}
    foreach ($fact in @($story.facts)) {
        if ($factMap.Contains([string]$fact.id)) {
            throw "Duplicate fact '$($fact.id)' in '$sourcePath'."
        }
        $factMap[[string]$fact.id] = $fact
    }
    $threadMap = [ordered]@{}
    foreach ($thread in @($story.threads)) {
        if ($threadMap.Contains([string]$thread.id)) {
            throw "Duplicate thread '$($thread.id)' in '$sourcePath'."
        }
        $threadMap[[string]$thread.id] = $thread
    }

    $maximumByArchetype = [ordered]@{}
    foreach ($archetypeId in @($story.compatibleArchetypes)) {
        if (-not $ArchetypeMap.Contains([string]$archetypeId)) {
            throw "Story '$($story.id)' references unknown archetype " +
                "'$archetypeId' in '$sourcePath'."
        }
        $archetype = $ArchetypeMap[[string]$archetypeId].value
        Assert-CaseKitTemplateContract -Story $story `
            -Archetype $archetype -SourcePath $sourcePath
        $threadCount = @($story.threads).Count
        if ($threadCount -lt [int]$archetype.threadRules.minimum -or
            $threadCount -gt [int]$archetype.threadRules.maximum) {
            throw "Story '$($story.id)' has $threadCount threads outside the " +
                "allowed range in '$sourcePath'."
        }

        $moduleCounts = [ordered]@{}
        foreach ($thread in @($story.threads)) {
            if (@($archetype.threadRules.allowedLeadModes) -notcontains
                [string]$thread.lead.mode) {
                throw "Thread '$($thread.id)' uses unsupported lead mode " +
                    "'$($thread.lead.mode)' in '$sourcePath'."
            }
            Assert-CaseKitFactsExist -FactIds @($thread.lead.requiresFacts) `
                -FactMap $factMap -Context "Thread '$($thread.id)' lead" `
                -SourcePath $sourcePath
            Assert-CaseKitAssetReference `
                -AssetKey ([string]$thread.lead.directionAsset) `
                -AssetKeys $story.assets.ru.PSObject.Properties.Name `
                -Context "Thread '$($thread.id)' lead" `
                -SourcePath $sourcePath

            $stepMap = [ordered]@{}
            foreach ($step in @($thread.steps)) {
                if ($stepMap.Contains([string]$step.id)) {
                    throw "Duplicate step '$($step.id)' in thread " +
                        "'$($thread.id)' in '$sourcePath'."
                }
                $stepMap[[string]$step.id] = $step
            }
            foreach ($entryStepId in @($thread.entryStepIds)) {
                if (-not $stepMap.Contains([string]$entryStepId)) {
                    throw "Thread '$($thread.id)' has unknown entry step " +
                        "'$entryStepId' in '$sourcePath'."
                }
            }
            if (@($thread.entryStepIds).Count -gt 1 -and
                [bool]$archetype.threadRules.allowOutOfOrder) {
                $hasConditionalPresentation = @($thread.steps |
                    Where-Object { @($_.presentations).Count -gt 1 }).Count -gt 0
                if (-not $hasConditionalPresentation) {
                    throw "Thread '$($thread.id)' declares multiple entry " +
                        "steps but has no conditional presentation in " +
                        "'$sourcePath'."
                }
            }

            foreach ($step in @($thread.steps)) {
                $context = "Step '$($thread.id)/$($step.id)'"
                if (@($archetype.threadRules.allowedStepKinds) -notcontains
                    [string]$step.kind) {
                    throw "$context uses unsupported kind '$($step.kind)' " +
                        "in '$sourcePath'."
                }
                $moduleId = [string]$step.action.evidenceModule
                if (-not $ModuleMap.Contains($moduleId)) {
                    throw "Unknown evidence module '$moduleId' in $context " +
                        "in '$sourcePath'."
                }
                $ruleProperty = $archetype.evidenceRules.PSObject.Properties[
                    $moduleId
                ]
                if ($null -eq $ruleProperty) {
                    throw "Archetype '$archetypeId' does not allow evidence " +
                        "module '$moduleId' in '$sourcePath'."
                }
                $module = $ModuleMap[$moduleId].value
                if ([string]$module.stepKind -ne [string]$step.kind) {
                    throw "Evidence module '$moduleId' requires step kind " +
                        "'$($module.stepKind)', got '$($step.kind)' in " +
                        "$context in '$sourcePath'."
                }
                $confidence = [int]$ruleProperty.Value.confidence
                if ($confidence -lt [int]$module.confidence.minimum -or
                    $confidence -gt [int]$module.confidence.maximum) {
                    throw "Confidence $confidence for '$moduleId' is outside " +
                        "its allowed range in '$sourcePath'."
                }
                if (-not $moduleCounts.Contains($moduleId)) {
                    $moduleCounts[$moduleId] = 0
                }
                $moduleCounts[$moduleId]++

                foreach ($port in $module.bindingPorts.PSObject.Properties) {
                    $slotName = Get-CaseKitProperty `
                        -Value $step.action.bindings -Name $port.Name
                    if ([string]::IsNullOrWhiteSpace([string]$slotName)) {
                        throw "$context is missing binding port '$($port.Name)' " +
                            "in '$sourcePath'."
                    }
                    $slotProperty = $archetype.slots.PSObject.Properties[
                        [string]$slotName
                    ]
                    if ($null -eq $slotProperty) {
                        throw "$context binds '$($port.Name)' to unknown slot " +
                            "'$slotName' in '$sourcePath'."
                    }
                    if ($slotProperty.Value.entityType -ne
                        $port.Value.entityType) {
                        throw "$context binds '$($port.Name)' to incompatible " +
                            "slot '$slotName' in '$sourcePath'."
                    }
                    foreach ($capability in @($port.Value.capabilities)) {
                        if (@($slotProperty.Value.capabilities) -notcontains
                            $capability) {
                            throw "Slot '$slotName' lacks capability " +
                                "'$capability' for $context in '$sourcePath'."
                        }
                    }
                }

                Assert-CaseKitFactsExist -FactIds @($step.requiresFacts) `
                    -FactMap $factMap -Context $context `
                    -SourcePath $sourcePath
                Assert-CaseKitFactsExist `
                    -FactIds @($step.result.revealsFacts) `
                    -FactMap $factMap -Context "$context result" `
                    -SourcePath $sourcePath
                foreach ($nextStepId in @($step.result.nextStepIds)) {
                    if (-not $stepMap.Contains([string]$nextStepId)) {
                        throw "$context points to unknown step '$nextStepId' " +
                            "in '$sourcePath'."
                    }
                }
                foreach ($nextThreadId in @(
                    $step.result.unlockThreadIds
                )) {
                    if (-not $threadMap.Contains([string]$nextThreadId)) {
                        throw "$context unlocks unknown thread " +
                            "'$nextThreadId' in '$sourcePath'."
                    }
                }
                foreach ($presentation in @($step.presentations)) {
                    Assert-CaseKitFactsExist `
                        -FactIds @($presentation.when.allKnown) `
                        -FactMap $factMap `
                        -Context "$context presentation '$($presentation.id)'" `
                        -SourcePath $sourcePath
                    Assert-CaseKitFactsExist `
                        -FactIds @($presentation.when.allUnknown) `
                        -FactMap $factMap `
                        -Context "$context presentation '$($presentation.id)'" `
                        -SourcePath $sourcePath
                    foreach ($contentPort in @($module.requiredContent)) {
                        if ($null -eq $presentation.content.PSObject.Properties[
                            [string]$contentPort
                        ]) {
                            throw "$context presentation '$($presentation.id)' " +
                                "is missing content '$contentPort' in " +
                                "'$sourcePath'."
                        }
                    }
                    foreach ($assetKey in @(Get-CaseKitContentAssetKeys `
                        -Content $presentation.content)) {
                        Assert-CaseKitAssetReference -AssetKey $assetKey `
                            -AssetKeys $story.assets.ru.PSObject.Properties.Name `
                            -Context "$context presentation '$($presentation.id)'" `
                            -SourcePath $sourcePath
                    }
                }
            }

            $reachableSteps = [System.Collections.Generic.HashSet[string]]::new()
            $pendingSteps = [System.Collections.Generic.Queue[string]]::new()
            foreach ($entryStepId in @($thread.entryStepIds)) {
                $pendingSteps.Enqueue([string]$entryStepId)
            }
            while ($pendingSteps.Count -gt 0) {
                $stepId = $pendingSteps.Dequeue()
                if (-not $reachableSteps.Add($stepId)) {
                    continue
                }
                foreach ($nextStepId in @(
                    $stepMap[$stepId].result.nextStepIds
                )) {
                    $pendingSteps.Enqueue([string]$nextStepId)
                }
            }
            foreach ($stepId in $stepMap.Keys) {
                if (-not $reachableSteps.Contains([string]$stepId)) {
                    throw "Thread '$($thread.id)' contains unreachable step " +
                        "'$stepId' in '$sourcePath'."
                }
            }
        }

        foreach ($ruleProperty in $archetype.evidenceRules.PSObject.Properties) {
            $count = if ($moduleCounts.Contains($ruleProperty.Name)) {
                [int]$moduleCounts[$ruleProperty.Name]
            }
            else {
                0
            }
            if ($count -lt [int]$ruleProperty.Value.minimum -or
                $count -gt [int]$ruleProperty.Value.maximum) {
                throw "Story '$($story.id)' uses '$($ruleProperty.Name)' " +
                    "$count times outside the allowed range in '$sourcePath'."
            }
        }

        $maximum = Get-CaseKitReachableConfidence `
            -Story $story -Archetype $archetype
        if ($maximum -lt [int]$archetype.revealThreshold) {
            throw "Story '$($story.id)' maximum reachable confidence " +
                "$maximum is below reveal threshold " +
                "$($archetype.revealThreshold) in '$sourcePath'."
        }
        $maximumByArchetype[$archetypeId] = $maximum
    }

    return [pscustomobject][ordered]@{
        storyId = [string]$story.id
        maximumReachableConfidence = [int](
            $maximumByArchetype.Values | Measure-Object -Maximum
        ).Maximum
        archetypes = [pscustomobject]$maximumByArchetype
    }
}

function Read-CaseKitAuthoredDeck {
    param(
        [Parameter(Mandatory)][string]$ArchetypeRoot,
        [Parameter(Mandatory)][string]$StoryRoot,
        [Parameter(Mandatory)][string]$EvidenceModuleRoot
    )

    $archetypeEntries = @(Get-CaseKitAuthoringFiles `
        -LiteralPath $ArchetypeRoot -Filter '*.archetype.json' |
        ForEach-Object {
            [pscustomobject]@{
                path = $_.FullName
                value = Read-CaseKitAuthoringJson -LiteralPath $_.FullName
            }
        })
    $storyEntries = @(Get-CaseKitAuthoringFiles `
        -LiteralPath $StoryRoot -Filter '*.story.json' |
        ForEach-Object {
            [pscustomobject]@{
                path = $_.FullName
                value = Read-CaseKitAuthoringJson -LiteralPath $_.FullName
            }
        })
    $moduleEntries = [System.Collections.Generic.List[object]]::new()
    foreach ($file in @(Get-CaseKitAuthoringFiles `
        -LiteralPath $EvidenceModuleRoot -Filter '*.evidence.json')) {
        $registry = Read-CaseKitAuthoringJson -LiteralPath $file.FullName
        foreach ($module in @($registry.modules)) {
            $moduleEntries.Add([pscustomobject]@{
                path = $file.FullName
                value = $module
            })
        }
    }

    $archetypeMap = New-CaseKitEntryMap `
        -Entries $archetypeEntries -Kind 'archetype'
    $moduleMap = New-CaseKitEntryMap `
        -Entries $moduleEntries.ToArray() -Kind 'evidence module'
    Assert-CaseKitEvidenceModules -ModuleMap $moduleMap

    $validation = @($storyEntries | ForEach-Object {
        Assert-CaseKitStoryContract -StoryEntry $_ `
            -ArchetypeMap $archetypeMap -ModuleMap $moduleMap
    })
    $maximum = if ($validation.Count -gt 0) {
        [int]($validation | Measure-Object `
            -Property maximumReachableConfidence -Maximum).Maximum
    }
    else {
        0
    }

    return [pscustomobject][ordered]@{
        schemaVersion = 1
        sourceFormat = 'casekit-authoring-v1'
        archetypes = @($archetypeEntries.value | Sort-Object id)
        stories = @($storyEntries.value | Sort-Object id)
        evidenceModules = @($moduleEntries.value | Sort-Object id)
        validation = [pscustomobject][ordered]@{
            maximumReachableConfidence = $maximum
            stories = $validation
        }
    }
}

Export-ModuleMember -Function 'Read-CaseKitAuthoredDeck'
