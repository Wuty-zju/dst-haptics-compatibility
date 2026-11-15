-- Named sound lifecycle and independent loop-envelope mixing.
local G = GLOBAL
local pairs, next, pcall, tostring, type = G.pairs, G.next, G.pcall, G.tostring, G.type
local Loops = {}
function Loops.New(state, d)
    local Clamp, NumberOr = d.Util.Clamp, d.Util.NumberOr
    local SpatialFactor, ScheduleProfile = d.SpatialFactor, d.ScheduleProfile
    local ChannelFor, DebugLog = d.ChannelFor, d.DebugLog
    local Parameters, Mixer = d.Parameters, d.Mixer
    local MapIntensity, EffectScale = d.MapIntensity, d.EffectScale
    local CalibratePulse, OutputAllowed = d.CalibratePulse, d.OutputAllowed
    local SuppressNative = d.SuppressNative
    local loop_channel = G.VIBRATION_BLOOD_OVER or 2
    local RefreshLoops
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

    RefreshLoops = function()
        if next(state.loops) == nil and not state.had_loop_output then return end
        -- Entity lifetime is not conditional on output availability. In
        -- particular, unplugging a controller must not retain removed FX.
        for key, loop in pairs(state.loops) do
            if loop.entity ~= nil and loop.entity.IsValid ~= nil and not loop.entity:IsValid() then
                state.loops[key] = nil
            end
        end
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
                if OutputAllowed() and revision == state.loop_revision and generation == state.generation then
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
    local function Remove(emitter, name)
        local key = LoopKey(emitter, name)
        if state.loops[key] ~= nil then
            state.loops[key] = nil
            StopLoopChannelIfIdle()
        end
    end
    local function RemoveEmitter(emitter)
        local changed = false
        for key, loop in pairs(state.loops) do
            if loop.emitter == emitter then state.loops[key] = nil; changed = true end
        end
        if changed then StopLoopChannelIfIdle() end
    end
    local function SetVolume(emitter, name, volume)
        local loop = state.loops[LoopKey(emitter, name)]
        if loop ~= nil then
            loop.volume = NumberOr(volume, loop.volume)
            StopLoopChannelIfIdle()
        end
    end
    local function SetParameter(emitter, name, parameter, value)
        local loop = state.loops[LoopKey(emitter, name)]
        if loop ~= nil and type(parameter) == "string" and type(value) == "number" then
            loop.params[parameter] = value
            state.metrics.parameter_updates = state.metrics.parameter_updates + 1
            StopLoopChannelIfIdle()
        end
    end
    return { Key = LoopKey, Register = RegisterLoop, Refresh = RefreshLoops,
        Remove = Remove, RemoveEmitter = RemoveEmitter, SetVolume = SetVolume,
        SetParameter = SetParameter, Changed = StopLoopChannelIfIdle }
end
return Loops
