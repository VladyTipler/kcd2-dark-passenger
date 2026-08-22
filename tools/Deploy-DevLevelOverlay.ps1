[CmdletBinding()]
param(
    [string]$BuildRoot = (
        Join-Path (Split-Path -Parent $PSScriptRoot) 'build\mod'
    ),
    [string]$DevGameRoot = $env:KCD2_DEV_ROOT,
    [string]$BackupRoot = (
        Join-Path (
            Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        ) '_deployment-backups\DarkPassenger'
    ),
    [string]$GameProcessName = 'KingdomCome'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($DevGameRoot)) {
    throw 'KCD2_DEV_ROOT or -DevGameRoot is required.'
}

$resolvedBuildRoot = [System.IO.Path]::GetFullPath($BuildRoot)
$resolvedDevRoot = [System.IO.Path]::GetFullPath($DevGameRoot)
$resolvedBackupRoot = [System.IO.Path]::GetFullPath($BackupRoot)
$devPrefix = $resolvedDevRoot + [System.IO.Path]::DirectorySeparatorChar
$backupPrefix =
    $resolvedBackupRoot + [System.IO.Path]::DirectorySeparatorChar
$fileNames = @('objects_mission0.xml', 'waitinglinks.xml')
$regionSpecifications = @(
    [pscustomobject]@{
        region = 'kutnohorsko'
        levelHolderGuid = '10702dff-9271-4a74'
        questHolderName = 'dark_within_k'
        questHolderGuid = 'f4a73e20-28c5-4bd2'
        questHolderEntityId = '1831841'
    }
    [pscustomobject]@{
        region = 'trosecko'
        levelHolderGuid = '30277b74-1c65-41e9'
        questHolderName = 'dark_within_t'
        questHolderGuid = 'a13d9e5c-7b42-4f61'
        questHolderEntityId = '1831842'
    }
)

function Assert-PathWithin {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][string]$RequiredPrefix,
        [Parameter(Mandatory)][string]$Label
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($LiteralPath)
    if (-not $resolvedPath.StartsWith(
        $RequiredPrefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to use $Label outside its root: $resolvedPath"
    }
    return $resolvedPath
}

function Get-LinkSignaturesFromMissionObjects {
    param(
        [Parameter(Mandatory)][xml]$Document,
        [Parameter(Mandatory)]$Specification
    )

    $entities = @($Document.Objects.Entity)
    $levelHolders = @($entities | Where-Object {
        [string]$_.EntityGuid -eq $Specification.levelHolderGuid -and
        [string]$_.EntityClass -eq 'LevelHolder'
    })
    $questHolders = @($entities | Where-Object {
        [string]$_.EntityGuid -eq $Specification.questHolderGuid -and
        [string]$_.EntityClass -eq 'SmartObjectHolder' -and
        [string]$_.EntityId -eq $Specification.questHolderEntityId -and
        [string]$_.Name -eq $Specification.questHolderName
    })
    if ($levelHolders.Count -ne 1 -or $questHolders.Count -ne 1) {
        throw "Generated $($Specification.region) mission objects lack unique regional holders."
    }
    $moduleLinks = @($levelHolders[0].EntityLinks.Link | Where-Object {
        [string]$_.Name -eq 'module' -and
        [string]$_.TargetId -eq $Specification.questHolderEntityId
    })
    if ($moduleLinks.Count -ne 1) {
        throw "Generated $($Specification.region) mission objects lack the regional module link."
    }

    $entityGuidsById = @{}
    foreach ($entity in $entities) {
        $entityId = [string]$entity.EntityId
        if (-not [string]::IsNullOrWhiteSpace($entityId)) {
            $entityGuidsById[$entityId] = [string]$entity.EntityGuid
        }
    }
    $signatures = @(
        $questHolders[0].EntityLinks.Link |
            Where-Object {
                [string]$_.Name -match "^asset\['DP_SearchArea_[A-Za-z0-9_]+'\]$"
            } |
            ForEach-Object {
                $targetId = [string]$_.TargetId
                if (-not $entityGuidsById.ContainsKey($targetId)) {
                    throw "Generated $($Specification.region) mission link target '$targetId' is unresolved."
                }
                '{0}|{1}' -f $entityGuidsById[$targetId], [string]$_.Name
            } |
            Sort-Object
    )
    if ($signatures.Count -eq 0) {
        throw "Generated $($Specification.region) mission objects contain no settlement area links."
    }
    return $signatures
}

