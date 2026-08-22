# DialogueMediaKit Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a standalone offline pipeline that turns exact CaseKit dialogue-media jobs into cached English voice, native KCD2 lip-sync and verified game packages.

**Architecture:** `H:\KCD2Mod\DialogueMediaKit` owns media contracts, providers and KCD2 adapters. Dark Passenger emits reachable jobs and consumes verified outputs; it does not synthesize media itself.

**Tech Stack:** Python 3.10+, JSON Schema, OmniVoice Gradio API, ffmpeg/ffprobe, Annosoft phoneme recognizer, C#/.NET facial tooling, KCD2 Resource Compiler, PowerShell integration tests.

---

### Task 1: Standalone contracts and CLI

**Files:**
- Create: `H:\KCD2Mod\DialogueMediaKit\pyproject.toml`
- Create: `H:\KCD2Mod\DialogueMediaKit\src\dialogue_media_kit\contracts.py`
- Create: `H:\KCD2Mod\DialogueMediaKit\src\dialogue_media_kit\planner.py`
- Create: `H:\KCD2Mod\DialogueMediaKit\src\dialogue_media_kit\cli.py`
- Create: `H:\KCD2Mod\DialogueMediaKit\schemas\dialogue-media-jobs.schema.json`
- Create: `H:\KCD2Mod\DialogueMediaKit\schemas\dialogue-media-results.schema.json`
- Test: `H:\KCD2Mod\DialogueMediaKit\tests\test_contracts.py`

1. Write RED tests for schema version, deterministic unique `jobId`, required
   voice/rig/media fields, duplicate output basename and structured diagnostics.
2. Run `python -m unittest discover -s H:\KCD2Mod\DialogueMediaKit\tests -p "test_*.py" -v`; expect contract failures.
3. Implement minimal typed loading, normalization, job planning and `validate`
   CLI.
4. Re-run; expect all Task 1 tests PASS.
5. Commit only Task 1 files.

### Task 2: CaseKit media-jobs bridge

**Files:**
- Modify: `H:\KCD2Mod\DarkPassenger\config\dialogue-voice-registry.json`
- Modify: `H:\KCD2Mod\DarkPassenger\tools\CaseSpecCompiler.psm1`
- Modify: `H:\KCD2Mod\DarkPassenger\tools\Compile-CaseSpecs.ps1`
- Modify: `H:\KCD2Mod\DarkPassenger\tests\Test-DialogueVoiceRegistry.ps1`

1. Replace the old empty `facialAssets` expectation with RED assertions for
   exactly 16 reachable jobs: eight `tmck` male and eight `aals` female, unique
   basenames, English text and `voice=native`, `lipSync=true`.
2. Run the focused PowerShell test; confirm RED because no media jobs exist.
3. Extend the compiler to resolve line text, selected actor profile and rig into
   `dialogue-media-jobs.json`; do not generate unselected voice combinations.
4. Re-run focused compiler and regional integration tests; expect PASS and no
   change to dialogue graph identity.
5. Commit only the manifest bridge.

### Task 3: Voice catalog and reference collector

**Files:**
- Create: `H:\KCD2Mod\DialogueMediaKit\schemas\voice-catalog.schema.json`
- Create: `H:\KCD2Mod\DialogueMediaKit\src\dialogue_media_kit\voice_catalog.py`
- Create: `H:\KCD2Mod\DialogueMediaKit\src\dialogue_media_kit\reference_collector.py`
- Create: `H:\KCD2Mod\DialogueMediaKit\tests\test_voice_catalog.py`
- Create: `H:\KCD2Mod\DialogueMediaKit\tests\test_reference_collector.py`

1. Write RED tests for exact transcript, provenance, rig, asset prefix,
   20-30-second duration and actor ineligibility on invalid reference.
2. Add a real ffmpeg boundary test that concatenates fixture clips with fixed
   gaps and verifies duration/hash without altering sources.
3. Implement catalog validation and deterministic reference collection.
4. Run unit and ffmpeg integration tests; expect PASS.
5. Commit Task 3.

### Task 4: OmniVoice provider and content cache

**Files:**
- Create: `H:\KCD2Mod\DialogueMediaKit\src\dialogue_media_kit\cache.py`
- Create: `H:\KCD2Mod\DialogueMediaKit\src\dialogue_media_kit\providers\omnivoice.py`
- Create: `H:\KCD2Mod\DialogueMediaKit\tests\test_cache.py`
- Create: `H:\KCD2Mod\DialogueMediaKit\tests\test_omnivoice.py`
- Create: `H:\KCD2Mod\DialogueMediaKit\tests\integration\test_omnivoice_api.py`

1. Write RED tests for stage-separated cache invalidation by text, reference
   hash/transcript, provider settings and tool version; an audio cache hit must
   skip OmniVoice even when later-stage versions change.
2. Port the proven Gradio `/_clone_fn` contract behind a provider interface and
   emit stable `OMNIVOICE_FAILED` diagnostics.
3. Add atomic sidecars with output hashes plus explicit `--force`; mere file
   existence must not count as a hit.
4. Run unit tests with a fake provider; expect PASS.
5. When OmniVoice is running, execute the opt-in real API test and save only
   generated fixtures/results, never vanilla references.
6. Commit Task 4.

### Task 5: KCD2 NPC voice discovery

