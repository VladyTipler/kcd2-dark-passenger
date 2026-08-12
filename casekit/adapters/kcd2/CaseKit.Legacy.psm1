Set-StrictMode -Version Latest

function Read-CaseKitLegacyJson {
    param([Parameter(Mandatory)][string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "Legacy CaseKit source not found: $LiteralPath"
    }
    try {
        return [System.IO.File]::ReadAllText($LiteralPath) |
            ConvertFrom-Json -Depth 100
    }
    catch {
        throw "Invalid JSON in '$LiteralPath': $($_.Exception.Message)"
    }
}

function ConvertTo-CaseKitLegacyCaseDefinition {
    param(
        [Parameter(Mandatory)]$CaseSpec,
        [Parameter(Mandatory)][object[]]$DialogueRoles
    )

    return [pscustomobject][ordered]@{
        source = [pscustomobject][ordered]@{
            format = 'legacy-case-spec-v2'
            schemaVersion = [int]$CaseSpec.schemaVersion
            dialogueRoles = @($DialogueRoles)
        }
        case = [pscustomobject][ordered]@{
            id = [string]$CaseSpec.id
            code = [int]$CaseSpec.code
            weight = $CaseSpec.weight
            revealThreshold = [int]$CaseSpec.revealThreshold
            identityRequirement = $CaseSpec.identityRequirement
        }
        constraints = [pscustomobject][ordered]@{
            region = [string]$CaseSpec.constraints.region
            settlement = [string]$CaseSpec.constraints.settlement
        }
        targetPolicy = $CaseSpec.targetPolicy
        story = [pscustomobject][ordered]@{
            crimeProfile = $CaseSpec.crimeProfile
            text = $CaseSpec.text
            localization = $CaseSpec.localization
        }
        evidence = @($CaseSpec.evidence)
        presentation = [pscustomobject][ordered]@{
            adapter = 'kcd2-legacy-case-spec'
            payload = $CaseSpec.native
        }
    }
}

function Read-CaseKitLegacyDeck {
    param(
        [Parameter(Mandatory)][string]$CaseRoot,
        [Parameter(Mandatory)][string]$BindingPath
    )

    if (-not (Test-Path -LiteralPath $CaseRoot -PathType Container)) {
        throw "Legacy CaseSpec root not found: $CaseRoot"
    }

    $bindings = Read-CaseKitLegacyJson -LiteralPath $BindingPath
    $caseSpecs = @(Get-ChildItem -LiteralPath $CaseRoot -Filter '*.case.json' `
        -File |
        ForEach-Object {
            Read-CaseKitLegacyJson -LiteralPath $_.FullName
        } |
        Sort-Object @{ Expression = { [int]$_.code } }, `
            @{ Expression = { [string]$_.id } })
    $cases = @($caseSpecs | ForEach-Object {
        ConvertTo-CaseKitLegacyCaseDefinition -CaseSpec $_ `
            -DialogueRoles @($bindings.dialogueRoles)
    })
    $settlements = @($bindings.settlements |
        Sort-Object @{ Expression = { [string]$_.region } }, `
            @{ Expression = { [string]$_.settlement } })

    return [ordered]@{
        schemaVersion = 1
        sourceFormat = 'legacy-case-spec-v2'
        cases = $cases
        settlements = $settlements
    }
}

function ConvertTo-CaseKitLegacyBackendInput {
    param([Parameter(Mandatory)][object[]]$Variants)

    $caseSpecs = [System.Collections.Generic.List[object]]::new()
    $settlementByKey = [ordered]@{}
    $dialogueRoles = $null

    foreach ($variant in @($Variants | Sort-Object `
        @{ Expression = { [int]$_.case.code } }, `
            @{ Expression = { [string]$_.case.id } })) {
        $variantDialogueRoles = @($variant.source.dialogueRoles)
        if ($null -eq $dialogueRoles) {
            $dialogueRoles = $variantDialogueRoles
        }
        elseif (($dialogueRoles | ConvertTo-Json -Depth 100 -Compress) -cne
            ($variantDialogueRoles | ConvertTo-Json -Depth 100 -Compress)) {
            throw 'Conflicting legacy dialogue role registries.'
        }
        $caseSpecs.Add([pscustomobject][ordered]@{
            schemaVersion = [int]$variant.source.schemaVersion
            id = [string]$variant.case.id
            code = [int]$variant.case.code
            weight = $variant.case.weight
            constraints = [pscustomobject][ordered]@{
                region = [string]$variant.world.region
                settlement = [string]$variant.world.settlement
            }
            targetPolicy = $variant.targetPolicy
            crimeProfile = $variant.story.crimeProfile
            revealThreshold = [int]$variant.case.revealThreshold
            identityRequirement = $variant.case.identityRequirement
            native = $variant.presentation.payload
            evidence = @($variant.evidence)
            text = $variant.story.text
            localization = $variant.story.localization
        })

        $key = "$([string]$variant.world.region)/" +
            [string]$variant.world.settlement
        $binding = [pscustomobject][ordered]@{
            region = [string]$variant.world.region
            settlement = [string]$variant.world.settlement
            roles = $variant.world.roles
        }
        if ($settlementByKey.Contains($key)) {
            $existingJson = $settlementByKey[$key] |
                ConvertTo-Json -Depth 100 -Compress
            $candidateJson = $binding |
                ConvertTo-Json -Depth 100 -Compress
            if ($existingJson -ne $candidateJson) {
                throw "Conflicting legacy bindings for '$key'."
            }
        }
        else {
            $settlementByKey[$key] = $binding
        }
    }

    return [pscustomobject][ordered]@{
        schemaVersion = 1
        caseSpecs = $caseSpecs.ToArray()
        bindings = [pscustomobject][ordered]@{
            schemaVersion = 1
            dialogueRoles = @($dialogueRoles)
            settlements = @($settlementByKey.Values)
        }
    }
}

Export-ModuleMember -Function @(
    'ConvertTo-CaseKitLegacyBackendInput',
    'Read-CaseKitLegacyDeck'
)
