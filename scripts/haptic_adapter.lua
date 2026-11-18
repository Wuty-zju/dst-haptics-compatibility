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

function Adapter.Install(config, LoadLocalModule)
    local L = LoadLocalModule("scripts/localization.lua")
    local SoundEmitter = G.SoundEmitter
    if SoundEmitter == nil or G.TheInputProxy == nil then
        print("[DST Haptics Compat] " .. L(config.language, "missing_proxies"))
        return
    end

    -- A reset normally recreates the Lua VM. This guard also protects hot reloads
    -- performed by development tools inside a surviving VM.
    local existing = rawget(SoundEmitter, "_dst_haptics_compat")
    if existing ~= nil and existing.installed then
        if existing.pipeline_schema ~= 1 or type(existing.api) ~= "table" then
            print("[DST Haptics Compat] " .. L(config.language, "restart_required"))
            return
        end
        existing.api.ApplyConfig(config)
        return existing.api
    end

    local Util = LoadLocalModule("scripts/haptic_util.lua")
    local Pack, Clamp, NumberOr = Util.Pack, Util.Clamp, Util.NumberOr
    local Registry = LoadLocalModule("scripts/haptic_registry.lua")
    local Device = LoadLocalModule("scripts/haptic_device.lua")
    local Spatial = LoadLocalModule("scripts/haptic_spatial.lua")
    local Loops = LoadLocalModule("scripts/haptic_loops.lua")
    local Hooks = LoadLocalModule("scripts/haptic_hooks.lua")
    local Profiles = LoadLocalModule("scripts/haptic_profiles.lua")
    local Parameters = LoadLocalModule("scripts/haptic_parameters.lua")
    local Mixer = LoadLocalModule("scripts/haptic_mixer.lua")
    local Tuning = LoadLocalModule("scripts/haptic_tuning.lua")

    local ok, native_effects = pcall(G.require, "haptics")
    if not ok or type(native_effects) ~= "table" then
        print("[DST Haptics Compat] " .. L(config.language, "load_failed", tostring(native_effects)))
        return
    end

    local state =
    {
        installed = true,
        pipeline_schema = 1,
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
        workers = {},
        cleanups = {},
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

    local device = Device.New(state, Util, L)
    local space = Spatial.New(state, Util)
    local ProfileAllowsVibration, OutputMode = device.ProfileAllowsVibration, device.OutputMode
    local OutputAllowed, SuppressNative = device.OutputAllowed, device.SuppressNative
    local GetOutputCalibration, CalibratePulse = device.GetOutputCalibration, device.CalibratePulse
    local MapIntensity, ChannelFor = device.MapIntensity, device.ChannelFor
    local GetEntity, IsUIEffect, SpatialFactor = space.GetEntity, space.IsUIEffect, space.Factor

    local unique_count = Registry.Populate(state, native_effects, Profiles)

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
        print("[DST Haptics Compat] " .. L(state.config.language, "event_log",
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

    local function EffectScale(effect, profile, suffix)
        return Tuning.Scale(state.config, effect, profile, suffix, IsUIEffect(effect))
    end

    local function AddPulse(channel, duration, magnitude, duration_scale, expected_generation)
        if magnitude <= 0 or duration <= 0 or duration_scale == 0 or not OutputAllowed() then
            return false
        end
        if expected_generation ~= nil and expected_generation ~= state.generation then return false end
        duration, magnitude = CalibratePulse(duration, magnitude, duration_scale)
        SuppressNative()
        G.TheInputProxy:AddVibration(channel, duration, magnitude, false)
        state.metrics.pulses = state.metrics.pulses + 1
        return true
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
                AddPulse(channel, pulse[2], magnitude, duration_scale, generation)
            else
                state.metrics.scheduled_pulses = state.metrics.scheduled_pulses + 1
                G.scheduler:ExecuteInTime(pulse[1] * time_scale, function()
                    if generation == state.generation
                        and (entity == nil or entity.IsValid == nil or entity:IsValid()) then
                        AddPulse(channel, pulse[2], magnitude, duration_scale, generation)
                    end
                end)
            end
        end
        DebugLog(effect, entity, distance, raw, strongest, profile.total * time_scale, channel, false, "accepted", source, params, parameter_scale)
    end

    local loops = Loops.New(state, {
        Util = Util, SpatialFactor = SpatialFactor, ScheduleProfile = ScheduleProfile,
        ChannelFor = ChannelFor, DebugLog = DebugLog, Parameters = Parameters, Mixer = Mixer,
        MapIntensity = MapIntensity, EffectScale = EffectScale, CalibratePulse = CalibratePulse,
        OutputAllowed = OutputAllowed, SuppressNative = SuppressNative,
    })
    local RegisterLoop = loops.Register

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
            if state.output_was_allowed then OutputAllowed() end
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
        local allowed, reason = OutputAllowed()
        if not allowed then
            DebugLog(effect, entity, nil, NumberOr(effect.vibration_intensity, 1), 0, 0, "n/a", true, reason, source)
            return false
        end
        local now = Now()
        -- Sound hooks and replicated-action bridges can observe the same native
        -- event through different Lua paths. Keep this key deliberately small:
        -- it only collapses virtually simultaneous copies for one entity.
        local cross_key = event .. "|" .. EntityKey(entity)
        local cross_last = state.bridge_recent[cross_key]
        if cross_last ~= nil
            and cross_last.source ~= source
            and now - cross_last.time < 0.08 then
            DebugLog(effect, entity, distance, NumberOr(effect.vibration_intensity, 1), 0, profile.total, ChannelFor(effect, profile), true, "cross_path_duplicate", source)
            return false
        end
        state.bridge_recent[cross_key] = { time = now, source = source }
        local key = dedupe_key or (event .. "|" .. EntityKey(entity) .. "|" .. tostring(name or "oneshot")
            .. "|" .. tostring(NumberOr(volume, 1)))
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
        if effect == nil or effect.vibration ~= true then
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
            -- Keep a real named sound's lifecycle even while distant, paused
            -- or disconnected. Eligibility is re-evaluated at every sample.
            local _, distance = SpatialFactor(effect, entity, local_context)
            RegisterLoop(effect, emitter, entity, name, volume, profile, distance, "sound", local_context, params)
            return
        end
        HandleEvent(event, entity, name, volume, "sound", nil, local_context, params)
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

    state.unhook = Hooks.Install(state, {
        play = function(emitter, event, name, volume, params)
            local current = name ~= nil and state.loops[loops.Key(emitter, name)] or nil
            if current ~= nil and current.effect.event ~= event then loops.Remove(emitter, name) end
            HandleSound(emitter, event, name, volume, params)
        end,
        kill = loops.Remove, kill_all = loops.RemoveEmitter,
        volume = loops.SetVolume, parameter = loops.SetParameter,
    }, Util, function(message)
        local now = Now()
        if state.last_hook_error == nil or now - state.last_hook_error > 5 then
            state.last_hook_error = now
            print("[DST Haptics Compat] " .. L(state.config.language, "hook_failed", tostring(message)))
        end
    end)
    local function Every(scheduler, period, callback)
        state.workers[#state.workers + 1] = scheduler:ExecutePeriodic(period, callback)
    end
    Every(G.scheduler, 0.085, function()
        if state.installed then loops.Refresh() end
    end)

    Every(G.staticScheduler or G.scheduler, 0.5, function()
        if state.installed then SuppressNative() end
    end)
    Every(G.staticScheduler or G.scheduler, 0.085, function()
        if state.installed then
            local allowed = OutputAllowed()
            local pending = state.pending_test
            if pending ~= nil then
                local id = device.GetOutputController(true)
                if Now() > pending.expires or G.ThePlayer ~= pending.player
                    or id ~= pending.controller_id
                    or G.TheInputProxy:GetInputDeviceType(id) ~= pending.controller_type then
                    state.pending_test = nil
                elseif allowed then
                    state.pending_test = nil
                    state.api.TestPulse(pending.level)
                end
            end
        end
    end)

    -- Bound the dedupe/debug caches without adding work to the hot sound path.
    Every(G.scheduler, 10, function()
        if not state.installed then return end
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
            print("[DST Haptics Compat] " .. L(state.config.language, "metrics",
                state.metrics.accepted,
                state.metrics.filtered,
                state.metrics.pulses,
                state.metrics.scheduled_pulses,
                state.metrics.parameter_updates,
                active_loops
            ))
        end
    end)


    local world_bindings = {}
    local function DetachWorld(inst)
        local callbacks = world_bindings[inst]
        if callbacks == nil then return end
        world_bindings[inst] = nil
        if inst.RemoveEventCallback ~= nil then
            for event, callback in pairs(callbacks) do inst:RemoveEventCallback(event, callback) end
        end
    end
    local function BindWorld(inst)
        -- Postinit callbacks remain registered in the VM after Shutdown. Never
        -- let an inactive owner attach listeners to the next world.
        if not state.installed or world_bindings[inst] ~= nil then return end
        local callbacks = {}
        local function CancelWorldOutput(clear)
            if not state.installed then return end
            device.CancelOutput()
            if clear then
                state.loops, state.recent, state.bridge_recent = {}, {}, {}
                state.last_special_hurt_time = nil
                state.pending_test = nil
            end
        end
        callbacks.playeractivated = function(_, player)
            if state.installed and player == G.ThePlayer then state.player_active = true end
        end
        callbacks.serverpauseddirty = function(_, data)
            if not state.installed then return end
            data = data or {}
            state.server_paused = data.pause or data.autopause or data.gameautopause or false
            if state.server_paused and OutputMode() == "compatibility" then CancelWorldOutput(false) end
        end
        callbacks.playerdeactivated = function(_, player)
            if state.installed and player == G.ThePlayer then
                state.player_active = false
                CancelWorldOutput(true)
            end
        end
        callbacks.onremove = function()
            CancelWorldOutput(true)
            state.server_paused = false
            state.player_active = nil
            state.last_controller_id = nil
            state.listener_position = nil
            DetachWorld(inst)
        end
        world_bindings[inst] = callbacks
        for event, callback in pairs(callbacks) do inst:ListenForEvent(event, callback) end
    end
    AddPrefabPostInit("world", BindWorld)
    if G.TheWorld ~= nil then BindWorld(G.TheWorld) end
    state.cleanups[#state.cleanups + 1] = function()
        for inst in pairs(world_bindings) do DetachWorld(inst) end
    end

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
        GetGeneration = function() return state.generation end,
        IsInstalled = function() return state.installed end,
        AddCleanup = function(callback)
            if type(callback) ~= "function" then return false end
            state.cleanups[#state.cleanups + 1] = callback
            return true
        end,
        ShouldBridge = function(kind)
            return state.installed and OutputMode() == "compatibility"
                and state.config[kind .. "_fallback"] == true
        end,
        CanObserve = function()
            -- Prediction confirmations compare their capture's generation after
            -- this check. Synchronize controller changes before they compare it.
            return G.ThePlayer ~= nil and OutputAllowed() == true
        end,
        ObserveLoop = function(event, emitter, entity, name)
            local effect, profile = state.effects[event], state.profiles[event]
            if not state.installed or OutputMode() ~= "compatibility" or name == nil
                or effect == nil or effect.vibration ~= true or profile == nil or not profile.loop
                or emitter == nil or emitter.PlayingSound == nil then return false end
            local ok, playing = pcall(emitter.PlayingSound, emitter, name)
            if not ok or playing ~= true then return false end
            local current = state.loops[loops.Key(emitter, name)]
            if current ~= nil then return current.effect.event == event end
            RegisterLoop(effect, emitter, entity, name, 1, profile, nil, "engine_sound_handle", false)
            return true
        end,
        Shutdown = function()
            if not state.installed then return end
            local mode = OutputMode()
            state.installed = false
            device.CancelOutput(mode)
            state.loops = {}
            state.pending_test = nil
            for i = #state.cleanups, 1, -1 do pcall(state.cleanups[i]) end
            state.cleanups = {}
            if state.unhook ~= nil then state.unhook() end
            for _, task in pairs(state.workers) do
                if task ~= nil and task.Cancel ~= nil then task:Cancel() end
            end
            if state.runtime_settings_task ~= nil and state.runtime_settings_task.Cancel ~= nil then
                state.runtime_settings_task:Cancel()
            end
            SuppressNative()
            if rawget(SoundEmitter, "_dst_haptics_compat") == state then
                rawset(SoundEmitter, "_dst_haptics_compat", nil)
            end
        end,
        TestPulse = function(level)
            local tests =
            {
                weak = { duration = 0.08, magnitude = 0.20 },
                medium = { duration = 0.14, magnitude = 0.50 },
                strong = { duration = 0.22, magnitude = 0.85 },
            }
            local test = tests[level]
            local id = test ~= nil and device.GetOutputController(true) or nil
            if id == nil then
                return false
            end
            if device.IsPaused() then
                state.pending_test = {
                    level = level, expires = Now() + 10, player = G.ThePlayer,
                    controller_id = id, controller_type = G.TheInputProxy:GetInputDeviceType(id),
                }
                return true
            end
            return AddPulse(G.VIBRATION_CAMERA_SHAKE or 0, test.duration, test.magnitude)
        end,
        ApplyConfig = function(values)
            if not state.installed then return end
            local previous_mode = OutputMode()
            -- A settings change invalidates old envelope tails immediately.
            device.CancelOutput(previous_mode)
            state.pending_test = nil
            if type(values) == "table" then
                for key, value in pairs(values) do
                    state.config[key] = value
                end
            end
            local mode = OutputMode()
            if mode ~= previous_mode then state.last_controller_id = nil end
            if mode ~= "compatibility" then
                state.recent = {}
                state.bridge_recent = {}
            end
            SuppressNative()
        end,
    }

    SuppressNative()
    print("[DST Haptics Compat] " .. L(config.language, "initialized", unique_count, state.definitions, state.duplicate_events))
    return state.api
end

return Adapter