**Files:**
- Create: `H:\KCD2Mod\DialogueMediaKit\src\dialogue_media_kit\adapters\kcd2\voice_discovery.py`
- Create: `H:\KCD2Mod\DialogueMediaKit\src\dialogue_media_kit\adapters\kcd2\subtitle_index.py`
- Create: `H:\KCD2Mod\DialogueMediaKit\tests\integration\test_kcd2_voice_discovery.py`

1. Write RED fixtures joining actor entity/soul metadata to native voice prefix,
   vanilla dialogue asset paths and exact English subtitles.
2. Implement read-only PAK/index discovery and deterministic clean-source
   ranking; extracted originals remain untouched.
3. Build 20-30-second catalog references for Henry, Beta and one additional
   eligible NPC without manually supplying their audio filenames.
4. Prove roles with several reachable candidates emit only their distinct voice
   profiles; unresolved/insufficient voices produce exclusion diagnostics and
   never use a generic fallback.
5. Run real retail archive/index integration tests and commit Task 5.

### Task 6: Native phoneme-to-facial proof

**Files:**
- Create: `H:\KCD2Mod\DialogueMediaKit\src\dialogue_media_kit\providers\annosoft.py`
- Create: `H:\KCD2Mod\DialogueMediaKit\src\dialogue_media_kit\adapters\kcd2\facial.py`
- Create: `H:\KCD2Mod\DialogueMediaKit\tools\Kcd2FacialCompiler\Kcd2FacialCompiler.csproj`
- Create: `H:\KCD2Mod\DialogueMediaKit\tools\Kcd2FacialCompiler\Program.cs`
- Create: `H:\KCD2Mod\DialogueMediaKit\tests\test_phonemes.py`
- Create: `H:\KCD2Mod\DialogueMediaKit\tests\integration\test_kcd2_facial_compiler.py`

1. Preserve the working Beta CAF as a control fixture and add RED tests proving
   generated duration, non-empty rig controllers and different curves for
   materially different phoneme timelines.
2. Extract and compare matched vanilla audio/facial controls for at least one
   male and one female line; record controller IDs and rig transforms as versioned
   adapter data, not hardcoded case content.
3. Implement time-aligned phoneme/viseme blending into legacy `0x0827` controller
   keys for both rigs.
4. Cross the real Annosoft and C# CAF boundary; inspect the produced CAF and
   reject copied duration-only curves.
5. Do not advance if Henry or Beta output has no mouth/jaw controller motion.
6. Commit the proven male/female facial adapter.

### Task 7: Official RC, DBA, IMG and PAK adapters

**Files:**
- Create: `H:\KCD2Mod\DialogueMediaKit\src\dialogue_media_kit\adapters\kcd2\resource_compiler.py`
- Create: `H:\KCD2Mod\DialogueMediaKit\src\dialogue_media_kit\adapters\kcd2\facial_img.py`
- Create: `H:\KCD2Mod\DialogueMediaKit\src\dialogue_media_kit\adapters\kcd2\packager.py`
- Create: `H:\KCD2Mod\DialogueMediaKit\tests\integration\test_kcd2_resource_pipeline.py`

1. Write RED integration tests using the official RC and real retail
   `FacialAnimations.img`: preserve all vanilla entries, add every custom CAF
   once, reject collisions and keep the DBA isolated.
2. Port the proven Dark Passenger legacy CAF/IMG merger logic behind adapters.
3. Build deterministic voice/facial PAKs in a temporary staging directory and
   verify archive integrity plus OGG/CAF basename joins.
4. Run the real boundary suite; expect zero missing or duplicate assets.
5. Commit Task 6.

### Task 8: Sixteen-line acceptance build

**Files:**
- Create: `H:\KCD2Mod\DialogueMediaKit\tests\fixtures\missing-traveler\dialogue-media-jobs.json`
- Create: `H:\KCD2Mod\DialogueMediaKit\tests\acceptance\test_missing_traveler_16_lines.py`
- Modify: `H:\KCD2Mod\DarkPassenger\tools\Build-Mod.ps1`

1. Write RED acceptance assertions for 16 successful jobs, 16 OGGs, 16 CAFs,
   eight male/eight female assets and two verified PAKs.
2. Generate all missing media through the local OmniVoice server; reuse cache
   only when its full key matches.
3. Build through Annosoft, facial compiler, official RC, DBA/IMG merger and PAK
   inspection.
4. Make Dark Passenger copy only `complete` results; incomplete media must fail
   the build with the originating diagnostic code.
5. Run the full acceptance test and relevant Dark Passenger build tests.
6. Commit Task 7.

### Task 9: Cold retail proof and documentation

**Files:**
- Create: `H:\KCD2Mod\DialogueMediaKit\README.md`
- Modify: `H:\KCD2Mod\DarkPassenger\docs\plans\2026-08-14-timed-area-native-hud-action.md`

1. Install the verified packages by full replacement and launch retail in the
   known devmode/HTTP bridge configuration.
2. Play the full Beta dialogue: confirm audible English and visible lip movement
   on all eight Beta and all eight Henry lines.
3. Record exact cold-runtime result and hashes; do not claim completion from
   static tests alone.
4. Document CLI, contracts, cache, required external tools and publication
   boundary.
5. Restore the listening-mechanic checkpoint as the next active task.
6. Commit docs and verified integration wiring.

## Unresolved questions

- Exact production phoneme-to-controller mapping must be derived and proven in
  Task 6; the current one-line Beta canary proves lookup/packaging only.
