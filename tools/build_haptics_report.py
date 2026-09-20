from __future__ import annotations

import argparse
import csv
import json
from collections import Counter
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_AUDIT = PROJECT_ROOT / "work" / "haptics_audit" / "audit.json"
DEFAULT_OUT = PROJECT_ROOT / "outputs"


WORK_EVENTS = {
    "dontstarve/wilson/use_axe_tree",
    "dontstarve/wilson/use_axe_mushroom",
    "dontstarve/characters/woodie/beaver_chop_tree",
    "rifts6/rock_tree/chop_normal",
    "dontstarve/wilson/use_pick_rock",
    "dontstarve_DLC001/common/iceboulder_hit",
    "turnoftides/common/together/moon_glass/mine",
    "dontstarve/wilson/dig",
}


def is_loop(event: str) -> bool:
    lower = event.lower()
    return "_lp" in lower or "/loop" in lower or "loop_" in lower


def is_ui(row: dict) -> bool:
    return row.get("category") == "UI" or "/hud/" in row["event"].lower()


def asset_family(event: str) -> str | None:
    lower = event.lower()
    if "wilson/hungry" in lower:
        return "Hungry 原版 WAV RMS 包络（约 1.2 s 有效段）"
    if "/freeze_" in lower:
        return "Freeze overlay 原版 WAV RMS 包络（约 1.6 s）"
    if "hud_hot_level" in lower:
        return "Heatwave 原版 WAV RMS 包络（约 3.0 s）"
    if any(value in lower for value in ("use_axe_tree", "beaver_chop_tree", "rock_tree/chop")):
        return "Chop tree 原版 WAV RMS 包络（约 0.2 s）"
    if "use_axe_mushroom" in lower:
        return "Chop mushtree 原版 WAV RMS 包络（约 0.2 s）"
    if "use_pick_rock" in lower:
        return "Pickaxe rock 原版 WAV RMS 包络（约 0.8 s）"
    if "iceboulder_hit" in lower:
        return "Mine ice 原版 WAV RMS 包络（约 1.0 s）"
    if "moon_glass/mine" in lower:
        return "Moonglass mine 原版 WAV RMS 包络（约 0.5 s）"
    if "/dig" in lower:
        return "Dig 原版 WAV RMS 包络（约 0.3 s）"
    if "/impacts/impact_" in lower:
        return "Impact 原版 WAV RMS 包络（约 0.5 s）+ 原版材质/尺寸/利钝系数"
    if any(value in lower for value in ("attack_whoosh", "attack_weapon", "/swing", "_swing")):
        return "Attack whoosh/weapon 原版 WAV RMS 包络（约 0.7 s 上限）"
    return None


def semantic_profile(row: dict) -> str:
    event = row["event"].lower()
    direct = asset_family(event)
    if direct:
        return direct
    if is_loop(event):
        return "具名循环：85 ms 更新、100 ms 连续脉冲；KillSound/音量/实体/暂停/卸载控制生命周期"
    if is_ui(row):
        return "UI 短触点；重要 UI 动画使用双脉冲"
    if any(value in event for value in ("roar", "taunt", "scream", "supernova", "finale")):
        return "咆哮/蓄力三段包络（上升—峰值—衰减）"
    if any(value in event for value in ("explode", "explosion", "slam", "groundpound", "ground_pound", "death_fall", "bodyfall", "smash", "breach")):
        return "爆炸/重击三段冲击包络"
    if row.get("category") == "DANGER" or any(value in event for value in ("/hit", "hurt", "shocked")):
        return "危险/受击三段衰减包络"
    if any(value in event for value in ("chop", "use_axe", "use_pick", "hammer", "plant")):
        return "工具双脉冲包络"
    if any(value in event for value in ("impact_", "_hit", "/hit_")):
        return "命中双脉冲包络"
    if any(value in event for value in ("footstep", "/step", "_step", "land")):
        return "脚步/落地双脉冲包络"
    if any(value in event for value in ("whoosh", "swing", "attack_", "/attack")):
        return "挥动/攻击双脉冲包络"
    if row.get("category") == "BOSS":
        return "Boss 双段重脉冲包络"
    if row.get("category") == "ENVIRONMENT":
        return "环境双段脉冲包络"
    return "通用单脉冲包络"


