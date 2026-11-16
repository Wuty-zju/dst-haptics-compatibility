local G = GLOBAL
local pairs = G.pairs
local pcall = G.pcall
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

function RuntimeSettings.Install(api, config, modname, read_config, L)
    if api == nil or api.ApplyConfig == nil or read_config == nil or type(L) ~= "function" then
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
        if state ~= nil and state.installed == false then return end
        if G.TheFrontEnd == nil then
            return
        end
        local ok, Screen = pcall(G.require, "screens/redux/modconfigurationscreen")
        if not ok or Screen == nil then
            print("[DST Haptics Compat] " .. L(config.language, "settings_open_failed", tostring(Screen)))
            return
        end
        local active = G.TheFrontEnd:GetActiveScreen()
        if active ~= nil and active.name == "ModConfigurationScreen" then
            return
        end
        G.TheFrontEnd:PushScreen(Screen(modname, true))
    end

    local shortcut_owner = {}
    local shortcuts = G.setmetatable({}, { __mode = "k" })
    local function BindPauseShortcut(screen)
        if state ~= nil and state.installed == false then return end
        local binding = screen._dst_haptics_settings_shortcut
        if type(binding) ~= "table" then
            binding = {}
            screen._dst_haptics_settings_shortcut = binding
            local original_control = screen.OnControl
            screen.OnControl = function(self, control, down, ...)
                if binding.active ~= nil and binding.active() and not down and control == G.CONTROL_MENU_MISC_2 then
                    binding.open()
                    return true
                end
                return original_control(self, control, down, ...)
            end
            local original_help = screen.GetHelpText
            screen.GetHelpText = function(self)
                local text = original_help ~= nil and original_help(self) or ""
                if binding.active ~= nil and binding.active() then
                    local prompt = binding.prompt()
                    if prompt ~= nil then return text ~= "" and (text .. "  " .. prompt) or prompt end
                end
                return text
            end
        end
        binding.owner = shortcut_owner
        binding.active = function() return state == nil or state.installed ~= false end
        binding.open = OpenSettings
        binding.prompt = function()
            if G.TheInput ~= nil and G.TheInput.ControllerAttached ~= nil and G.TheInput:ControllerAttached() then
                local id = G.TheInput:GetControllerID()
                return G.TheInput:GetLocalizedControl(id, G.CONTROL_MENU_MISC_2) .. " " .. L(config.language, "settings_title")
            end
        end
        shortcuts[binding] = true
    end

    AddClassPostConstruct("screens/redux/pausescreen", BindPauseShortcut)
    AddClassPostConstruct("screens/pausescreen", BindPauseShortcut)
    -- FrontEnd.screenstack and the native PauseScreen name are present in the
    -- current game. Rebind open screens once; never scan during input/update.
    if G.TheFrontEnd ~= nil and type(G.TheFrontEnd.screenstack) == "table" then
        for _, screen in G.ipairs(G.TheFrontEnd.screenstack) do
            if screen.name == "PauseScreen" then BindPauseShortcut(screen) end
        end
    end
    if api.AddCleanup ~= nil then
        api.AddCleanup(function()
            for binding in pairs(shortcuts) do
                if binding.owner == shortcut_owner then
                    binding.owner, binding.active, binding.open, binding.prompt = nil, nil, nil, nil
                end
            end
        end)
    end

    -- Keyboard access is useful when Steam Input has temporarily switched the
    -- active device. Controller users can use MENU_MISC_2 from the pause menu.
    if G.TheInput ~= nil and G.TheInput.AddKeyUpHandler ~= nil and G.KEY_F8 ~= nil then
        local handler = G.TheInput:AddKeyUpHandler(G.KEY_F8, function()
            if G.ThePlayer ~= nil and G.TheFrontEnd ~= nil then
                OpenSettings()
            end
        end)
        if api.AddCleanup ~= nil then
            api.AddCleanup(function()
                if handler ~= nil and handler.Remove ~= nil then handler:Remove() end
            end)
        end
    end

    -- The game's ordinary scheduler stops on server pause. Settings saved from
    -- the pause menu must update prompts and output gating before resuming.
    local settings_scheduler = G.staticScheduler or G.scheduler
    local settings_task = settings_scheduler:ExecutePeriodic(0.5, function()
        if state ~= nil and state.installed == false then return end
        local ok, values = pcall(read_config)
        if ok and type(values) == "table" and not SameConfig(config, values) then
            local previous_test = config.calibration_test
            api.ApplyConfig(values)
            -- Keep the UI's configuration current even when ApplyConfig replaces
            -- its own table. Resolve language on every prompt/log invocation.
            for key, value in pairs(values) do
                config[key] = value
            end
            if values.calibration_test ~= previous_test
                and values.calibration_test ~= "off"
                and api.TestPulse ~= nil then
                api.TestPulse(values.calibration_test)
            end
            if values.debug then
                print("[DST Haptics Compat] " .. L(config.language, "settings_applied",
                    tostring(values.compatibility),
                    tostring(values.output_mode),
                    tostring(values.controller_profile),
                    tostring(values.response_mode),
                    values.strength or 1
                ))
            end
        end
    end)
    if state ~= nil then state.runtime_settings_task = settings_task end
end

return RuntimeSettings
