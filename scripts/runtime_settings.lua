local G = GLOBAL
local pairs = G.pairs
local pcall = G.pcall
local string = G.string
local tostring = G.tostring
local type = G.type

local RuntimeSettings = {}

local function SameConfig(a, b)
    for key, value in pairs(b) do
        if a[key] ~= value then
            return false
        end
    end
    return true
end

function RuntimeSettings.Install(api, config, modname, read_config)
    if api == nil or api.ApplyConfig == nil or read_config == nil then
        return
    end
    local state = api.GetState ~= nil and api.GetState() or nil
    if state ~= nil and state.runtime_settings_installed then
        return
    end
    if state ~= nil then
        state.runtime_settings_installed = true
    end

    local function OpenSettings()
        if G.TheFrontEnd == nil then
            return
        end
        local ok, Screen = pcall(G.require, "screens/redux/modconfigurationscreen")
        if not ok or Screen == nil then
            print("[DST Haptics Compat] unable to open in-world configuration: " .. tostring(Screen))
            return
        end
        local active = G.TheFrontEnd:GetActiveScreen()
        if active ~= nil and active.name == "ModConfigurationScreen" then
            return
        end
        G.TheFrontEnd:PushScreen(Screen(modname, true))
    end

    local function InstallPauseShortcut(path)
        AddClassPostConstruct(path, function(screen)
            if screen._dst_haptics_settings_shortcut then
                return
            end
            screen._dst_haptics_settings_shortcut = true

            local original_control = screen.OnControl
            screen.OnControl = function(self, control, down)
                if not down and control == G.CONTROL_MENU_MISC_2 then
                    OpenSettings()
                    return true
                end
                return original_control(self, control, down)
            end

            local original_help = screen.GetHelpText
            screen.GetHelpText = function(self)
                local text = original_help ~= nil and original_help(self) or ""
                if G.TheInput ~= nil and G.TheInput.ControllerAttached ~= nil and G.TheInput:ControllerAttached() then
                    local id = G.TheInput:GetControllerID()
                    local prompt = G.TheInput:GetLocalizedControl(id, G.CONTROL_MENU_MISC_2)
                        .. " "
                        .. (config.language == "en" and "Haptics" or "震动设置")
                    return text ~= "" and (text .. "  " .. prompt) or prompt
                end
                return text
            end
        end)
    end

    InstallPauseShortcut("screens/redux/pausescreen")
    InstallPauseShortcut("screens/pausescreen")

    -- Keyboard access is useful when Steam Input has temporarily switched the
    -- active device. Controller users can use MENU_MISC_2 from the pause menu.
    if G.TheInput ~= nil and G.TheInput.AddKeyUpHandler ~= nil and G.KEY_F8 ~= nil then
        G.TheInput:AddKeyUpHandler(G.KEY_F8, function()
            if G.ThePlayer ~= nil and G.TheFrontEnd ~= nil then
                OpenSettings()
            end
        end)
    end

    G.scheduler:ExecutePeriodic(0.5, function()
        local ok, values = pcall(read_config)
        if ok and type(values) == "table" and not SameConfig(config, values) then
            local previous_test = config.calibration_test
            api.ApplyConfig(values)
            if values.calibration_test ~= previous_test
                and values.calibration_test ~= "off"
                and api.TestPulse ~= nil then
                api.TestPulse(values.calibration_test)
            end
            if values.debug then
                print(string.format(
                    "[DST Haptics Compat] runtime settings applied: enabled=%s mode=%s controller=%s response=%s strength=%.2f",
                    tostring(values.compatibility),
                    tostring(values.output_mode),
                    tostring(values.controller_profile),
                    tostring(values.response_mode),
                    values.strength or 1
                ))
            end
        end
    end)
end

return RuntimeSettings
