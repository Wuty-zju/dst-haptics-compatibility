name = "DST Haptics Compatibility / 手柄震动兼容"
description = [[
为 Windows 手柄提供兼容震动输出。读取当前 haptics.lua，保留真实声音事件与经过核对的客户端动作反馈；支持 Xbox、DS4、DualSense 及局内设置。默认严格事件；近战与受击近似补偿可单独开启。

Compatibility rumble for Windows controllers using the current haptics.lua, real sound events and audited client action feedback. Supports Xbox, DS4, DualSense and live settings. Melee and hurt estimates are optional and OFF by default.
]]
author = "wuty"
icon_atlas = "modicon.xml"
icon = "modicon.tex"
version = "1.6.0"
api_version = 10
dst_compatible = true
dont_starve_compatible = false
reign_of_giants_compatible = false
client_only_mod = true
all_clients_require_mod = false
server_only_mod = false

-- The configuration screen has no live language context: keep it bilingual.
local function Choices(rows)
    local options = {}
    for i = 1, #rows do
        options[i] = { description = rows[i][1], data = rows[i][2] }
    end
    return options
end

local function Toggle()
    return Choices({ { "开启 / ON", true }, { "关闭 / OFF", false } })
end

local function Percentages()
    local options = {}
    for percent = 0, 200, 5 do
        options[#options + 1] = { description = percent .. "%", data = percent / 100 }
    end
    return options
end

configuration_options = {}
local function Option(name, label, hover, options, default)
    configuration_options[#configuration_options + 1] =
    {
        name = name, label = label, hover = hover,
        options = options, default = default,
    }
end

Option("compatibility", "震动兼容 / Compatibility",
    "开启兼容输出；关闭后恢复原版输出。 / Enable compatibility rumble; OFF restores native output.", Toggle(), true)
Option("language", "语言 / Language",
    "局内提示和日志语言；配置页固定双语。局内更改后立即生效。 / Live prompts and logs update immediately in-world; configuration labels stay bilingual.",
    Choices({ { "中文", "zh" }, { "English", "en" } }), "zh")
Option("output_mode", "输出模式 / Output Mode",
    "兼容模式输出震动；原生模式恢复原版；诊断模式仅记录事件，需开启调试日志。 / Compatibility drives rumble; Native restores the game; Diagnostic logs events with Debug Logging enabled.",
    Choices({ { "兼容 / Compatibility", "compatibility" }, { "原生 / Native", "native" }, { "仅诊断 / Diagnostic", "diagnostic" } }), "compatibility")
Option("strength", "总体强度 / Overall Strength",
    "缩放最终震动强度。 / Scale final rumble strength.", Percentages(), 1)
Option("controller_profile", "手柄类型 / Controller Profile",
    "自动识别；Steam Input 映射不准确时可手动指定。 / Auto-detect, or select manually for Steam Input.",
    Choices({ { "自动 / Auto", "auto" }, { "Xbox / XInput", "xbox" }, { "DualShock 4", "ds4" }, { "PS5 / DualSense", "ds5" } }), "auto")
Option("response_mode", "马达响应 / Motor Response",
    "调整马达体感，不改变事件触发时机。 / Adjust motor response while preserving event timing.",
    Choices({ { "细节 / Detail", "detail" }, { "柔和 / Soft", "soft" }, { "强力 / Punchy", "punchy" } }), "detail")
Option("calibration_test", "测试脉冲 / Calibration Pulse",
    "局内选择弱、中、强播放一次测试；切回关闭后可重复。 / Select Weak, Medium or Strong in-world for one test pulse; return to OFF to repeat.",
    Choices({ { "关闭 / OFF", "off" }, { "弱 / Weak", "weak" }, { "中 / Medium", "medium" }, { "强 / Strong", "strong" } }), "off")
Option("hurt_fallback", "受击近似 / Hurt Estimate",
    "默认关闭，仅使用实际原声路径。开启后按复制的 attacked 信号估计通用受击反馈；该信号不能证明原版播放了此声音，可能与原版不同。 / OFF uses actual sound events. ON estimates generic hurt feedback from replicated attacked signals; these do not prove the native sound played and may differ from native behavior.", Toggle(), false)
Option("combat_fallback", "近战近似 / Melee Estimate",
    "默认关闭。开启后按服务器动作确认与距离估计近战材质反馈；不是服务器伤害确认，未知护甲会跳过。 / OFF by default. ON estimates melee feedback from action acknowledgement and range, not confirmed damage; unknown armour is skipped.", Toggle(), false)

-- Preserve every saved tuning key. All axes use the same 0..200% range.
local scales =
{
    { "tool_scale", "工具反馈 / Tools", "砍树、采矿、锤击、挖地与种植。 / Chop, mine, hammer, dig and plant." },
    { "combat_scale", "战斗反馈 / Combat", "武器挥动与材质命中。 / Weapon swings and material impacts." },
    { "danger_scale", "受伤危险 / Danger", "原版受伤、饥饿、寒冷和过热事件。 / Native hurt, hunger, cold and overheat events." },
    { "player_scale", "玩家交互 / Player Interaction", "装备、采集、箱子和复活等玩家事件。 / Equipment, pickup, chests, revival and other player events." },
    { "boss_scale", "Boss 反馈 / Boss", "实际可观察的 Boss 声音事件。 / Observable native Boss sound events." },
    { "environment_scale", "环境反馈 / Environment", "环境声音事件。 / Environmental sound events." },
    { "ui_scale", "界面反馈 / UI & HUD", "界面事件不受世界距离衰减。 / UI events bypass world-distance attenuation." },
    { "loop_scale", "持续震动 / Loops", "缩放持续声音反馈。 / Scale sustained sound feedback." },
}
for i = 1, #scales do
    local row = scales[i]
    Option(row[1], row[2], row[3], Percentages(), 1)
end
Option("spatial_scale", "空间范围 / Spatial Reach",
    "缩放世界事件的衰减距离。 / Scale world-event falloff distance.",
    Choices({ { "75%", 0.75 }, { "100%", 1 }, { "125%", 1.25 }, { "150%", 1.5 } }), 1)
Option("debug", "调试日志 / Debug Logging",
    "记录事件、强度、时长和过滤原因。 / Log events, strength, duration and filter reasons.", Toggle(), false)

local durations =
{
    { "duration", "总体时长 / Overall Duration" },
    { "tool_duration", "工具时长 / Tool Duration" },
    { "combat_duration", "战斗时长 / Combat Duration" },
    { "danger_duration", "危险时长 / Danger Duration" },
    { "player_duration", "玩家交互时长 / Player Duration" },
    { "boss_duration", "Boss 时长 / Boss Duration" },
    { "environment_duration", "环境时长 / Environment Duration" },
    { "ui_duration", "界面时长 / UI Duration" },
    { "loop_duration", "循环单次时长 / Loop Pulse Duration" },
}
for i = 1, #durations do
    Option(durations[i][1], durations[i][2],
        "100% 为兼容包络基准；0% 关闭该类型。 / 100% uses the compatibility envelope baseline; 0% mutes this type.", Percentages(), 1)
end
Option("controller_adaptation", "手柄适配 / Controller Adaptation",
    "开启设备响应曲线；关闭使用通用输出。 / Apply device response curves, or use generic output.",
    Choices({ { "适配 / Adapted", true }, { "通用 / Generic", false } }), true)
