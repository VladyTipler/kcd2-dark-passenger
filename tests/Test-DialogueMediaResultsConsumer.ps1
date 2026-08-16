$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$consumer = Join-Path $repoRoot 'tools\Import-DialogueMediaResults.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    "dark-passenger-media-results-$([guid]::NewGuid().ToString('N'))"
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

function Write-JsonFile {
    param([string]$LiteralPath, $Value)

    New-Item -ItemType Directory -Path (Split-Path -Parent $LiteralPath) `
        -Force | Out-Null
    [System.IO.File]::WriteAllText(
        $LiteralPath,
        ($Value | ConvertTo-Json -Depth 100) + "`n",
        [System.Text.UTF8Encoding]::new($false)
    )
}

function New-TestPak {
    param([string]$LiteralPath, [hashtable]$Entries)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $sourceRoot = Join-Path $tempRoot `
        "pak-source-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $sourceRoot -Force | Out-Null
    foreach ($entry in $Entries.GetEnumerator()) {
        $path = Join-Path $sourceRoot ([string]$entry.Key).Replace('/', '\')
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) `
            -Force | Out-Null
        [System.IO.File]::WriteAllBytes(
            $path,
            [System.Text.Encoding]::ASCII.GetBytes([string]$entry.Value)
        )
    }
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $sourceRoot,
        $LiteralPath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false
    )
}

