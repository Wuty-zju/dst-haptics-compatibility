local G = GLOBAL

if G.TheNet ~= nil and G.TheNet:IsDedicated() then
    return
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
    local Config = LoadLocalModule("scripts/haptic_config.lua")
    local function ReadRuntimeConfig()
        return Config.Read(GetModConfigData)
    end
    local config = ReadRuntimeConfig()
    local Adapter = LoadLocalModule("scripts/haptic_adapter.lua")
    local api = Adapter.Install(config, LoadLocalModule)
    local ClientActionBridge = LoadLocalModule("scripts/client_action_bridge.lua")
    ClientActionBridge.Install(api)
    local RuntimeSettings = LoadLocalModule("scripts/runtime_settings.lua")
    RuntimeSettings.Install(api, config, modname or "dst_haptics_compat", ReadRuntimeConfig)
end)

if not ok then
    print("[DST Haptics Compat] LOAD ERROR: " .. tostring(message))
    G.error(message)
end
