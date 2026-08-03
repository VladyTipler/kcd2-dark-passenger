Set-StrictMode -Version Latest

function Read-DpJsonFile {
    param([Parameter(Mandatory)][string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "JSON source not found: $LiteralPath"
    }
    try {
        return [System.IO.File]::ReadAllText($LiteralPath) |
            ConvertFrom-Json -Depth 100
    }
    catch {
        throw "Invalid JSON in '$LiteralPath': $($_.Exception.Message)"
    }
}

function Read-DpCaseSpec {
    param([Parameter(Mandatory)][string]$LiteralPath)
    return Read-DpJsonFile -LiteralPath $LiteralPath
}

function Read-DpCaseSettlementBindings {
    param([Parameter(Mandatory)][string]$LiteralPath)
    return Read-DpJsonFile -LiteralPath $LiteralPath
}

function Test-DpTextValue {
    param($Value)
    return -not [string]::IsNullOrWhiteSpace([string]$Value)
}

function ConvertTo-DpLuaString {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) { return 'nil' }
    $escaped = $Value.Replace('\', '\\')
    $escaped = $escaped.Replace('"', '\"')
    $escaped = $escaped.Replace("`r", '\r')
    $escaped = $escaped.Replace("`n", '\n')
    $escaped = $escaped.Replace("`t", '\t')
    return '"' + $escaped + '"'
}

function ConvertTo-DpLuaValue {
    param(
        [AllowNull()]$Value,
        [int]$Indent = 0
    )

    if ($null -eq $Value) { return 'nil' }
    if ($Value -is [string] -or $Value -is [char]) {
        return ConvertTo-DpLuaString ([string]$Value)
    }
    if ($Value -is [bool]) {
        if ($Value) { return 'true' }
        return 'false'
    }
    if ($Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64] -or
        $Value -is [single] -or $Value -is [double] -or
        $Value -is [decimal]) {
        return ([System.IFormattable]$Value).ToString(
            $null,
            [System.Globalization.CultureInfo]::InvariantCulture
        )
    }

    $padding = ' ' * $Indent
    $childPadding = ' ' * ($Indent + 4)
    $rows = [System.Collections.Generic.List[string]]::new()

    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            $name = [string]$key
            $luaKey = if ($name -match '^[A-Za-z_][A-Za-z0-9_]*$') {
                $name
            }
            else {
                '[' + (ConvertTo-DpLuaString $name) + ']'
            }
            $rendered = ConvertTo-DpLuaValue -Value $Value[$key] `
                -Indent ($Indent + 4)
            $rows.Add("$childPadding$luaKey = $rendered,")
        }
    }
    elseif ($Value -is [System.Management.Automation.PSCustomObject]) {
        foreach ($property in $Value.PSObject.Properties) {
            $name = [string]$property.Name
            $luaKey = if ($name -match '^[A-Za-z_][A-Za-z0-9_]*$') {
                $name
            }
            else {
                '[' + (ConvertTo-DpLuaString $name) + ']'
            }
            $rendered = ConvertTo-DpLuaValue -Value $property.Value `
                -Indent ($Indent + 4)
            $rows.Add("$childPadding$luaKey = $rendered,")
        }
    }
    elseif ($Value -is [System.Collections.IEnumerable]) {
        foreach ($item in $Value) {
            $rendered = ConvertTo-DpLuaValue -Value $item `
                -Indent ($Indent + 4)
            $rows.Add("$childPadding$rendered,")
        }
    }
    else {
        return ConvertTo-DpLuaString ([string]$Value)
    }

    if ($rows.Count -eq 0) { return '{}' }
    return "{`n$($rows -join "`n")`n$padding}"
}

function ConvertTo-DpRuntimeEvidence {
    param([Parameter(Mandatory)]$Evidence)

    return [ordered]@{
        id = [string]$Evidence.id
        code = [int]$Evidence.code
        kind = [string]$Evidence.kind
        role = [string]$Evidence.role
        weight = if ($null -ne $Evidence.PSObject.Properties['weight']) {
            [double]$Evidence.weight
        }
        else { 1 }
        purpose = if ($null -ne $Evidence.PSObject.Properties['purpose']) {
            [string]$Evidence.purpose
        }
        else { $null }
        source_stance = if (
            $null -ne $Evidence.PSObject.Properties['sourceStance']
        ) { [string]$Evidence.sourceStance } else { $null }
        confidence = [int]$Evidence.confidence
        placement = [string]$Evidence.placement
        discoverable_without_hint = [bool]$Evidence.discoverableWithoutHint
        hints_unlocked_by = @($Evidence.hintsUnlockedBy | ForEach-Object {
            [string]$_
        })
        reveals = @($Evidence.reveals | ForEach-Object { [string]$_ })
        prompt_key = if (
            $null -ne $Evidence.PSObject.Properties['promptKey']
        ) { [string]$Evidence.promptKey } else { $null }
    }
}

function ConvertTo-DpRuntimeCase {
    param(
        [Parameter(Mandatory)]$CaseSpec,
        [Parameter(Mandatory)]$Binding
    )

    $evidence = @(
        $CaseSpec.evidence | ForEach-Object {
            ConvertTo-DpRuntimeEvidence -Evidence $_
        }
    )
    $rumors = @($evidence | Where-Object {
        $_.kind -eq 'dialogue' -and $_.role -eq 'innkeeper'
    })

    return [ordered]@{
        id = [string]$CaseSpec.id
        code = [int]$CaseSpec.code
        weight = [double]$CaseSpec.weight
        constraints = [ordered]@{
            region = [string]$CaseSpec.constraints.region
            settlement = [string]$CaseSpec.constraints.settlement
        }
        target_policy = $CaseSpec.targetPolicy
        crime_profile = $CaseSpec.crimeProfile
        reveal_threshold = [int]$CaseSpec.revealThreshold
        rumors = $rumors
        evidence_steps = @($evidence | Select-Object -Skip 1)
        evidence = $evidence
        bindings = $Binding.roles
        text = $CaseSpec.text
    }
}

function ConvertTo-DpCaseCatalogLua {
    param(
        [Parameter(Mandatory)][object[]]$CaseSpecs,
        [Parameter(Mandatory)]$Bindings
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('-- Generated by Compile-CaseSpecs.ps1. Do not edit.')
    $lines.Add('DarkPassengerCaseCatalog = {}')
    $lines.Add('DarkPassengerCaseCatalogOrder = {')
    foreach ($case in $CaseSpecs) {
        $lines.Add('    ' + (ConvertTo-DpLuaString ([string]$case.id)) + ',')
    }
    $lines.Add('}')
    $lines.Add('DarkPassengerCaseCatalogByCode = {}')
    $lines.Add('')

    foreach ($case in $CaseSpecs) {
        $binding = @($Bindings.settlements | Where-Object {
            [string]$_.region -eq [string]$case.constraints.region -and
            [string]$_.settlement -eq [string]$case.constraints.settlement
        })[0]
        $runtimeCase = ConvertTo-DpRuntimeCase `
            -CaseSpec $case `
            -Binding $binding
        $caseId = ConvertTo-DpLuaString ([string]$case.id)
        $lines.Add("DarkPassengerCaseCatalog[$caseId] = " +
            (ConvertTo-DpLuaValue -Value $runtimeCase))
        $lines.Add(
            "DarkPassengerCaseCatalogByCode[$([int]$case.code)] = " +
            "DarkPassengerCaseCatalog[$caseId]"
        )
        $lines.Add('')
    }

    return ($lines -join "`n") + "`n"
}

function ConvertTo-DpCaseCompatibilityReport {
    param([Parameter(Mandatory)][object[]]$CaseSpecs)

    $cases = @($CaseSpecs | ForEach-Object {
        [ordered]@{
            id = [string]$_.id
            code = [int]$_.code
            bindingKey =
                [string]$_.constraints.region + '/' +
                [string]$_.constraints.settlement
            evidenceIds = @($_.evidence | ForEach-Object { [string]$_.id })
            evidenceCodes = @($_.evidence | ForEach-Object { [int]$_.code })
        }
    })
    return [ordered]@{
        schemaVersion = 1
        cases = $cases
    }
}

function ConvertTo-DpXmlText {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return '' }
    return [System.Security.SecurityElement]::Escape($Value)
}

function ConvertTo-DpLocalizationXml {
    param(
        [Parameter(Mandatory)][string]$BaseLiteralPath,
        [Parameter(Mandatory)][object[]]$CaseSpecs,
        [Parameter(Mandatory)][ValidateSet('ru', 'en')][string]$Language
    )

    [xml]$base = [System.IO.File]::ReadAllText($BaseLiteralPath)
    $rows = [System.Collections.Generic.List[object]]::new()
    $values = [ordered]@{}
    foreach ($row in @($base.Table.Row)) {
        $cells = @($row.Cell)
        if ($cells.Count -lt 2) { continue }
        $key = [string]$cells[0]
        $value = [string]$cells[1]
        if ($values.Contains($key)) {
            throw "Duplicate localization key '$key' in $BaseLiteralPath"
        }
        $values[$key] = $value
        $rows.Add([ordered]@{ key = $key; value = $value })
    }

    foreach ($case in @($CaseSpecs | Sort-Object code, id)) {
        if ($null -eq $case.PSObject.Properties['localization']) {
            continue
        }
        $languageRows = $case.localization.$Language
        if ($null -eq $languageRows) { continue }
        foreach ($property in $languageRows.PSObject.Properties) {
            $key = [string]$property.Name
            $value = [string]$property.Value
            if ($values.Contains($key)) {
                if ([string]$values[$key] -ne $value) {
                    throw (
                        "Localization key '$key' conflicts with existing " +
                        "$Language text."
                    )
                }
                continue
            }
            $values[$key] = $value
            $rows.Add([ordered]@{ key = $key; value = $value })
        }
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('<?xml version="1.0" encoding="utf-8"?>')
    $lines.Add('<Table>')
    foreach ($row in $rows) {
        $key = ConvertTo-DpXmlText ([string]$row.key)
        $value = ConvertTo-DpXmlText ([string]$row.value)
        $lines.Add("`t<Row><Cell>$key</Cell><Cell>$value</Cell></Row>")
    }
    $lines.Add('</Table>')
    return ($lines -join "`n") + "`n"
}

