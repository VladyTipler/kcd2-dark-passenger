$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repoRoot 'tools\CaseSpecCompiler.psm1') -Force

$passed = 0
$failed = 0
function Assert-True([bool]$Condition, [string]$Message) {
    if ($Condition) {
        $script:passed++
        Write-Host "PASS: $Message"
    }
    else {
        $script:failed++
        Write-Host "FAIL: $Message" -ForegroundColor Red
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'dp-dialogue-media-duration-' + [guid]::NewGuid().ToString('N')
)
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    $jobsPath = Join-Path $tempRoot 'jobs.json'
    $resultsPath = Join-Path $tempRoot 'results.json'
    $jobs = [ordered]@{
        schemaVersion = 1
        game = 'kcd2'
        packageLanguage = 'english'
        jobs = @(
            [ordered]@{
                jobId = 'beta'
                audioFolder = 'trosecko/dark_within_t'
                stringName = 'dp_line'
            },
            [ordered]@{
                jobId = 'other-actor-same-line'
                audioFolder = 'trosecko/dark_within_t'
                stringName = 'dp_line'
            },
            [ordered]@{
                jobId = 'henry'
                audioFolder = 'trosecko/dark_within_t'
                stringName = 'dp_reply'
            }
        )
    }
    $results = [ordered]@{
        schemaVersion = 1
        status = 'complete'
        jobs = @(
            [ordered]@{ jobId = 'beta'; status = 'complete'; durationSeconds = 4.2 },
            [ordered]@{ jobId = 'other-actor-same-line'; status = 'complete'; durationSeconds = 5.7 },
            [ordered]@{ jobId = 'henry'; status = 'complete'; durationSeconds = 3.1 }
        )
    }
    [System.IO.File]::WriteAllText(
        $jobsPath,
        ($jobs | ConvertTo-Json -Depth 20),
        [System.Text.UTF8Encoding]::new($false)
    )
    [System.IO.File]::WriteAllText(
        $resultsPath,
        ($results | ConvertTo-Json -Depth 20),
        [System.Text.UTF8Encoding]::new($false)
    )

    $lengths = Read-DpDialogueMediaReferenceLengths `
        -JobsManifestPath $jobsPath -ResultsManifestPath $resultsPath
    Assert-True (
        [decimal]$lengths['trosecko/dark_within_t|dp_line'] -eq 5.7
    ) 'different actor durations collapse to safe maximum'
    Assert-True (
        [decimal]$lengths['trosecko/dark_within_t|dp_reply'] -eq 3.1
    ) 'each StringName keeps its measured duration'

    $dialogue = [pscustomobject][ordered]@{
        graphName = 'dialogue'
        fileName = 'dialogue.xml'
        kind = 'rumor'
        rootKey = 'dp_root'
        promptKey = 'dp_prompt'
        sequenceName = 'sequence'
        availableLabel = 'Available'
        heardLabel = 'Heard'
        media = [pscustomobject][ordered]@{ voice = 'native'; lipSync = $true }
        responses = @(
            [pscustomobject][ordered]@{ role = 'innkeeper'; key = 'dp_line' },
            [pscustomobject][ordered]@{ role = 'HENRY'; key = 'dp_reply' }
        )
    }
    $caseSpec = [pscustomobject][ordered]@{
        id = 'probe'
        native = [pscustomobject][ordered]@{ questName = 'dark_within_t' }
    }
    $binding = [pscustomobject][ordered]@{
        roles = [pscustomobject][ordered]@{
            innkeeper = [pscustomobject][ordered]@{
                dialogueRole = 'DP_SLOT_INNKEEPER'
            }
        }
    }
    $silentDialogue = [pscustomobject][ordered]@{
        graphName = 'silent_dialogue'
        responses = @()
    }
    $missingMediaThrew = $false
    try {
        Get-DpDialogueMediaDemands -CaseSpec $caseSpec `
            -Region 'trosecko' -Settlement 'troskovice' `
            -Dialogue $silentDialogue -Binding $binding | Out-Null
    }
    catch {
        $missingMediaThrew =
            $_.Exception.Message -match 'must declare native voice'
    }
    Assert-True $missingMediaThrew `
        'Dark Passenger compiler rejects an implicitly silent dialogue'

    $assignment = Get-DpResolvedDialogueVoiceAssignment `
        -Registry $null -CaseSpec $caseSpec -Region 'trosecko' `
        -Settlement 'troskovice' -Dialogue $dialogue -Binding $binding `
        -MediaReferenceLengths $lengths
    $xml = ConvertTo-DpDialogueXml -Dialogue $dialogue `
        -Binding $binding -VoiceAssignment $assignment
    Assert-True (@($assignment.selectedSouls).Count -eq 0) `
        'generic media does not pin SelectedSouls'
    Assert-True ($xml -notmatch '<SelectedSouls>') `
        'generic dialogue leaves actor voice resolution to runtime'
    Assert-True ($xml -match 'ReferenceLength="5\.7"') `
        'shared NPC response uses maximum generated duration'
    Assert-True ($xml -match 'ReferenceLength="3\.1"') `
        'Henry response uses generated duration'

    $results.jobs = @($results.jobs | Where-Object jobId -ne 'henry')
    [System.IO.File]::WriteAllText(
        $resultsPath,
        ($results | ConvertTo-Json -Depth 20),
        [System.Text.UTF8Encoding]::new($false)
    )
    $threw = $false
    try {
        Read-DpDialogueMediaReferenceLengths `
            -JobsManifestPath $jobsPath -ResultsManifestPath $resultsPath | Out-Null
    }
    catch {
        $threw = $_.Exception.Message -match 'coverage'
    }
    Assert-True $threw 'stale media results fail exact job coverage'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Host "Dialogue media duration tests: $passed passed, $failed failed."
if ($failed -gt 0) { exit 1 }
