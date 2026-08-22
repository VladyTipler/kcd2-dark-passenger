param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$generatorPath = Join-Path $repoRoot 'tools\Generate-VictimArtifacts.ps1'
$areaBindingGeneratorPath = Join-Path $repoRoot `
    'tools\Generate-SettlementAreaBindings.ps1'
$buildScriptPath = Join-Path $repoRoot 'tools\Build-Mod.ps1'
$areaManifestPath = Join-Path $repoRoot `
    'config\settlement-investigation-areas.json'
$areaInventoryPath = Join-Path $repoRoot `
    'build\generated\vanilla-trigger-areas.json'
$templatePath = Join-Path $repoRoot `
    'src\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml.template'
$dialogPath = Join-Path $repoRoot `
    'src\Data\Quests\darkpassengertest\pose_probe_male.xml'
$runtimePath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dpposeprobe.lua'
$buffPath = Join-Path $repoRoot `
    'src\Data\Libs\Tables\rpg\buff__darkpassengertest.xml'
$buffTagPath = Join-Path $repoRoot `
    'src\Data\Libs\Tables\rpg\buff_ai_tag__darkpassengertest.xml'
$rolePath = Join-Path $repoRoot `
    'src\Data\Libs\Tables\rpg\role__darkpassengertest.xml'
$smartEntityPath = Join-Path $repoRoot `
    'src\Data\Libs\Tables\ai\smartEntity\SmartEntity__darkpassengertest.xml'
$schedulerBehaviorPath = Join-Path $repoRoot `
    'src\Data\AI\player\scheduler\darkPassengerConfession.xml'
$stormRolePath = Join-Path $repoRoot `
    'src\Data\Libs\Storm\roles\quests\darkpassengertest.xml'
$englishLocalizationPath = Join-Path $repoRoot `
    'localization\English\text__darkpassengertest.xml'
$russianLocalizationPath = Join-Path $repoRoot `
    'localization\Russian\text__darkpassengertest.xml'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'dark-passenger-confession-probe-' + [guid]::NewGuid().ToString('N')
)
$kuttenbergOutput = Join-Path $tempRoot `
    'Data\Quests\Final\Barbora\kutnohorsko\dark_within_k.xml'
$troskyOutput = Join-Path $tempRoot `
    'Data\Quests\Final\Barbora\trosecko\dark_within_t.xml'
$luaOutput = Join-Path $tempRoot `
    'Data\Scripts\mods\generated\dp_candidate_catalog.lua'

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

