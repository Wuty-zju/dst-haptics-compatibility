-- Controller routing, output gates and Legacy Rumble calibration.
local G = GLOBAL
local pcall, type, tostring = G.pcall, G.type, G.tostring
local Device = {}
function Device.New(state, Util, L)
    local Clamp, NumberOr = Util.Clamp, Util.NumberOr
    local function ProfileAllowsVibration()
        return G.Profile ~= nil
            and G.Profile.GetVibrationEnabled ~= nil
            and G.Profile:GetVibrationEnabled() == true
    end

    local function IsPaused()
        if state.server_paused then return true end
        if G.TheNet ~= nil and G.TheNet.IsServerPaused ~= nil then
            local ok, paused = pcall(G.TheNet.IsServerPaused, G.TheNet)
            if ok and paused then return true end
        end
        if G.IsPaused ~= nil then
            local success, paused = pcall(G.IsPaused)
            return success and paused == true
        end
        return false
    end

    local function OutputMode()
        if not state.installed or state.config.compatibility == false then
            return "native"
        end
        local mode = state.config.output_mode
        if mode == "native" or mode == "diagnostic" then
            return mode
        end
        return "compatibility"
    end

    local function CancelOutput(mode)
        state.generation = state.generation + 1
        state.loop_revision = state.loop_revision + 1
        state.had_loop_output = false
        state.output_was_allowed = false
        if (mode or OutputMode()) == "compatibility" then
            pcall(function() G.TheInputProxy:StopVibration() end)
        end
    end

    local CONTROLLER_TYPE_NAMES =
    {
        [1] = "Xbox/XInput",
        [2] = "DualShock 4",
        [4] = "Generic controller",
        [6] = "Steam Controller/Steam Input",
        [7] = "PS5 controller",
        [9] = "Switch controller",
        [10] = "Steam Deck",
        [11] = "DualSense",
        [12] = "Joy-Con L",
        [13] = "Joy-Con R",
    }

    local function IsUsableController(id)
        return type(id) == "number"
            and id > 0
            and G.TheInputProxy:IsInputDeviceConnected(id)
            and G.TheInputProxy:IsInputDeviceEnabled(id)
            and G.TheInputProxy:GetInputDeviceType(id) ~= 0
    end

    local function GetControllerID()
        if G.TheInput == nil or G.TheInput.ControllerAttached == nil or not G.TheInput:ControllerAttached() then
            return nil
        end
        local id = G.TheInput:GetControllerID()
        if IsUsableController(id) then
            return id
        end

        -- Hot-plug and Steam Input can briefly report device 0 as last active.
        -- Scan only while DST says a controller is active, never merely because
        -- a keyboard/mouse device exists.
        local count = G.TheInputProxy:GetInputDeviceCount()
        for candidate = 1, count - 1 do
            if IsUsableController(candidate) then
                return candidate
            end
        end
        return nil
    end

    local function GetOutputController(allow_paused)
        if OutputMode() ~= "compatibility" then return nil end
        if state.player_active == false then return nil, "player_inactive" end
        if not ProfileAllowsVibration() then return nil, "profile_vibration_off" end
        if not allow_paused and IsPaused() then return nil, "paused" end
        local id = GetControllerID()
        if id == nil then return nil, "no_active_controller" end
        return id
    end

    local function RefreshControllerOutput(id)
        local current_type = G.TheInputProxy:GetInputDeviceType(id)
        if state.last_controller_id == id and state.last_controller_type == current_type then
            return
        end
        if state.last_controller_id ~= nil then
            CancelOutput()
        end
        state.last_controller_id = id
        state.last_controller_type = current_type
        local success, name = pcall(G.TheInputProxy.GetInputDeviceName, G.TheInputProxy, id)
        state.last_controller_name = success and name or CONTROLLER_TYPE_NAMES[state.last_controller_type] or "controller"
        -- Profile normally owns this flag. Reapplying it on a newly active
        -- controller repairs hot-plug without selecting an engine-specific API.
        G.TheInputProxy:EnableVibration(true)
        if state.config.debug then
            print("[DST Haptics Compat] " .. L(state.config.language, "controller",
                id,
                state.last_controller_type,
                tostring(CONTROLLER_TYPE_NAMES[state.last_controller_type] or "controller"),
                tostring(state.last_controller_name)
            ))
        end
    end

    local function OutputAllowed()
        local id, reason = GetOutputController()
        if id == nil then
            if state.output_was_allowed then
                CancelOutput()
            end
            state.last_controller_id = nil
            return false, reason
        end
        RefreshControllerOutput(id)
        state.output_was_allowed = true
        return true
    end

    local function SuppressNative()
        if G.TheHaptics ~= nil and G.TheHaptics.EnableVibration ~= nil and OutputMode() ~= "native" then
            pcall(function() G.TheHaptics:EnableVibration(false) end)
            if not state.native_suppressed then
                state.native_suppressed = true
                if state.config.debug then
                    print("[DST Haptics Compat] " .. L(state.config.language, "native_suppressed"))
                end
            end
        elseif state.native_suppressed then
            state.native_suppressed = false
            if G.TheHaptics ~= nil and G.TheHaptics.EnableVibration ~= nil then
                pcall(function() G.TheHaptics:EnableVibration(ProfileAllowsVibration()) end)
            end
        end
    end

    local function MapIntensity(raw)
        raw = math.max(0, NumberOr(raw, 1))
        -- 1-exp(-0.35*x) is monotonic and leaves headroom at common 0.5..3
        -- values while allowing the exceptional original value 10 to feel large.
        return 1 - math.exp(-0.35 * raw)
    end

    local function ChannelFor(effect, profile)
        if profile.loop then
            return G.VIBRATION_BLOOD_OVER or 2
        elseif effect.category == "DANGER" then
            return G.VIBRATION_BLOOD_FLASH or 1
        end
        return G.VIBRATION_CAMERA_SHAKE or 0
    end

    local CONTROLLER_CALIBRATION =
    {
        xbox = { gain = 1.00, gamma = 1.00, time = 1.00, minimum_duration = 0.025 },
        ds4 = { gain = 0.97, gamma = 0.95, time = 1.08, minimum_duration = 0.040 },
        ds5 = { gain = 0.92, gamma = 0.90, time = 1.12, minimum_duration = 0.045 },
    }

    local RESPONSE_CALIBRATION =
    {
        detail = { gain = 1.00, time = 1.00 },
        soft = { gain = 0.72, time = 0.90 },
        punchy = { gain = 1.15, time = 1.12 },
    }

    local function GetControllerFamily()
        local forced = state.config.controller_profile
        if forced == "xbox" or forced == "ds4" or forced == "ds5" then
            return forced
        end
        if state.last_controller_type == 2 then
            return "ds4"
        elseif state.last_controller_type == 7 or state.last_controller_type == 11 then
            return "ds5"
        end
        -- Steam Input and generic devices normally expose legacy XInput-style
        -- rumble to the game; users can override this in the in-world menu.
        return "xbox"
    end

    local function GetOutputCalibration()
        local family = state.config.controller_adaptation == false and "xbox" or GetControllerFamily()
        local hardware = CONTROLLER_CALIBRATION[family] or CONTROLLER_CALIBRATION.xbox
        local response = RESPONSE_CALIBRATION[state.config.response_mode] or RESPONSE_CALIBRATION.detail
        return hardware, response
    end

    local function CalibratePulse(duration, magnitude, duration_scale)
        local hardware, response = GetOutputCalibration()
        local calibrated_duration = math.max(hardware.minimum_duration, duration * hardware.time * response.time)
            * (duration_scale or 1)
        local calibrated_magnitude = (Clamp(magnitude, 0, 1) ^ hardware.gamma) * hardware.gain * response.gain
        return calibrated_duration, Clamp(calibrated_magnitude, 0, 1)
    end

    return {
        ProfileAllowsVibration = ProfileAllowsVibration, IsPaused = IsPaused,
        OutputMode = OutputMode, GetOutputController = GetOutputController,
        CancelOutput = CancelOutput, OutputAllowed = OutputAllowed,
        SuppressNative = SuppressNative, GetOutputCalibration = GetOutputCalibration,
        CalibratePulse = CalibratePulse, MapIntensity = MapIntensity, ChannelFor = ChannelFor,
    }
end
return Device
