# Eligible Actor Dialogue Media Pipeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the Henry/Beta pilot assignment with a reusable offline pipeline that prepares voice and lip-sync for every NPC voice eligible for a CaseKit dialogue role and lets the runtime-selected actor use its own media automatically.

**Architecture:** CaseKit owns the bounded actor pool and expands authored dialogue lines only across distinct eligible voice profiles for their speaker role. DialogueMediaKit discovers references, builds cached audio/facials and publishes verified PAKs plus a complete results manifest. Dark Passenger consumes only complete matching results; runtime performs no synthesis.

**Tech Stack:** PowerShell 7, Python 3.10, JSON, OmniVoice Gradio API, ffmpeg/ffprobe, Annosoft, KCD2 Resource Compiler, ZIP/PAK inspection.

---

### Task 1: Freeze the working pilot build boundary

**Files:**
- Create: `H:\KCD2Mod\DarkPassenger\tests\Test-DialogueMediaResultsConsumer.ps1`
- Create: `H:\KCD2Mod\DarkPassenger\tools\Import-DialogueMediaResults.ps1`
- Modify: `H:\KCD2Mod\DarkPassenger\tools\Build-Mod.ps1`

1. Write a RED integration test using the verified 16-line results and both real pilot PAKs.
2. Require exact job coverage, `status=complete`, package hashes and OGG/CAF basename coverage.
3. Make incomplete, stale or mismatched results fail closed with a stable diagnostic.
4. Copy verified voice/facial PAKs into build staging only after validation.
5. Run the focused test and prove a clean build cannot silently delete lip-sync.
6. Commit only this boundary.

### Task 2: Propagate authored media and eligible actor pools

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\content\stories\missing-traveler\dialogues\innkeeper.json`
- Modify: `H:\KCD2Mod\DarkPassenger\casekit\core\CaseKit.Authoring.psm1`
- Modify: `H:\KCD2Mod\DarkPassenger\casekit\adapters\kcd2\CaseKit.Kcd2Backend.psm1`
- Modify: `H:\KCD2Mod\DarkPassenger\tools\CaseSpecCompiler.psm1`
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-DialogueVoiceRegistry.ps1`

1. Write RED unit tests that preserve `media:{voice:native,lipSync:true}` through authoring, materialization and backend output.
2. Write a RED feature test with two eligible innkeepers having different voice prefixes.
3. Emit one job for each distinct `(speakerRole, voiceProfile, stringName)` and deduplicate actors sharing a voice profile.
4. Include candidate actor identity and selection provenance in every job.
5. Remove exact settlement/NPC assignments and manual source asset/duration lists from the production contract.
6. Fail compatibility when a required voiced role has no eligible profile; never use a generic fallback.
7. Run CaseKit compiler and regional integration tests.
8. Commit the generic media-matrix bridge.

### Task 3: Build one cached job end to end

**Files:**
- Create: `H:\KCD2Mod\DialogueMediaKit\src\dialogue_media_kit\pipeline.py`
- Create: `H:\KCD2Mod\DialogueMediaKit\src\dialogue_media_kit\adapters\kcd2\audio_encoder.py`
- Create: `H:\KCD2Mod\DialogueMediaKit\src\dialogue_media_kit\adapters\kcd2\resource_compiler.py`
- Create: `H:\KCD2Mod\DialogueMediaKit\src\dialogue_media_kit\adapters\kcd2\voice_packager.py`
- Modify: `H:\KCD2Mod\DialogueMediaKit\src\dialogue_media_kit\cli.py`
- Test: `H:\KCD2Mod\DialogueMediaKit\tests\test_pipeline.py`
- Test: `H:\KCD2Mod\DialogueMediaKit\tests\integration\test_build_cli_cached_job.py`

1. Write a RED unit test with injected stage fakes and stable per-job diagnostics.
2. Prove an audio cache hit never calls OmniVoice.
3. Implement WAV-to-OGG, phoneme, CAF, official RC, IMG/DBA and deterministic voice/facial package orchestration.
4. Emit `dialogue-media-results.json`; `complete` requires audio, facial and both verified PAKs.
5. Add a cached integration fixture that crosses real ffmpeg, Annosoft and official RC without starting OmniVoice.
6. Run twice and require identical package contents and hashes.
7. Commit the standalone build command.

### Task 4: Scale the pipeline to the eligible media matrix

**Files:**
- Modify: `H:\KCD2Mod\DialogueMediaKit\src\dialogue_media_kit\pipeline.py`
- Modify: `H:\KCD2Mod\DialogueMediaKit\src\dialogue_media_kit\adapters\kcd2\voice_discovery.py`
- Test: `H:\KCD2Mod\DialogueMediaKit\tests\acceptance\test_missing_traveler_actor_pool.py`

1. Write a RED acceptance fixture with Henry plus multiple eligible NPC profiles.
2. Discover or reuse a cached 20-30 second reference for each distinct profile.
3. Generate only missing matrix cells; unchanged cells must be cache hits.
4. Verify every required prefix/string basename has one OGG and one CAF.
5. Emit structured exclusions for unresolved actors and return the eligible pool to CaseKit.
6. Commit actor-pool generation.

### Task 5: Troskovice and Zhelejov acceptance

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\tools\Build-Mod.ps1`
- Modify: `H:\KCD2Mod\DialogueMediaKit\README.md`
- Modify: `H:\KCD2Mod\DarkPassenger\docs\plans\2026-08-14-timed-area-native-hud-action.md`

1. Rebuild the existing 16-line Troskovice pilot solely through the generic pipeline.
2. Verify the six-line post-ledger branch in retail and recheck `Esc`/`T` after dialogue.
3. Compile Zhelejov without a hand-authored voice assignment.
4. Start a case, record the randomly selected actor and prove that actor speaks with its own generated prefix and lip-sync.
5. Run focused unit, feature, real-boundary and archive integrity tests.
6. Run `/simplify` over feature commits, update the LLM Wiki and commit documentation.

## Unresolved questions

- Whether one dynamic dialogue graph resolves every selected actor prefix directly; if not, CaseKit must generate actor-specific graph variants from the same media matrix without manual assignments.
