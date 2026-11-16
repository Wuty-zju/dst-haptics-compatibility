"""Waveform evidence must retain silence and never replace earlier output."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import wave

spec = importlib.util.spec_from_file_location(
    "analyze_waveform_envelopes", Path(__file__).resolve().parents[1] / "tools/analyze_waveform_envelopes.py")
envelopes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(envelopes)


class WaveformEvidenceTests(unittest.TestCase):
    def make_wave(self, path, width, silent=True):
        with wave.open(str(path), "wb") as output:
            output.setparams((1, width, 100, 0, "NONE", "not compressed"))
            sample = (b"\x80" if width == 1 else b"\0\0") if silent else b"\x01\0"
            output.writeframes(sample * 10)

    def run_analysis(self, wavs, out):
        with patch("sys.argv", ["analyze_waveform_envelopes.py", "--wav-root", str(wavs), "--out", str(out)]):
            with contextlib.redirect_stdout(io.StringIO()):
                envelopes.main()

    def test_silent_pcm_produces_zero_bins_and_a_valid_report(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            wavs = root / "wavs"
            wavs.mkdir()
            for width in (1, 2):
                path = wavs / f"chop_tree_{width}.wav"
                self.make_wave(path, width)
                self.assertEqual(envelopes.rms_bins(path), [0.0, 0.0])
            out = root / "evidence/envelopes.json"
            self.run_analysis(wavs, out)
            self.assertEqual(json.loads(out.read_text())["chop_tree"]["envelope"], [0.0, 0.0])

    def test_existing_output_is_never_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_wave(root / "chop_tree_1.wav", 2, silent=False)
            out = root / "envelopes.json"
            out.write_bytes(b"existing evidence")
            with self.assertRaisesRegex(SystemExit, "already exists"):
                self.run_analysis(root, out)
            self.assertEqual(out.read_bytes(), b"existing evidence")

    def test_empty_wav_root_does_not_write_an_empty_success_report(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            out = root / "evidence/envelopes.json"
            with self.assertRaisesRegex(SystemExit, "WAV"):
                self.run_analysis(root, out)
            self.assertFalse(out.exists())
