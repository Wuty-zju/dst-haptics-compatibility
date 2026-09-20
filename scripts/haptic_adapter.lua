local G = GLOBAL
local unpack = G.unpack
local pairs = G.pairs
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
    return type(value) == "number" and value or fallback
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

    local function DebugLog(effect, entity, distance, raw_intensity, final_intensity, duration, channel, filtered, reason, source)
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
            "[DST Haptics Compat] event=%s category=%s source=%s entity=%s distance=%s raw=%.3f final=%.3f duration=%.3f channel=%s filtered=%s reason=%s",
            effect.event,
            tostring(effect.category or "UNSPECIFIED"),
            tostring(source or "sound"),
            tostring(identity),
            distance ~= nil and string.format("%.2f", distance) or "n/a",
            raw_intensity or 0,
            final_intensity or 0,
            duration or 0,
            tostring(channel),
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
        if state.config.compatibility == false or not ProfileAllowsVibration() or IsPaused() then
            return false
        end
        local id = GetControllerID()
        if id == nil then
            return false
        end
        RefreshControllerOutput(id)
        return true
    end

    local function SuppressNative()
        if G.TheHaptics ~= nil and G.TheHaptics.EnableVibration ~= nil and state.config.compatibility ~= false then
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
        if G.ThePlayer == nil or G.ThePlayer.Transform == nil then
            return 0, nil, "no_local_player"
        end
        if effect.player_only == true then
            if entity ~= G.ThePlayer then
                return 0, nil, "player_only_nonlocal"
            end
            return 1, 0, nil
        end
        if entity == G.ThePlayer then
            return 1, 0, nil
        end
        -- Freeze/overheat and similar HUD danger events are played through the
        -- frontend SoundEmitter, which intentionally has no world entity.
        if entity == nil and local_context and effect.category == "DANGER" then
            return 1, nil, nil
        end
        if entity == nil or entity.Transform == nil then
            return 0, nil, "no_spatial_entity"
        end

        local px, _, pz = G.ThePlayer.Transform:GetWorldPosition()
        local ex, _, ez = entity.Transform:GetWorldPosition()
        local dx, dz = ex - px, ez - pz
        local distance = math.sqrt(dx * dx + dz * dz)
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
        local hardware = CONTROLLER_CALIBRATION[GetControllerFamily()] or CONTROLLER_CALIBRATION.xbox
        local response = RESPONSE_CALIBRATION[state.config.response_mode] or RESPONSE_CALIBRATION.detail
        return hardware, response
    end

    local function CalibratePulse(duration, magnitude)
        local hardware, response = GetOutputCalibration()
        local calibrated_duration = math.max(hardware.minimum_duration, duration * hardware.time * response.time)
        local calibrated_magnitude = (Clamp(magnitude, 0, 1) ^ hardware.gamma) * hardware.gain * response.gain
        return calibrated_duration, Clamp(calibrated_magnitude, 0, 1)
    end

    local function EffectScale(effect, profile)
        local kind = profile.kind
        local scale
        if kind == "tool" then
            scale = state.config.tool_scale
        elseif kind == "combat" then
            scale = state.config.combat_scale
        elseif effect.category == "DANGER" then
            scale = state.config.danger_scale
        elseif effect.category == "BOSS" then
            scale = state.config.boss_scale
        elseif effect.category == "ENVIRONMENT" then
            scale = state.config.environment_scale
        elseif IsUIEffect(effect) then
            scale = state.config.ui_scale
        else
            scale = state.config.player_scale
        end
        local result = Clamp(NumberOr(scale, 1), 0, 2)
        if profile.loop then
            result = result * Clamp(NumberOr(state.config.loop_scale, 1), 0, 2)
        end
        return result
    end

    local function AddPulse(channel, duration, magnitude)
        if magnitude <= 0 or duration <= 0 or not OutputAllowed() then
            return
        end
        duration, magnitude = CalibratePulse(duration, magnitude)
        SuppressNative()
        G.TheInputProxy:AddVibration(channel, duration, magnitude, false)
    end

    local function ScheduleProfile(effect, entity, profile, volume, spatial, distance, source)
        local raw = NumberOr(effect.vibration_intensity, 1)
        local base = MapIntensity(raw)
            * Clamp(NumberOr(state.config.strength, 1), 0, 2)
            * NumberOr(profile.factor, 1)
            * EffectScale(effect, profile)
        base = base * Clamp(NumberOr(volume, 1), 0, 1) * spatial
        local channel = ChannelFor(effect, profile)
        local strongest = 0
        local generation = state.generation
        local hardware, response = GetOutputCalibration()
        local time_scale = hardware.time * response.time
        for i = 1, #profile.pulses do
            local pulse = profile.pulses[i]
            local magnitude = Clamp(base * pulse[3], 0, 1)
            local _, calibrated = CalibratePulse(pulse[2], magnitude)
            strongest = math.max(strongest, calibrated)
            if pulse[1] <= 0 then
                AddPulse(channel, pulse[2], magnitude)
            else
                G.scheduler:ExecuteInTime(pulse[1] * time_scale, function()
                    if generation == state.generation then
                        AddPulse(channel, pulse[2], magnitude)
                    end
                end)
            end
        end
        DebugLog(effect, entity, distance, raw, strongest, profile.total, channel, false, "accepted", source)
    end

    local function LoopKey(emitter, name)
        return tostring(emitter) .. "|" .. tostring(name)
    end

    local function RegisterLoop(effect, emitter, entity, name, volume, profile, distance, source, local_context)
        if name == nil then
            local bounded = { pulses = { { 0, 0.10, 0.70 }, { 0.09, 0.10, 0.55 }, { 0.18, 0.08, 0.40 } }, total = 0.26 }
            local spatial = SpatialFactor(effect, entity, local_context)
            ScheduleProfile(effect, entity, bounded, volume, spatial, distance, source)
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
        }
        DebugLog(effect, entity, distance, NumberOr(effect.vibration_intensity, 1), 0, -1, ChannelFor(effect, profile), false, "loop_started", source)
    end

    local function HandleEvent(event, entity, name, volume, source, dedupe_key, local_context)
        local effect = state.effects[event]
        if effect == nil then
            return false
        end
        if state.config.compatibility == false then
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
        local controller_id = GetControllerID()
        if controller_id == nil then
            DebugLog(effect, entity, nil, NumberOr(effect.vibration_intensity, 1), 0, 0, "n/a", true, "no_active_controller", source)
            return false
        end
        RefreshControllerOutput(controller_id)
        local spatial, distance, reason = SpatialFactor(effect, entity, local_context)
        if spatial <= 0 then
            DebugLog(effect, entity, distance, NumberOr(effect.vibration_intensity, 1), 0, 0, "n/a", true, reason or "spatially_filtered", source)
            return false
        end

        local profile = Profiles.Get(effect)
        local now = Now()
        -- Sound hooks and replicated-action bridges can observe the same native
        -- event through different Lua paths. Keep this key deliberately small:
        -- it only collapses virtually simultaneous copies for one entity.
        local cross_key = event .. "|" .. EntityKey(entity)
        local cross_last = state.bridge_recent[cross_key]
        if cross_last ~= nil and now - cross_last < 0.025 then
            DebugLog(effect, entity, distance, NumberOr(effect.vibration_intensity, 1), 0, profile.total, ChannelFor(effect, profile), true, "cross_path_duplicate", source)
            return false
        end
        state.bridge_recent[cross_key] = now
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
            ScheduleProfile(effect, entity, profile, volume, spatial, distance, source)
        end
        return true
    end

    local function HandleSound(emitter, event, name, volume)
        local effect = state.effects[event]
        if effect == nil then
            return
        end
        local entity = GetEntity(emitter)
        local local_context = false
        if entity == nil and G.TheFrontEnd ~= nil and G.TheFrontEnd.GetSound ~= nil then
            local success, frontend_sound = pcall(G.TheFrontEnd.GetSound, G.TheFrontEnd)
            local_context = success and emitter == frontend_sound
        end
        local profile = Profiles.Get(effect)
        if profile.loop then
            if not ProfileAllowsVibration() or GetControllerID() == nil then
                return
            end
            local spatial, distance = SpatialFactor(effect, entity, local_context)
            if spatial > 0 then
                RegisterLoop(effect, emitter, entity, name, volume, profile, distance, "sound", local_context)
            end
            return
        end
        HandleEvent(event, entity, name, volume, "sound", nil, local_context)
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
            context.local_context == true
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
            SafeHandle(emitter, event, nil, volume)
            return unpack(results, 1, results.n)
        end
    end

    local original_kill = SoundEmitter.KillSound
    SoundEmitter.KillSound = function(emitter, name, ...)
        local results = Pack(original_kill(emitter, name, ...))
        state.loops[LoopKey(emitter, name)] = nil
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
        return unpack(results, 1, results.n)
    end

    if SoundEmitter.SetVolume ~= nil then
        local original_set_volume = SoundEmitter.SetVolume
        SoundEmitter.SetVolume = function(emitter, name, volume, ...)
            local results = Pack(original_set_volume(emitter, name, volume, ...))
            local loop = state.loops[LoopKey(emitter, name)]
            if loop ~= nil then
                loop.volume = NumberOr(volume, loop.volume)
            end
            return unpack(results, 1, results.n)
        end
    end

    local loop_channel = G.VIBRATION_BLOOD_OVER or 2
    G.scheduler:ExecutePeriodic(0.085, function()
        local combined = 0
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
                    local raw = NumberOr(loop.effect.vibration_intensity, 1)
                    local magnitude = MapIntensity(raw)
                        * Clamp(NumberOr(state.config.strength, 1), 0, 2)
                        * EffectScale(loop.effect, loop.profile)
                        * Clamp(loop.volume or 1, 0, 1)
                        * spatial
                        * loop.profile.factor
                    combined = math.max(combined, magnitude)
                end
            end
        end

        if combined > 0.01 then
            AddPulse(loop_channel, 0.10, Clamp(combined, 0, 1))
            state.had_loop_output = true
        elseif state.had_loop_output then
            pcall(function() G.TheInputProxy:RemoveVibration(loop_channel) end)
            state.had_loop_output = false
        end
    end)

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
        for key, timestamp in pairs(state.bridge_recent) do
            if now - timestamp > 2 then
                state.bridge_recent[key] = nil
            end
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
        ApplyConfig = function(values)
            if type(values) == "table" then
                for key, value in pairs(values) do
                    state.config[key] = value
                end
            end
            if state.config.compatibility == false then
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
