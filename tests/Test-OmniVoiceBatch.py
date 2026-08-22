import json
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = PROJECT_ROOT / "tools" / "voice" / "omni_voice_batch.py"


def load_batch_module():
    spec = importlib.util.spec_from_file_location("omni_voice_batch", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def make_manifest(root: Path) -> dict:
    reference = root / "reference.wav"
    reference.write_bytes(b"reference")
    return {
        "version": 1,
        "serverUrl": "http://127.0.0.1:7860",
        "outputRoot": str(root / "output"),
        "defaults": {
            "language": "English",
            "inferenceSteps": 32,
            "guidanceScale": 2.0,
            "denoise": True,
            "speed": 1.0,
            "preprocessPrompt": True,
            "postprocessOutput": True,
        },
        "voices": {
            "henry": {
                "outputPrefix": "tmck",
                "referenceAudio": str(reference),
                "referenceText": "",
                "instruct": "male, young adult, british accent",
            }
        },
        "lines": [
            {
                "lineId": "dp_mt_rumor_henry_missing",
                "speaker": "henry",
                "text": "I hear one of your guests disappeared.",
                "durationSeconds": 4.0,
            }
        ],
    }


class OmniVoiceBatchCliTests(unittest.TestCase):
    def test_dry_run_builds_deterministic_job_plan(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest = make_manifest(root)
            output_root = Path(manifest["outputRoot"])
            manifest_path = root / "manifest.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            completed = subprocess.run(
                [sys.executable, str(SCRIPT_PATH), "--manifest", str(manifest_path), "--dry-run"],
                capture_output=True,
                text=True,
                encoding="utf-8",
                check=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            plan = json.loads(completed.stdout)
            self.assertEqual(len(plan), 1)
            self.assertEqual(plan[0]["lineId"], "dp_mt_rumor_henry_missing")
            self.assertEqual(plan[0]["outputPath"], str(output_root / "tmck_dp_mt_rumor_henry_missing.wav"))

    def test_gradio_predictor_maps_manifest_contract_to_clone_endpoint(self) -> None:
        module = load_batch_module()

        class FakeClient:
            def __init__(self) -> None:
                self.kwargs = None

            def predict(self, **kwargs):
                self.kwargs = kwargs
                return ("C:\\temp\\audio.wav", "Done.")

        fake_client = FakeClient()
        predictor = module.GradioOmniVoicePredictor(
            client=fake_client,
            file_handler=lambda path: f"FILE:{path}",
        )
        defaults = make_manifest(Path(tempfile.mkdtemp()))["defaults"]
        voice = {
            "outputPrefix": "tmck",
            "referenceAudio": "H:\\voices\\henry.wav",
            "referenceText": "Reference words.",
            "instruct": "male, young adult, british accent",
        }
        job = {
            "text": "A test line.",
            "durationSeconds": 3.5,
        }

        result = predictor.predict(job=job, voice=voice, defaults=defaults)

        self.assertEqual(result, (Path("C:\\temp\\audio.wav"), "Done."))
        self.assertEqual(fake_client.kwargs["api_name"], "/_clone_fn")
        self.assertEqual(fake_client.kwargs["ref_aud"], "FILE:H:\\voices\\henry.wav")
        self.assertEqual(fake_client.kwargs["du"], 3.5)
        self.assertEqual(fake_client.kwargs["ns"], 32)
        self.assertEqual(fake_client.kwargs["gs"], 2.0)

    def test_batch_copies_output_records_duration_and_skips_existing_file(self) -> None:
        module = load_batch_module()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest = module.load_manifest_from_data(make_manifest(root))
            generated = root / "gradio.wav"
            generated.write_bytes(b"generated audio")

            class FakePredictor:
                def __init__(self) -> None:
                    self.calls = 0

                def predict(self, **_kwargs):
                    self.calls += 1
                    return generated, "Done."

            predictor = FakePredictor()
            first = module.run_batch(
                manifest,
                predictor=predictor,
                duration_reader=lambda _path: 3.25,
            )
            second = module.run_batch(
                manifest,
                predictor=predictor,
                duration_reader=lambda _path: 3.25,
            )

            output = Path(manifest["outputRoot"]) / "tmck_dp_mt_rumor_henry_missing.wav"
            self.assertEqual(output.read_bytes(), b"generated audio")
            self.assertEqual(predictor.calls, 1)
            self.assertEqual(first[0]["status"], "generated")
            self.assertEqual(first[0]["actualDurationSeconds"], 3.25)
            self.assertEqual(second[0]["status"], "skipped")
            results = json.loads((Path(manifest["outputRoot"]) / "results.json").read_text(encoding="utf-8"))
            self.assertEqual(results[0]["status"], "skipped")


if __name__ == "__main__":
    unittest.main()
