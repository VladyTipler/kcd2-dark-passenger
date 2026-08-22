---
title: DialogueMediaKit Design
date: 2026-08-16
status: approved
---

# DialogueMediaKit Design

## Goal

Build a standalone offline tool that turns authored KCD2 dialogue lines and
the bounded pool of actors eligible to speak them into reproducible voice,
native facial animation and game package artifacts. Dark Passenger and CaseKit
consume the result but do not own media generation.

## Module boundary

- Initial workspace: `H:\KCD2Mod\DialogueMediaKit`.
- CaseKit remains the source of dialogue text, localization keys and the actor
  candidates eligible for each dialogue role.
- CaseKit emits the bounded product of reachable role lines and distinct voice
  profiles in that role's eligible actor pool. It must not build the blind
  Cartesian product of every game voice and every story line.
- DialogueMediaKit owns reference preparation, OmniVoice calls, phoneme timing,
  native facial CAF generation, official Resource Compiler invocation, DBA/IMG
  assembly, caching and package output.
- Dark Passenger receives immutable built artifacts plus a result manifest. It
  performs no voice cloning or facial generation at runtime.
- The module must remain publishable independently of Dark Passenger and usable
  by other QuestKit/CaseKit consumers.

## Authoring contract

Dialogue authoring may opt into native media:

```json
{
  "media": {
    "voice": "native",
    "lipSync": true
  }
}
```

`voice: native` means the line must be rendered with the selected game's voice
profile. `lipSync: true` is a build requirement, not a best-effort decoration:
every voiced participant, including Henry, needs a facial asset.

## Input contract

CaseKit writes `dialogue-media-jobs.json` after regional candidate resolution
and dialogue compilation, before the runtime case selects one actor:

```json
{
  "schemaVersion": 1,
  "game": "kcd2",
  "packageLanguage": "english",
  "jobs": [
    {
      "jobId": "missing_traveler.troskovice.dp_mt_rumor_innkeeper_left.aals",
      "storyId": "missing_traveler",
      "dialogueGraph": "dpcase2001_trosecko_troskovice_innkeeper_missing_traveler_dialog_t",
      "stringName": "dp_mt_rumor_innkeeper_left",
      "text": "He left before dawn...",
      "speakerRole": "innkeeper",
      "candidateActor": "ttkc_inkeeper",
      "voiceProfile": "beta-troskovice-en",
      "assetPrefix": "aals",
      "rig": "human_female",
      "audioFolder": "trosecko/dark_within_t",
      "media": {
        "voice": "native",
        "lipSync": true
      }
    }
  ]
}
```

Required invariants:

- `jobId` is unique and deterministic.
- `(voiceProfile, stringName, normalized text, rig)` uniquely describes an
  output job.
- Every reachable `(speakerRole, candidate voiceProfile, stringName)` has one
  job. Multiple actors sharing one voice prefix reuse the same media job.
- `assetPrefix + '_' + stringName` is the shared KCD2 basename for OGG and CAF.
- The English text sent to synthesis is the English subtitle text for the line.
- Every `voiceProfile` resolves to one exact actor voice, a 20-30 second clean
  English reference clip, its exact transcript, `assetPrefix`, and compatible
  facial rig. Reference target length is about 25 seconds.
- A missing or invalid voice reference makes the actor ineligible for a voiced
  binding and produces a build diagnostic; it never silently switches voice.
- Dialogue graphs do not pin a randomly assigned role to one authored NPC
  voice. KCD2 resolves the selected actor's native voice prefix and loads the
  matching prebuilt `assetPrefix + '_' + stringName` media.

## Output and error contract

DialogueMediaKit writes `dialogue-media-results.json`:

```json
{
  "schemaVersion": 1,
  "status": "complete",
  "jobs": [
    {
      "jobId": "missing_traveler.troskovice.dp_mt_rumor_innkeeper_left.aals",
      "status": "generated",
      "audio": "dialog/trosecko/dark_within_t/aals_dp_mt_rumor_innkeeper_left.ogg",
      "facial": "animations/humans/facials/dialog/trosecko/dark_within_t/aals_dp_mt_rumor_innkeeper_left.caf",
      "durationSeconds": 6.99,
      "cacheKey": "sha256:..."
    }
  ],
  "packages": {
    "voice": "darkpassenger_dialogue_english.pak",
    "facial": "darkpassenger_facials_english.pak"
  },
  "diagnostics": []
}
```

Failures use stable codes such as `VOICE_PROFILE_MISSING`,
`REFERENCE_AUDIO_INVALID`, `OMNIVOICE_FAILED`, `PHONEME_EXTRACTION_FAILED`,
`FACIAL_COMPILE_FAILED`, `IMG_MERGE_CONFLICT` and `PACKAGE_INCOMPLETE`. A run is
`complete` only when every required job has both audio and facial output.

## Components

1. `Core` validates manifests, plans deterministic jobs and computes cache keys.
2. `Kcd2VoiceDiscoveryAdapter` resolves every eligible actor/soul voice prefix,
   indexes vanilla dialogue audio plus subtitles and proposes clean reference
   sources.
3. `VoiceCatalog` stores actor/voice eligibility, references and transcripts.
4. `OmniVoiceProvider` talks to the local Gradio API and normalizes output audio.
5. `PhonemeProvider` extracts time-aligned phonemes from the generated audio.
6. `Kcd2FacialAdapter` maps timed phonemes to the appropriate male/female facial
   controllers and writes legacy `0x0827` CAF sources.
