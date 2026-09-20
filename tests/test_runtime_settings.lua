GLOBAL = _G
CONTROL_MENU_MISC_2 = 99
KEY_F8 = 119
ThePlayer = { prefab = "wilson" }

local postconstructs = {}
local periodic
local key_handler
local pushed = {}

function AddClassPostConstruct(path, fn)
    postconstructs[path] = fn
end

scheduler =
{
    ExecutePeriodic = function(_, _, fn) periodic = fn end,
}

TheInput =
{
    ControllerAttached = function() return true end,
    GetControllerID = function() return 2 end,
    GetLocalizedControl = function(_, _, control) return control == CONTROL_MENU_MISC_2 and "Triangle" or "?" end,
    AddKeyUpHandler = function(_, key, fn) assert(key == KEY_F8); key_handler = fn end,
}

TheFrontEnd =
{
    GetActiveScreen = function() return pushed[#pushed] end,
    PushScreen = function(_, screen) table.insert(pushed, screen) end,
}

package.preload["screens/redux/modconfigurationscreen"] = function()
    return function(modname, client_config)
        return { name = "ModConfigurationScreen", modname = modname, client_config = client_config }
    end
end

local applied = {}
local state = {}
local api =
{
    GetState = function() return state end,
    ApplyConfig = function(values) table.insert(applied, values) end,
}
local config = { language = "zh", compatibility = true, strength = 1 }
local next_config = { language = "zh", compatibility = true, strength = 1 }

local source = assert(os.getenv("DST_HAPTICS_MOD_ROOT"), "DST_HAPTICS_MOD_ROOT is required")
    .. "/scripts/runtime_settings.lua"
local fn, err = loadfile(source)
assert(fn, err)
setfenv(fn, _G)
local RuntimeSettings = fn()
RuntimeSettings.Install(api, config, "dst_haptics_compat", function() return next_config end)

assert(state.runtime_settings_installed == true)
assert(postconstructs["screens/redux/pausescreen"] ~= nil)
assert(postconstructs["screens/pausescreen"] ~= nil)
assert(key_handler ~= nil and periodic ~= nil)

local pause =
{
    OnControl = function() return false end,
    GetHelpText = function() return "Cancel Back" end,
}
postconstructs["screens/redux/pausescreen"](pause)
assert(pause:OnControl(CONTROL_MENU_MISC_2, false) == true)
assert(#pushed == 1 and pushed[1].modname == "dst_haptics_compat" and pushed[1].client_config == true)
assert(string.find(pause:GetHelpText(), "Triangle 震动设置", 1, true) ~= nil)

-- Opening while already on the configuration screen must not stack duplicates.
key_handler()
assert(#pushed == 1)

periodic()
assert(#applied == 0, "unchanged runtime configuration was reapplied")
next_config = { language = "en", compatibility = true, strength = 0.75 }
periodic()
assert(#applied == 1 and applied[1].strength == 0.75)

print("runtime settings tests passed")
