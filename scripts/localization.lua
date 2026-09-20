local select = GLOBAL.select
local string = GLOBAL.string

local TEXT =
{
    zh =
    {
        initialized = "已初始化：%d 个唯一原版事件（%d 条定义，%d 个重复事件），架构=兼容输出，原生输出已抑制",
        load_failed = "无法读取当前版本 haptics.lua：%s",
        hook_failed = "声音钩子处理失败：%s",
        native_suppressed = "兼容层工作时已关闭原生 TheHaptics 输出，避免未来版本双重震动",
    },
    en =
    {
        initialized = "initialized: %d unique native events (%d definitions, %d duplicate events), architecture=compatibility output, native output suppressed",
        load_failed = "could not read the current haptics.lua: %s",
        hook_failed = "sound hook processing failed: %s",
        native_suppressed = "native TheHaptics output is disabled while compatibility output is active to prevent future double rumble",
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