try {
    $compiledDialogSourceRoot = Join-Path $repoRoot `
        'build\mod\Data\Quests\darkpassengertest'
    $testDialogSourceRoot = Join-Path $tempRoot `
        'Data\Quests\darkpassengertest'
    New-Item -ItemType Directory -Path $testDialogSourceRoot -Force |
        Out-Null
    foreach ($region in @('kutnohorsko', 'trosecko')) {
        Copy-Item `
            -LiteralPath (Join-Path $compiledDialogSourceRoot $region) `
            -Destination $testDialogSourceRoot `
            -Recurse
    }

    & $generatorPath `
        -TemplatePath $templatePath `
        -KuttenbergQuestOutputPath $kuttenbergOutput `
        -TroskyQuestOutputPath $troskyOutput `
        -LuaOutputPath $luaOutput

    $levelOutputRoot = Join-Path $tempRoot 'Data\Levels'
    & $areaBindingGeneratorPath `
        -ManifestPath $areaManifestPath `
        -AreaInventoryPath $areaInventoryPath `
        -OutputRoot $levelOutputRoot `
        -LuaOutputPath (Join-Path $tempRoot `
            'Data\Scripts\mods\generated\dp_investigation_area_catalog.lua')

    $kuttenberg = Get-Content -Raw -LiteralPath $kuttenbergOutput
    $trosky = Get-Content -Raw -LiteralPath $troskyOutput
    $dialog = Get-Content -Raw -LiteralPath $dialogPath
    $runtime = Get-Content -Raw -LiteralPath $runtimePath
    $buildScript = Get-Content -Raw -LiteralPath $buildScriptPath
    $buffs = [xml](Get-Content -Raw -LiteralPath $buffPath)
    $buffTags = [xml](Get-Content -Raw -LiteralPath $buffTagPath)
    $roleTable = Get-Content -Raw -LiteralPath $rolePath
    $stormRoles = Get-Content -Raw -LiteralPath $stormRolePath
    $englishLocalization = Get-Content -Raw `
        -LiteralPath $englishLocalizationPath
    $russianLocalization = Get-Content -Raw `
        -LiteralPath $russianLocalizationPath
    $smartEntities = Get-Content -Raw -LiteralPath $smartEntityPath
    $schedulerBehavior = if (Test-Path -LiteralPath $schedulerBehaviorPath) {
        Get-Content -Raw -LiteralPath $schedulerBehaviorPath
    } else {
        ''
    }
    $troskyObjects = Get-Content -Raw -LiteralPath (Join-Path `
        $levelOutputRoot 'trosecko\objects_mission0.patch.xml')
    $troskyWaitingLinks = Get-Content -Raw -LiteralPath (Join-Path `
        $levelOutputRoot 'trosecko\waitinglinks.xml')

    Add-Result (
        $trosky.Contains(
            '<Definition File="dark_within_t/pose_probe_male.xml" />'
        ) -and
        (Test-Path -LiteralPath (
            Join-Path (Split-Path -Parent $troskyOutput) `
                'dark_within_t\pose_probe_male.xml'
        ))
    ) 'generated Trosky quest registers and copies the confession dialog'

    foreach ($token in @(
        '<BuffTagTrigger Name="confessionProbeTrigger">',
        '<State Name="confessionProbeActive" TypeT="bool">',
        '<Function Name="confessionProbeDialogParams" MethodName="wh::dialogmodule::CreateDialogParams" DeclaringType="wh::dialogmodule">',
        '<Asset Name="Participants" Alias="poseProbeLavrentiy" />',
        '<Constant Name="EnableEnding" Value="true" />',
        '<Constant Name="MovePlayer" Value="true" />',
        '<Constant Name="RotateParticipants" Value="true" />',
        '<Constant Name="HideNearbyNPCs" Value="false" />',
        '<EnableBehavior Name="confessionProbeLyingBehavior" Signature="empty" EventSet="">',
        '<Constant Name="Behavior" Value="lyingHarmed" />',
        '<Asset Name="SmartEntity" Alias="confessionProbeLyingSpot" />',
        '<Asset Name="NPC" Alias="poseProbeLavrentiy" />',
        '<Edge From="confessionProbeStanceActive.State" To="IsActive" />',
        '<InstantSendMessage Name="confessionProbeHolsterWeapon" MessageType="player:holsterWeapon">',
        '<Edge From="confessionProbeTrigger.OnAdded" To="Exec" />',
        '<Edge From="confessionProbeHolsterWeapon.OnExec" To="EnqueueDialogue" />',
        '<Asset Name="DialogueHolder" Alias="confessionProbeDialogueHolder" />',
        '<Edge From="confessionProbeDialogParams.DialogParams" To="DialogParams" />',
        '<SceneFinishedWaiter Name="confessionProbeSceneFinished">',
        '<Edge From="confessionProbeSceneFinished.OnFinished" To="SetFalse" />',
        'MethodName="wh::rpgmodule::RemoveBuff"',
        'MethodName="wh::rpgmodule::AddBuff"',
        '<SoulAsset Name="poseProbeLavrentiy" SharedSoulGuids="449022cc-0fbf-ffa4-021b-2b4b13e113be" />',
        '<DialogueHolderAsset Name="confessionProbeDialogueHolder" />',
        '<SmartObjectAsset Name="confessionProbeLyingSpot" />'
    )) {
        Add-Result ($trosky.Contains($token)) `
            "generated Trosky forced-dialog probe contains $token"
    }

    Add-Result (
        $trosky.Contains(
            '<Edge From="confessionProbeTrigger.OnAdded" To="Exec" />'
        ) -and
        -not $trosky.Contains('confessionProbeDistance') -and
        -not $trosky.Contains('confessionProbeApproach')
    ) 'manual confession signal enqueues once without a proximity auto-start'

    Add-Result (
        $trosky.Contains(
            '<Constant Name="Duration" Value="500ms" />'
        ) -and
        -not $trosky.Contains('Value="0.5s"')
    ) 'confession release delay uses a valid engine TimeSpan literal'

    Add-Result (
        -not $kuttenberg.Contains('confessionProbe') -and
        -not $kuttenberg.Contains('poseProbeLavrentiy') -and
        -not $kuttenberg.Contains('pose_probe_male.xml')
    ) 'confession scheduler probe is isolated from Kuttenberg'

    Add-Result (
        $troskyObjects.Contains('Name="DP_ConfessionDialogueHolder_Trosecko"') -and
        $troskyObjects.Contains('EntityClass="DialogueHolder"') -and
        $troskyObjects.Contains('EntityId="1831843"') -and
        $troskyObjects.Contains('EntityGuid="cd93a0b2-762f-4d22"') -and
        $troskyObjects.Contains('Name="DP_ConfessionLyingSpot_Trosecko"') -and
        $troskyObjects.Contains('EntityClass="SO_LyingHarmed"') -and
        $troskyObjects.Contains('EntityId="1831844"') -and
        $troskyObjects.Contains('EntityGuid="8f827fee-38a5-41db"') -and
        $troskyObjects.Contains('guidSmartObjectType="fac19edd-46e9-4dd5-914f-72502c70af07"') -and
        $troskyObjects.Contains('esLyingHarmedPose="male_lyingWounded_04"') -and
        $troskyObjects.Contains(
            '<Link TargetId="2268" TargetGuid="fd4604bf-062f-4cf7" Name="_,harmedOne|,!priv,use" />'
        ) -and
        @(
            [regex]::Matches(
                $troskyObjects,
                'Name="DP_ConfessionCameraRig_[^"]+"[^>]+EntityClass="CameraSource"'
            )
        ).Count -eq 6 -and
        $troskyObjects.Contains('<CameraProxy Fov=') -and
        @(
            [regex]::Matches(
                $troskyWaitingLinks,
                '<LinkDefinition>cameraOverride</LinkDefinition>'
            )
        ).Count -eq 6 -and
        $troskyWaitingLinks.Contains(
            'SourceId="a13d9e5c-7b42-4f61" TargetId="cd93a0b2-762f-4d22"'
        ) -and
        $troskyWaitingLinks.Contains(
            '<LinkDefinition>asset[&apos;confessionProbeDialogueHolder&apos;]</LinkDefinition>'
        ) -and
        $troskyWaitingLinks.Contains(
            'SourceId="a13d9e5c-7b42-4f61" TargetId="8f827fee-38a5-41db"'
        ) -and
        $troskyWaitingLinks.Contains(
            '<LinkDefinition>asset[&apos;confessionProbeLyingSpot&apos;]</LinkDefinition>'
        ) -and
        $troskyWaitingLinks.Contains(
            'SourceId="8f827fee-38a5-41db" TargetId="cd93a0b2-762f-4d22"'
        ) -and
        $troskyWaitingLinks.Contains(
            '<LinkDefinition>dialogueHolder</LinkDefinition>'
        ) -and
        -not $troskyObjects.Contains('dark_passenger_confession_scheduler') -and
        -not $troskyObjects.Contains('b6c8473a-1e21-4d6f') -and
        -not $troskyWaitingLinks.Contains('DP_ConfessionScheduler')
    ) 'forced-dialog probe binds one authored DialogueHolder and one vanilla lying-harmed smart object'

    Add-Result (
        $buildScript.Contains("`$definition -eq 'cameraOverride'") -and
        $buildScript.Contains(
            "`$expectedMissionObjectCount = if (`$region -eq 'trosecko') { 9 } else { 1 }"
        )
    ) 'build validation admits six authored confession cameras and nine Trosky mission objects'

    Add-Result (
        -not $smartEntities.Contains('dark_passenger_confession_scheduler') -and
        -not $smartEntities.Contains('chatOnPlayerDialogAnim')
    ) 'forced-dialog probe adds no private world scheduler row'

    Add-Result (
        $smartEntities.Contains(
            'DatabaseId="45cdb687-7080-f41f-0008-89523752249f"'
        ) -and
        $smartEntities.Contains('Name="so_player_scheduler"') -and
        $smartEntities.Contains(
            'Name="darkPassengerConfession_GoToPlayer"'
        ) -and
        $smartEntities.Contains(
            'FileName="player/scheduler/darkPassengerConfession.xml"'
        )
    ) 'the modid-suffixed patch extends the existing Barbora player scheduler'

    Add-Result (
        -not (Test-Path -LiteralPath (Join-Path (
            Split-Path -Parent $smartEntityPath
        ) 'SmartEntity__so_player_scheduler.xml'))
    ) 'scheduler row is not hidden in a dev-ignored replacement-named table file'

    Add-Result (
        $schedulerBehavior.Contains(
            '<BehaviorTree name="darkPassengerConfession_GoToPlayer"'
        ) -and
        $schedulerBehavior.Contains(
            '<CrimeFollower Target="$__player" Mode="DontBackOff"'
        ) -and
        $schedulerBehavior.Contains(
            '<MeasureDistance position1="$this.id" position2="$__player"'
        ) -and
        $schedulerBehavior.Contains('$distanceMeTarget &lt; 3') -and
        -not $schedulerBehavior.Contains('Ruthardka')
    ) 'generic confession scheduler approaches the player without a Temptation location lock'

    Add-Result (
        $dialog.Contains('<ForcedDialog Name="pose_probe_male">') -and
        -not $dialog.Contains('<FaderDialog Name="pose_probe_male">') -and
        $dialog.Contains('Initiator="NonPlayer"') -and
        $dialog.Contains('<SelectedSoul Role="HENRY"') -and
        $dialog.Contains('<SelectedSoul Role="DP_CONFESSION_PROBE_MALE"') -and
        $dialog.Contains('Role="DP_CONFESSION_PROBE_MALE"') -and
        $dialog.Contains('Alias="dp_pose_confession_probe"') -and
        -not $dialog.Contains('Role="RANENY_NA_ZEMI_MUZ"') -and
        $runtime.Contains('role = "DP_CONFESSION_PROBE_MALE"') -and
        $roleTable.Contains('role_name="DP_CONFESSION_PROBE_MALE"')
    ) 'confession dialogue is a non-player initiated ForcedDialog with one mod-private target role'

    Add-Result (
        -not $stormRoles.Contains(
            'name="darkpassenger_confession_probe_lavrentiy"'
        ) -and
        -not $stormRoles.Contains('<hasName name="tzel_vavrinec" />')
    ) 'production Storm does not permanently bind the confession probe to Lavrentiy'

    Add-Result (
        $dialog.Contains(
            '<Sequence EndType="Decision" EntryCondition="Port(''available'')" Name="probe_intro">'
        ) -and
        $dialog.Contains(
            '<Decision Name="probe_root" Priority="General" Alias="dp_pose_confession_probe">'
        ) -and
        -not $dialog.Contains(
            '<Decision Name="probe_root" Autoselect="true"'
        ) -and
        $dialog.Contains('<Decision Name="probe_questions">') -and
        $dialog.Contains(
            '<Sequence GoToDecision="probe_questions" EndType="GoTo" EntryCondition="true" Name="probe_question_motive">'
        ) -and
        $dialog.Contains(
            '<Sequence GoToDecision="probe_questions" EndType="GoTo" EntryCondition="true" Name="probe_question_truth">'
        ) -and
        $dialog.Contains(
            '<Sequence EndType="EndDialogue" EntryCondition="true" Name="probe_finish">'
        ) -and
        -not $dialog.Contains('ThisSequenceUsed()') -and
        -not $dialog.Contains('SequenceUsed(')
    ) 'probe dialogue is deliberately repeatable across saves while production cases may persist used branches'

    [xml]$dialogXml = $dialog
    $spokenResponses = @(
        $dialogXml.SelectNodes('//Response[Text]')
    )
    Add-Result (
        $spokenResponses.Count -ge 7 -and
        @($spokenResponses | Where-Object {
            [string]::IsNullOrWhiteSpace([string]$_.ReferenceLength)
        }).Count -eq 0
    ) 'every spoken confession line has explicit text-only reference timing'

    $unboundedTargetSpeech = @(
        $dialogXml.SelectNodes(
            '//Response[@Role="DP_CONFESSION_PROBE_MALE"]/Commands/AnimationCommand[@FragmentId="ADLG_Speak" and not(@DesiredDuration)]'
        )
    )
    Add-Result (
        $unboundedTargetSpeech.Count -eq 0
    ) 'unvoiced target responses cannot hold the dialog on an unbounded ADLG_Speak animation'

    $woundedMoodCommands = @(
        $dialogXml.SelectNodes(
            '//MoodCommand[@Role="DP_CONFESSION_PROBE_MALE" and @Mood="woundedLying"]'
        )
    )
    Add-Result (
        $woundedMoodCommands.Count -ge 4
    ) 'every confession branch re-enters the vanilla wounded-lying dialogue mood'

    Add-Result (
        -not $dialog.Contains('FragmentId="ADLG_LyingHarmed_In"')
    ) 'confession does not call the lying-harmed transition without its authored smart-object state'

    foreach ($localizationKey in @(
        'dp_pose_probe_question_motive',
        'dp_pose_probe_question_truth',
        'dp_pose_probe_question_finish',
        'dp_confession_wake_action',
        'dp_confession_requires_cockerel'
    )) {
        Add-Result (
            $englishLocalization.Contains("<Cell>$localizationKey</Cell>") -and
            $russianLocalization.Contains("<Cell>$localizationKey</Cell>")
        ) "confession question key $localizationKey is bilingual"
    }

    Add-Result (
        $runtime.Contains(
            'COCKEREL_GUID = "6a3efa9e-700a-412a-88ee-721d34da98a8"'
        ) -and
        $runtime.Contains(
            'UNCONSCIOUS_BUFF_GUID = "f8d60fe4-e2c1-420a-946a-213e1cd09265"'
        ) -and
        $runtime.Contains(
            'function DarkPassengerPoseProbe.AddWakeAction('
        ) -and
        $runtime.Contains(':hint("@dp_confession_wake_action")') -and
        $runtime.Contains(':hintType(AHT_HOLD)') -and
        $runtime.Contains(
            'function DarkPassengerPoseProbe.OnWakeForConfession('
        ) -and
        $runtime.Contains('RemoveAllBuffsByGuid(') -and
        $runtime.Contains('ConsumeCockerel(') -and
        $runtime.Contains('"confession_wake",')
    ) 'unconscious Lavrentiy exposes one Cockerel-gated held action that arms the confession'

    foreach ($token in @(
        '<Port Name="available" Direction="In" Type="bool">',
        '<Port Name="started" Direction="Out" Type="trigger">',
        'EntryCondition="Port(''available'')"',
        '<Port Name="started" />'
    )) {
        Add-Result ($dialog.Contains($token)) `
            "confession dialog exposes lifecycle token $token"
    }

    foreach ($token in @(
        'CONFESSION_PROBE_BUFF_GUID',
        'CONFESSION_STANCE_BUFF_GUID',
        'CONFESSION_DIALOGUE_HOLDER_NAME',
        'CONFESSION_LYING_SPOT_NAME',
        'CONFESSION_RIG_ENTITY_PREFIX',
        'function DarkPassengerPoseProbe.PositionConfessionLyingSpot(',
        'function DarkPassengerPoseProbe.CreateConfessionCameraRig(',
        'System.GetEntityByName(cameraSpec.entityName)',
        'local function LookAngles(direction)',
        'x = math.asin(direction.z)',
        'z = math.atan2(-direction.x, direction.y)',
        'camera:SetWorldAngles(',
        'PositionConfessionLyingSpot(entity)',
        'CreateConfessionCameraRig(entity)',
        'function DarkPassengerPoseProbe.StartConfession(',
        'g_localActor.soul:AddBuff(',
        'entity.soul:AddMetaRoleByName(',
        'dp_pose_confession'
    )) {
        Add-Result ($runtime.Contains($token)) `
            "Lua confession entry contains $token"
    }
    Add-Result (
        -not $runtime.Contains('class = "TagPoint"') -and
        -not $runtime.Contains('holder:CreateLink("teleportBefore"') -and
        -not $runtime.Contains('System.SpawnEntity({') -and
        -not $runtime.Contains('holder:CreateLink("cameraOverride"')
    ) 'runtime repositions six pre-registered vanilla camera overrides without spawning or relinking entities'
    $startConfessionMatch = [regex]::Match(
        $runtime,
        '(?s)function DarkPassengerPoseProbe\.StartConfession\(.*?\nend\r?\n\r?\nfunction DarkPassengerPoseProbe\.CanWakeForConfession'
    )
    $stanceBuffIndex = $startConfessionMatch.Value.IndexOf(
        'CONFESSION_STANCE_BUFF_GUID'
    )
    $wakeIndex = $startConfessionMatch.Value.IndexOf(
        'RemoveAllBuffsByGuid('
    )
    $dialogBuffIndex = $startConfessionMatch.Value.LastIndexOf(
        'CONFESSION_PROBE_BUFF_GUID'
    )
    Add-Result (
        $startConfessionMatch.Success -and
        -not $startConfessionMatch.Value.Contains(
            'g_localActor.actor:RequestDialog('
        ) -and
        $runtime.Contains(
            'DarkPassengerPoseProbe.CONFESSION_DIALOG_DELAY_MS = 1500'
        ) -and
        $stanceBuffIndex -ge 0 -and
        $wakeIndex -gt $stanceBuffIndex -and
        $dialogBuffIndex -gt $wakeIndex
    ) 'Lua arms the lying stance, wakes the target, then gives the authored pose time to settle before dialog'
    Add-Result (
        $runtime.Contains('dp_pose_confession') -and
        -not $runtime.Contains('DarkPassengerPoseProbe.InstallAction()')
    ) 'confession probe uses a console command without the temporary HUD action'

    $probeBuffGuid = 'd0c1935f-2d7a-4f4e-bb5c-9ce734d99271'
    $probeBuff = @(
        $buffs.database.buffs.buff |
            Where-Object { [string]$_.buff_id -eq $probeBuffGuid }
    )
    Add-Result (
        $probeBuff.Count -eq 1 -and
        [string]$probeBuff[0].buff_ai_tag_id -eq '120' -and
        [string]$probeBuff[0].buff_ui_visibility_id -eq '0' -and
        [string]$probeBuff[0].is_persistent -eq 'false'
    ) 'confession trigger buff is hidden and nonpersistent'

    $tagIds = @($buffTags.database.buff_ai_tags.buff_ai_tag) |
        ForEach-Object { [string]$_.buff_ai_tag_id }
    Add-Result (
        @($tagIds | Where-Object { $_ -eq '120' }).Count -eq 1
    ) 'confession trigger owns one globally unique AI tag'

    $stanceBuffGuid = '5138624d-76d9-42de-ae19-e144031249cc'
    $stanceBuff = @(
        $buffs.database.buffs.buff |
            Where-Object { [string]$_.buff_id -eq $stanceBuffGuid }
    )
    Add-Result (
        $stanceBuff.Count -eq 1 -and
        [string]$stanceBuff[0].buff_ai_tag_id -eq '121' -and
        [string]$stanceBuff[0].buff_ui_visibility_id -eq '0' -and
        [string]$stanceBuff[0].is_persistent -eq 'false' -and
        @($tagIds | Where-Object { $_ -eq '121' }).Count -eq 1
    ) 'lying-harmed preparation owns one hidden nonpersistent AI tag'
}
finally {
    $resolvedTemp = [System.IO.Path]::GetFullPath($tempRoot)
    $requiredPrefix = [System.IO.Path]::GetFullPath(
        [System.IO.Path]::GetTempPath()
    )
    if (
        $resolvedTemp.StartsWith(
            $requiredPrefix,
            [System.StringComparison]::OrdinalIgnoreCase
        ) -and
        [System.IO.Path]::GetFileName($resolvedTemp).StartsWith(
            'dark-passenger-confession-probe-',
            [System.StringComparison]::Ordinal
        ) -and
        [System.IO.Directory]::Exists($resolvedTemp)
    ) {
        [System.IO.Directory]::Delete($resolvedTemp, $true)
    }
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