function Get-LinkSignaturesFromWaitingLinks {
    param(
        [Parameter(Mandatory)][xml]$Document,
        [Parameter(Mandatory)]$Specification
    )

    if (
        [string]$Document.StaticLinksInfo.version -ne '1' -or
        $null -eq $Document.StaticLinksInfo.WaitingLinks
    ) {
        throw "Generated $($Specification.region) waitinglinks lack StaticLinksInfo version 1."
    }
    $links = @($Document.StaticLinksInfo.WaitingLinks.WaitingLink)
    $moduleLinks = @($links | Where-Object {
        [string]$_.SourceId -eq $Specification.levelHolderGuid -and
        [string]$_.TargetId -eq $Specification.questHolderGuid -and
        [string]$_.LinkDefinition -eq 'module'
    })
    if ($moduleLinks.Count -ne 1) {
        throw "Generated $($Specification.region) waitinglinks lack the regional module link."
    }
    $signatures = @(
        $links |
            Where-Object {
                [string]$_.SourceId -eq $Specification.questHolderGuid -and
                [string]$_.LinkDefinition -match
                    "^asset\['DP_SearchArea_[A-Za-z0-9_]+'\]$"
            } |
            ForEach-Object {
                '{0}|{1}' -f [string]$_.TargetId, [string]$_.LinkDefinition
            } |
            Sort-Object
    )
    if ($signatures.Count -eq 0) {
        throw "Generated $($Specification.region) waitinglinks contain no settlement area links."
    }
    return $signatures
}

if (Get-Process -Name $GameProcessName -ErrorAction SilentlyContinue) {
    throw "Close $GameProcessName before deploying the dev level overlay."
}
$userCfg = Join-Path $resolvedDevRoot 'user.cfg'
$userCfgText = if (Test-Path -LiteralPath $userCfg -PathType Leaf) {
    [System.IO.File]::ReadAllText($userCfg)
}
else {
    ''
}
if ($userCfgText -notmatch '(?m)^\s*sys_PakPriority\s*=\s*0\s*$') {
    throw 'Dev loose overlay requires sys_PakPriority = 0.'
}

