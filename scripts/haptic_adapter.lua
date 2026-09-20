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
        return
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
        native_suppressed = false,
        had_loop_output = false,
        last_controller_id = nil,
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

    local function DebugLog(effect, entity, distance, raw_intensity, final_intensity, duration, channel, filtered, reason)
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
            "[DST Haptics Compat] event=%s category=%s entity=%s distance=%s raw=%.3f final=%.3f duration=%.3f channel=%s filtered=%s reason=%s",
            effect.event,
            tostring(effect.category or "UNSPECIFIED"),
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

    local function GetControllerID()
        if G.TheInput == nil or G.TheInput.ControllerAttached == nil or not G.TheInput:ControllerAttached() then
            return nil
        end
        local id = G.TheInput:GetControllerID()
        if type(id) ~= "number" or id <= 0 then
            return nil
        end
        if not G.TheInputProxy:IsInputDeviceConnected(id) or not G.TheInputProxy:IsInputDeviceEnabled(id) then
            return nil
        end
        return id
    end

    local function OutputAllowed()
        if not ProfileAllowsVibration() or IsPaused() then
            return false
        end
        local id = GetControllerID()
        if id == nil then
            return false
        end
        state.last_controller_id = id
        return true
    end

    local function SuppressNative()
        if G.TheHaptics ~= nil and G.TheHaptics.EnableVibration ~= nil then
            pcall(function() G.TheHaptics:EnableVibration(false) end)
            if not state.native_suppressed then
                state.native_suppressed = true
                if state.config.debug then
                    print("[DST Haptics Compat] " .. L(state.config.language, "native_suppressed"))
                end
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

    local function SpatialFactor(effect, entity)
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
        if entity == nil or entity.Transform == nil then
            return 0, nil, "no_spatial_entity"
        end

        local px, _, pz = G.ThePlayer.Transform:GetWorldPosition()
        local ex, _, ez = entity.Transform:GetWorldPosition()
        local dx, dz = ex - px, ez - pz
        local distance = math.sqrt(dx * dx + dz * dz)
        local policy = DISTANCE_POLICY[effect.category] or DISTANCE_POLICY.PLAYER
        if distance <= policy.near then
            return 1, distance, nil
        elseif distance >= policy.far then
            return 0, distance, "outside_spatial_range"
        end
        local t = (distance - policy.near) / (policy.far - policy.near)
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

    local function AddPulse(channel, duration, magnitude)
        if magnitude <= 0 or duration <= 0 or not OutputAllowed() then
            return
        end
        SuppressNative()
        G.TheInputProxy:AddVibration(channel, duration, Clamp(magnitude, 0, 1), false)
    end

    local function ScheduleProfile(effect, entity, profile, volume, spatial, distance)
        local raw = NumberOr(effect.vibration_intensity, 1)
        local base = MapIntensity(raw) * Clamp(NumberOr(state.config.strength, 1), 0, 2)
        base = base * Clamp(NumberOr(volume, 1), 0, 1) * spatial
        local channel = ChannelFor(effect, profile)
        local strongest = 0
        for i = 1, #profile.pulses do
            local pulse = profile.pulses[i]
            local magnitude = Clamp(base * pulse[3], 0, 1)
            strongest = math.max(strongest, magnitude)
            if pulse[1] <= 0 then
                AddPulse(channel, pulse[2], magnitude)
            else
                G.scheduler:ExecuteInTime(pulse[1], function()
                    AddPulse(channel, pulse[2], magnitude)
                end)
            end
        end
        DebugLog(effect, entity, distance, raw, strongest, profile.total, channel, false, "accepted")
    end

    local function LoopKey(emitter, name)
        return tostring(emitter) .. "|" .. tostring(name)
    end

    local function RegisterLoop(effect, emitter, entity, name, volume, profile, distance)
        if name == nil then
            local bounded = { pulses = { { 0, 0.10, 0.70 }, { 0.09, 0.10, 0.55 }, { 0.18, 0.08, 0.40 } }, total = 0.26 }
            local spatial = SpatialFactor(effect, entity)
            ScheduleProfile(effect, entity, bounded, volume, spatial, distance)
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
        }
        DebugLog(effect, entity, distance, NumberOr(effect.vibration_intensity, 1), 0, -1, ChannelFor(effect, profile), false, "loop_started")
    end

    local function HandleSound(emitter, event, name, volume)
        local effect = state.effects[event]
        if effect == nil then
            return
        end
        local entity = GetEntity(emitter)
        if effect.vibration ~= true then
            DebugLog(effect, entity, nil, NumberOr(effect.vibration_intensity, 0), 0, 0, "n/a", true, "vibration_disabled_in_native_table")
            return
        end
        if not ProfileAllowsVibration() then
            DebugLog(effect, entity, nil, NumberOr(effect.vibration_intensity, 1), 0, 0, "n/a", true, "profile_vibration_off")
            return
        end
        if GetControllerID() == nil then
            DebugLog(effect, entity, nil, NumberOr(effect.vibration_intensity, 1), 0, 0, "n/a", true, "no_active_controller")
            return
        end
        local spatial, distance, reason = SpatialFactor(effect, entity)
        if spatial <= 0 then
            DebugLog(effect, entity, distance, NumberOr(effect.vibration_intensity, 1), 0, 0, "n/a", true, reason or "spatially_filtered")
            return
        end

        local profile = Profiles.Get(effect)
        local now = Now()
        local key = event .. "|" .. EntityKey(entity) .. "|" .. tostring(name or "oneshot")
        local last = state.recent[key]
        if last ~= nil and now - last < DedupeWindow(effect, profile) then
            DebugLog(effect, entity, distance, NumberOr(effect.vibration_intensity, 1), 0, profile.total, ChannelFor(effect, profile), true, "deduplicated")
            return
        end
        state.recent[key] = now

        if profile.loop then
            RegisterLoop(effect, emitter, entity, name, volume, profile, distance)
        else
            ScheduleProfile(effect, entity, profile, volume, spatial, distance)
        end
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
                    local spatial = SpatialFactor(loop.effect, loop.entity)
                    local raw = NumberOr(loop.effect.vibration_intensity, 1)
                    local magnitude = MapIntensity(raw)
                        * Clamp(NumberOr(state.config.strength, 1), 0, 2)
                        * Clamp(loop.volume or 1, 0, 1)
                        * spatial
                        * loop.profile.factor
                    combined = math.max(combined, magnitude)
                end
            end
        end

        if combined > 0.01 then
            G.TheInputProxy:AddVibration(loop_channel, 0.10, Clamp(combined, 0, 1), false)
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
    end)


    -- World removal is the one lifecycle boundary where stopping every vibration
    -- is desirable: no controller output may leak into the loading/frontend state.
    AddPrefabPostInit("world", function(inst)
        inst:ListenForEvent("onremove", function()
            state.loops = {}
            state.recent = {}
            state.had_loop_output = false
            pcall(function() G.TheInputProxy:StopVibration() end)
        end)
    end)

    SuppressNative()
    print("[DST Haptics Compat] " .. L(config.language, "initialized", unique_count, state.definitions, state.duplicate_events))
end

return Adapter
