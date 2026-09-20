name = "DST Haptics Compatibility / 手柄震动兼容"
description = [[
修复 Windows 下原版 TheHaptics 无输出的问题。动态读取当前版本 haptics.lua，补齐服务器声音缺口，提供 Xbox/DS4/DualSense 输出模式和可即时生效的局内细粒度配置。

Fixes silent native TheHaptics output on Windows. Uses the current haptics.lua plus replicated action bridges, controller-family output profiles, and live in-world configuration.
]]
author = "Local compatibility build"
version = "1.2.0"

api_version = 10
dst_compatible = true
dont_starve_compatible = false
reign_of_giants_compatible = false

client_only_mod = true
all_clients_require_mod = false
server_only_mod = false

local function ScaleOptions()
    return
    {
        { description = "关闭 / OFF", data = 0.00 },
        { description = "50%", data = 0.50 },
        { description = "75%", data = 0.75 },
        { description = "100%", data = 1.00 },
        { description = "125%", data = 1.25 },
        { description = "150%", data = 1.50 },
    }
end

configuration_options =
{
    {
        name = "compatibility",
        label = "震动适配 / Vibration Compatibility",
        hover = "开启兼容输出；关闭时不注入任何声音钩子，并保留原版行为。 / Enable compatibility output; OFF leaves native behavior untouched.",
        options =
        {
            { description = "开启 / ON", data = true },
            { description = "关闭 / OFF", data = false },
        },
        default = true,
    },
    {
        name = "language",
        label = "语言 / Language",
        hover = "运行时日志语言。配置页文本固定为双语；更改后重新载入 Mod 生效。 / Runtime log language. Config labels stay bilingual; reload the mod after changing.",
        options =
        {
            { description = "中文", data = "zh" },
            { description = "English", data = "en" },
        },
        default = "zh",
    },
    {
        name = "strength",
        label = "总体震动强度 / Overall Strength",
        hover = "在保留原版相对层级的基础上缩放最终输出。 / Scales final output while preserving original relative levels.",
        options =
        {
            { description = "50%", data = 0.50 },
            { description = "75%", data = 0.75 },
            { description = "100%", data = 1.00 },
            { description = "125%", data = 1.25 },
            { description = "150%", data = 1.50 },
        },
        default = 1.00,
    },
    {
        name = "controller_profile",
        label = "手柄震动模式 / Controller Profile",
        hover = "自动识别 Xbox、DS4、PS5/DualSense；Steam Input 映射不准确时可手动指定。 / Auto-detect the controller family, or force one for Steam Input.",
        options =
        {
            { description = "自动 / Auto", data = "auto" },
            { description = "Xbox / XInput", data = "xbox" },
            { description = "DualShock 4", data = "ds4" },
            { description = "PS5 / DualSense", data = "ds5" },
        },
        default = "auto",
    },
    {
        name = "response_mode",
        label = "马达响应 / Motor Response",
        hover = "原版细节保留完整包络；柔和与强力只改变输出体感，不改变事件时机。 / Detail preserves the calibrated envelope; Soft and Punchy only alter motor response.",
        options =
        {
            { description = "原版细节 / Detail", data = "detail" },
            { description = "柔和 / Soft", data = "soft" },
            { description = "强力 / Punchy", data = "punchy" },
        },
        default = "detail",
    },
    {
        name = "tool_scale",
        label = "工具反馈 / Tools",
        hover = "砍树、采矿、锤击、挖地与种植。 / Chop, mine, hammer, dig and plant feedback.",
        options = ScaleOptions(),
        default = 1.00,
    },
    {
        name = "combat_scale",
        label = "战斗反馈 / Combat",
        hover = "武器挥动与实际材质命中。 / Weapon swings and material impacts.",
        options = ScaleOptions(),
        default = 1.00,
    },
    {
        name = "danger_scale",
        label = "受伤危险 / Danger",
        hover = "本地玩家受伤、饥饿、寒冷、过热等原版危险事件。 / Native hurt, hunger, cold and overheat feedback.",
        options = ScaleOptions(),
        default = 1.00,
    },
    {
        name = "player_scale",
        label = "玩家交互 / Player Interaction",
        hover = "装备、采集、箱子、复活等其它 PLAYER 事件。 / Other PLAYER events such as equipment, pickup, chests and revival.",
        options = ScaleOptions(),
        default = 1.00,
    },
    {
        name = "boss_scale",
        label = "Boss 反馈 / Boss",
        hover = "Boss 脚步、落地、重击与技能。 / Boss footsteps, landings, slams and abilities.",
        options = ScaleOptions(),
        default = 1.00,
    },
    {
        name = "environment_scale",
        label = "环境反馈 / Environment",
        hover = "环境事件的独立倍率。 / Independent scale for environmental events.",
        options = ScaleOptions(),
        default = 1.00,
    },
    {
        name = "ui_scale",
        label = "界面反馈 / UI & HUD",
        hover = "UI/HUD 原版事件，不经过世界距离衰减。 / Native UI/HUD events without world-distance attenuation.",
        options = ScaleOptions(),
        default = 1.00,
    },
    {
        name = "loop_scale",
        label = "持续震动 / Loops",
        hover = "仅缩放具名循环效果，KillSound 和世界卸载仍会立即清理。 / Scales named loop effects; lifecycle cleanup remains unchanged.",
        options = ScaleOptions(),
        default = 1.00,
    },
    {
        name = "spatial_scale",
        label = "空间作用范围 / Spatial Reach",
        hover = "缩放 PLAYER、DANGER、ENVIRONMENT、BOSS 的远端衰减距离；UI 不受影响。 / Scales world-event falloff distance; UI is unaffected.",
        options =
        {
            { description = "75%", data = 0.75 },
            { description = "100%", data = 1.00 },
            { description = "125%", data = 1.25 },
            { description = "150%", data = 1.50 },
        },
        default = 1.00,
    },
    {
        name = "debug",
        label = "调试日志 / Debug Logging",
        hover = "记录匹配、距离、强度、持续时间、通道与过滤原因；默认关闭。 / Log matches, distance, intensity, duration, channel and filter reasons; OFF by default.",
        options =
        {
            { description = "关闭 / OFF", data = false },
            { description = "开启 / ON", data = true },
        },
        default = false,
    },
}
