local G = GLOBAL
local unpack = G.unpack
local pairs = G.pairs
local next = G.next
local pcall = G.pcall
local rawget = G.rawget
local rawset = G.rawset
local select = G.select
local tostring = G.tostring
local type = G.type

local Adapter = {}

local function Pack(...)
    return { n = select("#", ...), ... }
end

local function Clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    elseif value > maximum then
        return maximum
    end
    return value
end

local function NumberOr(value, fallback)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge and value or fallback
end

function Adapter.Install(config, LoadLocalModule)
    local SoundEmitter = G.SoundEmitter
    if SoundEmitter == nil or G.TheInputProxy == nil then
        print("[DST Haptics Compat] required client engine proxies are unavailable")
        return
    end

    -- A reset normally recreates the Lua VM. This guard also protects hot reloads
    -- performed by development tools inside a surviving VM.
    local existing = rawget(SoundEmitter, "_dst_haptics_compat")
    if existing ~= nil and existing.installed then
        existing.config = config
        return existing.api
    end

    local Profiles = LoadLocalModule("scripts/haptic_profiles.lua")
    local Parameters = LoadLocalModule("scripts/haptic_parameters.lua")
    local Mixer = LoadLocalModule("scripts/haptic_mixer.lua")
    local Tuning = LoadLocalModule("scripts/haptic_tuning.lua")
    local L = LoadLocalModule("scripts/localization.lua")

    local ok, native_effects = pcall(G.require, "haptics")
    if not ok or type(native_effects) ~= "table" then
        print("[DST Haptics Compat] " .. L(config.language, "load_failed", tostring(native_effects)))
        return
    end

    local state =
    {
        installed = true,
        config = config,
        effects = {},
        profiles = {},
        definitions = 0,
        duplicate_events = 0,
        recent = {},
        loops = {},
        debug_recent = {},
        bridge_recent = {},
        native_suppressed = false,
        had_loop_output = false,
        last_controller_id = nil,
        last_controller_type = nil,
        last_controller_name = nil,
        generation = 0,
        loop_revision = 0,
        output_was_allowed = false,
        listener_position = nil,
        last_special_hurt_time = nil,
        metrics =
        {
            accepted = 0,
            filtered = 0,
            pulses = 0,
            scheduled_pulses = 0,
            parameter_updates = 0,
        },
    }
    rawset(SoundEmitter, "_dst_haptics_compat", state)

    local function Now()
        if G.GetTimeRealSeconds ~= nil then
            return G.GetTimeRealSeconds()
        end
        return G.TheSim ~= nil and G.TheSim:GetRealTime() / 1000 or 0
    end

    for i = 1, #native_effects do
        local effect = native_effects[i]
        if type(effect) == "table" and type(effect.event) == "string" then
            state.definitions = state.definitions + 1
            if state.effects[effect.event] ~= nil then
                state.duplicate_events = state.duplicate_events + 1
            end
            -- RegisterEffect is called in file order by the game. A keyed native
            -- registry consequently resolves duplicate event names to the final
            -- definition; mirroring that also avoids accidental double rumble.
            state.effects[effect.event] = effect
        end
    end

    local unique_count = 0
    for _ in pairs(state.effects) do
        unique_count = unique_count + 1
    end
    -- Resolve immutable event envelopes once, including the final duplicate
    -- definition. User tuning is applied at output time without mutating them.
    for event, effect in pairs(state.effects) do
        state.profiles[event] = Profiles.Get(effect)
    end

    local function FormatParams(params)
        if type(params) ~= "table" then
            return "n/a"
        end
        local values = {}
        for key, value in pairs(params) do
            values[#values + 1] = tostring(key) .. "=" .. tostring(value)
        end
        G.table.sort(values)
        return #values > 0 and G.table.concat(values, ",") or "n/a"
    end

    local function DebugLog(effect, entity, distance, raw_intensity, final_intensity, duration, channel, filtered, reason, source, params, parameter_scale)
        if filtered then
            state.metrics.filtered = state.metrics.filtered + 1
        else
            state.metrics.accepted = state.metrics.accepted + 1
        end
        if not state.config.debug then
            return
        end
        local now = Now()
        local identity = entity ~= nil and (entity.prefab or tostring(entity.GUID or entity)) or "UI/no-entity"
        local key = effect.event .. "|" .. tostring(reason)
        local last = state.debug_recent[key]
        if filtered and last ~= nil and now - last < 0.5 then
            return
        end
        state.debug_recent[key] = now
        print(string.format(
            "[DST Haptics Compat] event=%s category=%s player_only=%s audio=%s audio_intensity=%.3f source=%s entity=%s distance=%s raw=%.3f final=%.3f duration=%.3f channel=%s params=%s param_scale=%.3f filtered=%s reason=%s",
            effect.event,
            tostring(effect.category or "UNSPECIFIED"),
            tostring(effect.player_only == true),
            tostring(effect.audio),
            NumberOr(effect.audio_intensity, 1),
            tostring(source or "sound"),
            tostring(identity),
            distance ~= nil and string.format("%.2f", distance) or "n/a",
            raw_intensity or 0,
            final_intensity or 0,
            duration or 0,
            tostring(channel),
            FormatParams(params),
            parameter_scale or 1,
            tostring(filtered == true),
            tostring(reason or "accepted")
        ))
    end

    local function ProfileAllowsVibration()
        return G.Profile ~= nil
            and G.Profile.GetVibrationEnabled ~= nil
            and G.Profile:GetVibrationEnabled() == true
    end

    local function IsPaused()
        if G.IsPaused == nil then
            return false
        end
        local success, paused = pcall(G.IsPaused)
        return success and paused == true
    end

    local function OutputMode()
        if state.config.compatibility == false then
            return "native"
        end
        local mode = state.config.output_mode
        if mode == "native" or mode == "diagnostic" then
            return mode
        end
        return "compatibility"
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

    local function RefreshControllerOutput(id)
        local current_type = G.TheInputProxy:GetInputDeviceType(id)
        if state.last_controller_id == id and state.last_controller_type == current_type then
            return
        end
        state.last_controller_id = id
        state.last_controller_type = current_type
        local success, name = pcall(G.TheInputProxy.GetInputDeviceName, G.TheInputProxy, id)
        state.last_controller_name = success and name or CONTROLLER_TYPE_NAMES[state.last_controller_type] or "controller"
        -- Profile normally owns this flag. Reapplying it on a newly active
        -- controller repairs hot-plug without selecting an engine-specific API.
        G.TheInputProxy:EnableVibration(true)
        if state.config.debug then
            print(string.format(
                "[DST Haptics Compat] controller id=%d type=%d family=%s name=%s output=TheInputProxy",
                id,
                state.last_controller_type,
                tostring(CONTROLLER_TYPE_NAMES[state.last_controller_type] or "controller"),
                tostring(state.last_controller_name)
            ))
        end
    end

    local function OutputAllowed()
        local allowed = OutputMode() == "compatibility" and ProfileAllowsVibration() and not IsPaused()
        local id = allowed and GetControllerID() or nil
        if not id then
            if state.output_was_allowed then
                state.generation = state.generation + 1
                state.loop_revision = state.loop_revision + 1
                state.had_loop_output = false
                pcall(function() G.TheInputProxy:StopVibration() end)
            end
            state.output_was_allowed = false
            state.last_controller_id = nil
            return false
        end
        state.output_was_allowed = true
        RefreshControllerOutput(id)
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
            pcall(function() G.TheInputProxy:StopVibration() end)
            if G.TheHaptics ~= nil and G.TheHaptics.EnableVibration ~= nil then
                pcall(function() G.TheHaptics:EnableVibration(ProfileAllowsVibration()) end)
            end
        end
    end

    local function GetEntity(emitter)
        if emitter == nil or emitter.GetEntity == nil then
            return nil
        end
        local success, entity = pcall(emitter.GetEntity, emitter)
        return success and entity or nil
    end

    local DISTANCE_POLICY =
    {
        PLAYER = { near = 5, far = 26 },
        DANGER = { near = 7, far = 34 },
        ENVIRONMENT = { near = 8, far = 46 },
        BOSS = { near = 12, far = 64 },
    }

    local function IsUIEffect(effect)
        return effect.category == "UI" or string.find(string.lower(effect.event), "/hud/", 1, true) ~= nil
    end

    local function SpatialFactor(effect, entity, local_context)
        if IsUIEffect(effect) then
            return 1, nil, nil
        end
        -- FrontEnd and FocalPoint emitters are native proof that the sound is
        -- listener-local. Equip, burn, worm travel/digestion and lunar-burn
        -- feedback use this path despite not belonging to the UI category.
        if local_context then
            return 1, nil, nil
        end
        if G.ThePlayer == nil or G.ThePlayer.Transform == nil then
            return 0, nil, "no_local_player"
        end
        if effect.player_only == true then
            -- A small set of player_only effects is intentionally emitted by
            -- local HUD widgets (for example WX-78 shield feedback). The
            -- frontend/focal-point emitter is local-player proof even though
            -- SoundEmitter:GetEntity() is nil or the focal point, not ThePlayer.
            if entity ~= G.ThePlayer then
                return 0, nil, "player_only_nonlocal"
            end
            return 1, entity == G.ThePlayer and 0 or nil, nil
        end
        if entity == G.ThePlayer then
            return 1, 0, nil
        end
        -- Freeze/overheat and similar HUD danger events are played through the
        -- frontend SoundEmitter, which intentionally has no world entity.
        if entity == nil or entity.Transform == nil then
            return 0, nil, "no_spatial_entity"
        end

        local px, py, pz
        if state.listener_position ~= nil then
            px, py, pz = state.listener_position[1], state.listener_position[2], state.listener_position[3]
        else
            px, py, pz = G.ThePlayer.Transform:GetWorldPosition()
        end
        local ex, ey, ez = entity.Transform:GetWorldPosition()
        local dx, dy, dz = ex - px, ey - py, ez - pz
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
        local policy = DISTANCE_POLICY[effect.category] or DISTANCE_POLICY.PLAYER
        local spatial_scale = Clamp(NumberOr(state.config.spatial_scale, 1), 0.5, 2)
        local far = policy.near + (policy.far - policy.near) * spatial_scale
        if distance <= policy.near then
            return 1, distance, nil
        elseif distance >= far then
            return 0, distance, "outside_spatial_range"
        end
        local t = (distance - policy.near) / (far - policy.near)
        -- Cubic smoothstep avoids a hard audible edge while reaching exact zero.
        local smooth = t * t * (3 - 2 * t)
        return 1 - smooth, distance, nil
    end

    local function MapIntensity(raw)
        raw = math.max(0, NumberOr(raw, 1))
        -- 1-exp(-0.35*x) is monotonic and leaves headroom at common 0.5..3
        -- values while allowing the exceptional original value 10 to feel large.
        return 1 - math.exp(-0.35 * raw)
    end

    local function DedupeWindow(effect, profile)
        if profile.loop then
            return 0.20
        elseif IsUIEffect(effect) then
            return 0.025
        elseif effect.category == "BOSS" then
            return 0.060
        end
        return 0.045
    end

    local function EntityKey(entity)
        return entity ~= nil and tostring(entity.GUID or entity) or "ui"
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

    local function EffectScale(effect, profile, suffix)
        return Tuning.Scale(state.config, effect, profile, suffix, IsUIEffect(effect))
    end

    local function AddPulse(channel, duration, magnitude, duration_scale)
        if magnitude <= 0 or duration <= 0 or duration_scale == 0 or not OutputAllowed() then
            return
        end
        duration, magnitude = CalibratePulse(duration, magnitude, duration_scale)
        SuppressNative()
        G.TheInputProxy:AddVibration(channel, duration, magnitude, false)
        state.metrics.pulses = state.metrics.pulses + 1
    end

    local function ScheduleProfile(effect, entity, profile, volume, spatial, distance, source, params)
        -- Reject at observation time as well as playback time: events born
        -- during a pause/disconnection must not turn into delayed feedback.
        if not OutputAllowed() then
            return
        end
        local duration_scale = Clamp(NumberOr(state.config.duration, 1), 0, 2)
            * EffectScale(effect, profile, "_duration")
        if duration_scale <= 0 then
            return
        end
        local raw = NumberOr(effect.vibration_intensity, 1)
        local parameter_scale = Parameters.GetScale(effect.event, params)
        local base = MapIntensity(raw)
            * Clamp(NumberOr(state.config.strength, 1), 0, 2)
            * NumberOr(profile.factor, 1)
            * EffectScale(effect, profile)
        base = base * Clamp(NumberOr(volume, 1), 0, 1) * spatial * parameter_scale
        if base <= 0 then
            return
        end
        local channel = ChannelFor(effect, profile)
        local strongest = 0
        local generation = state.generation
        local hardware, response = GetOutputCalibration()
        local time_scale = hardware.time * response.time * duration_scale
        for i = 1, #profile.pulses do
            local pulse = profile.pulses[i]
            local magnitude = Clamp(base * pulse[3], 0, 1)
            local _, calibrated = CalibratePulse(pulse[2], magnitude)
            strongest = math.max(strongest, calibrated)
            if pulse[1] <= 0 then
                AddPulse(channel, pulse[2], magnitude, duration_scale)
            else
                state.metrics.scheduled_pulses = state.metrics.scheduled_pulses + 1
                G.scheduler:ExecuteInTime(pulse[1] * time_scale, function()
                    if generation == state.generation then
                        AddPulse(channel, pulse[2], magnitude, duration_scale)
                    end
                end)
            end
        end
        DebugLog(effect, entity, distance, raw, strongest, profile.total * time_scale, channel, false, "accepted", source, params, parameter_scale)
    end

    local function LoopKey(emitter, name)
        return tostring(emitter) .. "|" .. tostring(name)
    end

    local function RegisterLoop(effect, emitter, entity, name, volume, profile, distance, source, local_context, params)
        if name == nil then
            local bounded = { pulses = { { 0, 0.10, 0.70 }, { 0.09, 0.10, 0.55 }, { 0.18, 0.08, 0.40 } }, total = 0.26 }
            local spatial = SpatialFactor(effect, entity, local_context)
            ScheduleProfile(effect, entity, bounded, volume, spatial, distance, source, params)
            return
        end
        state.loops[LoopKey(emitter, name)] =
        {
            emitter = emitter,
            entity = entity,
            name = name,
            effect = effect,
            volume = NumberOr(volume, 1),
            profile = profile,
            local_context = local_context,
            params = Parameters.Copy(params) or {},
        }
        local parameter_scale = Parameters.GetScale(effect.event, params)
        DebugLog(effect, entity, distance, NumberOr(effect.vibration_intensity, 1), 0, -1, ChannelFor(effect, profile), false, "loop_started", source, params, parameter_scale)
    end

    local function HandleEvent(event, entity, name, volume, source, dedupe_key, local_context, params)
        local effect = state.effects[event]
        if effect == nil then
            return false
        end
        local output_mode = OutputMode()
        if output_mode == "native" then
            return false
        end
        if effect.vibration ~= true then
            DebugLog(effect, entity, nil, NumberOr(effect.vibration_intensity, 0), 0, 0, "n/a", true, "vibration_disabled_in_native_table", source)
            return false
        end
        if not ProfileAllowsVibration() then
            DebugLog(effect, entity, nil, NumberOr(effect.vibration_intensity, 1), 0, 0, "n/a", true, "profile_vibration_off", source)
            return false
        end
        local spatial, distance, reason = SpatialFactor(effect, entity, local_context)
        if spatial <= 0 then
            DebugLog(effect, entity, distance, NumberOr(effect.vibration_intensity, 1), 0, 0, "n/a", true, reason or "spatially_filtered", source)
            return false
        end

        local profile = state.profiles[event]
        if output_mode == "diagnostic" then
            local parameter_scale = Parameters.GetScale(effect.event, params)
            DebugLog(effect, entity, distance, NumberOr(effect.vibration_intensity, 1), 0, profile.total, ChannelFor(effect, profile), true, "diagnostic_no_output", source, params, parameter_scale)
            return true
        end
        local controller_id = GetControllerID()
        if controller_id == nil then
            DebugLog(effect, entity, nil, NumberOr(effect.vibration_intensity, 1), 0, 0, "n/a", true, "no_active_controller", source)
            return false
        end
        RefreshControllerOutput(controller_id)
        local now = Now()
        -- Sound hooks and replicated-action bridges can observe the same native
        -- event through different Lua paths. Keep this key deliberately small:
        -- it only collapses virtually simultaneous copies for one entity.
        local cross_key = event .. "|" .. EntityKey(entity)
        local cross_last = state.bridge_recent[cross_key]
        if cross_last ~= nil
            and cross_last.source ~= source
            and now - cross_last.time < 0.20 then
            DebugLog(effect, entity, distance, NumberOr(effect.vibration_intensity, 1), 0, profile.total, ChannelFor(effect, profile), true, "cross_path_duplicate", source)
            return false
        end
        state.bridge_recent[cross_key] = { time = now, source = source }
        local key = dedupe_key or (event .. "|" .. EntityKey(entity) .. "|" .. tostring(name or "oneshot"))
        local last = state.recent[key]
        if last ~= nil and now - last < DedupeWindow(effect, profile) then
            DebugLog(effect, entity, distance, NumberOr(effect.vibration_intensity, 1), 0, profile.total, ChannelFor(effect, profile), true, "deduplicated", source)
            return false
        end
        state.recent[key] = now

        if profile.loop then
            return false
        else
            local lower_event = string.lower(event)
            if source == "sound" and (entity == G.ThePlayer or local_context)
                and event ~= "dontstarve/wilson/hit"
                and (string.find(lower_event, "shocked", 1, true) ~= nil
                    or string.find(lower_event, "/freeze_", 1, true) ~= nil
                    or string.find(lower_event, "hud_hot_level", 1, true) ~= nil
                    or string.find(lower_event, "burned", 1, true) ~= nil
                    or string.find(lower_event, "charlie/attack", 1, true) ~= nil) then
                state.last_special_hurt_time = now
            end
            ScheduleProfile(effect, entity, profile, volume, spatial, distance, source, params)
        end
        return true
    end

    local function HandleSound(emitter, event, name, volume, params)
        local effect = state.effects[event]
        if effect == nil then
            return
        end
        local entity = GetEntity(emitter)
        local local_context = false
        if G.TheFrontEnd ~= nil and G.TheFrontEnd.GetSound ~= nil then
            local success, frontend_sound = pcall(G.TheFrontEnd.GetSound, G.TheFrontEnd)
            local_context = success and emitter == frontend_sound
        end
        if not local_context and G.TheFocalPoint ~= nil then
            local_context = emitter == G.TheFocalPoint.SoundEmitter
        end
        local profile = state.profiles[event]
        if profile.loop then
            local mode = OutputMode()
            if mode == "native" then
                return
            elseif mode == "diagnostic" then
                HandleEvent(event, entity, name, volume, "sound", nil, local_context, params)
                return
            end
            if not ProfileAllowsVibration() or GetControllerID() == nil then
                return
            end
            local spatial, distance = SpatialFactor(effect, entity, local_context)
            if spatial > 0 then
                RegisterLoop(effect, emitter, entity, name, volume, profile, distance, "sound", local_context, params)
            end
            return
        end
        HandleEvent(event, entity, name, volume, "sound", nil, local_context, params)
    end

    local function SafeHandle(...)
        local success, message = pcall(HandleSound, ...)
        if not success then
            local now = Now()
            if state.last_hook_error == nil or now - state.last_hook_error > 5 then
                state.last_hook_error = now
                print("[DST Haptics Compat] " .. L(state.config.language, "hook_failed", tostring(message)))
            end
        end
    end

    local function BridgeEmit(event, entity, context)
        context = context or {}
        local key = context.dedupe_key
        if key == nil and context.semantic_key ~= nil then
            key = "bridge|" .. tostring(context.semantic_key)
        end
        return HandleEvent(
            event,
            entity,
            context.name,
            context.volume,
            context.source or "bridge",
            key,
            context.local_context == true,
            context.params
        )
    end

    local original_play = SoundEmitter.PlaySound
    SoundEmitter.PlaySound = function(emitter, event, name, volume, ...)
        local results = Pack(original_play(emitter, event, name, volume, ...))
        SafeHandle(emitter, event, name, volume)
        return unpack(results, 1, results.n)
    end

    if SoundEmitter.PlaySoundWithParams ~= nil then
        local original_play_params = SoundEmitter.PlaySoundWithParams
        SoundEmitter.PlaySoundWithParams = function(emitter, event, params, volume, ...)
            local results = Pack(original_play_params(emitter, event, params, volume, ...))
            SafeHandle(emitter, event, nil, volume, params)
            return unpack(results, 1, results.n)
        end
    end

    local original_kill = SoundEmitter.KillSound
    local loop_channel = G.VIBRATION_BLOOD_OVER or 2
    local RefreshLoops
    local function StopLoopChannelIfIdle()
        state.loop_revision = state.loop_revision + 1
        if state.had_loop_output then
            pcall(function() G.TheInputProxy:RemoveVibration(loop_channel) end)
            state.had_loop_output = false
        end
        if next(state.loops) ~= nil and RefreshLoops ~= nil then
            RefreshLoops()
        end
    end

    SoundEmitter.KillSound = function(emitter, name, ...)
        local results = Pack(original_kill(emitter, name, ...))
        state.loops[LoopKey(emitter, name)] = nil
        StopLoopChannelIfIdle()
        return unpack(results, 1, results.n)
    end

    local original_kill_all = SoundEmitter.KillAllSounds
    SoundEmitter.KillAllSounds = function(emitter, ...)
        local results = Pack(original_kill_all(emitter, ...))
        local prefix = tostring(emitter) .. "|"
        for key in pairs(state.loops) do
            if string.sub(key, 1, #prefix) == prefix then
                state.loops[key] = nil
            end
        end
        StopLoopChannelIfIdle()
        return unpack(results, 1, results.n)
    end

    if SoundEmitter.SetVolume ~= nil then
        local original_set_volume = SoundEmitter.SetVolume
        SoundEmitter.SetVolume = function(emitter, name, volume, ...)
            local results = Pack(original_set_volume(emitter, name, volume, ...))
            local loop = state.loops[LoopKey(emitter, name)]
            if loop ~= nil then
                loop.volume = NumberOr(volume, loop.volume)
                StopLoopChannelIfIdle()
            end
            return unpack(results, 1, results.n)
        end
    end

    if SoundEmitter.SetParameter ~= nil then
        local original_set_parameter = SoundEmitter.SetParameter
        SoundEmitter.SetParameter = function(emitter, name, parameter, value, ...)
            local results = Pack(original_set_parameter(emitter, name, parameter, value, ...))
            local loop = state.loops[LoopKey(emitter, name)]
            if loop ~= nil and type(parameter) == "string" and type(value) == "number" then
                loop.params[parameter] = value
                state.metrics.parameter_updates = state.metrics.parameter_updates + 1
                StopLoopChannelIfIdle()
            end
            return unpack(results, 1, results.n)
        end
    end

    if G.Sim ~= nil and G.Sim.SetListener ~= nil then
        local original_set_listener = G.Sim.SetListener
        G.Sim.SetListener = function(sim, x, y, z, ...)
            state.listener_position = { NumberOr(x, 0), NumberOr(y, 0), NumberOr(z, 0) }
            return original_set_listener(sim, x, y, z, ...)
        end
    end

    RefreshLoops = function()
        state.loop_revision = state.loop_revision + 1
        local revision, generation = state.loop_revision, state.generation
        local contributions = {}
        if OutputAllowed() then
            for key, loop in pairs(state.loops) do
                local valid = loop.emitter ~= nil
                if valid and loop.entity ~= nil and loop.entity.IsValid ~= nil then
                    valid = loop.entity:IsValid()
                end
                if valid and loop.emitter.PlayingSound ~= nil then
                    local success, playing = pcall(loop.emitter.PlayingSound, loop.emitter, loop.name)
                    valid = success and playing == true
                end
                if not valid then
                    state.loops[key] = nil
                else
                    local spatial = SpatialFactor(loop.effect, loop.entity, loop.local_context)
                    local magnitude = MapIntensity(NumberOr(loop.effect.vibration_intensity, 1))
                        * Clamp(NumberOr(state.config.strength, 1), 0, 2)
                        * EffectScale(loop.effect, loop.profile)
                        * Clamp(loop.volume or 1, 0, 1)
                        * spatial
                        * loop.profile.factor
                        * Parameters.GetScale(loop.effect.event, loop.params)
                    local duration_scale = Clamp(NumberOr(state.config.duration, 1), 0, 2)
                        * EffectScale(loop.effect, loop.profile, "_duration")
                    if magnitude > 0 and duration_scale > 0 then
                        local duration, calibrated = CalibratePulse(loop.profile.duration, magnitude, duration_scale)
                        contributions[#contributions + 1] = { duration = duration, magnitude = calibrated }
                    end
                end
            end
        end
        local segments = Mixer.Build(contributions)
        if state.had_loop_output then
            pcall(function() G.TheInputProxy:RemoveVibration(loop_channel) end)
            state.had_loop_output = false
        end
        for i = 1, #segments do
            local segment = segments[i]
            local function EmitSegment()
                if revision == state.loop_revision and generation == state.generation and OutputAllowed() then
                    SuppressNative()
                    G.TheInputProxy:AddVibration(loop_channel, segment.duration, segment.magnitude, false)
                    state.had_loop_output = true
                    state.metrics.pulses = state.metrics.pulses + 1
                end
            end
            if segment.delay == 0 then
                EmitSegment()
            elseif segment.delay < 0.085 then
                -- The next periodic sample replaces later segments. Never leave
                -- callbacks queued beyond that sample merely to invalidate them.
                G.scheduler:ExecuteInTime(segment.delay, EmitSegment)
            end
        end
    end
    G.scheduler:ExecutePeriodic(0.085, RefreshLoops)

    G.scheduler:ExecutePeriodic(0.5, SuppressNative)

    -- Bound the dedupe/debug caches without adding work to the hot sound path.
    G.scheduler:ExecutePeriodic(10, function()
        local now = Now()
        for key, timestamp in pairs(state.recent) do
            if now - timestamp > 2 then
                state.recent[key] = nil
            end
        end
        for key, timestamp in pairs(state.debug_recent) do
            if now - timestamp > 10 then
                state.debug_recent[key] = nil
            end
        end
        for key, value in pairs(state.bridge_recent) do
            if now - value.time > 2 then
                state.bridge_recent[key] = nil
            end
        end
        if state.config.debug then
            local active_loops = 0
            for _ in pairs(state.loops) do
                active_loops = active_loops + 1
            end
            print(string.format(
                "[DST Haptics Compat] metrics accepted=%d filtered=%d pulses=%d scheduled=%d parameter_updates=%d active_loops=%d",
                state.metrics.accepted,
                state.metrics.filtered,
                state.metrics.pulses,
                state.metrics.scheduled_pulses,
                state.metrics.parameter_updates,
                active_loops
            ))
        end
    end)


    -- World removal is the one lifecycle boundary where stopping every vibration
    -- is desirable: no controller output may leak into the loading/frontend state.
    AddPrefabPostInit("world", function(inst)
        inst:ListenForEvent("onremove", function()
            state.loops = {}
            state.recent = {}
            state.bridge_recent = {}
            state.generation = state.generation + 1
            state.had_loop_output = false
            pcall(function() G.TheInputProxy:StopVibration() end)
        end)
    end)

    state.api =
    {
        Emit = BridgeEmit,
        GetEffect = function(event) return state.effects[event] end,
        GetState = function() return state end,
        HasRecentSpecialHurt = function(window)
            return state.last_special_hurt_time ~= nil
                and Now() - state.last_special_hurt_time <= NumberOr(window, 0.12)
        end,
        GetDiagnostics = function() return state.metrics end,
        TestPulse = function(level)
            local tests =
            {
                weak = { duration = 0.08, magnitude = 0.20 },
                medium = { duration = 0.14, magnitude = 0.50 },
                strong = { duration = 0.22, magnitude = 0.85 },
            }
            local test = tests[level]
            if test == nil or OutputMode() ~= "compatibility" then
                return false
            end
            AddPulse(G.VIBRATION_CAMERA_SHAKE or 0, test.duration, test.magnitude)
            return true
        end,
        ApplyConfig = function(values)
            -- A settings change invalidates old envelope tails immediately.
            state.generation = state.generation + 1
            state.loop_revision = state.loop_revision + 1
            pcall(function() G.TheInputProxy:StopVibration() end)
            state.had_loop_output = false
            if type(values) == "table" then
                for key, value in pairs(values) do
                    state.config[key] = value
                end
            end
            if OutputMode() ~= "compatibility" then
                state.loops = {}
                state.recent = {}
                state.bridge_recent = {}
                state.generation = state.generation + 1
                state.had_loop_output = false
                pcall(function() G.TheInputProxy:StopVibration() end)
            end
            SuppressNative()
        end,
    }

    SuppressNative()
    print("[DST Haptics Compat] " .. L(config.language, "initialized", unique_count, state.definitions, state.duplicate_events))
    return state.api
end

return Adapter
