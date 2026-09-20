from __future__ import annotations

import argparse
import json
import math
import os
import statistics
import struct
import wave
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_WAV_ROOT = Path(r"C:\Program Files (x86)\Steam\steamapps\common\Don't Starve Together\data\haptics\vibration\vibration")
DEFAULT_OUT = PROJECT_ROOT / "work" / "haptics_audit" / "core_envelopes.json"

FAMILIES = {
    "chop_tree": ("chop_tree_",),
    "chop_mushroom": ("chop_mushtree_",),
    "mine_rock": ("pickaxe_hitrock_",),
    "mine_ice": ("mine_iceboulder_",),
    "mine_moonglass": ("moonglass_mine_",),
    "dig": ("dig_",),
    "impact_flesh": ("impact_flesh_dull_",),
    "attack_whoosh": ("attack_whoosh_",),
    "hungry": ("hungry_",),
    "freeze": ("freezeoverlay_",),
    "heat": ("heatwave_level",),
}


def read_mono(path: Path):
    with wave.open(str(path), "rb") as wav:
        rate = wav.getframerate()
        channels = wav.getnchannels()
        width = wav.getsampwidth()
        raw = wav.readframes(wav.getnframes())
    if width == 2:
        samples = struct.unpack("<" + "h" * (len(raw) // 2), raw)
        scale = 32768.0
    elif width == 1:
        samples = tuple(value - 128 for value in raw)
        scale = 128.0
    else:
        raise ValueError(f"unsupported width {width}: {path}")
    mono = [sum(abs(samples[i + c]) for c in range(channels)) / channels / scale for i in range(0, len(samples), channels)]
    return rate, mono


def rms_bins(path: Path, bin_seconds: float = 0.05):
    rate, samples = read_mono(path)
    size = max(1, round(rate * bin_seconds))
    result = []
    for start in range(0, len(samples), size):
        chunk = samples[start:start + size]
        result.append(math.sqrt(sum(value * value for value in chunk) / len(chunk)))
    peak = max(result) if result else 1
    return [value / peak for value in result]


def main():
    parser = argparse.ArgumentParser(description="Down-sample shipped DST haptic WAV families into normalized RMS envelopes.")
    parser.add_argument("--wav-root", type=Path, default=Path(os.environ.get("DST_HAPTICS_WAV_ROOT", DEFAULT_WAV_ROOT)))
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    wav_root = args.wav_root.resolve()
    out = args.out.resolve()
    if not wav_root.exists():
        raise SystemExit(f"haptic WAV directory not found: {wav_root}; pass --wav-root or set DST_HAPTICS_WAV_ROOT")
    result = {}
    paths = list(wav_root.glob("*.wav"))
    for family, prefixes in FAMILIES.items():
        selected = [path for path in paths if any(path.name.lower().startswith(prefix) for prefix in prefixes)]
        envelopes = [rms_bins(path) for path in selected]
        length = max((len(envelope) for envelope in envelopes), default=0)
        median = []
        for index in range(length):
            values = [envelope[index] for envelope in envelopes if index < len(envelope)]
            median.append(round(statistics.median(values), 4) if values else 0)
        result[family] = {
            "files": [path.name for path in selected],
            "bin_seconds": 0.05,
            "duration_median": round(statistics.median(len(envelope) * 0.05 for envelope in envelopes), 3) if envelopes else None,
            "envelope": median,
        }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
