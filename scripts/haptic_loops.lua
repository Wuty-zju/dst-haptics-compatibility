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
    local function LoopKey(emitter, name)
        return tostring(emitter) .. "|" .. tostring(name)
    end

    local function ClearLoopChannel()
        if state.had_loop_output then
            pcall(function() G.TheInputProxy:RemoveVibration(loop_channel) end)
            state.had_loop_output = false
        end
    end

    local function IsPlaying(loop)
        if loop.emitter == nil then return false end
        if loop.emitter.PlayingSound == nil then return true end
        local success, playing = pcall(loop.emitter.PlayingSound, loop.emitter, loop.name)
        return success and playing == true
    end

    local function EmitSegment(segment)
        SuppressNative()
        G.TheInputProxy:AddVibration(loop_channel, segment.duration, segment.magnitude, false)
        state.had_loop_output = true
        state.metrics.pulses = state.metrics.pulses + 1
    end

    local function IsCurrentMix(revision, generation)
        return revision == state.loop_revision and generation == state.generation
    end

    local function RefreshLoops(remix)
        if next(state.loops) == nil and not state.had_loop_output then return end
        local previous_revision = state.loop_revision
        local allowed = OutputAllowed()
        state.loop_revision = state.loop_revision + 1
        local revision, generation = state.loop_revision, state.generation
        local contributions = allowed and {} or nil
        for key, loop in pairs(state.loops) do
            -- Entity lifetime is independent of whether a controller can play.
            if loop.entity ~= nil and loop.entity.IsValid ~= nil and not loop.entity:IsValid() then
                state.loops[key] = nil
            elseif allowed and (not remix or loop.mixed_revision == previous_revision) then
                -- Immediate mute/kill re-mixes the previously sampled sounds.
                -- New handles and their initial gain wait for a normal sample.
                if IsPlaying(loop) then
                    local spatial = SpatialFactor(loop.effect, loop.entity, loop.local_context)
                    local magnitude = MapIntensity(NumberOr(loop.effect.vibration_intensity, 1))
                        * Clamp(NumberOr(state.config.strength, 1), 0, 2)
                        * EffectScale(loop.effect, loop.profile)
                        * Clamp(loop.volume, 0, 1)
                        * spatial
                        * loop.profile.factor
                        * loop.parameter_scale
                    local duration_scale = Clamp(NumberOr(state.config.duration, 1), 0, 2)
                        * EffectScale(loop.effect, loop.profile, "_duration")
                    if magnitude > 0 and duration_scale > 0 then
                        local duration, calibrated = CalibratePulse(loop.profile.duration, magnitude, duration_scale)
                        contributions[#contributions + 1] = { duration = duration, magnitude = calibrated }
                        loop.mixed_revision = revision
                    end
                elseif not remix then
                    state.loops[key] = nil
                end
            end
        end
        ClearLoopChannel()
        if not allowed or #contributions == 0 then return end
        local segments = Mixer.Build(contributions)
        for i = 1, #segments do
            local segment = segments[i]
            if segment.delay == 0 then
                EmitSegment(segment)
            elseif segment.delay < 0.085 then
                -- The next periodic sample replaces later segments. Never leave
                -- callbacks queued beyond that sample merely to invalidate them.
                G.scheduler:ExecuteInTime(segment.delay, function()
                    if IsCurrentMix(revision, generation) and OutputAllowed() and IsCurrentMix(revision, generation) then
                        EmitSegment(segment)
                    end
                end)
            end
        end
    end

    local function RemixIfContributing(loop)
        if state.had_loop_output and loop.mixed_revision == state.loop_revision then
            RefreshLoops(true)
        end
    end

    local function RegisterLoop(effect, emitter, entity, name, volume, profile, distance, source, local_context, params)
        if name == nil then
            local bounded = { pulses = { { 0, 0.10, 0.70 }, { 0.09, 0.10, 0.55 }, { 0.18, 0.08, 0.40 } }, total = 0.26 }
            local spatial = SpatialFactor(effect, entity, local_context)
            ScheduleProfile(effect, entity, bounded, volume, spatial, distance, source, params)
            return
        end
        local key = LoopKey(emitter, name)
        local previous = state.loops[key]
        local snapshot = Parameters.Copy(params) or {}
        local loop =
        {
            emitter = emitter,
            entity = entity,
            name = name,
            effect = effect,
            volume = NumberOr(volume, 1),
            profile = profile,
            local_context = local_context,
            params = snapshot,
            parameter_scale = Parameters.GetScale(effect.event, snapshot),
            -- A stop before the next sample must still clear the old pulse.
            mixed_revision = previous ~= nil and previous.mixed_revision or nil,
        }
        state.loops[key] = loop
        if loop.volume <= 0 or loop.parameter_scale == 0 then RemixIfContributing(loop) end
        if source ~= nil then
            DebugLog(effect, entity, distance, NumberOr(effect.vibration_intensity, 1), 0, -1, ChannelFor(effect, profile), false, "loop_started", source, params, loop.parameter_scale)
        end
    end

    local function Remove(emitter, name)
        local key = LoopKey(emitter, name)
        local loop = state.loops[key]
        if loop ~= nil then
            state.loops[key] = nil
            RemixIfContributing(loop)
        end
    end
    local function RemoveEmitter(emitter)
        local contributed = false
        for key, loop in pairs(state.loops) do
            if loop.emitter == emitter then
                state.loops[key] = nil
                contributed = contributed or loop.mixed_revision == state.loop_revision
            end
        end
        if contributed and state.had_loop_output then RefreshLoops(true) end
    end
    local function ForgetPlayer(player)
        -- The caller has already stopped the retiring player's mixed output.
        for key, loop in pairs(state.loops) do
            if loop.entity == player or (loop.local_context and loop.effect.player_only == true) then
                state.loops[key] = nil
            end
        end
    end
    local function SetVolume(emitter, name, volume)
        local loop = state.loops[LoopKey(emitter, name)]
        if loop ~= nil then
            local previous = loop.volume
            loop.volume = NumberOr(volume, loop.volume)
            if previous > 0 and loop.volume <= 0 then RemixIfContributing(loop) end
        end
    end
    local function SetParameter(emitter, name, parameter, value)
        local loop = state.loops[LoopKey(emitter, name)]
        if loop ~= nil and type(parameter) == "string" and type(value) == "number" then
            state.metrics.parameter_updates = state.metrics.parameter_updates + 1
            if loop.params[parameter] == value then return end
            local previous = loop.parameter_scale
            loop.params[parameter] = value
            loop.parameter_scale = Parameters.GetScale(loop.effect.event, loop.params)
            -- Ordinary gain changes are consumed together by the next sample.
            if previous > 0 and loop.parameter_scale == 0 then RemixIfContributing(loop) end
        end
    end
    return { Key = LoopKey, Register = RegisterLoop, Refresh = RefreshLoops,
        Remove = Remove, RemoveEmitter = RemoveEmitter, ForgetPlayer = ForgetPlayer, SetVolume = SetVolume,
        SetParameter = SetParameter }
end
return Loops