function ConvertTo-DpStormRoleXml {
    param(
        [Parameter(Mandatory)][string]$BaseXml,
        [Parameter(Mandatory)][object[]]$CaseSpecs,
        [Parameter(Mandatory)]$Bindings
    )

    $rules = @([regex]::Matches($BaseXml, '(?s)<rule\b.*?</rule>'))
    $additions = [System.Collections.Generic.List[string]]::new()
    foreach ($case in @($CaseSpecs | Sort-Object code, id)) {
        $binding = @($Bindings.settlements | Where-Object {
            [string]$_.region -eq [string]$case.constraints.region -and
            [string]$_.settlement -eq [string]$case.constraints.settlement
        })[0]
        foreach ($role in 'innkeeper', 'witness') {
            $roleBinding = $binding.roles.PSObject.Properties[$role].Value
            $entityName = [string]$roleBinding.entityName
            $dialogueRole = [string]$roleBinding.dialogueRole
            $existing = @($rules | Where-Object {
                $_.Value.Contains("<hasName name=`"$entityName`" />") -and
                $_.Value.Contains("<addRole name=`"$dialogueRole`" />")
            })
            if ($existing.Count -gt 0) { continue }

            $ruleName = 'darkpassenger_' +
                ([string]$case.constraints.settlement -replace '[^A-Za-z0-9_]', '_') +
                '_' + $role
            if ($BaseXml.Contains("<rule name=`"$ruleName`">") -or
                @($additions | Where-Object {
                    $_.Contains("<rule name=`"$ruleName`">")
                }).Count -gt 0) {
                throw "Storm rule name collision: $ruleName"
            }
            $entityXml = ConvertTo-DpXmlText $entityName
            $roleXml = ConvertTo-DpXmlText $dialogueRole
            $additions.Add(@"
    <rule name="$ruleName">
      <selectors>
        <hasName name="$entityXml" />
      </selectors>
      <operations>
        <addRole name="$roleXml" />
      </operations>
    </rule>
"@.TrimEnd())
        }
    }
    if ($additions.Count -eq 0) { return $BaseXml }
    $marker = '  </rules>'
    $index = $BaseXml.LastIndexOf($marker)
    if ($index -lt 0) { throw 'Storm role table has no rules terminator.' }
    return $BaseXml.Insert(
        $index,
        ($additions -join "`n") + "`n"
    )
}

function ConvertTo-DpScriptContextXml {
    param(
        [Parameter(Mandatory)][string]$BaseXml,
        [Parameter(Mandatory)][object[]]$CaseSpecs
    )

    $names = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($match in [regex]::Matches(
        $BaseXml,
        '<ScriptContextDatabaseNode\s+Name="([^"]+)"'
    )) {
        [void]$names.Add([string]$match.Groups[1].Value)
    }
    $additions = [System.Collections.Generic.List[string]]::new()
    foreach ($case in @($CaseSpecs | Sort-Object code, id)) {
        foreach ($context in @(
            [string]$case.native.contexts.rumorHeard,
            [string]$case.native.contexts.witnessHeard
        )) {
            if ($names.Add($context)) {
                $contextXml = ConvertTo-DpXmlText $context
                $additions.Add(
                    "    <ScriptContextDatabaseNode Name=`"$contextXml`" Class=`"Entity`" />"
                )
            }
        }
    }
    if ($additions.Count -eq 0) { return $BaseXml }
    $marker = '  </ScriptContexts>'
    $index = $BaseXml.LastIndexOf($marker)
    if ($index -lt 0) { throw 'ScriptContext table has no terminator.' }
    return $BaseXml.Insert($index, ($additions -join "`n") + "`n")
}

function ConvertTo-DpItemTableXml {
    param(
        [Parameter(Mandatory)][string]$BaseXml,
        [Parameter(Mandatory)][object[]]$CaseSpecs,
        [Parameter(Mandatory)]$Bindings
    )

    $knownIds = [ordered]@{}
    $knownNames = [ordered]@{}
    foreach ($match in [regex]::Matches(
        $BaseXml,
        '<Document\b[^>]*\bId="([^"]+)"[^>]*\bName="([^"]+)"'
    )) {
        $knownIds[[string]$match.Groups[1].Value] =
            [string]$match.Groups[2].Value
        $knownNames[[string]$match.Groups[2].Value] =
            [string]$match.Groups[1].Value
    }

    $additions = [System.Collections.Generic.List[string]]::new()
    foreach ($case in @($CaseSpecs | Sort-Object code, id)) {
        $documentSteps = @($case.evidence | Where-Object kind -eq 'document')
        if ($documentSteps.Count -eq 0) { continue }
        $binding = @($Bindings.settlements | Where-Object {
            [string]$_.region -eq [string]$case.constraints.region -and
            [string]$_.settlement -eq [string]$case.constraints.settlement
        })[0]
        foreach ($step in $documentSteps) {
            $id = [string]$binding.roles.document.documentGuid
            $name = [string]$step.item.name
            if ($knownIds.Contains($id)) {
                if ([string]$knownIds[$id] -ne $name) {
                    throw "Document GUID collision: $id"
                }
                continue
            }
            if ($knownNames.Contains($name)) {
                throw "Document item name collision: $name"
            }
            $knownIds[$id] = $name
            $knownNames[$name] = $id
            $idXml = ConvertTo-DpXmlText $id
            $nameXml = ConvertTo-DpXmlText $name
            $nameKeyXml = ConvertTo-DpXmlText ([string]$step.item.nameKey)
            $infoKeyXml = ConvertTo-DpXmlText ([string]$step.item.infoKey)
            $contentKeyXml = ConvertTo-DpXmlText ([string]$step.item.contentKey)
            $additions.Add(@"
        <Document Type="5" IconId="letter_simple" UIInfo="$infoKeyXml" UIName="$nameKeyXml" PickpocketInPouch="true" Model="characters/assets/parchment_folded/parchment_folded.cdf" EntityScript="Book" Weight="0" Price="0" FadeCoef="1.333333" VisibilityCoef="1" Id="$idXml" Name="$nameXml">
            <DocumentContent Parts="$contentKeyXml" />
        </Document>
"@.TrimEnd())
        }
    }
    if ($additions.Count -eq 0) { return $BaseXml }
    $marker = "`t</ItemClasses>"
    $index = $BaseXml.LastIndexOf($marker)
    if ($index -lt 0) { throw 'Item table has no ItemClasses terminator.' }
    return $BaseXml.Insert($index, ($additions -join "`n") + "`n")
}

function ConvertTo-DpDialogueXml {
    param(
        [Parameter(Mandatory)]$Dialogue,
        [Parameter(Mandatory)]$Binding
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('<?xml version="1.0" encoding="utf-8"?>')
    $lines.Add('<Database xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" Name="brambora">')
    $lines.Add('  <Skald>')
    $lines.Add("    <FaderDialog Name=`"$($Dialogue.graphName)`">")
    $lines.Add('      <Ports>')
    $lines.Add('        <Port Name="available" Direction="In" Type="bool">')
    $lines.Add(
        "          <DesignName Text=`"$(ConvertTo-DpXmlText $Dialogue.availableLabel)`" />"
    )
    $lines.Add('        </Port>')
    $lines.Add('        <Port Name="heard" Direction="Out" Type="trigger">')
    $lines.Add(
        "          <DesignName Text=`"$(ConvertTo-DpXmlText $Dialogue.heardLabel)`" />"
    )
    $lines.Add('        </Port>')
    $lines.Add('      </Ports>')
    $lines.Add("      <Text StringName=`"$($Dialogue.rootKey)`" />")
    $lines.Add('      <Dialogue TechnicalStatus="Enabled" AllowFarewell="false" AllowGreeting="false">')
    $lines.Add("        <Decision Name=`"$($Dialogue.kind)_root`" Priority=`"General`">")
    $lines.Add('          <Sequences>')
    $lines.Add(
        "            <Sequence EndType=`"EndDialogue`" EntryCondition=`"Port('available')`" Name=`"$($Dialogue.sequenceName)`">"
    )
    $lines.Add("              <UiPrompt StringName=`"$($Dialogue.promptKey)`" />")
    $lines.Add('              <Triggers>')
    $lines.Add('                <Port Name="heard" />')
    $lines.Add('              </Triggers>')
    $lines.Add('              <Elements>')
    foreach ($response in @($Dialogue.responses)) {
        $role = [string]$response.role
        if ($role -ne 'HENRY') {
            $roleBinding = $Binding.roles.PSObject.Properties[$role]
            if ($null -eq $roleBinding) {
                throw "Dialogue '$($Dialogue.graphName)' uses unbound role '$role'."
            }
            $role = [string]$roleBinding.Value.dialogueRole
        }
        $lines.Add("                <Response Role=`"$role`">")
        $lines.Add("                  <Text StringName=`"$($response.key)`" />")
        $lines.Add('                  <Commands><CameraCommand CameraType="CloseUp" /></Commands>')
        $lines.Add('                </Response>')
    }
    $lines.Add('              </Elements>')
    $lines.Add('            </Sequence>')
    $lines.Add('          </Sequences>')
    $lines.Add('        </Decision>')
    $lines.Add('      </Dialogue>')
    $lines.Add('    </FaderDialog>')
    $lines.Add('  </Skald>')
    $lines.Add('</Database>')
    return ($lines -join "`n") + "`n"
}

function ConvertTo-DpNativeRegionWiring {
    param(
        [Parameter(Mandatory)]$CaseSpec,
        [Parameter(Mandatory)]$Binding
    )

    $native = $CaseSpec.native
    $rumor = @($native.dialogues | Where-Object kind -eq 'rumor')
    $witness = @($native.dialogues | Where-Object kind -eq 'witness')
    if ($rumor.Count -ne 1 -or $witness.Count -ne 1) {
        throw "Case '$($CaseSpec.id)' requires one rumor and one witness dialogue."
    }
    $rumor = $rumor[0]
    $witness = $witness[0]
    $folder = [string]$native.dialogFolder
    $rumorTag = [int]$native.signals.rumorAvailableTag
    $witnessTag = [int]$native.signals.witnessAvailableTag
    $rumorContext = [string]$native.contexts.rumorHeard
    $witnessContext = [string]$native.contexts.witnessHeard
    $objective = $native.witnessObjective
    $objectiveAssetName = [string]$objective.assetName

    $definitions = @"
      <Definitions>
        <Definition File="$folder/$($rumor.fileName)" />
        <Definition File="$folder/$($witness.fileName)" />
      </Definitions>
"@
    $rumorNodes = @"
        <MakeArray Name="rumorAvailableTags" TypeT="wh::rpgmodule::BuffDefinitionAITags">
          <Constant Name="A" Value="$rumorTag" />
        </MakeArray>
        <BuffTagTrigger Name="rumorAvailableTrigger">
          <Asset Name="Souls" Alias="player" />
          <Edge From="rumorAvailableTags.Array" To="BuffTags" />
          <Edge From="questProgress.Active" To="IsActive" />
        </BuffTagTrigger>
        <State Name="rumorDialogueAvailable" TypeT="bool">
          <Edge From="rumorAvailableTrigger.OnAdded" To="SetTrue" />
          <Edge From="rumorAvailableTrigger.OnRemoved" To="SetFalse" />
          <Edge From="firstLeadTrigger.OnAdded" To="SetFalse" />
          <Edge From="satisfactionTrigger.OnAdded" To="SetFalse" />
          <Edge From="cleanResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="controlledResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="noisyResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="externalResultTrigger.OnAdded" To="SetFalse" />
        </State>
        <$($rumor.graphName) Name="innkeeperRumorDialog">
          <Edge From="rumorDialogueAvailable.State" To="available" />
        </$($rumor.graphName)>
        <State Name="rumorDialogueRequestActive" TypeT="bool">
          <Edge From="questProgress.OnActive" To="SetFalse" />
          <Edge From="innkeeperRumorDialog.heard" To="SetTrue" />
          <Edge From="firstLeadTrigger.OnAdded" To="SetFalse" />
          <Edge From="satisfactionTrigger.OnAdded" To="SetFalse" />
          <Edge From="cleanResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="controlledResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="noisyResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="externalResultTrigger.OnAdded" To="SetFalse" />
        </State>
        <SetEntityContext Name="rumorDialogueRequest">
          <Constant Name="Context" Value="$rumorContext" />
          <Asset Name="Souls" Alias="player" />
          <Edge From="rumorDialogueRequestActive.State" To="IsActive" />
        </SetEntityContext>
"@
    $witnessNodes = @"
        <MakeArray Name="witnessAvailableTags" TypeT="wh::rpgmodule::BuffDefinitionAITags">
          <Constant Name="A" Value="$witnessTag" />
        </MakeArray>
        <BuffTagTrigger Name="witnessAvailableTrigger">
          <Asset Name="Souls" Alias="player" />
          <Edge From="witnessAvailableTags.Array" To="BuffTags" />
          <Edge From="questProgress.Active" To="IsActive" />
        </BuffTagTrigger>
        <State Name="witnessDialogueAvailable" TypeT="bool">
          <Edge From="witnessAvailableTrigger.OnAdded" To="SetTrue" />
          <Edge From="witnessAvailableTrigger.OnRemoved" To="SetFalse" />
          <Edge From="revealTagTrigger.OnAdded" To="SetFalse" />
          <Edge From="satisfactionTrigger.OnAdded" To="SetFalse" />
          <Edge From="cleanResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="controlledResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="noisyResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="externalResultTrigger.OnAdded" To="SetFalse" />
        </State>
        <$($witness.graphName) Name="tavernWitnessDialog">
          <Edge From="witnessDialogueAvailable.State" To="available" />
        </$($witness.graphName)>
        <State Name="witnessDialogueRequestActive" TypeT="bool">
          <Edge From="questProgress.OnActive" To="SetFalse" />
          <Edge From="tavernWitnessDialog.heard" To="SetTrue" />
          <Edge From="revealTagTrigger.OnAdded" To="SetFalse" />
          <Edge From="satisfactionTrigger.OnAdded" To="SetFalse" />
          <Edge From="cleanResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="controlledResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="noisyResultTrigger.OnAdded" To="SetFalse" />
          <Edge From="externalResultTrigger.OnAdded" To="SetFalse" />
        </State>
        <SetEntityContext Name="witnessDialogueRequest">
          <Constant Name="Context" Value="$witnessContext" />
          <Asset Name="Souls" Alias="player" />
          <Edge From="witnessDialogueRequestActive.State" To="IsActive" />
        </SetEntityContext>
"@
    $witnessObjectiveNodes = @"
        <State Name="witnessObjectiveProgress" TypeT="DP_WitnessProgress">
          <Edge From="satisfactionTrigger.OnRemoved" To="SetNone" />
          <Edge From="questProgress.OnActive" To="SetNone" />
          <Edge From="witnessAvailableTrigger.OnAdded" To="SetActive" />
          <Edge From="revealTagTrigger.OnAdded" To="SetDone" />
        </State>
        <$objectiveAssetName Name="witnessVisual">
          <Edge From="witnessObjectiveProgress.State" To="Progress" />
        </$objectiveAssetName>
"@
    $witnessType = @"
        <Type TypeName="DP_WitnessProgress">
          <StateTypeEnumeration Name="None" ObjectiveValueType="None" />
          <StateTypeEnumeration Name="Active" ObjectiveValueType="Started" />
          <StateTypeEnumeration Name="Done" ObjectiveValueType="Completed" />
        </Type>
"@
    $fallbackName = ConvertTo-DpXmlText $objective.fallbackName
    $fallbackActive = ConvertTo-DpXmlText $objective.fallbackActive
    $fallbackDone = ConvertTo-DpXmlText $objective.fallbackDone
    $witnessObjective = @"
        <Objective TypeT="DP_WitnessProgress" Name="$objectiveAssetName">
          <LocalizedName StringName="$($objective.nameKey)" Text="$fallbackName">
            <Localization Text="$fallbackName" Language="WHS" />
          </LocalizedName>
          <Logs>
            <EnumLog Type="None" Name="None" />
            <EnumLog Type="Started" Name="Active" IsTracked="true">
              <Log StringName="$($objective.activeKey)" Text="$fallbackActive">
                <Localization Text="$fallbackActive" Language="WHS" />
              </Log>
            </EnumLog>
            <EnumLog Type="Completed" Name="Done">
              <Log StringName="$($objective.doneKey)" Text="$fallbackDone">
                <Localization Text="$fallbackDone" Language="WHS" />
              </Log>
            </EnumLog>
          </Logs>
        </Objective>
"@

    return [ordered]@{
        caseId = [string]$CaseSpec.id
        region = [string]$CaseSpec.constraints.region
        settlement = [string]$CaseSpec.constraints.settlement
        questName = [string]$native.questName
        dialogFolder = $folder
        dialogDefinitions = $definitions.TrimEnd()
        rumorNodes = $rumorNodes.TrimEnd()
        witnessNodes = $witnessNodes.TrimEnd()
        evidenceWitnessEdge =
            '          <Edge From="witnessAvailableTrigger.OnAdded" To="SetDone" />'
        witnessObjectiveNodes = $witnessObjectiveNodes.TrimEnd()
        witnessType = $witnessType.TrimEnd()
        witnessObjective = $witnessObjective.TrimEnd()
        dialogues = @($native.dialogues | ForEach-Object {
            [ordered]@{
                fileName = [string]$_.fileName
                xml = ConvertTo-DpDialogueXml -Dialogue $_ -Binding $Binding
            }
        })
    }
}

function Get-DpCaseSpecValidationErrors {
    param(
        [Parameter(Mandatory)]$CaseSpec,
        [Parameter(Mandatory)]$Bindings,
        [string]$SourceName = '<case>'
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    $prefix = "${SourceName}:"

    if (-not (Test-DpTextValue $CaseSpec.id)) {
        $errors.Add("$prefix id is required")
    }
    if ([int]$CaseSpec.schemaVersion -ne 2) {
        $errors.Add("$prefix schemaVersion must be 2")
    }
    if ([int]$CaseSpec.code -le 0) {
        $errors.Add("$prefix code must be a positive integer")
    }
    if ([double]$CaseSpec.weight -le 0) {
        $errors.Add("$prefix weight must be positive")
    }

    $region = [string]$CaseSpec.constraints.region
    $settlement = [string]$CaseSpec.constraints.settlement
    if (-not (Test-DpTextValue $region)) {
        $errors.Add("$prefix constraints.region is required")
    }
    if (-not (Test-DpTextValue $settlement)) {
        $errors.Add("$prefix constraints.settlement is required")
    }

    $binding = @($Bindings.settlements | Where-Object {
        [string]$_.region -eq $region -and
        [string]$_.settlement -eq $settlement
    })
    if ($binding.Count -ne 1 -and
        (Test-DpTextValue $region) -and
        (Test-DpTextValue $settlement)) {
        $errors.Add("$prefix no settlement binding for '$region/$settlement'")
    }

    foreach ($language in 'ru', 'en') {
        $languageText = $CaseSpec.text.$language
        foreach ($field in 'title', 'description') {
            if (-not (Test-DpTextValue $languageText.$field)) {
                $errors.Add("$prefix text.$language.$field is required")
            }
        }
    }

    $localizationProperty = $CaseSpec.PSObject.Properties['localization']
    if ($null -ne $localizationProperty) {
        $ruLocalization = $CaseSpec.localization.ru
        $enLocalization = $CaseSpec.localization.en
        $ruKeys = if ($null -ne $ruLocalization) {
            @($ruLocalization.PSObject.Properties.Name | Sort-Object)
        }
        else { @() }
        $enKeys = if ($null -ne $enLocalization) {
            @($enLocalization.PSObject.Properties.Name | Sort-Object)
        }
        else { @() }
        if (($ruKeys -join "`n") -ne ($enKeys -join "`n")) {
            $errors.Add(
                "$prefix localization.ru and localization.en key sets must match"
            )
        }
        foreach ($language in 'ru', 'en') {
            $languageLocalization = $CaseSpec.localization.$language
            if ($null -eq $languageLocalization) { continue }
            foreach ($property in $languageLocalization.PSObject.Properties) {
                if (-not (Test-DpTextValue $property.Value)) {
                    $errors.Add(
                        "$prefix localization.$language.$($property.Name) is required"
                    )
                }
            }
        }
    }

    if (-not (Test-DpTextValue $CaseSpec.native.questName)) {
        $errors.Add("$prefix native.questName is required")
    }
    if (-not (Test-DpTextValue $CaseSpec.native.dialogFolder)) {
        $errors.Add("$prefix native.dialogFolder is required")
    }
    foreach ($dialogueKind in 'rumor', 'witness') {
        $dialogues = @($CaseSpec.native.dialogues | Where-Object {
            [string]$_.kind -eq $dialogueKind
        })
        if ($dialogues.Count -ne 1) {
            $errors.Add(
                "$prefix native.dialogues requires one '$dialogueKind' entry"
            )
            continue
        }
        $dialogue = $dialogues[0]
        foreach ($field in 'graphName', 'fileName', 'rootKey',
            'sequenceName', 'promptKey') {
            if (-not (Test-DpTextValue $dialogue.$field)) {
                $errors.Add(
                    "$prefix native dialogue '$dialogueKind' $field is required"
                )
            }
        }
        foreach ($response in @($dialogue.responses)) {
            $role = [string]$response.role
            if (-not (Test-DpTextValue $response.key)) {
                $errors.Add(
                    "$prefix native dialogue '$dialogueKind' response key is required"
                )
            }
            if ($role -ne 'HENRY' -and $binding.Count -eq 1 -and
                $null -eq $binding[0].roles.PSObject.Properties[$role]) {
                $errors.Add(
                    "$prefix native dialogue '$dialogueKind' role '$role' is not bound"
                )
            }
        }
    }
    if ([int]$CaseSpec.native.signals.rumorAvailableTag -le 0 -or
        [int]$CaseSpec.native.signals.witnessAvailableTag -le 0) {
        $errors.Add("$prefix native signal tags must be positive")
    }
    if (-not (Test-DpTextValue $CaseSpec.native.contexts.rumorHeard) -or
        -not (Test-DpTextValue $CaseSpec.native.contexts.witnessHeard)) {
        $errors.Add("$prefix native dialogue contexts are required")
    }
    if (-not (Test-DpTextValue $CaseSpec.native.witnessObjective.assetName)) {
        $errors.Add("$prefix native.witnessObjective.assetName is required")
    }

    $evidence = @($CaseSpec.evidence)
    if ($evidence.Count -eq 0) {
        $errors.Add("$prefix evidence must contain at least one step")
    }
    $seenEvidence = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $seenEvidenceCodes = [System.Collections.Generic.HashSet[int]]::new()
    $confidenceTotal = 0
    foreach ($step in $evidence) {
        $evidenceId = [string]$step.id
        if (-not (Test-DpTextValue $evidenceId)) {
            $errors.Add("$prefix evidence id is required")
        }
        elseif (-not $seenEvidence.Add($evidenceId)) {
            $errors.Add("$prefix evidence id '$evidenceId' is duplicated")
        }
        $evidenceCode = [int]$step.code
        if ($evidenceCode -le 0) {
            $errors.Add("$prefix evidence '$evidenceId' code must be positive")
        }
        elseif (-not $seenEvidenceCodes.Add($evidenceCode)) {
            $errors.Add("$prefix evidence code '$evidenceCode' is duplicated")
        }
        $kind = [string]$step.kind
        if (-not (Test-DpTextValue $kind)) {
            $errors.Add("$prefix evidence '$evidenceId' kind is required")
        }
        elseif ($kind -notin @('dialogue', 'document')) {
            $errors.Add(
                "$prefix evidence '$evidenceId' kind '$kind' is not supported"
            )
        }
        if ($kind -eq 'document') {
            foreach ($field in 'name', 'nameKey', 'infoKey', 'contentKey') {
                if ($null -eq $step.PSObject.Properties['item'] -or
                    -not (Test-DpTextValue $step.item.$field)) {
                    $errors.Add(
                        "$prefix evidence '$evidenceId' item.$field is required"
                    )
                }
            }
            if (-not (Test-DpTextValue $step.reaction)) {
                $errors.Add(
                    "$prefix evidence '$evidenceId' reaction is required"
                )
            }
        }
        if ([int]$step.confidence -le 0) {
            $errors.Add("$prefix evidence '$evidenceId' confidence must be positive")
        }
        else {
            $confidenceTotal += [int]$step.confidence
        }

        $role = [string]$step.role
        if (-not (Test-DpTextValue $role)) {
            $errors.Add("$prefix evidence '$evidenceId' role is required")
        }
        elseif ($binding.Count -eq 1 -and
            $null -eq $binding[0].roles.PSObject.Properties[$role]) {
            $errors.Add("$prefix semantic role '$role' is not bound")
        }

        $placementProperty = $step.PSObject.Properties['placement']
        $placement = if ($null -ne $placementProperty) {
            [string]$placementProperty.Value
        }
        else { '' }
        if ($placement -notin @('case_start', 'on_event')) {
            $errors.Add(
                "$prefix evidence '$evidenceId' placement must be " +
                "'case_start' or 'on_event'"
            )
        }

        $discoverableProperty =
            $step.PSObject.Properties['discoverableWithoutHint']
        if ($null -eq $discoverableProperty -or
            $discoverableProperty.Value -isnot [bool]) {
            $errors.Add(
                "$prefix evidence '$evidenceId' " +
                'discoverableWithoutHint must be boolean'
            )
        }

        $hintProperty = $step.PSObject.Properties['hintsUnlockedBy']
        if ($null -eq $hintProperty) {
            $errors.Add(
                "$prefix evidence '$evidenceId' hintsUnlockedBy is required"
            )
        }

        $revealsProperty = $step.PSObject.Properties['reveals']
        $revealedFacts = if ($null -ne $revealsProperty) {
            @($revealsProperty.Value | Where-Object {
                Test-DpTextValue $_
            })
        }
        else { @() }
        if (@($revealedFacts).Count -eq 0) {
            $errors.Add(
                "$prefix evidence '$evidenceId' reveals must contain a fact"
            )
        }
    }

    $evidenceIds = @($evidence | ForEach-Object { [string]$_.id })
    foreach ($step in $evidence) {
        $hintProperty = $step.PSObject.Properties['hintsUnlockedBy']
        if ($null -eq $hintProperty) { continue }
        foreach ($hintSource in @($hintProperty.Value)) {
            $hintSourceId = [string]$hintSource
            if ((Test-DpTextValue $hintSourceId) -and
                $hintSourceId -notin $evidenceIds) {
                $errors.Add(
                    "$prefix evidence '$($step.id)' references unknown " +
                    "hint source '$hintSourceId'"
                )
            }
        }
    }

    $threshold = [int]$CaseSpec.revealThreshold
    if ($threshold -le 0) {
        $errors.Add("$prefix revealThreshold must be positive")
    }
    elseif ($confidenceTotal -lt $threshold) {
        $errors.Add(
            "$prefix evidence confidence total $confidenceTotal is below revealThreshold $threshold"
        )
    }

    return $errors.ToArray()
}

function Get-DpValidatedCaseSpecs {
    param(
        [Parameter(Mandatory)][string]$CaseRoot,
        [Parameter(Mandatory)][string]$BindingPath
    )

    $bindings = Read-DpCaseSettlementBindings -LiteralPath $BindingPath
    if ([int]$bindings.schemaVersion -ne 1) {
        throw "Settlement bindings schemaVersion must be 1: $BindingPath"
    }

    $files = @(Get-ChildItem -LiteralPath $CaseRoot -Filter '*.case.json' |
        Sort-Object FullName)
    if ($files.Count -eq 0) {
        throw "No CaseSpec files found in: $CaseRoot"
    }

    $cases = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()
    $ids = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $codes = [System.Collections.Generic.HashSet[int]]::new()

    foreach ($file in $files) {
        $case = Read-DpCaseSpec -LiteralPath $file.FullName
        foreach ($errorMessage in @(Get-DpCaseSpecValidationErrors `
            -CaseSpec $case `
            -Bindings $bindings `
            -SourceName $file.Name)) {
            $errors.Add($errorMessage)
        }
        if ((Test-DpTextValue $case.id) -and
            -not $ids.Add([string]$case.id)) {
            $errors.Add("$($file.Name): case id '$($case.id)' is duplicated")
        }
        if ([int]$case.code -gt 0 -and -not $codes.Add([int]$case.code)) {
            $errors.Add("$($file.Name): case code '$($case.code)' is duplicated")
        }
        $cases.Add($case)
    }

    if ($errors.Count -gt 0) {
        throw "CaseSpec validation failed:`n - $($errors -join "`n - ")"
    }

    return @($cases | Sort-Object code, id)
}

Export-ModuleMember -Function @(
    'Read-DpCaseSpec',
    'Read-DpCaseSettlementBindings',
    'Get-DpCaseSpecValidationErrors',
    'Get-DpValidatedCaseSpecs',
    'ConvertTo-DpLuaString',
    'ConvertTo-DpLuaValue',
    'ConvertTo-DpCaseCatalogLua',
    'ConvertTo-DpCaseCompatibilityReport',
    'ConvertTo-DpDialogueXml',
    'ConvertTo-DpNativeRegionWiring',
    'ConvertTo-DpLocalizationXml',
    'ConvertTo-DpStormRoleXml',
    'ConvertTo-DpScriptContextXml',
    'ConvertTo-DpItemTableXml'
)
