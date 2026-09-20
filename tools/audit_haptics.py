from __future__ import annotations

import argparse
import csv
import json
import os
import re
import wave
from collections import Counter, defaultdict
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SCRIPTS = PROJECT_ROOT / "work" / "original_scripts" / "scripts"
DEFAULT_WAV_ROOT = Path(r"C:\Program Files (x86)\Steam\steamapps\common\Don't Starve Together\data\haptics\vibration\vibration")
DEFAULT_OUT = PROJECT_ROOT / "work" / "haptics_audit"


ENTRY_RE = re.compile(r"^\s*\{\s*event\s*=\s*\"([^\"]+)\"\s*,(.*?)\}\s*,?.*$")
FIELD_RE = re.compile(r"(\w+)\s*=\s*(\"[^\"]*\"|true|false|-?\d+(?:\.\d+)?)")


def parse_value(raw: str):
    if raw.startswith('"'):
        return raw[1:-1]
    if raw == "true":
        return True
    if raw == "false":
        return False
    return float(raw)


def normalized_tokens(text: str) -> set[str]:
    text = text.lower().replace("dontstarve", "").replace("dst", "")
    parts = re.split(r"[^a-z0-9]+", text)
    stop = {"common", "together", "wilson", "creatures", "sound", "v2", "v3", "new", "test"}
    return {p for p in parts if len(p) > 1 and p not in stop and not p.isdigit()}


def waveform_info(path: Path):
    try:
        with wave.open(str(path), "rb") as wav:
            frames = wav.getnframes()
            rate = wav.getframerate()
            return {
                "duration": round(frames / rate, 6) if rate else None,
                "rate": rate,
                "channels": wav.getnchannels(),
                "width": wav.getsampwidth(),
                "frames": frames,
            }
    except Exception as exc:
        return {"error": str(exc)}


def main():
    parser = argparse.ArgumentParser(description="Audit current DST haptics.lua against extracted Lua sources and shipped WAV assets.")
    parser.add_argument("--scripts", type=Path, default=Path(os.environ.get("DST_ORIGINAL_SCRIPTS", DEFAULT_SCRIPTS)))
    parser.add_argument("--wav-root", type=Path, default=Path(os.environ.get("DST_HAPTICS_WAV_ROOT", DEFAULT_WAV_ROOT)))
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    scripts = args.scripts.resolve()
    haptics = scripts / "haptics.lua"
    wav_root = args.wav_root.resolve()
    out = args.out.resolve()
    if not haptics.exists():
        raise SystemExit(f"haptics.lua not found: {haptics}; pass --scripts or set DST_ORIGINAL_SCRIPTS")
    if not wav_root.exists():
        raise SystemExit(f"haptic WAV directory not found: {wav_root}; pass --wav-root or set DST_HAPTICS_WAV_ROOT")
    out.mkdir(parents=True, exist_ok=True)
    effects = []
    for lineno, line in enumerate(haptics.read_text(encoding="utf-8-sig").splitlines(), 1):
        if line.lstrip().startswith("--"):
            continue
        match = ENTRY_RE.match(line)
        if not match:
            continue
        fields = {"event": match.group(1), "line": lineno}
        for key, raw in FIELD_RE.findall(match.group(2)):
            fields[key] = parse_value(raw)
        effects.append(fields)

    sources = []
    for path in scripts.rglob("*.lua"):
        if path == haptics:
            continue
        try:
            lines = path.read_text(encoding="utf-8-sig", errors="ignore").splitlines()
        except OSError:
            continue
        sources.append((path, lines))

    wavs = []
    for path in wav_root.glob("*.wav"):
        info = waveform_info(path)
        info.update(path=str(path), name=path.name, tokens=sorted(normalized_tokens(path.stem)))
        wavs.append(info)

    unique = {}
    duplicate_defs = defaultdict(list)
    for effect in effects:
        duplicate_defs[effect["event"]].append(effect)
        unique[effect["event"]] = effect

    references = defaultdict(list)
    event_pattern = re.compile("|".join(re.escape(event) for event in sorted(unique, key=len, reverse=True)))
    for path, lines in sources:
        relative = str(path.relative_to(scripts)).replace("\\", "/")
        for lineno, line in enumerate(lines, 1):
            for match in event_pattern.finditer(line):
                references[match.group(0)].append({
                    "file": relative,
                    "line": lineno,
                    "text": line.strip(),
                })

    rows = []
    for event, effect in unique.items():
        refs = references[event]

        event_tokens = normalized_tokens(event)
        leaf_tokens = normalized_tokens(event.rsplit("/", 1)[-1])
        candidates = []
        for wav in wavs:
            wt = set(wav["tokens"])
            if not wt or not event_tokens:
                continue
            overlap = len(event_tokens & wt)
            leaf_overlap = len(leaf_tokens & wt)
            if overlap == 0:
                continue
            precision = overlap / len(wt)
            recall = overlap / len(event_tokens)
            leaf_recall = leaf_overlap / max(1, len(leaf_tokens))
            score = 0.42 * precision + 0.38 * recall + 0.20 * leaf_recall
            if leaf_tokens and leaf_tokens <= wt:
                score += 0.25
            if score >= 0.48:
                candidates.append((round(score, 4), wav))
        candidates.sort(key=lambda item: (-item[0], item[1]["name"]))
        best = candidates[:12]

        rows.append({
            **effect,
            "definition_count": len(duplicate_defs[event]),
            "reference_count": len(refs),
            "references": refs,
            "waveforms": [
                {"score": score, "name": wav["name"], "duration": wav.get("duration")}
                for score, wav in best
            ],
        })

    summary = {
        "definitions": len(effects),
        "unique_events": len(unique),
        "duplicate_events": {key: value for key, value in duplicate_defs.items() if len(value) > 1},
        "categories": Counter(str(effect.get("category", "UNSPECIFIED")) for effect in effects),
        "intensities": Counter(str(effect.get("vibration_intensity")) for effect in effects),
        "audio_false": [effect for effect in effects if effect.get("audio") is False],
        "player_only": [effect for effect in effects if effect.get("player_only") is True],
        "with_literal_references": sum(row["reference_count"] > 0 for row in rows),
        "without_literal_references": sum(row["reference_count"] == 0 for row in rows),
        "with_waveform_candidates": sum(bool(row["waveforms"]) for row in rows),
        "wav_count": len(wavs),
        "wav_durations": {
            "min": min(wav["duration"] for wav in wavs if wav.get("duration") is not None),
            "max": max(wav["duration"] for wav in wavs if wav.get("duration") is not None),
        },
    }
    (out / "audit.json").write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
    (out / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2, default=dict), encoding="utf-8")
    (out / "waveforms.json").write_text(json.dumps(wavs, ensure_ascii=False, indent=2), encoding="utf-8")

    with (out / "events.csv").open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow([
            "event", "category", "vibration_intensity", "audio", "audio_intensity", "player_only",
            "haptics_line", "definition_count", "reference_count", "references", "waveform_candidates",
        ])
        for row in rows:
            writer.writerow([
                row["event"], row.get("category"), row.get("vibration_intensity"), row.get("audio"),
                row.get("audio_intensity"), row.get("player_only", False), row["line"],
                row["definition_count"], row["reference_count"],
                " | ".join(f'{ref["file"]}:{ref["line"]} {ref["text"]}' for ref in row["references"]),
                " | ".join(f'{wave["name"]} ({wave["duration"]}s, score={wave["score"]})' for wave in row["waveforms"]),
            ])

    print(json.dumps(summary, ensure_ascii=False, indent=2, default=dict))


if __name__ == "__main__":
    main()
