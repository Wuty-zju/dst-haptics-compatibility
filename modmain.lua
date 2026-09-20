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
local config =
{
    language = GetModConfigData("language", true) or "zh",
    -- DST's restricted mod environment does not expose Lua's tonumber.
    strength = type(strength_value) == "number" and strength_value or 1,
    debug = GetModConfigData("debug", true) == true,
}

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
end)

if not ok then
    print("[DST Haptics Compat] LOAD ERROR: " .. tostring(message))
    G.error(message)
end
