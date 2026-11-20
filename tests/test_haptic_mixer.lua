local root = os.getenv("DST_HAPTICS_MOD_ROOT") or "."
GLOBAL = _G
local Mixer = dofile(root .. "/scripts/haptic_mixer.lua")
assert(#Mixer.Build({}) == 0)
assert(#Mixer.Build({ { duration = 0, magnitude = 1 } }) == 0)
local result = Mixer.Build({ { duration = 0.02, magnitude = 0.8 }, { duration = 0.2, magnitude = 0.2 } })
assert(#result == 2)
assert(result[1].delay == 0 and result[1].duration == 0.02 and result[1].magnitude == 0.8)
assert(result[2].delay == 0.02 and math.abs(result[2].duration - 0.18) < 1e-9 and result[2].magnitude == 0.2)
result = Mixer.Build({ { duration = 0.2, magnitude = 0.8 }, { duration = 0.02, magnitude = 0.2 } })
assert(#result == 1 and result[1].duration == 0.2 and result[1].magnitude == 0.8)
result = Mixer.Build({ { duration = 0.1, magnitude = 0.5 }, { duration = 0.1, magnitude = 0.5 } })
assert(#result == 1 and result[1].duration == 0.1)

local Loops = dofile(root .. "/scripts/haptic_loops.lua")
local Util = dofile(root .. "/scripts/haptic_util.lua")
local Parameters = dofile(root .. "/scripts/haptic_parameters.lua")
local state = { config = {}, loops = {}, generation = 0, loop_revision = 0, metrics = { pulses = 0, parameter_updates = 0 } }
local magnitudes, durations, removes, playback_queries = {}, {}, 0, 0
local queued = {}
local output_allowed, change_controller = true, false
TheInputProxy = {
    AddVibration = function(_, _, duration, magnitude)
        magnitudes[#magnitudes + 1] = magnitude
        durations[#durations + 1] = duration
    end,
    RemoveVibration = function() removes = removes + 1 end,
}
scheduler = {
    ExecuteInTime = function(_, _, fn) queued[#queued + 1] = fn end,
}
local loops = Loops.New(state, {
    Util = Util, Parameters = Parameters, Mixer = Mixer,
    SpatialFactor = function() return 1 end,
    MapIntensity = function(value) return value end,
    EffectScale = function() return 1 end,
    CalibratePulse = function(duration, magnitude) return duration, magnitude end,
    OutputAllowed = function()
        if change_controller then
            state.generation = state.generation + 1
            state.loop_revision = state.loop_revision + 1
            state.had_loop_output = false
            change_controller = false
        end
        return output_allowed
    end,
    SuppressNative = function() end,
    ChannelFor = function() return 2 end,
    DebugLog = function() end,
})
local function Emitter()
    return {
        playing = false,
        PlayingSound = function(self)
            playback_queries = playback_queries + 1
            return self.playing
        end,
    }
end
local rain, tree = Emitter(), Emitter()
local rain_effect = { event = "dontstarve/AMB/rain", vibration_intensity = 1 }
local tree_effect = { event = "dontstarve_DLC001/common/rain_on_tree", vibration_intensity = 1 }
local profile = { duration = 0.10, factor = 1 }
local tree_entity = { IsValid = function(self) return self.valid end, valid = true }

-- Native weather can play a loop and update its parameter in the same update.
loops.Register(rain_effect, rain, nil, "rain", 1, profile)
loops.SetParameter(rain, "rain", "intensity", 0.2)
assert(playback_queries == 0 and #magnitudes == 0, "initial parameter queried the handle before the sample")
rain.playing = true
tree.playing = true
loops.Register(tree_effect, tree, tree_entity, "treerainsound", 1, profile)
loops.SetParameter(tree, "treerainsound", "intensity", 0.6)
loops.Refresh()
assert(#magnitudes == 1 and magnitudes[1] == 0.6, "sample lost the stronger live weather contribution")

-- A weather update writes both handles, including unchanged values, before the
-- mix is rendered. Only their latest state should reach the output channel.
local queries_before = playback_queries
loops.SetParameter(tree, "treerainsound", "intensity", 0.6)
loops.SetParameter(rain, "rain", "intensity", 0.2)
loops.SetParameter(rain, "rain", "unmapped", 100)
loops.SetVolume(rain, "rain", 2)
loops.SetParameter(tree, "treerainsound", "intensity", 0.4)
loops.SetParameter(rain, "rain", "intensity", 0.8)
loops.SetVolume(rain, "rain", 0.75)
assert(playback_queries == queries_before and #magnitudes == 1 and removes == 0, "same-frame gains redrew the channel")
loops.Refresh()
assert(#magnitudes == 2 and math.abs(magnitudes[2] - 0.6) < 1e-9 and removes == 1)

-- Actual mute removes the previous mix immediately, then restores an already
-- sampled survivor. A newly registered handle waits for its own sample.
local pending = Emitter()
loops.Register(rain_effect, pending, nil, "pending", 1, profile)
queries_before = playback_queries
loops.SetVolume(rain, "rain", 0)
assert(removes == 2 and #magnitudes == 3 and magnitudes[3] == 0.4, "mute did not replace the active mix")
assert(playback_queries == queries_before + 2 and state.loops[loops.Key(pending, "pending")] ~= nil,
    "mute probed or removed a newly registered handle")
loops.SetParameter(tree, "treerainsound", "intensity", 0)
assert(removes == 3 and #magnitudes == 3, "zero parameter did not clear the previous mix")
loops.Remove(tree, "treerainsound")
loops.Remove(rain, "rain")
loops.Remove(pending, "pending")

-- Inactive output accepts live state updates and still releases invalid
-- entities. Resuming reads the latest values without replaying old gains.
output_allowed = false
loops.Register(tree_effect, tree, tree_entity, "treerainsound", 1, profile)
loops.Register(rain_effect, rain, nil, "rain", 1, profile)
queries_before = playback_queries
loops.SetParameter(rain, "rain", "intensity", 0.3)
loops.SetVolume(rain, "rain", 0.5)
tree_entity.valid = false
loops.Refresh()
assert(playback_queries == queries_before and #magnitudes == 3)
assert(state.loops[loops.Key(tree, "treerainsound")] == nil, "gated mix retained an invalid entity")
output_allowed = true
change_controller = true
loops.Refresh()
assert(#magnitudes == 4 and magnitudes[4] == 0.15, "detecting the new controller discarded its first eligible mix")

-- A restart with the same name resets gain. A kill before the next sample
-- still removes the previous vibration belonging to that handle.
loops.Register(rain_effect, rain, nil, "rain", 1, profile)
assert(state.loops[loops.Key(rain, "rain")].params.intensity == nil, "restart inherited a prior instance's parameter")
loops.Remove(rain, "rain")
assert(removes == 4 and #magnitudes == 4 and next(state.loops) == nil, "restart followed by kill left the prior vibration")

-- A delayed mix segment must recheck its ownership after the gate, which may
-- detect a new controller and cancel the previous controller's generation.
loops.Register(rain_effect, rain, nil, "rain", 0.8, { duration = 0.02, factor = 1 })
loops.Register(tree_effect, tree, nil, "treerainsound", 0.25, profile)
loops.Refresh()
assert(#magnitudes == 5 and magnitudes[5] == 0.8 and #queued == 1)
change_controller = true
queued[1]()
assert(#magnitudes == 5, "delayed segment leaked across controller generations")

-- Native lighter unequip removes the lighterfire FX without a KillSound call.
-- A weak torch contribution can remain queued behind a shorter lunar hail pulse.
local hail_effect = { event = "rifts3/lunarhail/lunar_rainAMB", vibration_intensity = 1 }
local lighter_effect = { event = "dontstarve/wilson/lighter_LP", vibration_intensity = 1 }
local function CheckLighterRemoval(survivor_duration, expected_pulses)
    state.loops = {}
    queued = {}
    local torch, nearby_torch = Emitter(), Emitter()
    local lighter_fx = { IsValid = function(self) return self.valid end, valid = true }
    torch.playing, nearby_torch.playing = true, true
    loops.Register(hail_effect, rain, nil, "rain", 0.8, { duration = 0.05, factor = 1 })
    loops.SetParameter(rain, "rain", "intensity", 1)
    loops.Register(lighter_effect, torch, lighter_fx, "torch", 0.4, profile)
    loops.SetParameter(torch, "torch", "intensity", 1)
    if survivor_duration ~= nil then
        local nearby_fx = { IsValid = function() return true end }
        loops.Register(lighter_effect, nearby_torch, nearby_fx, "torch", 0.4, { duration = survivor_duration, factor = 1 })
    end
    local before = #magnitudes
    loops.Refresh()
    assert(#magnitudes == before + 1 and magnitudes[#magnitudes] == 0.8
        and durations[#durations] == 0.05 and #queued == 1, "test did not build the expected hail and lighter mix")
    lighter_fx.valid = false
    local previous_removes = removes
    queued[1]()
    assert(#magnitudes == before + 1 + expected_pulses, "delayed mix did not respect the remaining live contributions")
    assert(removes == previous_removes and #queued == 1, "delayed mix restarted the expired hail pulse")
    if expected_pulses == 1 then
        assert(magnitudes[#magnitudes] == 0.4 and durations[#durations] == 0.05, "live support changed the planned tail")
    end
end
CheckLighterRemoval(nil, 0)
CheckLighterRemoval(0.08, 0) -- Same gain, but the survivor ends before this segment.
CheckLighterRemoval(0.10, 1)
print("loop mixer tests passed: sampled gain, immediate stops, and supported delayed segments")
