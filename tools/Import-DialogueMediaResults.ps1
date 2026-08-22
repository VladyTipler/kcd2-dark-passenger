param(
    [Parameter(Mandatory)][string]$JobsManifestPath,
    [Parameter(Mandatory)][string]$ResultsManifestPath,
    [Parameter(Mandatory)][string]$OutputModRoot
)

$ErrorActionPreference = 'Stop'

function Throw-DpDialogueMediaError {
    param([Parameter(Mandatory)][string]$Code, [Parameter(Mandatory)][string]$Message)

    throw "$Code`: $Message"
}

function Read-DpJsonFile {
    param([Parameter(Mandatory)][string]$LiteralPath, [string]$Code)

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        Throw-DpDialogueMediaError $Code "file not found: $LiteralPath"
    }
    try {
        return [System.IO.File]::ReadAllText($LiteralPath) |
            ConvertFrom-Json -Depth 100
    }
    catch {
        Throw-DpDialogueMediaError $Code $_.Exception.Message
    }
}

function Resolve-DpDialogueMediaPackage {
    param(
        [Parameter(Mandatory)]$Package,
        [Parameter(Mandatory)][string]$ResultsRoot,
        [Parameter(Mandatory)][string]$Kind
    )

    $pathValue = [string]$Package.path
    $expectedHash = ([string]$Package.sha256).ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($pathValue) -or
        $expectedHash -notmatch '^[0-9a-f]{64}$') {
        Throw-DpDialogueMediaError 'DIALOGUE_MEDIA_PACKAGE_INVALID' `
            "$Kind package path or SHA256 is invalid."
    }
    $path = if ([System.IO.Path]::IsPathRooted($pathValue)) {
        [System.IO.Path]::GetFullPath($pathValue)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $ResultsRoot $pathValue))
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Throw-DpDialogueMediaError 'DIALOGUE_MEDIA_PACKAGE_MISSING' `
            "$Kind package not found: $path"
    }
    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.
        ToLowerInvariant()
    if ($actualHash -cne $expectedHash) {
        Throw-DpDialogueMediaError 'DIALOGUE_MEDIA_PACKAGE_HASH_MISMATCH' `
            "$Kind package hash differs: $path"
    }
    return $path
}

function Get-DpPakEntryMap {
    param([Parameter(Mandatory)][string]$LiteralPath)

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($LiteralPath)
    try {
        $entries = @{}
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName.Replace('\', '/').ToLowerInvariant()
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                if ($entries.ContainsKey($name)) {
                    Throw-DpDialogueMediaError 'DIALOGUE_MEDIA_PACKAGE_DUPLICATE' `
                        "duplicate archive entry: $name"
                }
                $entries[$name] = $entry
            }
        }
        return [ordered]@{ archive = $archive; entries = $entries }
    }
    catch {
        $archive.Dispose()
        throw
    }
}

$resolvedJobsPath = [System.IO.Path]::GetFullPath($JobsManifestPath)
$resolvedResultsPath = [System.IO.Path]::GetFullPath($ResultsManifestPath)
$jobsManifest = Read-DpJsonFile $resolvedJobsPath 'DIALOGUE_MEDIA_JOBS_INVALID'
$resultsManifest = Read-DpJsonFile $resolvedResultsPath `
    'DIALOGUE_MEDIA_RESULTS_INVALID'

if ([int]$jobsManifest.schemaVersion -ne 1 -or
    [string]$jobsManifest.game -cne 'kcd2' -or
    [string]$jobsManifest.packageLanguage -cne 'english') {
    Throw-DpDialogueMediaError 'DIALOGUE_MEDIA_JOBS_INVALID' `
        'jobs manifest must be KCD2 schema 1 in English.'
}
if ([int]$resultsManifest.schemaVersion -ne 1 -or
    [string]$resultsManifest.status -cne 'complete') {
    Throw-DpDialogueMediaError 'DIALOGUE_MEDIA_INCOMPLETE' `
        'results manifest is not complete.'
}

$jobs = @($jobsManifest.jobs)
$resultJobs = @($resultsManifest.jobs)
if ($jobs.Count -eq 0) {
    Throw-DpDialogueMediaError 'DIALOGUE_MEDIA_JOBS_INVALID' `
        'jobs manifest contains no jobs.'
}
$duplicateJob = $jobs | Group-Object { [string]$_.jobId } |
    Where-Object { $_.Count -gt 1 } | Select-Object -First 1
$duplicateResult = $resultJobs | Group-Object { [string]$_.jobId } |
    Where-Object { $_.Count -gt 1 } | Select-Object -First 1
