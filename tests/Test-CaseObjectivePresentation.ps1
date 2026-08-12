$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'dark-passenger-objectives-' + [guid]::NewGuid().ToString('N')
)
$compilerInput = Join-Path $tempRoot 'build\generated\casekit\compiler-input'
$buildRoot = Join-Path $tempRoot 'build'
$questRoot = Join-Path $buildRoot 'mod\Data\Quests\Final\Barbora'
$kuttenbergQuest = Join-Path $questRoot 'kutnohorsko\dark_within_k.xml'
$troskyQuest = Join-Path $questRoot 'trosecko\dark_within_t.xml'
$luaOutput = Join-Path $buildRoot `
    'mod\Data\Scripts\mods\generated\dp_candidate_catalog.lua'

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

function Test-QuestSiblingNodeNamesUnique {
    param([System.Xml.XmlDocument]$Document)

    foreach ($parent in @($Document.SelectNodes('//*'))) {
        $namedChildren = @($parent.ChildNodes | Where-Object {
            $_.NodeType -eq [System.Xml.XmlNodeType]::Element -and
            $_.HasAttribute('Name')
        })
        if (@($namedChildren | Group-Object {
            $_.GetAttribute('Name')
        } | Where-Object Count -gt 1).Count -gt 0) {
            return $false
        }
    }
    return $true
}

try {
    [System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null
    & (Join-Path $repoRoot 'casekit\cli\Compile-CaseKit.ps1') `
        -ArchetypeRoot (Join-Path $repoRoot 'content\archetypes') `
        -StoryRoot (Join-Path $repoRoot 'content\stories') `
        -EvidenceModuleRoot (Join-Path $repoRoot `
            'content\evidence-modules') `
        -WorldIndexPath (Join-Path $repoRoot `
            'config\world-semantic-index.json') `
        -SettlementCatalogPath (Join-Path $repoRoot `
            'config\settlement-investigation-areas.json') `
        -SettlementProfileRoot (Join-Path $repoRoot 'config\settlements') `
        -StableIdRegistryPath (Join-Path $repoRoot `
            'config\casekit-stable-ids.json') `
        -Kcd2AdapterPath (Join-Path $repoRoot `
            'config\casekit-kcd2-native.json') `
        -MaxVariantsPerCombination 8 `
        -OutputRoot $compilerInput

    & (Join-Path $repoRoot 'tools\Compile-CaseSpecs.ps1') `
        -CaseVariantRoot $compilerInput `
        -BuildRoot $buildRoot

    $nativeWiringPath = Join-Path $buildRoot `
        'generated\cases\native-wiring.json'
    $nativeWiring = [System.IO.File]::ReadAllText($nativeWiringPath) |
        ConvertFrom-Json -AsHashtable -Depth 100
    $troskyWiring = @($nativeWiring.regions | Where-Object {
        $_.region -eq 'trosecko'
    })[0]
    $kuttenbergWiring = @($nativeWiring.regions | Where-Object {
        $_.region -eq 'kutnohorsko'
    })[0]
    $troskyWiring.journalObjectives.cleanup.states.Remove('witnessed')
    $kuttenbergWiring.journalObjectives.investigation = $null
    [System.IO.File]::WriteAllText(
        $nativeWiringPath,
        ($nativeWiring | ConvertTo-Json -Depth 100),
        [System.Text.UTF8Encoding]::new($false)
    )

    & (Join-Path $repoRoot 'tools\Generate-VictimArtifacts.ps1') `
        -NativeWiringPath $nativeWiringPath `
        -KuttenbergQuestOutputPath $kuttenbergQuest `
        -TroskyQuestOutputPath $troskyQuest `
        -LuaOutputPath $luaOutput

    [xml]$quest = [System.IO.File]::ReadAllText($troskyQuest)
    $objectives = @($quest.Database.Skald.Quest.Objectives.Objective)
    $investigation = @($objectives | Where-Object {
        [string]$_.LocalizedName.StringName -eq
            'dp_case_2001_objective_investigation_name'
    })
    $listen = @($objectives | Where-Object {
        [string]$_.LocalizedName.StringName -eq
            'dp_case_2001_objective_guidance_listen_name'
    })
    Add-Result (
        $investigation.Count -eq 1 -and $listen.Count -gt 0 -and
        [string]$investigation[0].LocalizedName.StringName -ne
            [string]$listen[0].LocalizedName.StringName
    ) 'compiled quest separates the broad investigation from marker objectives'

    [xml]$kuttenberg = [System.IO.File]::ReadAllText($kuttenbergQuest)
    foreach ($regionalQuest in @($quest, $kuttenberg)) {
        $regionalText = $regionalQuest.OuterXml
        Add-Result (
            $regionalText.Contains('dp_case_1001_objective_search_name') -and
            $regionalText.Contains('dp_case_2001_objective_search_name') -and
            -not $regionalText.Contains('System.Object[]') -and
            $regionalText -notmatch '\{\{DP_[A-Z0-9_]+\}\}' -and
            (Test-QuestSiblingNodeNamesUnique -Document $regionalQuest)
        ) 'regional quest contains both isolated StoryPacks without XML collisions'
    }

    foreach ($expectedKey in @(
        'dp_case_2001_objective_search_name',
        'dp_case_2001_objective_investigation_name',
        'dp_case_2001_objective_target_name',
        'dp_case_2001_objective_cleanup_name'
    )) {
        Add-Result (
            @($objectives | Where-Object {
                [string]$_.LocalizedName.StringName -eq $expectedKey
            }).Count -gt 0
        ) "compiled quest uses StoryPack objective '$expectedKey'"
    }

    $russianLocalizationPath = Join-Path $buildRoot `
        'generated\localization\Russian\text__darkpassengertest.xml'
    [xml]$russian = [System.IO.File]::ReadAllText($russianLocalizationPath)
    $russianRows = @{}
    foreach ($row in @($russian.Table.Row)) {
        $russianRows[[string]$row.Cell[0]] = [string]$row.Cell[1]
    }
    Add-Result (
        $russianRows['dp_case_2001_objective_investigation_name'] -eq
            'Раскрыть судьбу Матея' -and
        $russianRows['dp_case_2001_objective_guidance_listen_name'] -eq
            'Прислушаться к разговорам во дворе корчмы'
    ) 'StoryPack objective localization crosses into the final table'
    Add-Result (
        -not ([System.IO.File]::ReadAllText(
            $russianLocalizationPath
        )).Contains('{{')
    ) 'generated native localization contains no unresolved template tokens'

    $questText = [System.IO.File]::ReadAllText($troskyQuest)
    Add-Result (
        $questText.Contains(
            'StringName="dp_case_2001_objective_cleanup_active"'
        ) -and
        $questText.Contains('StringName="dark_within_cleanup_witnessed"') -and
        $questText.Contains('Someone saw too much.')
    ) 'partial lifecycle objective preserves authored states and fills missing states'

    $kuttenbergObjectives = @(
        $kuttenberg.Database.Skald.Quest.Objectives.Objective
    )
    Add-Result (
        @($kuttenbergObjectives | Where-Object {
            [string]$_.LocalizedName.StringName -eq
                'dark_within_evidence_name'
        }).Count -eq 1
    ) 'null lifecycle objective falls back to the universal presentation'
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
