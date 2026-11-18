"""Build a snapshot-bound event CSV and a concise compatibility audit summary."""

from __future__ import annotations

import argparse
from collections import Counter
import csv
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import tempfile

from verify import file_hash, lua_test_command, run_command, select_runtime


PROJECT_ROOT = Path(__file__).resolve().parent.parent
NATIVE_FIELDS = (
    "event", "vibration", "vibration_intensity", "audio", "audio_intensity", "player_only", "category",
)
COLUMNS = (
    *NATIVE_FIELDS, "haptics_line", "definition_count", "reference_count", "reference_locations",
    "strict_route", "optional_approximation", "observation_boundary",
    "profile_mode", "profile_kind", "profile_asset_family", "profile_factor", "profile_total_s",
    "loop_interval_s", "loop_pulse_s", "loop_listener_local", "pulses",
    "anonymous_factor", "anonymous_total_s", "anonymous_pulses",
)

# Audited additions to the always-available SoundEmitter hook route. Profile
# classification and pulse figures come only from the Lua exporter.
WORK_EVENTS = {
    "dontstarve/wilson/use_axe_tree", "dontstarve/wilson/use_axe_mushroom",
    "dontstarve/characters/woodie/beaver_chop_tree", "rifts6/rock_tree/chop_normal",
    "dontstarve/wilson/use_pick_rock", "dontstarve_DLC001/common/iceboulder_hit",
    "turnoftides/common/together/moon_glass/mine", "dontstarve/wilson/dig",
    "dontstarve/wilson/hit",
}
BEAM_HANDLES = {"rifts8/shrouden/opticblast_LP": "loop", "rifts8/shrouden/opticblast_big_LP": "bigloop"}


def export_profiles(scripts, lua, lua_deps):
    runtime, checks = select_runtime(lua, lua_deps, PROJECT_ROOT)
    if runtime is None:
        raise ValueError(checks[-1]["reason"])
    exporter = PROJECT_ROOT / "tools" / "export_haptic_profiles.lua"
    command = lua_test_command(runtime, PROJECT_ROOT, exporter, scripts)
    with tempfile.TemporaryDirectory() as directory:
        export = Path(directory) / "profiles.json"
        env = {
            **os.environ,
            "DST_HAPTICS_MOD_ROOT": str(PROJECT_ROOT),
            "DST_ORIGINAL_SCRIPTS": str(scripts),
            "DST_HAPTICS_REPORT_EXPORT": str(export),
        }
        check = run_command("export-haptic-profiles", command, PROJECT_ROOT, env)
        if check["status"] != "PASS":
            message = check.get("error") or (check["stderr"] + check["stdout"]).strip()
            raise ValueError(f"Lua profile export failed: {message}")
        return json.loads(export.read_bytes())


def checked_rows(rows, events):
    if not isinstance(rows, list) or not rows:
        raise ValueError("audit.json must contain a nonempty list of event records")
    indexed = {}
    for row in rows:
        event = row.get("event") if isinstance(row, dict) else None
        if not isinstance(event, str) or not event or event in indexed:
            raise ValueError(f"Invalid or duplicate audit event: {event!r}")
        indexed[event] = row
    if indexed.keys() != events.keys():
        missing = sorted(events.keys() - indexed.keys())
        extra = sorted(indexed.keys() - events.keys())
        raise ValueError(f"Audit and native event sets differ (missing {missing[:4]!r}, extra {extra[:4]!r})")

    for event, row in indexed.items():
        data = events[event]
        native = data["native"]
        for field in NATIVE_FIELDS:
            left, right = row.get(field), native.get(field)
            if ((field in row) != (field in native) or left != right
                    or isinstance(left, bool) != isinstance(right, bool)):
                raise ValueError(f"Audit native field {field} does not match haptics.lua for {event}")
        if type(row.get("definition_count")) is not int or row["definition_count"] != data["definition_count"]:
            raise ValueError(f"Audit definition count does not match haptics.lua for {event}")
        if type(row.get("line")) is not int or row["line"] <= 0:
            raise ValueError(f"Invalid haptics.lua line for {event}")
        yield row, data


def reference_locations(row):
    refs = row.get("references")
    if not isinstance(refs, list) or len(refs) != row.get("reference_count"):
        raise ValueError(f"Audit reference count does not match reference list for {row['event']}")
    locations = []
    for ref in refs:
        if not isinstance(ref, dict):
            raise ValueError(f"Invalid Lua reference for {row['event']}")
        filename = ref.get("file", "")
        path = PurePosixPath(filename) if isinstance(filename, str) else PurePosixPath()
        line = ref.get("line")
        if (path.suffix != ".lua" or path.is_absolute() or ".." in path.parts
                or any(char in filename for char in "\\:\r\n") or type(line) is not int or line <= 0):
            raise ValueError(f"Invalid relative Lua reference for {row['event']}")
        locations.append((path.as_posix(), line))
    return " | ".join(f"{file}:{line}" for file, line in sorted(locations))


