name = "DST Haptics Compatibility / 手柄震动兼容"
description = [[
修复 Windows 下原版 TheHaptics 无输出的问题。动态读取当前版本 haptics.lua，并补齐服务器声音在客户端 Lua 层不可见的工作/战斗事件。适配 Xbox/XInput、DS4 与 PS5/DualSense。

Fixes silent native TheHaptics output on Windows. Uses the current haptics.lua plus replicated action bridges. Supports Xbox/XInput, DS4 and PS5/DualSense through TheInputProxy.
]]
author = "Local compatibility build"
version = "1.1.0"

api_version = 10
dst_compatible = true
dont_starve_compatible = false
reign_of_giants_compatible = false

client_only_mod = true
all_clients_require_mod = false
server_only_mod = false

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
