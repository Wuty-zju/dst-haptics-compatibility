local G = GLOBAL

if G.TheNet ~= nil and G.TheNet:IsDedicated() then
    return
end

local compatibility = GetModConfigData("compatibility", true)
if compatibility == false then
    print("[DST Haptics Compat] compatibility disabled; native TheHaptics left untouched")
    return
end

local strength_value = GetModConfigData("strength", true)
local function ConfigNumber(name, fallback)
    local value = GetModConfigData(name, true)
    return type(value) == "number" and value or fallback
end

local config =
{
    compatibility = true,
    language = GetModConfigData("language", true) or "zh",
    -- DST's restricted mod environment does not expose Lua's tonumber.
    strength = type(strength_value) == "number" and strength_value or 1,
    controller_profile = GetModConfigData("controller_profile", true) or "auto",
    response_mode = GetModConfigData("response_mode", true) or "detail",
    tool_scale = ConfigNumber("tool_scale", 1),
    combat_scale = ConfigNumber("combat_scale", 1),
    danger_scale = ConfigNumber("danger_scale", 1),
    player_scale = ConfigNumber("player_scale", 1),
    boss_scale = ConfigNumber("boss_scale", 1),
    environment_scale = ConfigNumber("environment_scale", 1),
    ui_scale = ConfigNumber("ui_scale", 1),
    loop_scale = ConfigNumber("loop_scale", 1),
    spatial_scale = ConfigNumber("spatial_scale", 1),
    debug = GetModConfigData("debug", true) == true,
}

local function ReadRuntimeConfig()
    return
    {
        compatibility = GetModConfigData("compatibility", true) ~= false,
        language = GetModConfigData("language", true) or "zh",
        strength = ConfigNumber("strength", 1),
        controller_profile = GetModConfigData("controller_profile", true) or "auto",
        response_mode = GetModConfigData("response_mode", true) or "detail",
        tool_scale = ConfigNumber("tool_scale", 1),
        combat_scale = ConfigNumber("combat_scale", 1),
        danger_scale = ConfigNumber("danger_scale", 1),
        player_scale = ConfigNumber("player_scale", 1),
        boss_scale = ConfigNumber("boss_scale", 1),
        environment_scale = ConfigNumber("environment_scale", 1),
        ui_scale = ConfigNumber("ui_scale", 1),
        loop_scale = ConfigNumber("loop_scale", 1),
        spatial_scale = ConfigNumber("spatial_scale", 1),
        debug = GetModConfigData("debug", true) == true,
    }
end

local function LoadLocalModule(relative_path)
    local chunk = G.kleiloadlua(MODROOT .. relative_path)
    if type(chunk) == "string" then
        error(chunk)
    end
    G.assert(type(chunk) == "function", "unable to load " .. relative_path)
    G.setfenv(chunk, G.getfenv(1))
    return chunk()
end

local ok, message = G.pcall(function()
    local Adapter = LoadLocalModule("scripts/haptic_adapter.lua")
    local api = Adapter.Install(config, LoadLocalModule)
    local ClientActionBridge = LoadLocalModule("scripts/client_action_bridge.lua")
    ClientActionBridge.Install(api, config)
    local RuntimeSettings = LoadLocalModule("scripts/runtime_settings.lua")
    RuntimeSettings.Install(api, config, modname or "dst_haptics_compat", ReadRuntimeConfig)
end)

if not ok then
    print("[DST Haptics Compat] LOAD ERROR: " .. tostring(message))
    G.error(message)
end
