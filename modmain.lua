local G = GLOBAL

if G.TheNet ~= nil and G.TheNet:IsDedicated() then
    return
end


local modules = {}
local function LoadLocalModule(relative_path)
    if modules[relative_path] ~= nil then return modules[relative_path] end
    local chunk = G.kleiloadlua(MODROOT .. relative_path)
    if type(chunk) == "string" then
        error(chunk)
    end
    G.assert(type(chunk) == "function", "unable to load " .. relative_path)
    G.setfenv(chunk, G.getfenv(1))
    local module = chunk()
    modules[relative_path] = module
    return module
end

local ok, message = G.pcall(function()
    local Config = LoadLocalModule("scripts/haptic_config.lua")
    local function ReadRuntimeConfig()
        return Config.Read(GetModConfigData)
    end
    local config = ReadRuntimeConfig()
    local Adapter = LoadLocalModule("scripts/haptic_adapter.lua")
    local api = Adapter.Install(config, LoadLocalModule)
    if api == nil then return end
    local ClientActionBridge = LoadLocalModule("scripts/client_action_bridge.lua")
    api.AddCleanup(ClientActionBridge.Install(api))
    LoadLocalModule("scripts/haptic_observers.lua").Install(api)
    local RuntimeSettings = LoadLocalModule("scripts/runtime_settings.lua")
    RuntimeSettings.Install(api, config, modname or "dst_haptics_compat", ReadRuntimeConfig,
        LoadLocalModule("scripts/localization.lua"))
end)

if not ok then
    print("[DST Haptics Compat] LOAD ERROR: " .. tostring(message))
    G.error(message)
end