7. `Kcd2ResourceCompilerAdapter` invokes the official RC, creates an isolated
   custom DBA and merges only custom entries into the retail
   `FacialAnimations.img` registry.
8. `Kcd2Packager` builds deterministic voice/facial PAKs and verifies their
   contents before publishing them.
9. `CLI` exposes discover-voices, validate, collect-reference, generate, build
   and verify stages.

Provider interfaces keep OmniVoice replaceable. KCD2-specific CAF, RC, DBA, IMG
and PAK logic stays behind KCD2 adapters rather than leaking into core jobs.

## Voice reference collection

- Start from the CaseKit role's eligible actor pool, not a manually chosen
  actor or voice.
- Resolve actor entity/soul metadata to the same native voice prefix used by
  `SelectedSoul Voice` in KCD2 dialogue XML.
- Index matching vanilla dialogue assets and join them to their exact English
  subtitle strings before selecting reference material.
- Collect only dialogue audio belonging to an allowed actor voice profile.
- Prefer clean speech without music, combat sounds, overlaps or long silence.
- Concatenate multiple source clips non-destructively until 20-30 seconds.
- Store the exact English transcript next to the resulting reference WAV.
- Preserve source provenance so a profile can be rebuilt and audited.
- Do not overwrite extracted vanilla sources.
- Emit a reusable voice catalog entry keyed by actor identity and voice prefix.
- If several reachable NPC candidates can fill one role, emit jobs for every
  distinct eligible candidate voice profile and every line spoken by that role;
  do not expand unrelated game voices.
- Actors sharing one native prefix/reference deduplicate to one voice profile.
- Actors whose voice cannot be resolved or whose clean reference is insufficient
  are excluded from voiced-case eligibility. Never substitute a generic voice.

## Cache contract

Caching is content-addressed and separated by stage:

- audio key: normalized English text, reference audio hash, exact reference
  transcript, OmniVoice model/settings and provider version;
- phoneme key: generated audio hash, normalized text and extractor version;
- facial key: phoneme payload hash, rig, facial mapping/compiler version and RC
  version;
- package key: ordered artifact hashes and packager version.

A matching audio cache hit never calls OmniVoice again, even when phoneme,
facial or packaging code changes. Mere file existence is not a cache hit: the
sidecar key, output hash and expected metadata must match. Corrupt or partial
entries are regenerated atomically. Changed text or reference invalidates only
affected audio; `--force` explicitly bypasses selected or all stages.

## Native KCD2 facial pipeline

For every generated OGG:

1. Extract timed phonemes.
2. Convert phonemes into rig-specific facial controller keys.
3. Write a legacy uncompressed `0x0827` CAF with matching KCD2 asset basename.
4. Compile through the official KCD2 Resource Compiler.
5. Route the output into an isolated DialogueMediaKit DBA.
6. Merge custom CAF registry chunks into a copy of the retail
   `FacialAnimations.img`, rejecting duplicate paths.
7. Package the merged IMG and isolated DBA.

Raw FSQ files and global `female.chrparams`/`male.chrparams` overrides are never
shipped. The proven Beta pilot is the integration control; copied vanilla facial
curves are acceptable only as a diagnostic canary, not final generated lip-sync.

## Build flow

1. CaseKit validates content and resolves the eligible actor pool per role.
2. CaseKit emits the exact reachable role-line by candidate-voice matrix.
3. DialogueMediaKit validates the job manifest and voice catalog.
4. Cached jobs are reused; missing jobs run audio, phoneme and facial stages.
5. KCD2 adapters compile, merge and package artifacts.
6. Package inspection joins every required `stringName` to one OGG and one CAF.
7. Dark Passenger build copies verified artifacts and result manifest only.

## Acceptance proof

The first acceptance case is the existing 16-line Troskovice dialogue:

- eight Henry lines using `tmck` and the male rig;
- eight Beta lines using `aals` and the female rig;
- real OmniVoice API boundary;
- real phoneme extraction;
- all 16 legacy CAFs compiled through the official RC;
- isolated custom DBA plus real retail IMG merge;
- PAK inspection proving 16 OGG/CAF basename pairs;
- cold retail dialogue proving audible speech and visible lip movement for both
  Henry and Beta across the full conversation.

Static tests and archive inspection do not replace the final cold retail proof.

The second acceptance case is Zhelejov and must not add a hand-authored actor
assignment. It is only the first proof of the global rule: CaseKit supplies the
eligible local actor pool for every supported settlement, DialogueMediaKit
discovers and prepares each distinct voice, and whichever NPC the runtime case
selects in the nearest compatible settlement must speak with that NPC's native
voice prefix and matching lip-sync.

## Non-goals

- Runtime synthesis or GPU inference while the game runs.
- Generating every story line in every vanilla voice outside its eligible role
  pool.
- Shipping cloned voice references or extracted vanilla source archives.
- Replacing the game's global facial registries or character parameters.
- Automatic support for unsupported rigs before the male/female human pilot is
  proven.

## Unresolved questions

- Exact phoneme-to-controller mapping for production-quality male and female
  native curves remains the main research boundary; the current Beta proof only
  establishes packaging and runtime lookup.