if ($null -ne $duplicateJob -or $null -ne $duplicateResult) {
    Throw-DpDialogueMediaError 'DIALOGUE_MEDIA_JOB_COVERAGE_MISMATCH' `
        'job identifiers must be unique.'
}

$jobIds = @($jobs | ForEach-Object { [string]$_.jobId } | Sort-Object)
$resultJobIds = @($resultJobs | ForEach-Object {
    [string]$_.jobId
} | Sort-Object)
if (($jobIds -join "`n") -cne ($resultJobIds -join "`n")) {
    Throw-DpDialogueMediaError 'DIALOGUE_MEDIA_JOB_COVERAGE_MISMATCH' `
        'results jobs do not exactly match current compiler jobs.'
}

$resultsById = @{}
foreach ($result in $resultJobs) {
    $resultsById[[string]$result.jobId] = $result
}
$expectedAudio = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
$expectedFacial = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
foreach ($job in $jobs) {
    $jobId = [string]$job.jobId
    $folder = ([string]$job.audioFolder).Replace('\', '/').Trim('/')
    $prefix = [string]$job.assetPrefix
    $stringName = [string]$job.stringName
    if ($folder -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or
        $prefix -notmatch '^[A-Za-z0-9_.-]+$' -or
        $stringName -notmatch '^[A-Za-z0-9_.-]+$') {
        Throw-DpDialogueMediaError 'DIALOGUE_MEDIA_JOBS_INVALID' `
            "unsafe media destination in job: $jobId"
    }
    $basename = "${prefix}_${stringName}"
    $audio = "dialog/$folder/$basename.ogg"
    $facial = "animations/humans/facials/dialog/$folder/$basename.caf"
    $result = $resultsById[$jobId]
    if ([string]$result.status -eq 'failed' -or
        [string]$result.audio -cne $audio -or
        [string]$result.facial -cne $facial) {
        Throw-DpDialogueMediaError 'DIALOGUE_MEDIA_JOB_RESULT_MISMATCH' `
            "result destinations differ for job: $jobId"
    }
    $null = $expectedAudio.Add($audio)
    $null = $expectedFacial.Add($facial)
}

$resultsRoot = Split-Path -Parent $resolvedResultsPath
$voicePak = Resolve-DpDialogueMediaPackage `
    -Package $resultsManifest.packages.voice `
    -ResultsRoot $resultsRoot `
    -Kind 'voice'
$facialPak = Resolve-DpDialogueMediaPackage `
    -Package $resultsManifest.packages.facial `
    -ResultsRoot $resultsRoot `
    -Kind 'facial'

$voiceArchive = Get-DpPakEntryMap $voicePak
try {
    foreach ($path in $expectedAudio) {
        if (-not $voiceArchive.entries.ContainsKey($path.ToLowerInvariant())) {
            Throw-DpDialogueMediaError 'DIALOGUE_MEDIA_PACKAGE_INCOMPLETE' `
                "voice package has no expected entry: $path"
        }
    }
}
finally {
    $voiceArchive.archive.Dispose()
}

$facialArchive = Get-DpPakEntryMap $facialPak
try {
    $imageName = 'animations/facialanimations.img'
    if (-not $facialArchive.entries.ContainsKey($imageName)) {
        Throw-DpDialogueMediaError 'DIALOGUE_MEDIA_PACKAGE_INCOMPLETE' `
            'facial package has no FacialAnimations.img.'
    }
    $dbaCount = @($facialArchive.entries.Keys | Where-Object {
        $_.EndsWith('.dba', [System.StringComparison]::OrdinalIgnoreCase)
    }).Count
    if ($dbaCount -eq 0) {
        Throw-DpDialogueMediaError 'DIALOGUE_MEDIA_PACKAGE_INCOMPLETE' `
            'facial package has no DBA.'
    }
    $imageEntry = $facialArchive.entries[$imageName]
    $stream = $imageEntry.Open()
    try {
        $memory = [System.IO.MemoryStream]::new()
        $stream.CopyTo($memory)
        $imageText = [System.Text.Encoding]::ASCII.GetString($memory.ToArray())
    }
    finally {
        if ($null -ne $memory) { $memory.Dispose() }
        $stream.Dispose()
    }
    foreach ($path in $expectedFacial) {
        if ($imageText.IndexOf(
            $path,
            [System.StringComparison]::OrdinalIgnoreCase
        ) -lt 0) {
            Throw-DpDialogueMediaError 'DIALOGUE_MEDIA_PACKAGE_INCOMPLETE' `
                "facial image has no expected entry: $path"
        }
    }
}
finally {
    $facialArchive.archive.Dispose()
}

$resolvedOutput = [System.IO.Path]::GetFullPath($OutputModRoot)
$voiceDestination = Join-Path $resolvedOutput 'Localization\english.pak'
$facialDestination = Join-Path $resolvedOutput `
    'Data\darkpassenger_facials_english.pak'
New-Item -ItemType Directory -Path (Split-Path -Parent $voiceDestination) `
    -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $facialDestination) `
    -Force | Out-Null
Copy-Item -LiteralPath $voicePak -Destination $voiceDestination -Force
Copy-Item -LiteralPath $facialPak -Destination $facialDestination -Force

Write-Host "Imported $($jobs.Count) verified dialogue media jobs."
