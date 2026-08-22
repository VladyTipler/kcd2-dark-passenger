[CmdletBinding(DefaultParameterSetName = 'Directory')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Directory')]
    [string]$InputDirectory,

    [Parameter(Mandatory, ParameterSetName = 'Pak')]
    [string]$TablesPakPath,

    [string[]]$AdditionalInputDirectory = @(),

    [string]$OutputPath = (
        Join-Path (
            Split-Path -Parent $PSScriptRoot
        ) 'src\Data\Scripts\mods\generated\dp_quest_item_catalog.lua'
    )
)

$ErrorActionPreference = 'Stop'
$temporaryRoot = $null

function Resolve-SevenZip {
    $command = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    foreach ($candidate in @(
        'C:\Program Files\7-Zip\7z.exe',
        'C:\Program Files (x86)\7-Zip\7z.exe'
    )) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    throw '7-Zip was not found.'
}

try {
    $sourceDirectory = $InputDirectory
    if ($PSCmdlet.ParameterSetName -eq 'Pak') {
        if (-not (Test-Path -LiteralPath $TablesPakPath -PathType Leaf)) {
            throw "Tables pak not found: $TablesPakPath"
        }

        $temporaryRoot = Join-Path (
            [System.IO.Path]::GetTempPath()
        ) ('dp-quest-items-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $temporaryRoot -Force |
            Out-Null

        $sevenZip = Resolve-SevenZip
        & $sevenZip x $TablesPakPath `
            "-o$temporaryRoot" `
            'Libs\Tables\item\item*.xml' `
            -r -y | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "7-Zip extraction failed with exit code $LASTEXITCODE."
        }
        $sourceDirectory = Join-Path $temporaryRoot 'Libs\Tables\item'
    }

    $sourceDirectories = @($sourceDirectory) + @($AdditionalInputDirectory)
    foreach ($directory in $sourceDirectories) {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            throw "Item table directory not found: $directory"
        }
    }

    $questItemIds = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $guidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

    $itemFiles = @(
        $sourceDirectories | ForEach-Object {
            Get-ChildItem -LiteralPath $_ `
                -Filter 'item*.xml' -File -Recurse
        } | Sort-Object FullName -Unique
    )
    if ($itemFiles.Count -eq 0) {
        throw "No item*.xml files found in configured directories."
    }

    foreach ($itemFile in $itemFiles) {
        [xml]$document = Get-Content -Raw -LiteralPath $itemFile.FullName
        foreach ($node in $document.SelectNodes('//*[@IsQuestItem="true"]')) {
            $id = [string]$node.Id
            if ($id -notmatch $guidPattern) {
                throw "Invalid quest-item GUID '$id' in $($itemFile.FullName)"
            }
            $null = $questItemIds.Add($id.ToLowerInvariant())
        }
    }

    $sortedIds = @($questItemIds) | Sort-Object
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add(
        '-- Generated from authoritative KCD2 item tables. Do not edit.'
    )
    $lines.Add('DarkPassengerQuestItemCatalog = {')
    foreach ($id in $sortedIds) {
        $lines.Add("    [`"$id`"] = true,")
    }
    $lines.Add('}')
    $lines.Add('')

    $outputDirectory = Split-Path -Parent $OutputPath
    New-Item -ItemType Directory -Path $outputDirectory -Force |
        Out-Null
    [System.IO.File]::WriteAllText(
        $OutputPath,
        [string]::Join("`n", $lines),
        [System.Text.UTF8Encoding]::new($false)
    )

    Write-Host (
        "Generated {0} quest-item GUIDs: {1}" -f
        $sortedIds.Count,
        $OutputPath
    )
}
finally {
    if ($null -ne $temporaryRoot) {
        $resolved = [System.IO.Path]::GetFullPath($temporaryRoot)
        $tempPrefix = [System.IO.Path]::GetFullPath(
            [System.IO.Path]::GetTempPath()
        )
        if (
            $resolved.StartsWith(
                $tempPrefix,
                [System.StringComparison]::OrdinalIgnoreCase
            ) -and
            (Test-Path -LiteralPath $resolved)
        ) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}
