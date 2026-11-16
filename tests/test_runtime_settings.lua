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
    ExecutePeriodic = function() error("runtime settings must update during server pause") end,
}
staticScheduler =
{
    ExecutePeriodic = function(_, interval, fn) assert(interval == 0.5); periodic = fn end,
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
local test_pulses = {}
local state = {}
local cleanups = {}
local api =
{
    GetState = function() return state end,
    ApplyConfig = function(values) table.insert(applied, values) end,
    TestPulse = function(level) table.insert(test_pulses, level) end,
    AddCleanup = function(callback) cleanups[#cleanups + 1] = callback end,
}
local config = { language = "zh", compatibility = true, strength = 1, calibration_test = "off" }
local next_config = { language = "zh", compatibility = true, strength = 1, calibration_test = "off" }

local source = assert(os.getenv("DST_HAPTICS_MOD_ROOT"), "DST_HAPTICS_MOD_ROOT is required")
    .. "/scripts/runtime_settings.lua"
local fn, err = loadfile(source)
assert(fn, err)
setfenv(fn, _G)
local RuntimeSettings = fn()
local L = dofile(assert(os.getenv("DST_HAPTICS_MOD_ROOT")) .. "/scripts/localization.lua")
RuntimeSettings.Install(api, config, "dst_haptics_compat", function() return next_config end, L)

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
next_config = { language = "en", compatibility = true, strength = 0.75, calibration_test = "medium" }
periodic()
assert(#applied == 1 and applied[1].strength == 0.75)
assert(test_pulses[1] == "medium", "in-world calibration selection did not play a test pulse")
assert(string.find(pause:GetHelpText(), "Triangle Haptics", 1, true) ~= nil,
    "existing pause shortcut did not immediately switch language")
periodic()
assert(#applied == 1, "unchanged settings were reapplied after updating the UI configuration")

local original_print = print
local logs = {}
print = function(message) logs[#logs + 1] = message end
next_config = { language = "zh", compatibility = true, strength = 0.5, calibration_test = "medium", debug = true }
periodic()
assert(string.find(logs[#logs], "局内设置已应用", 1, true) ~= nil)
assert(string.find(pause:GetHelpText(), "Triangle 震动设置", 1, true) ~= nil)
assert(#test_pulses == 1, "language changes replayed the calibration pulse")
next_config = { language = "en", compatibility = true, strength = 0.5, calibration_test = "medium", debug = true }
periodic()
assert(string.find(logs[#logs], "runtime settings applied", 1, true) ~= nil)

-- A failed import uses the currently selected language too.
pushed = {}
package.loaded["screens/redux/modconfigurationscreen"] = nil
package.preload["screens/redux/modconfigurationscreen"] = function() error("test import failure") end
key_handler()
assert(string.find(logs[#logs], "unable to open in-world haptics settings", 1, true) ~= nil)
assert(#pushed == 0)
print = original_print

-- Existing pause screens outlive a same-VM reload. Keep a later mod's wrapper
-- and rebind its original shortcut to the new language/API instead of nesting.
state.installed = false
for _, cleanup in ipairs(cleanups) do cleanup() end
local original_control, original_help = pause.OnControl, pause.GetHelpText
local later_calls = 0
pause.OnControl = function(...)
    later_calls = later_calls + 1
    return original_control(...)
end
local later_control = pause.OnControl
pause.name = "PauseScreen"
TheFrontEnd.screenstack = { pause }
local replacement_state, replacement_cleanups = { installed = true }, {}
local replacement_api = {
    GetState = function() return replacement_state end,
    ApplyConfig = function() end,
    AddCleanup = function(callback) replacement_cleanups[#replacement_cleanups + 1] = callback end,
}
package.loaded["screens/redux/modconfigurationscreen"] = nil
package.preload["screens/redux/modconfigurationscreen"] = function()
    return function(modname) return { name = "ModConfigurationScreen", modname = modname } end
end
RuntimeSettings.Install(replacement_api, { language = "zh" }, "reloaded_mod", function() return {} end, L)
assert(pause.OnControl == later_control and pause.GetHelpText == original_help,
    "reinstall nested an existing pause shortcut or replaced another mod's wrapper")
assert(pause:OnControl(CONTROL_MENU_MISC_2, false) == true and later_calls == 1,
    "existing pause shortcut was not rebound after reinstall")
assert(#pushed == 1 and pushed[1].modname == "reloaded_mod")
assert(string.find(pause:GetHelpText(), "Triangle 震动设置", 1, true) ~= nil,
    "reloaded pause shortcut retained the retired language")
-- Even repeated, late cleanup from the old owner must preserve the new owner.
for _, cleanup in ipairs(cleanups) do cleanup() end
assert(string.find(pause:GetHelpText(), "Triangle 震动设置", 1, true) ~= nil)
replacement_state.installed = false
for _, cleanup in ipairs(replacement_cleanups) do cleanup() end
assert(pause:OnControl(CONTROL_MENU_MISC_2, false) == false)
assert(pause:GetHelpText() == "Cancel Back", "inactive pause shortcut still changed help text")

print("runtime settings tests passed")
