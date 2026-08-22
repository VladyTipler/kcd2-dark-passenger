#!/usr/bin/env python3
"""Generate deterministic Dark Passenger dialogue audio through OmniVoice."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from pathlib import Path
from typing import Any, Callable, Protocol


class Predictor(Protocol):
    def predict(
        self,
        *,
        job: dict[str, Any],
        voice: dict[str, Any],
        defaults: dict[str, Any],
    ) -> tuple[Path | None, str]: ...


def load_manifest(path: Path) -> dict[str, Any]:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    return load_manifest_from_data(manifest, base_dir=path.parent)


def load_manifest_from_data(
    manifest: dict[str, Any],
    *,
    base_dir: Path | None = None,
) -> dict[str, Any]:
    manifest = dict(manifest)
    base_dir = base_dir or Path.cwd()
    output_root = Path(manifest["outputRoot"])
    if not output_root.is_absolute():
        output_root = base_dir / output_root
    voices = manifest["voices"]
    seen: set[str] = set()

    for voice_id, voice in voices.items():
        reference = Path(voice["referenceAudio"])
        if not reference.is_absolute():
            reference = base_dir / reference
        if not reference.is_file():
            raise ValueError(f"reference audio not found for {voice_id}: {reference}")
        voice["referenceAudio"] = str(reference)

    for line in manifest["lines"]:
        line_id = line["lineId"]
        if line_id in seen:
            raise ValueError(f"duplicate lineId: {line_id}")
        if line["speaker"] not in voices:
            raise ValueError(f"unknown voice '{line['speaker']}' for line '{line_id}'")
        seen.add(line_id)

    manifest["outputRoot"] = str(output_root)
    return manifest


def plan_jobs(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    output_root = Path(manifest["outputRoot"])
    return [
        {
            "lineId": line["lineId"],
            "speaker": line["speaker"],
            "text": line["text"],
            "durationSeconds": line["durationSeconds"],
            "outputPath": str(
                output_root
                / f"{manifest['voices'][line['speaker']]['outputPrefix']}_{line['lineId']}.wav"
            ),
        }
        for line in manifest["lines"]
    ]


class GradioOmniVoicePredictor:
    def __init__(
        self,
        server_url: str | None = None,
        *,
        client: Any | None = None,
        file_handler: Callable[[str], Any] | None = None,
    ) -> None:
        if client is None or file_handler is None:
            from gradio_client import Client, handle_file

            client = client or Client(server_url)
            file_handler = file_handler or handle_file
        self.client = client
        self.file_handler = file_handler

    def predict(
        self,
        *,
        job: dict[str, Any],
        voice: dict[str, Any],
        defaults: dict[str, Any],
    ) -> tuple[Path | None, str]:
        audio_path, status = self.client.predict(
            text=job["text"],
            lang=defaults["language"],
            ref_aud=self.file_handler(voice["referenceAudio"]),
            ref_text=voice["referenceText"],
            instruct=voice["instruct"],
            ns=defaults["inferenceSteps"],
            gs=defaults["guidanceScale"],
            dn=defaults["denoise"],
            sp=defaults["speed"],
            du=job["durationSeconds"],
            pp=defaults["preprocessPrompt"],
            po=defaults["postprocessOutput"],
            api_name="/_clone_fn",
        )
        return (Path(audio_path) if audio_path else None, status)


def read_audio_duration(path: Path) -> float:
    completed = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(path),
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=True,
    )
    return round(float(completed.stdout.strip()), 3)


def run_batch(
    manifest: dict[str, Any],
    *,
    predictor: Predictor,
    duration_reader: Callable[[Path], float] = read_audio_duration,
    force: bool = False,
) -> list[dict[str, Any]]:
    output_root = Path(manifest["outputRoot"])
    output_root.mkdir(parents=True, exist_ok=True)
    results: list[dict[str, Any]] = []

    for line, planned in zip(manifest["lines"], plan_jobs(manifest), strict=True):
        output_path = Path(planned["outputPath"])
        server_status: str | None = None
        if output_path.is_file() and not force:
            status = "skipped"
        else:
            source_path, server_status = predictor.predict(
                job=line,
                voice=manifest["voices"][line["speaker"]],
                defaults=manifest["defaults"],
            )
            if source_path is None or not source_path.is_file() or server_status != "Done.":
                raise RuntimeError(
                    f"OmniVoice failed for {line['lineId']}: {server_status or 'missing output'}"
                )
            if source_path.resolve() != output_path.resolve():
                shutil.copy2(source_path, output_path)
            status = "generated"

        results.append(
            {
                "lineId": line["lineId"],
                "speaker": line["speaker"],
                "text": line["text"],
                "requestedDurationSeconds": line["durationSeconds"],
                "actualDurationSeconds": duration_reader(output_path),
                "status": status,
                "serverStatus": server_status,
                "outputPath": str(output_path),
            }
        )
        (output_root / "results.json").write_text(
            json.dumps(results, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    return results


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--force", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manifest = load_manifest(args.manifest.resolve())
    jobs = plan_jobs(manifest)
    if args.dry_run:
        print(json.dumps(jobs, ensure_ascii=False, indent=2))
        return 0
    predictor = GradioOmniVoicePredictor(manifest["serverUrl"])
    results = run_batch(manifest, predictor=predictor, force=args.force)
    print(json.dumps(results, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