$deployments = [System.Collections.Generic.List[object]]::new()
foreach ($specification in $regionSpecifications) {
    $sourceLevelRoot =
        Join-Path $resolvedBuildRoot "Data\Levels\$($specification.region)"
    $targetLevelRoot =
        Join-Path $resolvedDevRoot "Data\Levels\$($specification.region)"
    [void](Assert-PathWithin `
        -LiteralPath $targetLevelRoot `
        -RequiredPrefix $devPrefix `
        -Label "$($specification.region) level root")
    $sourceObjects = Join-Path $sourceLevelRoot 'objects_mission0.xml'
    $sourceWaitingLinks = Join-Path $sourceLevelRoot 'waitinglinks.xml'
    foreach ($sourcePath in @($sourceObjects, $sourceWaitingLinks)) {
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Generated regional overlay not found: $sourcePath"
        }
    }

    try {
        $missionDocument = [xml][System.IO.File]::ReadAllText($sourceObjects)
        $waitingDocument = [xml][System.IO.File]::ReadAllText($sourceWaitingLinks)
    }
    catch {
        throw "Generated $($specification.region) overlay is invalid XML: $($_.Exception.Message)"
    }
    $missionSignatures = @(
        Get-LinkSignaturesFromMissionObjects `
            -Document $missionDocument `
            -Specification $specification
    )
    $waitingSignatures = @(
        Get-LinkSignaturesFromWaitingLinks `
            -Document $waitingDocument `
            -Specification $specification
    )
    if (@(Compare-Object $missionSignatures $waitingSignatures).Count -ne 0) {
        throw "Generated $($specification.region) mission and waiting area links differ."
    }

    $deployments.Add([pscustomobject]@{
        specification = $specification
        sourceLevelRoot = $sourceLevelRoot
        targetLevelRoot = $targetLevelRoot
        sourceObjects = $sourceObjects
        sourceWaitingLinks = $sourceWaitingLinks
        targetObjects = Join-Path $targetLevelRoot 'objects_mission0.xml'
        targetWaitingLinks = Join-Path $targetLevelRoot 'waitinglinks.xml'
    })
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$backupDir = Join-Path $resolvedBackupRoot "dev-level-$stamp"
[void](Assert-PathWithin `
    -LiteralPath $backupDir `
    -RequiredPrefix $backupPrefix `
    -Label 'deployment backup')
$stageRoot = Join-Path $backupDir '_staged'
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null

foreach ($deployment in $deployments) {
    $region = $deployment.specification.region
    $stageRegion = Join-Path $stageRoot $region
    New-Item -ItemType Directory -Path $stageRegion -Force | Out-Null
    foreach ($fileName in $fileNames) {
        $sourcePath = Join-Path $deployment.sourceLevelRoot $fileName
        $stagePath = Join-Path $stageRegion $fileName
        Copy-Item -LiteralPath $sourcePath -Destination $stagePath
        if (
            (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $stagePath -Algorithm SHA256).Hash
        ) {
            throw "Staged $region/$fileName hash mismatch."
        }
    }
}

$obsoleteRelativePaths = @(
    'Layers\darkpassenger_investigation_areas_1b986e82-f241-016c-c428-a298fa47119a.xml',
    'Layers\main\_quest\activity\darkpassenger_investigation_areas.lyr'
)
$transactionRecords = [System.Collections.Generic.List[object]]::new()
foreach ($deployment in $deployments) {
    $region = $deployment.specification.region
    $backupRegion = Join-Path $backupDir $region
    foreach ($fileName in $fileNames) {
        $transactionRecords.Add([pscustomobject]@{
            region = $region
            targetLevelRoot = $deployment.targetLevelRoot
            targetPath = Join-Path $deployment.targetLevelRoot $fileName
            backupPath = Join-Path $backupRegion $fileName
            stagePath = Join-Path $stageRoot "$region\$fileName"
            oldBackedUp = $false
            newDeployed = $false
        })
    }
}
$kuttenbergDeployment = @($deployments | Where-Object {
    $_.specification.region -eq 'kutnohorsko'
})[0]
$obsoleteRecords = [System.Collections.Generic.List[object]]::new()
foreach ($relativePath in $obsoleteRelativePaths) {
    $obsoleteRecords.Add([pscustomobject]@{
        targetPath = Join-Path $kuttenbergDeployment.targetLevelRoot $relativePath
        backupPath = Join-Path $backupDir "kutnohorsko\obsolete\$relativePath"
        moved = $false
    })
}
$completed = $false
try {
    foreach ($record in $transactionRecords) {
        New-Item -ItemType Directory -Path (
            Split-Path -Parent $record.backupPath
        ), $record.targetLevelRoot -Force |
            Out-Null
        if (Test-Path -LiteralPath $record.targetPath -PathType Leaf) {
            Move-Item `
                -LiteralPath $record.targetPath `
                -Destination $record.backupPath
            $record.oldBackedUp = $true
        }
        Move-Item `
            -LiteralPath $record.stagePath `
            -Destination $record.targetPath
        $record.newDeployed = $true
    }

    foreach ($obsoleteRecord in $obsoleteRecords) {
        [void](Assert-PathWithin `
            -LiteralPath $obsoleteRecord.targetPath `
            -RequiredPrefix $devPrefix `
            -Label 'obsolete Pritoky layer')
        if (Test-Path -LiteralPath $obsoleteRecord.targetPath -PathType Leaf) {
            [void](Assert-PathWithin `
                -LiteralPath $obsoleteRecord.backupPath `
                -RequiredPrefix $backupPrefix `
                -Label 'obsolete Pritoky layer backup')
            New-Item -ItemType Directory -Path (
                Split-Path -Parent $obsoleteRecord.backupPath
            ) -Force | Out-Null
            Move-Item `
                -LiteralPath $obsoleteRecord.targetPath `
                -Destination $obsoleteRecord.backupPath
            $obsoleteRecord.moved = $true
        }
    }

    foreach ($deployment in $deployments) {
        foreach ($fileName in $fileNames) {
            $sourcePath = Join-Path $deployment.sourceLevelRoot $fileName
            $targetPath = Join-Path $deployment.targetLevelRoot $fileName
            if (
                (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ne
                (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash
            ) {
                throw "Deployed $($deployment.specification.region)/$fileName hash mismatch."
            }
        }
    }
    $completed = $true
}
finally {
    if (-not $completed) {
        for ($index = $transactionRecords.Count - 1; $index -ge 0; $index--) {
            $record = $transactionRecords[$index]
            if (
                $record.newDeployed -and
                (Test-Path -LiteralPath $record.targetPath -PathType Leaf)
            ) {
                Remove-Item -LiteralPath $record.targetPath -Force
            }
            if (
                $record.oldBackedUp -and
                (Test-Path -LiteralPath $record.backupPath -PathType Leaf)
            ) {
                Move-Item `
                    -LiteralPath $record.backupPath `
                    -Destination $record.targetPath
            }
        }
        for ($index = $obsoleteRecords.Count - 1; $index -ge 0; $index--) {
            $obsoleteRecord = $obsoleteRecords[$index]
            if (
                $obsoleteRecord.moved -and
                (Test-Path -LiteralPath $obsoleteRecord.backupPath -PathType Leaf)
            ) {
                New-Item -ItemType Directory -Path (
                    Split-Path -Parent $obsoleteRecord.targetPath
                ) -Force | Out-Null
                Move-Item `
                    -LiteralPath $obsoleteRecord.backupPath `
                    -Destination $obsoleteRecord.targetPath
            }
        }
    }
}

if (Test-Path -LiteralPath $stageRoot) {
    $resolvedStageRoot = [System.IO.Path]::GetFullPath($stageRoot)
    if (-not $resolvedStageRoot.StartsWith(
        $backupPrefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to remove staging outside backup root: $resolvedStageRoot"
    }
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}

foreach ($deployment in $deployments) {
    $region = $deployment.specification.region
    $objectsHash = (
        Get-FileHash -LiteralPath $deployment.targetObjects -Algorithm SHA256
    ).Hash
    $waitingLinksHash = (
        Get-FileHash -LiteralPath $deployment.targetWaitingLinks -Algorithm SHA256
    ).Hash
    Write-Host (
        "Dev level overlay deployed: $region " +
        "objects=$objectsHash waitinglinks=$waitingLinksHash"
    )
}
Write-Host "Backup: $backupDir"
