local select = GLOBAL.select
local string = GLOBAL.string

-- Preserve the machine-readable field order in both languages.
local EVENT_FIELDS = "event=%s category=%s player_only=%s audio=%s audio_intensity=%.3f source=%s entity=%s distance=%s raw=%.3f final=%.3f duration=%.3f channel=%s params=%s param_scale=%.3f filtered=%s reason=%s"

local TEXT =
{
    zh =
    {
        initialized = "已初始化：%d 个唯一原版事件（%d 条定义，%d 个重复事件）",
        load_failed = "无法读取当前版本 haptics.lua：%s",
        hook_failed = "声音钩子处理失败：%s",
        native_suppressed = "兼容层工作时已关闭原生 TheHaptics 输出，避免未来版本双重震动",
        missing_proxies = "客户端声音或震动接口不可用",
        restart_required = "检测到旧版或未完成的震动会话，请重启 DST 后加载新版；未重复安装钩子",
        settings_title = "震动设置",
        settings_open_failed = "无法打开局内震动设置：%s",
        settings_applied = "局内设置已应用：enabled=%s mode=%s controller=%s response=%s strength=%.2f",
        controller = "已连接手柄：id=%d type=%d family=%s name=%s output=TheInputProxy",
        metrics = "震动统计：accepted=%d filtered=%d pulses=%d scheduled=%d parameter_updates=%d active_loops=%d",
        event_log = "震动事件（过滤状态见 filtered）：" .. EVENT_FIELDS,
    },
    en =
    {
        initialized = "initialized: %d unique native events (%d definitions, %d duplicate events)",
        load_failed = "could not read the current haptics.lua: %s",
        hook_failed = "sound hook processing failed: %s",
        native_suppressed = "native TheHaptics output is disabled while compatibility output is active to prevent future double rumble",
        missing_proxies = "client sound or vibration interfaces are unavailable",
        restart_required = "restart DST to replace an older or incomplete haptics session; no duplicate hooks were installed",
        settings_title = "Haptics",
        settings_open_failed = "unable to open in-world haptics settings: %s",
        settings_applied = "runtime settings applied: enabled=%s mode=%s controller=%s response=%s strength=%.2f",
        controller = "controller connected: id=%d type=%d family=%s name=%s output=TheInputProxy",
        metrics = "haptics metrics: accepted=%d filtered=%d pulses=%d scheduled=%d parameter_updates=%d active_loops=%d",
        event_log = "haptics event (output eligibility in filtered): " .. EVENT_FIELDS,
    },
}

return function(language, key, ...)
    local selected = TEXT[language] or TEXT.zh
    local value = selected[key] or TEXT.en[key] or key
    if select("#", ...) > 0 then
        return string.format(value, ...)
    end
    return value
end