def source_realm(refs: list[dict]) -> str:
    if not refs:
        return "unresolved"
    client_prefixes = ("widgets/", "screens/", "frontend.lua", "stategraphs/SGwilson_client.lua")
    has_client = any(ref["file"].startswith(client_prefixes) for ref in refs)
    has_serverish = any(ref["file"].startswith(("stategraphs/", "components/", "brains/", "prefabs/")) and not ref["file"].endswith("player_classified.lua") for ref in refs)
    if has_client and has_serverish:
        return "mixed"
    if has_client:
        return "client"
    if has_serverish:
        return "server_or_shared"
    return "data_or_shared"


def current_trigger(row: dict) -> tuple[str, str]:
    event = row["event"]
    if event == "dontstarve/wilson/hungry":
        return "本地 ThePlayer hungry 动画进入沿桥接；不依赖声音（原版 audio=false）", "高：本地语义准确；波形为原版 WAV 降采样"
    if event == "dontstarve/wilson/hit":
        return "客户端原声钩子 + player_classified 的 attacked 服务器脉冲；锤击由成功动作桥接", "高但非逐分支完美：attacked 无 stimuli 字段，特殊受击仍优先由各自声音事件覆盖"
    if event in WORK_EVENTS:
        return "客户端原声钩子 + player_classified performaction 回传后的工作事件解析", "高：取消/失败动作不震；目标特殊材质按原版标签选择"
    if event.startswith("dontstarve/impacts/impact_"):
        return "客户端原声钩子 + 服务器回传 ATTACK 后的 client-safe CanHitTarget 等价校验与原版材质解析", "中高：挥空被过滤；NPC 服务端隐藏护甲/AOE 特例无法由纯客户端完全获知"
    if is_loop(event):
        return "SoundEmitter 具名循环钩子；PlayingSound、SetVolume、KillSound/KillAllSounds 驱动", "高（客户端 Lua 可见循环）；纯服务端直接复制且无 Lua 回调的循环受引擎边界限制"
    realm = source_realm(row.get("references", []))
    if realm == "client":
        return "SoundEmitter.PlaySound / PlaySoundWithParams 原事件 O(1) 索引钩子", "高：客户端 Lua 原调用、参数与返回值不改变"
    if realm == "mixed":
        return "客户端 Lua 路径由 SoundEmitter 钩子精确处理；服务端直接复制路径依赖同事件是否也有客户端回调", "混合：客户端路径精确，纯服务端路径存在引擎可观察性限制"
    if realm == "server_or_shared":
        return "客户端可见的同名 SoundEmitter 调用由钩子处理；纯服务端直接复制声音无法被 Lua 通用枚举", "条件覆盖：事件表语义完整，触发可观察性由引擎路径决定"
    if realm == "unresolved":
        return "事件仍动态入索引；出现客户端 SoundEmitter 调用时自动处理", "保留未来/动态入口；当前源码无字面触发点，不能伪造触发"
    return "SoundEmitter 原事件钩子（动态/数据表选声同样按最终事件匹配）", "高（客户端调用可见时）"


def original_logic(row: dict) -> str:
    refs = row.get("references", [])
    if refs:
        evidence = "；".join(f'{ref["file"]}:{ref["line"]} {ref["text"]}' for ref in refs[:3])
        if len(refs) > 3:
            evidence += f"；另 {len(refs) - 3} 处"
    else:
        evidence = "当前 Lua 源码无字面引用（可能由动态变量、资源/引擎路径触发，或为保留定义）"
    return f'haptics.lua 第 {row["line"]} 行注册；触发证据：{evidence}'


def spatial_logic(row: dict) -> str:
    if row.get("player_only") is True:
        return "要求 emitter entity == ThePlayer；原版明确由本地 FrontEnd/FocalPoint HUD 发出的少数事件视为本地上下文；其它玩家/NPC 过滤"
    if is_ui(row):
        return "UI/HUD 非空间，强度不随世界距离衰减"
    category = row.get("category") or "PLAYER"
    ranges = {"PLAYER": "5–26", "DANGER": "7–34", "ENVIRONMENT": "8–46", "BOSS": "12–64"}
    return f'{category} 世界空间平滑衰减，默认近—远 {ranges.get(category, "5–26")} 单位；超距归零，可由 Spatial Reach 缩放'


def interaction_guard(row: dict) -> str:
    guards = ["原版 Controller Vibration=ON", "Mod=ON", "活动手柄已连接", "非暂停", "同事件/实体/实例短窗去重"]
    if not is_ui(row) and row.get("player_only") is not True:
        guards.append("空间距离过滤")
    if row.get("player_only") is True:
        guards.append("本地玩家归属过滤")
    return "；".join(guards)


