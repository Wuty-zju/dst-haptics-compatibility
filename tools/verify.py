"""Read-only validation of maintained source, with optional local DST evidence.

No game files are discovered automatically. Reports are created exclusively so
that rerunning validation cannot replace evidence from a previous run.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from urllib.parse import unquote, urlsplit


PROJECT_ROOT = Path(__file__).resolve().parent.parent
PORTABLE_TESTS = (
    "test_adapter.lua",
    "test_client_action_bridge.lua",
    "test_haptic_parameters.lua",
    "test_haptic_config.lua",
    "test_haptic_mixer.lua",
    "test_runtime_settings.lua",
)
DEFAULT_DLL_DIR = Path(
    r"C:\Program Files (x86)\Steam\steamapps\common\Don't Starve Together\mods\Luajit\deps"
)
SOURCE_DIRECTORIES = ("scripts", "tests", "tools", "docs", ".github", ".codex", "assets")
OUTPUT_LIMIT = 32000


def timestamp():
    return datetime.now(timezone.utc).isoformat()


def result(name, status, **details):
    return {"name": name, "status": status, "time_utc": timestamp(), **details}


def run_command(name, command, root, env=None, timeout=120):
    command = [str(part) for part in command]
    started = time.monotonic()
    try:
        completed = subprocess.run(
            command, cwd=root, env=env, capture_output=True,
            text=True, encoding="utf-8", errors="replace", timeout=timeout,
        )
        return result(
            name, "PASS" if completed.returncode == 0 else "FAIL",
            command=command, exit_code=completed.returncode,
            duration_seconds=round(time.monotonic() - started, 3),
            stdout=completed.stdout[:OUTPUT_LIMIT],
            stderr=completed.stderr[:OUTPUT_LIMIT],
            output_truncated=(len(completed.stdout) > OUTPUT_LIMIT
                              or len(completed.stderr) > OUTPUT_LIMIT),
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return result(
            name, "FAIL", command=command, exit_code=None,
            duration_seconds=round(time.monotonic() - started, 3),
            error=str(exc),
        )


def lua_sources(root):
    """An explicit scope; never walk build, work, outputs or other checkouts."""
    return [root / "modinfo.lua", root / "modmain.lua"] + sorted(
        (root / "scripts").rglob("*.lua")
    ) + sorted((root / "tests").glob("*.lua"))


def source_files(root):
    files = [
        path for path in root.iterdir()
        if path.is_file() and path.suffix not in (".zip", ".log")
    ]
    for directory in SOURCE_DIRECTORIES:
        files.extend(
            path for path in (root / directory).rglob("*")
            if path.is_file() and "__pycache__" not in path.parts
            and ".pytest_cache" not in path.parts
        )
    return sorted(set(files))


def file_hash(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def select_runtime(lua, lua_deps, root):
    checks = []
    # Explicit executable/dependency choices must never silently fall back.
    if lua:
        candidates = [lua]
    elif lua_deps:
        candidates = []
    else:
        candidates = list(dict.fromkeys(
            found for name in ("lua5.1", "lua51", "lua")
            if (found := shutil.which(name))
        ))
    for executable in candidates:
        probe = run_command(
            "lua-runtime", [executable, "-e", "io.write(_VERSION)"], root,
        )
        if probe["status"] == "PASS" and probe.get("stdout", "").strip() == "Lua 5.1":
            probe["version"] = "Lua 5.1"
            checks.append(probe)
            return {"kind": "executable", "executable": str(executable)}, checks
        probe["reason"] = "The executable must report exactly Lua 5.1."
        probe["status"] = "FAIL" if lua else "SKIP"
        checks.append(probe)
        if lua:
            return None, checks

    deps = Path(lua_deps or os.environ.get("DST_LUA51_DEPS") or DEFAULT_DLL_DIR).resolve()
    dll = deps / "lua51Original.dll"
    if os.name == "nt" and dll.is_file():
        checks.append(result(
            "lua-runtime", "PASS", backend="Windows Lua 5.1 DLL",
            path=str(dll), sha256=file_hash(dll),
        ))
        return {"kind": "dll", "deps": str(deps)}, checks
    checks.append(result(
        "lua-runtime", "FAIL",
        reason="No usable Lua 5.1 runtime; pass --lua or Windows --lua-deps.",
        dll_path=str(dll) if os.name == "nt" else None,
    ))
    return None, checks


def lua_test_command(runtime, root, test_name, original_scripts=None):
    test = root / "tests" / test_name
    if runtime["kind"] == "executable":
        return [runtime["executable"], str(test)]
    command = [
        sys.executable, "-B", str(root / "tools" / "run_lua51.py"),
        str(test), "--mod-root", str(root), "--lua-deps", runtime["deps"],
    ]
    if original_scripts is not None:
        command += ["--original-scripts", str(original_scripts)]
    return command


def lua_string(value):
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace(
        "\n", "\\n"
    ).replace("\r", "\\r") + '"'


def check_lua(root, runtime, original_scripts):
    checks = []
    env = os.environ.copy()
    env["DST_HAPTICS_MOD_ROOT"] = str(root)
    env.pop("DST_ORIGINAL_SCRIPTS", None)
    if original_scripts is not None:
        env["DST_ORIGINAL_SCRIPTS"] = str(original_scripts)
    if runtime is None:
        checks.append(result("lua-syntax", "SKIP", reason="Lua 5.1 runtime unavailable."))
        for name in PORTABLE_TESTS:
            checks.append(result(name, "SKIP", reason="Lua 5.1 runtime unavailable."))
    elif runtime["kind"] == "dll":
        checks.append(run_command("lua-syntax", [
            sys.executable, "-B", str(root / "tools" / "validate_lua.py"),
            "--mod-root", str(root), "--lua-deps", runtime["deps"],
        ], root, env))
    else:
        for path in lua_sources(root):
            # Passing a file after -e would execute it. Compile it inside -e.
            checks.append(run_command(
                "lua-syntax:" + path.relative_to(root).as_posix(),
                [runtime["executable"], "-e", "assert(loadfile(" + lua_string(str(path)) + "))"],
                root, env,
            ))
    if runtime is not None:
        for name in PORTABLE_TESTS:
            checks.append(run_command(name, lua_test_command(runtime, root, name), root, env))

    original = None
    if original_scripts is None:
        checks.append(result(
            "test_original_haptics.lua", "SKIP",
            reason="Provide --original-scripts or DST_ORIGINAL_SCRIPTS for current game data.",
        ))
    else:
        haptics = original_scripts / "haptics.lua"
        original = {"scripts_directory": str(original_scripts), "haptics_sha256": None, "counts": None}
        if not haptics.is_file():
            checks.append(result("test_original_haptics.lua", "FAIL", reason=f"Missing {haptics}"))
        else:
            original["haptics_sha256"] = file_hash(haptics)
            if runtime is None:
                checks.append(result("test_original_haptics.lua", "SKIP", reason="Lua 5.1 runtime unavailable."))
            else:
                check = run_command(
                    "test_original_haptics.lua",
                    lua_test_command(runtime, root, "test_original_haptics.lua", original_scripts),
                    root, env,
                )
                counts = re.search(r"definitions=(\d+) vibrating=(\d+)", check.get("stdout", ""))
                if counts:
                    original["counts"] = {"definitions": int(counts[1]), "vibrating": int(counts[2])}
                checks.append(check)
    return checks, original


def mask_markdown_code(text):
    def blank(value):
        return re.sub(r"[^\n]", " ", value)

    lines = []
    fence = None
    for line in text.splitlines(keepends=True):
        match = re.match(r"^ {0,3}(`{3,}|~{3,})(.*)$", line)
        if fence is None and match:
            fence = match[1]
            lines.append(blank(line))
        elif fence is not None:
            lines.append(blank(line))
            if match and match[1][0] == fence[0] and len(match[1]) >= len(fence) and not match[2].strip():
                fence = None
        else:
            lines.append(line)
    return re.sub(
        r"(?<!`)(`+)(?!`)([\s\S]*?)(?<!`)\1(?!`)",
        lambda match: blank(match[0]), "".join(lines),
    )


def markdown_targets(text):
    text = mask_markdown_code(text)
    # Lightweight file-target checks; heading anchors and remote URLs are not fetched.
    patterns = (
        r"!?\[[^\]\n]*\]\(\s*(?:<([^>\n]+)>|([^\s)]+))(?:\s+[\"'][^\n]*?[\"'])?\s*\)",
        r"^ {0,3}\[[^\]\n]+\]:\s*(?:<([^>\n]+)>|([^\s]+))",
    )
    for pattern in patterns:
        for match in re.finditer(pattern, text, re.MULTILINE):
            target = match[1] if match[1] is not None else match[2]
            parsed = urlsplit(target)
            if parsed.scheme or parsed.netloc or not parsed.path or parsed.path.startswith(("/", "\\")):
                continue
            yield text.count("\n", 0, match.start()) + 1, unquote(parsed.path)


def check_markdown(files, root):
    broken = []
    count = 0
    for path in files:
        if path.suffix.lower() != ".md":
            continue
        for line, target in markdown_targets(path.read_text(encoding="utf-8-sig")):
            count += 1
            if not (path.parent / target).exists():
                broken.append({"file": path.relative_to(root).as_posix(), "line": line, "target": target})
    return result("markdown-relative-links", "FAIL" if broken else "PASS", checked_targets=count, broken=broken)


def check_python(files, root):
    errors = []
    count = 0
    for path in files:
        if path.suffix != ".py":
            continue
        count += 1
        try:
            compile(path.read_text(encoding="utf-8-sig"), str(path), "exec")
        except (SyntaxError, UnicodeError) as exc:
            errors.append({"file": path.relative_to(root).as_posix(), "error": str(exc)})
    return result("python-syntax", "FAIL" if errors else "PASS", checked_files=count, errors=errors)


def check_toml(files, root):
    paths = [path for path in files if path.suffix == ".toml"]
    if not paths:
        return result("toml-syntax", "SKIP", reason="No maintained TOML files.")
    try:
        import tomllib
    except ImportError:
        return result("toml-syntax", "SKIP", reason="tomllib requires Python 3.11 or later.")
    errors = []
    for path in paths:
        try:
            tomllib.loads(path.read_text(encoding="utf-8-sig"))
        except (tomllib.TOMLDecodeError, UnicodeError) as exc:
            errors.append({"file": path.relative_to(root).as_posix(), "error": str(exc)})
    return result("toml-syntax", "FAIL" if errors else "PASS", checked_files=len(paths), errors=errors)


def collect_report(args, root):
    started = time.monotonic()
    report = {"schema_version": 1, "started_utc": timestamp(), "root": str(root), "checks": []}
    files = source_files(root)
    if args.report:
        files = [path for path in files if path.resolve() != args.report.resolve()]
    report["source_sha256"] = {path.relative_to(root).as_posix(): file_hash(path) for path in files}
    baseline = run_command("git-baseline", ["git", "rev-parse", "HEAD"], root, timeout=15)
    if baseline["status"] == "PASS":
        report["baseline_git_sha"] = baseline["stdout"].strip()
    else:
        baseline["status"] = "SKIP"
        baseline["reason"] = "Git baseline unavailable; source hashes remain recorded."
        report["baseline_git_sha"] = None
    report["checks"].append(baseline)
    status = run_command("git-worktree-status", ["git", "status", "--porcelain", "--untracked-files=normal"], root, timeout=15)
    if status["status"] != "PASS":
        status["status"] = "SKIP"
    report["checks"].append(status)

    runtime, checks = select_runtime(args.lua, args.lua_deps, root)
    report["runtime"] = runtime
    report["checks"].extend(checks)
    original_value = args.original_scripts or os.environ.get("DST_ORIGINAL_SCRIPTS")
    original_path = Path(original_value).resolve() if original_value else None
    checks, original = check_lua(root, runtime, original_path)
    report["checks"].extend(checks)
    report["original_haptics"] = original
    report["checks"].append(check_python(files, root))
    python_tests = list((root / "tests").glob("test_*.py"))
    if python_tests:
        env = os.environ.copy()
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        report["checks"].append(run_command("python-unittests", [
            sys.executable, "-B", "-m", "unittest", "discover",
            "-s", str(root / "tests"), "-p", "test_*.py",
        ], root, env))
    else:
        report["checks"].append(result("python-unittests", "SKIP", reason="No Python unit tests."))
    report["checks"].append(check_markdown(files, root))
    report["checks"].append(check_toml(files, root))
    report["finished_utc"] = timestamp()
    report["duration_seconds"] = round(time.monotonic() - started, 3)
    report["status"] = "FAIL" if any(check["status"] == "FAIL" for check in report["checks"]) else "PASS"
    report["counts"] = {status: sum(check["status"] == status for check in report["checks"]) for status in ("PASS", "FAIL", "SKIP")}
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua", help="Lua 5.1 executable; an invalid explicit choice is a failure")
    parser.add_argument("--lua-deps", type=Path, help="Explicit Windows directory containing lua51Original.dll")
    parser.add_argument("--original-scripts", type=Path, help="Current extracted DST scripts (otherwise DST_ORIGINAL_SCRIPTS)")
    parser.add_argument("--report", type=Path, help="Create a new JSON evidence file; never overwrite")
    args = parser.parse_args(argv)
    handle = None
    if args.report:
        try:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            handle = args.report.open("x", encoding="utf-8", newline="\n")
        except OSError as exc:
            print(json.dumps(result("report-file", "FAIL", error=str(exc)), ensure_ascii=False))
            return 2
    try:
        report = collect_report(args, PROJECT_ROOT)
    except Exception as exc:
        report = {"status": "FAIL", "checks": [result("verification-error", "FAIL", error=f"{type(exc).__name__}: {exc}")]}
    rendered = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    try:
        if handle:
            handle.write(rendered)
    finally:
        if handle:
            handle.close()
    print(rendered, end="")
    return 1 if report["status"] == "FAIL" else 0


if __name__ == "__main__":
    raise SystemExit(main())
