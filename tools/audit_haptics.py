from __future__ import annotations

import argparse
import csv
import hashlib
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

# Preserve strings (including long strings) but mask Lua comments without
# shifting line numbers. Literal references inside disabled SG blocks are not
# producer evidence. This remains a static reference audit, not a Lua call graph.
LUA_TOKEN_RE = re.compile(
    r'''"(?:\\[\s\S]|[^"\\])*"|'(?:\\[\s\S]|[^'\\])*'|\[(=*)\[[\s\S]*?\]\1\]|--\[(=*)\[[\s\S]*?\]\2\]|--[^\n]*'''
)


def strip_lua_comments(text: str) -> str:
    return LUA_TOKEN_RE.sub(
        lambda match: re.sub(r"[^\n]", " ", match[0]) if match[0].startswith("--") else match[0],
        text,
    )


def lua_string_literals(text: str):
    """Yield complete Lua 5.1 string values and their opening source lines.

    A literal may be data rather than a sound producer. Do not inspect strings
    embedded inside another string, or infer concatenated/dynamic event values.
    """
    escapes = {"a": "\a", "b": "\b", "f": "\f", "n": "\n",
               "r": "\r", "t": "\t", "v": "\v"}

    def unescape(match):
        value = match[0][1:]
        if value.isascii() and value.isdigit():
            number = int(value)
            if number > 255:
                raise ValueError("invalid Lua 5.1 decimal escape")
            return chr(number)
        if value in ("\r\n", "\n\r", "\r", "\n"):
            return "\n"
        return escapes.get(value, value)

    line, previous = 1, 0
    for match in LUA_TOKEN_RE.finditer(text):
        line += text.count("\n", previous, match.start())
        previous = match.start()
        token = match[0]
        if token.startswith("--"):
            continue
        if token[0] in ('"', "'"):
            try:
                value = re.sub(r"\\(?:[0-9]{1,3}|\r\n|\n\r|[\s\S])", unescape, token[1:-1])
            except ValueError:
                continue
        else:
            delimiter = re.match(r"\[(=*)\[", token)
            width = len(delimiter[0])
            value = token[width:-width]
            value = re.sub(r"\r\n|\n\r|\r", "\n", value)
            if value.startswith("\n"):
                value = value[1:]
        yield value, line


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
    if out.exists():
        raise SystemExit(f"Audit output already exists; choose a new evidence directory: {out}")
    wav_paths = sorted(wav_root.glob("*.wav"))
    if not wav_paths:
        raise SystemExit(f"No WAV files found: {wav_root}")
    effects = []
    for lineno, line in enumerate(strip_lua_comments(haptics.read_text(encoding="utf-8-sig")).splitlines(), 1):
        if line.lstrip().startswith("--"):
            continue
        match = ENTRY_RE.match(line)
        if not match:
            continue
        fields = {"event": match.group(1), "line": lineno}
        for key, raw in FIELD_RE.findall(match.group(2)):
            fields[key] = parse_value(raw)
        effects.append(fields)
    if not effects:
        raise SystemExit(f"No haptics definitions parsed from {haptics}; check the input and table format")

    sources = []
    for path in scripts.rglob("*.lua"):
        if path == haptics:
            continue
        try:
            text = path.read_text(encoding="utf-8-sig", errors="ignore")
        except OSError:
            continue
        sources.append((path, text))

    wavs = []
    for path in wav_paths:
        info = waveform_info(path)
        info.update(path=str(path), name=path.name, tokens=sorted(normalized_tokens(path.stem)))
        wavs.append(info)
    durations = [wav["duration"] for wav in wavs if wav.get("duration") is not None]
    if not durations:
        raise SystemExit(f"No readable WAV files found: {wav_root}")

    unique = {}
    duplicate_defs = defaultdict(list)
    for effect in effects:
        duplicate_defs[effect["event"]].append(effect)
        unique[effect["event"]] = effect

    references = defaultdict(list)
    for path, text in sources:
        relative = str(path.relative_to(scripts)).replace("\\", "/")
        lines = text.splitlines()
        for value, lineno in lua_string_literals(text):
            if value in unique:
                references[value].append({
                    "file": relative,
                    "line": lineno,
                    "text": lines[lineno - 1].strip(),
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
        "haptics_sha256": hashlib.sha256(haptics.read_bytes()).hexdigest(),
        "definition_fields": sorted({key for effect in effects for key in effect if key not in {"line"}}),
        "definitions": len(effects),
        "unique_events": len(unique),
        "duplicate_events": {key: value for key, value in duplicate_defs.items() if len(value) > 1},
        "categories": Counter(str(effect.get("category", "UNSPECIFIED")) for effect in effects),
        "intensities": Counter(str(effect.get("vibration_intensity")) for effect in effects),
        "audio_false": [effect for effect in effects if effect.get("audio") is False],
        "player_only": [effect for effect in effects if effect.get("player_only") is True],
        "with_literal_references": sum(row["reference_count"] > 0 for row in rows),
        "without_literal_references": sum(row["reference_count"] == 0 for row in rows),
        "reference_scope": "Complete Lua string values outside comments; static data references do not prove a sound producer or client observability.",
        "with_waveform_candidates": sum(bool(row["waveforms"]) for row in rows),
        "wav_count": len(wavs),
        "wav_durations": {
            "min": min(durations),
            "max": max(durations),
        },
    }
    # Exclusive creation also closes a race with a second audit using this path.
    out.mkdir(parents=True)
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