function Invoke-ExpectedFailure {
    param(
        [string]$ExpectedCode,
        [string]$JobsPath,
        [string]$ResultsPath,
        [string]$StageRoot
    )

    try {
        & $consumer `
            -JobsManifestPath $JobsPath `
            -ResultsManifestPath $ResultsPath `
            -OutputModRoot $StageRoot
        return $false
    }
    catch {
        return $_.Exception.Message.Contains(
            $ExpectedCode,
            [System.StringComparison]::Ordinal
        )
    }
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    Add-Result (Test-Path -LiteralPath $consumer -PathType Leaf) `
        'Dialogue media results consumer exists'
    if (-not (Test-Path -LiteralPath $consumer -PathType Leaf)) {
        throw 'Dialogue media results consumer is missing.'
    }
    $buildMod = [System.IO.File]::ReadAllText((Join-Path $repoRoot `
        'tools\Build-Mod.ps1'))
    Add-Result (
        $buildMod.Contains('Import-DialogueMediaResults.ps1') -and
        $buildMod.Contains('DIALOGUE_MEDIA_RESULTS_MISSING')
    ) 'clean mod build consumes complete media results and fails closed'

    $jobId = 'missing_traveler.troskovice.dp_line.aals'
    $audioPath = 'dialog/trosecko/dark_within_t/aals_dp_line.ogg'
    $facialPath = `
        'animations/humans/facials/dialog/trosecko/dark_within_t/' +
        'aals_dp_line.caf'
    $jobsPath = Join-Path $tempRoot 'dialogue-media-jobs.json'
    Write-JsonFile $jobsPath ([ordered]@{
        schemaVersion = 1
        game = 'kcd2'
        packageLanguage = 'english'
        jobs = @([ordered]@{
            jobId = $jobId
            storyId = 'missing_traveler'
            dialogueGraph = 'dp_dialog'
            stringName = 'dp_line'
            text = 'He left before dawn.'
            voiceProfile = 'beta-en'
            assetPrefix = 'aals'
            rig = 'human_female'
            audioFolder = 'trosecko/dark_within_t'
            media = [ordered]@{ voice = 'native'; lipSync = $true }
        })
    })

    $voicePak = Join-Path $tempRoot 'voice.pak'
    $facialPak = Join-Path $tempRoot 'facial.pak'
    New-TestPak $voicePak @{ $audioPath = 'OggS-test' }
    New-TestPak $facialPak @{
        'Animations/FacialAnimations.img' = "vanilla`0$facialPath`0"
        'Animations/humans/facials/dialog/trosecko/dialogue_media_kit/test.dba' = 'dba'
    }
    $resultsPath = Join-Path $tempRoot 'dialogue-media-results.json'
    $results = [ordered]@{
        schemaVersion = 1
        status = 'complete'
        jobs = @([ordered]@{
            jobId = $jobId
            status = 'generated'
            audio = $audioPath
            facial = $facialPath
            durationSeconds = 3.2
        })
        packages = [ordered]@{
            voice = [ordered]@{
                path = $voicePak
                sha256 = (Get-FileHash $voicePak -Algorithm SHA256).Hash.ToLowerInvariant()
            }
            facial = [ordered]@{
                path = $facialPak
                sha256 = (Get-FileHash $facialPak -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
        diagnostics = @()
    }
    Write-JsonFile $resultsPath $results

    $stageRoot = Join-Path $tempRoot 'stage'
    & $consumer `
        -JobsManifestPath $jobsPath `
        -ResultsManifestPath $resultsPath `
        -OutputModRoot $stageRoot
    Add-Result (
        Test-Path -LiteralPath (Join-Path $stageRoot `
            'Localization\english.pak') -PathType Leaf
    ) 'complete results stage the verified voice PAK'
    Add-Result (
        Test-Path -LiteralPath (Join-Path $stageRoot `
            'Data\darkpassenger_facials_english.pak') -PathType Leaf
    ) 'complete results stage the verified facial PAK'

    $results.status = 'failed'
    Write-JsonFile $resultsPath $results
    Add-Result (Invoke-ExpectedFailure `
        -ExpectedCode 'DIALOGUE_MEDIA_INCOMPLETE' `
        -JobsPath $jobsPath `
        -ResultsPath $resultsPath `
        -StageRoot (Join-Path $tempRoot 'failed-stage')) `
        'incomplete results fail closed'

    $results.status = 'complete'
    $results.packages.voice.sha256 = ('0' * 64)
    Write-JsonFile $resultsPath $results
    Add-Result (Invoke-ExpectedFailure `
        -ExpectedCode 'DIALOGUE_MEDIA_PACKAGE_HASH_MISMATCH' `
        -JobsPath $jobsPath `
        -ResultsPath $resultsPath `
        -StageRoot (Join-Path $tempRoot 'hash-stage')) `
        'package hash mismatch fails closed'

    $results.packages.voice.sha256 = (
        Get-FileHash $voicePak -Algorithm SHA256
    ).Hash.ToLowerInvariant()
    $results.jobs = @()
    Write-JsonFile $resultsPath $results
    Add-Result (Invoke-ExpectedFailure `
        -ExpectedCode 'DIALOGUE_MEDIA_JOB_COVERAGE_MISMATCH' `
        -JobsPath $jobsPath `
        -ResultsPath $resultsPath `
        -StageRoot (Join-Path $tempRoot 'coverage-stage')) `
        'stale job coverage fails closed'

    $pilotVoiceManifestPath = Join-Path $repoRoot `
        'build\generated\voice\dialogue-voice-manifest.json'
    $pilotVoicePak = Join-Path $repoRoot `
        'build\mod\Localization\english.pak'
    $pilotFacialPak = Join-Path (Split-Path -Parent $repoRoot) `
        '_work\custom-facial-16-2026-08-16\darkpassenger_facials_english_16.pak'
    $pilotAvailable =
        (Test-Path -LiteralPath $pilotVoiceManifestPath -PathType Leaf) -and
        (Test-Path -LiteralPath $pilotVoicePak -PathType Leaf) -and
        (Test-Path -LiteralPath $pilotFacialPak -PathType Leaf)
    Add-Result $pilotAvailable 'verified 16-line pilot packages are available'
    if ($pilotAvailable) {
        $pilotVoiceManifest = [System.IO.File]::ReadAllText(
            $pilotVoiceManifestPath
        ) | ConvertFrom-Json -Depth 100
        $pilotJobs = @($pilotVoiceManifest.assets | ForEach-Object {
            $fileName = [System.IO.Path]::GetFileNameWithoutExtension(
                ([string]$_.destination).Replace('/', '\')
            )
            $prefix = $fileName.Substring(0, $fileName.IndexOf('_'))
            [ordered]@{
                jobId = @(
                    [string]$_.storyId,
                    [string]$_.settlement,
                    [string]$_.stringName,
                    $prefix
                ) -join '.'
                storyId = [string]$_.storyId
                dialogueGraph = [string]$_.dialogueGraph
                stringName = [string]$_.stringName
                text = [string]$_.stringName
                voiceProfile = [string]$_.voiceProfile
                assetPrefix = $prefix
                rig = if ($prefix -ceq 'tmck') {
                    'human_male'
                } else { 'human_female' }
                audioFolder = [string]$_.audioFolder
                media = [ordered]@{ voice = 'native'; lipSync = $true }
            }
        })
        $pilotJobsPath = Join-Path $tempRoot 'pilot-jobs.json'
        Write-JsonFile $pilotJobsPath ([ordered]@{
            schemaVersion = 1
            game = 'kcd2'
            packageLanguage = 'english'
            jobs = $pilotJobs
        })
        $pilotResultsPath = Join-Path $tempRoot 'pilot-results.json'
        Write-JsonFile $pilotResultsPath ([ordered]@{
            schemaVersion = 1
            status = 'complete'
            jobs = @($pilotJobs | ForEach-Object {
                $basename = "$($_.assetPrefix)_$($_.stringName)"
                [ordered]@{
                    jobId = [string]$_.jobId
                    status = 'cached'
                    audio = "dialog/$($_.audioFolder)/$basename.ogg"
                    facial = (
                        'animations/humans/facials/dialog/' +
                        "$($_.audioFolder)/$basename.caf"
                    )
                    durationSeconds = 1
                }
            })
            packages = [ordered]@{
                voice = [ordered]@{
                    path = $pilotVoicePak
                    sha256 = (Get-FileHash $pilotVoicePak `
                        -Algorithm SHA256).Hash.ToLowerInvariant()
                }
                facial = [ordered]@{
                    path = $pilotFacialPak
                    sha256 = (Get-FileHash $pilotFacialPak `
                        -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            }
            diagnostics = @()
        })
        $pilotStage = Join-Path $tempRoot 'pilot-stage'
        & $consumer `
            -JobsManifestPath $pilotJobsPath `
            -ResultsManifestPath $pilotResultsPath `
            -OutputModRoot $pilotStage
        Add-Result (
            (Get-FileHash (Join-Path $pilotStage `
                'Localization\english.pak') -Algorithm SHA256).Hash -eq
            (Get-FileHash $pilotVoicePak -Algorithm SHA256).Hash -and
            (Get-FileHash (Join-Path $pilotStage `
                'Data\darkpassenger_facials_english.pak') `
                -Algorithm SHA256).Hash -eq
            (Get-FileHash $pilotFacialPak -Algorithm SHA256).Hash
        ) 'real 16-line voice and facial PAKs cross the consumer boundary'
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

if ($script:failures.Count -gt 0) {
    throw "Dialogue media results consumer failed $($script:failures.Count) " +
        "of $($script:checks) checks: $($script:failures -join '; ')"
}

Write-Host "All $($script:checks) dialogue media results checks passed."