def main():
    parser = argparse.ArgumentParser(description="Build the complete original-vs-current DST haptics audit table.")
    parser.add_argument("--audit", type=Path, default=DEFAULT_AUDIT)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--version", default="1.3.0")
    args = parser.parse_args()
    version = args.version
    args.out.mkdir(parents=True, exist_ok=True)
    rows = json.loads(args.audit.read_text(encoding="utf-8"))
    csv_path = args.out / f"DST-Haptics-Event-Audit-{version}.csv"
    headers = [
        "序号", "原版 event", "category", "vibration_intensity", "audio", "audio_intensity", "player_only",
        "haptics.lua 行", "重复定义数", "源码字面引用数", "原版原始逻辑/证据", "目前实现的触发逻辑",
        "正常交互保护", "空间/player_only 逻辑", "目前具体震动方式", "保真度与限制",
    ]
    with csv_path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=headers)
        writer.writeheader()
        for index, row in enumerate(rows, 1):
            trigger, fidelity = current_trigger(row)
            writer.writerow({
                "序号": index,
                "原版 event": row["event"],
                "category": row.get("category", "UNSPECIFIED"),
                "vibration_intensity": row.get("vibration_intensity"),
                "audio": row.get("audio"),
                "audio_intensity": row.get("audio_intensity"),
                "player_only": row.get("player_only", False),
                "haptics.lua 行": row["line"],
                "重复定义数": row["definition_count"],
                "源码字面引用数": row["reference_count"],
                "原版原始逻辑/证据": original_logic(row),
                "目前实现的触发逻辑": trigger,
                "正常交互保护": interaction_guard(row),
                "空间/player_only 逻辑": spatial_logic(row),
                "目前具体震动方式": semantic_profile(row),
                "保真度与限制": fidelity,
            })

    categories = Counter(row.get("category", "UNSPECIFIED") for row in rows)
    routes = Counter(source_realm(row.get("references", [])) for row in rows)
    audio_false = sum(row.get("audio") is False for row in rows)
    player_only = sum(row.get("player_only") is True for row in rows)
    loops = sum(is_loop(row["event"]) for row in rows)
    direct = sum(asset_family(row["event"]) is not None for row in rows)
    referenced = sum(row.get("reference_count", 0) > 0 for row in rows)

    md_path = args.out / f"DST-Haptics-Audit-Summary-{version}.md"
    md_path.write_text(f"""# DST Haptics Compatibility {version} — 全量审计摘要

审计基准：本机当前 `scripts/haptics.lua` 与解包后的原版 Lua 源码；定义 492 条，唯一 event {len(rows)} 条。逐事件明细见同目录 CSV。

## 全量统计

| 项目 | 数量 | 结论 |
|---|---:|---|
| 唯一原版 event | {len(rows)} | 全部动态进入 O(1) 索引，无手抄事件白名单 |
| 有 Lua 字面触发证据 | {referenced} | 明细记录文件、行号和原始调用 |
| 无字面引用 | {len(rows) - referenced} | 保留动态/资源/未来入口，不伪造触发 |
| `audio=false` | {audio_false} | 仍保留震动；Hungry 另设状态桥，其余 UI/地面移动仍由 PlaySound 调用进入 |
| `player_only=true` | {player_only} | 严格要求 emitter 对应本地 ThePlayer |
| `_LP`/loop | {loops} | 具名生命周期管理，停止、静音、暂停和卸载清理 |
| 直接取样本机 Haptic WAV 包络的语义事件 | {direct} | 工具、命中、挥动、饥饿、寒冷、过热 |

## 分类与当前机制

| 原版分类 | 唯一事件数 | 原版逻辑 | 当前实现 | 防止“傻震” |
|---|---:|---|---|---|
| DANGER | {categories['DANGER']} | Wilson 受击、饥饿、Charlie、冻伤/过热等；原版表决定强度和 player_only | 原声钩子；Hungry 动画进入沿；受击用服务器 attacked 脉冲 | 排除普通 healthdelta（饥饿、建造耗血、治疗）；本地玩家限制；暂停/总开关 |
| PLAYER | {categories['PLAYER']} | 移动、交互、装备、复活、采集、工具、挥动和 84 类材质 impact | 原声钩子；工作用 performaction 回传；近战 impact 用 client-safe 命中等价校验 | 不监听 A/X；动作取消/失败不震；挥空无材质 impact；挥动仍尊重原版事件 |
| ENVIRONMENT | {categories['ENVIRONMENT']} | 地震、裂隙、船/地形、环境实体和新内容 | 客户端可见原声事件动态匹配 | 8–46 单位平滑衰减，远处归零 |
| BOSS | {categories['BOSS']} | 脚步、重击、落地、咆哮、技能、阶段/死亡 | 客户端可见原声事件动态匹配，循环按具名 sound 生命周期 | 12–64 单位平滑衰减；同实体短窗去重；纯服务端无 Lua 回调的事件不伪造 |
| UI | {categories['UI']} | 菜单、HUD、礼物、制作、图鉴等 | FrontEnd/FocalPoint SoundEmitter 精确钩子 | 不做世界距离衰减；仍服从原版总开关和去重 |
| UNSPECIFIED | {categories['UNSPECIFIED']} | 原版未填 category 的 HUD 条目 | event 路径识别为 UI | 非空间；不错误套用世界距离 |

## 关键原版逻辑与实现对照

| 机制 | 原版原始逻辑 | {version} 实现 |
|---|---|---|
| 砍树 | 目标 `workable` 成功回调在树的 SoundEmitter 播放 axe/mushroom/beaver/rock-tree 事件 | 捕获本地动作上下文，仅在 `player_classified.performaction` 回传后按目标标签发出同一个 haptics event |
| 采矿 | `PlayMiningFX` 在动作帧按 frozen/moonglass/crystal 选择三个原版事件 | 服务器动作回传后按同一标签顺序选择；取消动作不震 |
| 锤击/挖地 | SGwilson 动作帧播放 `wilson/hit` 或 `wilson/dig` | 成功动作回传触发；锤皮肤音若在 haptics.lua 中存在则优先 |
| 武器挥动 | SGwilson_client 在攻击开始播放 whoosh/weapon/角色专属声音，挥空也可能存在 | 直接钩原始客户端声；不把挥动伪装成命中 |
| 近战命中 | `Combat:DoAttack` 先 `CanHitTarget`；成功路径由目标 `GetImpactSound` 按护甲、墙、物体、生物材质/尺寸/利钝播放 | ATTACK 回传后复刻 release 版 client-safe 3D 距离与 0.5 预测容差，再调用原版 resolver；本地可见装备按原版护甲优先级解析 |
| 玩家受击 | `Combat:GetAttacked_Internal` 推送 `attacked`，SGwilson 根据状态播放 hit/电击/特例 | 使用 player_classified 的服务器 attacked 脉冲而不是“任何掉血”；特殊声音仍由原声钩子覆盖 |
| Boss/环境 | Boss/环境实体 SG 或 prefab 在具体动画帧播放已登记声音 | 对客户端 Lua 可见调用按 event 精确触发并空间衰减；引擎直接复制且不回到 Lua 的一发声音是纯客户端 API 的明确边界 |
| 循环 | `PlaySound(event,name)` 开始，`KillSound(name)`/状态退出停止，SetVolume 可变 | 同名注册、`PlayingSound` 复核、音量跟随、失效/暂停/卸载即时清理 |
| 强度 | 原版 `vibration_intensity`（0.5/1/1.5/2/2.5/3/10）+ 原始 WAV | 单调非饱和映射 `1-exp(-0.35*x)`，再乘 WAV 包络、分类/总倍率、距离与手柄校准 |
| Xbox/DS4/DS5 | 原版通过当前输入设备输出 | 同一事件语义；按 DST 设备类型 1/2/7/11 选择 Legacy Rumble 脉冲时长/增益校准 |

## 第一性原理结论

事件的唯一事实源仍是当前游戏 `haptics.lua`；Mod 不从按键或玩法状态另造一套事件。只有原版事件已经发生、或服务器复制信号足以证明原版动作路径成立时才桥接。空间、归属、去重、循环生命周期和原版总开关均在输出前处理。

无法由纯 Lua 完全恢复的是两项：原始 WAV 的逐采样左右马达波形，以及完全绕过客户端 Lua 的服务器复制一发声音。前者已用本机 WAV 的 RMS 包络近似；后者不会用“看见 Boss 动画就猜一次”来制造误震，明细表逐项标为条件覆盖。
""", encoding="utf-8")
    print(csv_path)
    print(md_path)


if __name__ == "__main__":
    main()
