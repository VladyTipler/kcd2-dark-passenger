import importlib.util
import json
import os
import tempfile
import unittest
import urllib.request
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = PROJECT_ROOT / "tools" / "voice" / "omni_voice_batch.py"
SERVER_URL = os.environ.get("OMNIVOICE_SERVER_URL", "http://127.0.0.1:7860")
REFERENCE_AUDIO = os.environ.get("OMNIVOICE_REFERENCE_AUDIO")


def load_batch_module():
    spec = importlib.util.spec_from_file_location("omni_voice_batch", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class OmniVoiceApiIntegrationTests(unittest.TestCase):
    def test_live_api_exposes_clone_contract(self) -> None:
        with urllib.request.urlopen(f"{SERVER_URL}/gradio_api/info", timeout=10) as response:
            info = json.load(response)

        endpoint = info["named_endpoints"]["/_clone_fn"]
        parameter_names = [item["parameter_name"] for item in endpoint["parameters"]]
        self.assertEqual(
            parameter_names,
            ["text", "lang", "ref_aud", "ref_text", "instruct", "ns", "gs", "dn", "sp", "du", "pp", "po"],
        )

    @unittest.skipUnless(REFERENCE_AUDIO, "set OMNIVOICE_REFERENCE_AUDIO for a full generation proof")
    def test_live_clone_returns_downloaded_audio(self) -> None:
        module = load_batch_module()
        predictor = module.GradioOmniVoicePredictor(SERVER_URL)
        source, status = predictor.predict(
            job={"text": "I need to see it.", "durationSeconds": 2.5},
            voice={
                "referenceAudio": REFERENCE_AUDIO,
                "referenceText": "",
                "instruct": "male, young adult, british accent",
            },
            defaults={
                "language": "English",
                "inferenceSteps": 32,
                "guidanceScale": 2.0,
                "denoise": True,
                "speed": 1.0,
                "preprocessPrompt": True,
                "postprocessOutput": True,
            },
        )

        self.assertEqual(status, "Done.")
        self.assertIsNotNone(source)
        self.assertTrue(source.is_file())


if __name__ == "__main__":
    unittest.main()
