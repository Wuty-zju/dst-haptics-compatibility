GLOBAL = _G
local root = assert(os.getenv("DST_HAPTICS_MOD_ROOT"), "DST_HAPTICS_MOD_ROOT is required")
local L = dofile(root .. "/scripts/localization.lua")
assert(type(L) == "function")

-- Inspect the private dictionary without adding a public maintenance-only API.
local text
for i = 1, 10 do
    local name, value = debug.getupvalue(L, i)
    if name == nil then break end
    if name == "TEXT" then text = value end
end
assert(text ~= nil)
local samples =
{
    initialized = { 503, 506, 3 },
    load_failed = { "test" }, hook_failed = { "test" },
    native_suppressed = {}, missing_proxies = {}, settings_title = {},
    settings_open_failed = { "test" },
    settings_applied = { "true", "compatibility", "auto", "detail", 1 },
    controller = { 1, 2, "DualShock 4", "test", },
    metrics = { 1, 2, 3, 4, 5, 6 },
    event_log = { "test/event", "BOSS", "false", "true", 1, "sound", "test", "0.00", 1, 0.5, 0.1, "2", "none", 1, "false", "accepted" },
}
local count = 0
for key in pairs(text.zh) do
    assert(text.en[key] ~= nil, "missing English key: " .. key)
    assert(samples[key] ~= nil, "missing format regression: " .. key)
    count = count + 1
end
for key in pairs(text.en) do
    assert(text.zh[key] ~= nil, "missing Chinese key: " .. key)
end
for key, args in pairs(samples) do
    local _, zh_count = string.gsub(text.zh[key], "%%[sd%.%d]+", "")
    local _, en_count = string.gsub(text.en[key], "%%[sd%.%d]+", "")
    assert(zh_count == #args and en_count == #args, "format arity mismatch: " .. key)
    for _, language in ipairs({ "zh", "en" }) do
        local value = L(language, key, unpack(args))
        assert(type(value) == "string" and value ~= key, key)
    end
end
assert(L(nil, "settings_title") == L("zh", "settings_title"))
assert(L("invalid", "settings_title") == L("zh", "settings_title"))
assert(L("en", "unknown_key") == "unknown_key")
assert(not string.find(L("en", "initialized", 503, 506, 3), "suppressed", 1, true))

local fields = "event=test/event category=BOSS player_only=false audio=true audio_intensity=1.000 source=sound entity=test distance=0.00 raw=1.000 final=0.500 duration=0.100 channel=2 params=none param_scale=1.000 filtered=false reason=accepted"
for _, language in ipairs({ "zh", "en" }) do
    assert(string.find(L(language, "event_log", unpack(samples.event_log)), fields, 1, true),
        "event fields changed in " .. language)
end

-- Mod configuration runs in its own sandbox without a runtime translator.
local info = {}
local chunk = assert(loadfile(root .. "/modinfo.lua"))
setfenv(chunk, info)
chunk()
assert(info.version == "1.6.0")
local options = {}
for _, option in ipairs(info.configuration_options) do
    assert(not options[option.name], "duplicate option: " .. option.name)
    options[option.name] = option
    assert(string.find(option.label, "/", 1, true), "configuration label must stay bilingual")
end
for _, name in ipairs({ "compatibility", "language", "output_mode", "strength", "controller_profile",
    "response_mode", "calibration_test", "tool_scale", "combat_scale", "danger_scale", "player_scale",
    "boss_scale", "environment_scale", "ui_scale", "loop_scale", "spatial_scale", "debug", "duration",
    "tool_duration", "combat_duration", "danger_duration", "player_duration", "boss_duration",
    "environment_duration", "ui_duration", "loop_duration", "controller_adaptation" }) do
    assert(options[name], "saved configuration key removed: " .. name)
end
assert(options.language.default == "zh")
assert(options.hurt_fallback.default == false)
assert(options.hurt_fallback.options[1].data == true and options.hurt_fallback.options[2].data == false)
assert(string.find(options.hurt_fallback.hover, "不能证明", 1, true))
print("localization tests passed: " .. count .. " bilingual keys, format contracts and saved configuration keys")