def routes(native, profile, has_references):
    event = native["event"]
    if native.get("vibration") is not True:
        return "原版定义未启用震动", "", "兼容层不会输出此事件。"
    strict = ["客户端可见的同名 SoundEmitter 播放"]
    optional = ""
    if event in WORK_EVENTS:
        strict.append("本地工具动作上下文与 performaction 确认")
    if event == "dontstarve/wilson/hungry":
        strict.append("远程客户端 funnyidle 状态与 hungry 动画分支上升沿")
    if event in BEAM_HANDLES:
        strict.append(f"光束 emitter 的真实 {BEAM_HANDLES[event]} 句柄返回 PlayingSound=true")
    if event == "dontstarve/wilson/hit":
        optional = "hurt_fallback=ON 时才用远程 attacked 估计通用受击。原声特例优先。"
    if event.startswith("dontstarve/impacts/impact_") and "_armour_" not in event:
        optional = "combat_fallback=ON 时才用远程 ATTACK 确认、距离与原版材质解析估计。跳过护甲不明的目标。"
    boundary = ("静态字面引用只证明字符串存在。" if has_references
                else "当前未找到静态字面引用。动态或引擎入口仍可能存在。")
    if profile.get("loop"):
        boundary += "持续输出需要具名声音及其生命周期。匿名调用只播放有界短包络。"
        if event in BEAM_HANDLES:
            boundary += "远程客户端能否读到光束句柄及其时序需要实机核验。"
    elif event in WORK_EVENTS:
        boundary += "动作确认绑定本地上下文，不提供逐帧原声证明。"
    else:
        boundary += "引擎复制的一次性声音可能绕过客户端 Lua。"
    return " | ".join(strict), optional, boundary


def pulse_text(pulses):
    # Keep the table machine-readable while formatting Lua floats for display.
    if not pulses:
        return ""
    triples = [",".join(f"{value:.10g}" for value in pulse) for pulse in pulses]
    return "[[" + "],[".join(triples) + "]]"


def csv_row(row, data):
    native, profile = data["native"], data["profile"]
    anonymous = data.get("anonymous", {})
    strict, optional, boundary = routes(native, profile, row["reference_count"] > 0)
    return {
        **{name: str(value).lower() if isinstance(value, bool) else value for name, value in native.items()},
        "haptics_line": row["line"],
        "definition_count": data["definition_count"],
        "reference_count": row["reference_count"],
        "reference_locations": reference_locations(row),
        "strict_route": strict,
        "optional_approximation": optional,
        "observation_boundary": boundary,
        "profile_mode": "named_loop_or_anonymous_bounded" if profile.get("loop") else "one_shot",
        "profile_kind": profile.get("kind"),
        "profile_asset_family": profile.get("asset_family"),
        "profile_factor": format(profile.get("factor", 1), ".10g"),
        "profile_total_s": None if profile.get("loop") else format(profile["total"], ".10g"),
        "loop_interval_s": profile.get("interval"),
        "loop_pulse_s": profile.get("duration") if profile.get("loop") else None,
        "loop_listener_local": str(profile["listener_local"]).lower() if "listener_local" in profile else None,
        "pulses": pulse_text(profile.get("pulses")),
        "anonymous_factor": anonymous.get("factor", 1) if anonymous else None,
        "anonymous_total_s": anonymous.get("total"),
        "anonymous_pulses": pulse_text(anonymous.get("pulses")),
    }


def summary_text(version, payload, rows, native_hash, audit_hash, csv_name):
    referenced = sum(row["reference_count"] > 0 for row in rows)
    categories = Counter(row.get("category", "未设置") for row in rows)
    category_lines = "\n".join(f"| {category} | {count} |" for category, count in sorted(categories.items()))
    defaults = {key: "ON" if value else "OFF" for key, value in payload["defaults"].items()}
    return f"""# DST Haptics Compatibility {version} 全量审计

[逐事件 CSV]({csv_name})记录最后生效的每条定义、原版七字段、静态引用位置和当前兼容包络。空原版字段表示未设置。定义行取自审计输入。

- 原版 `haptics.lua` SHA-256 `{native_hash}`
- 静态 `audit.json` SHA-256 `{audit_hash}`
- 运行时 `modinfo.lua` 版本 `{payload['version']}`

| 项目 | 数量 |
|---|---:|
| 原版定义 | {payload['definitions']} |
| 唯一事件 | {len(rows)} |
| 重复出现的附加定义 | {payload['definitions'] - len(rows)} |
| 有静态 Lua 字面引用的事件 | {referenced} |
| 无静态 Lua 字面引用的事件 | {len(rows) - referenced} |
| `vibration=true` | {sum(row.get('vibration') == 'true' for row in rows)} |
| `audio=false` | {sum(row.get('audio') == 'false' for row in rows)} |
| `player_only=true` | {sum(row.get('player_only') == 'true' for row in rows)} |
| 具名可循环、匿名有界的 profile | {sum(row['profile_mode'] == 'named_loop_or_anonymous_bounded' for row in rows)} |
| 使用 RMS 包络族的事件 | {sum(bool(row['profile_asset_family']) for row in rows)} |

| 原版分类 | 唯一事件数 |
|---|---:|
{category_lines}

### 触发与可观察性

- 严格路径使用客户端可观察的原声，或经审计的工具动作确认、远程饥饿分支和光束句柄。字面引用可能出现在数据表内。绕过客户端 Lua 的引擎复制声音仍可能无法观察。
- `hurt_fallback` 默认 {defaults['hurt_fallback']}，`combat_fallback` 默认 {defaults['combat_fallback']}。各自显式开启后才使用复制受击事件或近战动作确认来估计反馈。复制动作确认无法证明伤害或对应原声。
- `player_only` 先检查本地归属。经过核实的 FrontEnd/FocalPoint 声音、UI 和已审计的世界天气声音不按世界距离衰减。其他空间事件按听者位置衰减。实际输出仍受模式、Profile、暂停、控制器和强度配置影响。

### 兼容包络

- CSV 从 Lua 5.1 执行的运行时 registry、profile 和匿名循环路径取得包络。脉冲数组每项为 [延迟秒数, 时长秒数, 相对幅度]，字段 `profile_total_s` 为运行时声明的总时长。具名循环另列采样间隔和每次脉冲宽度。
- 数值为兼容映射、配置倍率、距离、参数和手柄响应调整前的 profile。部分包络来自已提取的 WAV RMS 采样。报表无法证明逐样本波形、引擎路由或物理马达响应。
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scripts", type=Path, help="Extracted DST scripts (or set DST_ORIGINAL_SCRIPTS)")
    parser.add_argument("--audit", type=Path, required=True, help="audit.json generated from those scripts")
    parser.add_argument("--out", type=Path, required=True, help="New report directory")
    parser.add_argument("--version", help="Report filename and heading version (default: modinfo.lua)")
    runtime = parser.add_mutually_exclusive_group()
    runtime.add_argument("--lua", help="Lua 5.1 executable")
    runtime.add_argument("--lua-deps", type=Path, help="Windows directory containing lua51Original.dll")
    args = parser.parse_args()
    scripts = args.scripts or os.environ.get("DST_ORIGINAL_SCRIPTS")
    if not scripts:
        parser.error("Supply --scripts or set DST_ORIGINAL_SCRIPTS")
    scripts = Path(scripts).resolve()
    out = args.out.absolute()
    if out.exists() or out.is_symlink():
        parser.error(f"Report output already exists; choose a new directory: {out}")

    try:
        native = scripts / "haptics.lua"
        native_hash = file_hash(native)
        audit = args.audit.read_bytes()
        audit_summary = args.audit.with_name("summary.json")
        if audit_summary.is_file():
            expected = json.loads(audit_summary.read_bytes()).get("haptics_sha256")
            if expected is not None and expected != native_hash:
                raise ValueError("Audit haptics.lua hash does not match the supplied scripts")
        payload = export_profiles(scripts, args.lua, args.lua_deps)
        if file_hash(native) != native_hash:
            raise ValueError("haptics.lua changed during report generation")
        version = args.version or payload["version"]
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+\-]*", version):
            raise ValueError("Report version must be a single filename component")
        rows = [csv_row(row, data) for row, data in checked_rows(json.loads(audit), payload["events"])]
        csv_path = out / f"DST-Haptics-Event-Audit-{version}.csv"
        md_path = out / f"DST-Haptics-Audit-Summary-{version}.md"
        summary = summary_text(version, payload, rows, native_hash, hashlib.sha256(audit).hexdigest(), csv_path.name)
        out.mkdir(parents=True)
        with csv_path.open("x", encoding="utf-8-sig", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=COLUMNS)
            writer.writeheader()
            writer.writerows(rows)
        with md_path.open("x", encoding="utf-8") as handle:
            handle.write(summary)
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    print(csv_path)
    print(md_path)


if __name__ == "__main__":
    main()
