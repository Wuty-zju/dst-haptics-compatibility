GLOBAL = _G

local now = 0
local paused = false
local profile_enabled = true
local controller_enabled = true
local controller_type = 1
local vibrations = {}
local removes = {}
local stop_count = 0
local native_enable_calls = {}
local delayed = {}
local periodic = {}
local world_postinit = nil

function GetTimeRealSeconds() return now end
function IsPaused() return paused end
function AddPrefabPostInit(name, fn)
    assert(name == "world")
    world_postinit = fn
end

scheduler = {}
function scheduler:ExecuteInTime(delay, fn)
    table.insert(delayed, { at = now + delay, fn = fn })
end
function scheduler:ExecutePeriodic(period, fn)
    table.insert(periodic, { period = period, fn = fn })
    return periodic[#periodic]
end

local function RunDelayed()
    local pending = delayed
    delayed = {}
    for i = 1, #pending do pending[i].fn() end
end

Profile = { GetVibrationEnabled = function() return profile_enabled end }
TheInput =
{
    ControllerAttached = function() return controller_enabled end,
    GetControllerID = function() return controller_enabled and 1 or 0 end,
}
TheInputProxy =
{
    IsInputDeviceConnected = function(_, id) return controller_enabled and id == 1 end,
    IsInputDeviceEnabled = function(_, id) return controller_enabled and id == 1 end,
    GetInputDeviceCount = function() return 2 end,
    GetInputDeviceType = function(_, id) return id == 1 and controller_type or 0 end,
    GetInputDeviceName = function(_, id) return id == 1 and "Test Xbox Controller" or "Keyboard" end,
    EnableVibration = function() end,
    AddVibration = function(_, channel, duration, magnitude, looped)
        table.insert(vibrations, { channel = channel, duration = duration, magnitude = magnitude, looped = looped })
    end,
    RemoveVibration = function(_, channel) table.insert(removes, channel) end,
    StopVibration = function() stop_count = stop_count + 1 end,
}
TheHaptics =
{
    EnableVibration = function(_, value) table.insert(native_enable_calls, value) end,
}

local function Transform(x, z)
    return { GetWorldPosition = function() return x, 0, z end }
end
local player = { GUID = 1, prefab = "wilson", Transform = Transform(0, 0), IsValid = function() return true end }
local other_player = { GUID = 2, prefab = "willow", Transform = Transform(0, 0), IsValid = function() return true end }
local near_boss = { GUID = 3, prefab = "deerclops", Transform = Transform(14, 0), IsValid = function() return true end }
local far_boss = { GUID = 4, prefab = "deerclops", Transform = Transform(100, 0), IsValid = function() return true end }
ThePlayer = player

local function Emitter(entity)
    local e = { entity = entity, playing = {} }
    function e:GetEntity() return self.entity end
    function e:PlayingSound(name) return self.playing[name] == true end
    return e
end

local frontend_emitter = Emitter(nil)
TheFrontEnd = { GetSound = function() return frontend_emitter end }

SoundEmitter = {}
function SoundEmitter.PlaySound(emitter, event, name, volume)
    if name then emitter.playing[name] = true end
    return "sound-ok", nil, "tail"
end
function SoundEmitter.PlaySoundWithParams(emitter, event, params, volume)
    return "params-ok", params
end
function SoundEmitter.KillSound(emitter, name)
    emitter.playing[name] = nil
    return "kill-ok"
end
function SoundEmitter.KillAllSounds(emitter)
    emitter.playing = {}
    return "kill-all-ok"
end
function SoundEmitter.SetVolume(emitter, name, volume)
    return "volume-ok", volume
end

VIBRATION_CAMERA_SHAKE = 0
VIBRATION_BLOOD_FLASH = 1
VIBRATION_BLOOD_OVER = 2

package.preload.haptics = function()
    return {
        { event = "test/player", vibration = true, vibration_intensity = 1, player_only = true, category = "PLAYER" },
        { event = "test/boss/step", vibration = true, vibration_intensity = 1, category = "BOSS" },
        { event = "test/ui/click", vibration = true, vibration_intensity = 0.5, category = "UI" },
        { event = "test/strong", vibration = true, vibration_intensity = 10, category = "PLAYER" },
        { event = "test/loop_LP", vibration = true, vibration_intensity = 1, category = "ENVIRONMENT" },
        { event = "test/duplicate", vibration = true, vibration_intensity = 0.5, category = "PLAYER" },
        { event = "test/duplicate", vibration = true, vibration_intensity = 2, category = "PLAYER" },
    }
end

local source_root = assert(os.getenv("DST_HAPTICS_MOD_ROOT"), "DST_HAPTICS_MOD_ROOT is required") .. "/"
local function LoadLocalModule(relative)
    local fn, err = loadfile(source_root .. relative)
    assert(fn, err)
    setfenv(fn, _G)
    return fn()
end

local Adapter = LoadLocalModule("scripts/haptic_adapter.lua")
local api = Adapter.Install({ language = "en", strength = 1, debug = false }, LoadLocalModule)
assert(api ~= nil and api.Emit ~= nil)
assert(SoundEmitter._dst_haptics_compat ~= nil)
assert(SoundEmitter._dst_haptics_compat.definitions == 7)
assert(SoundEmitter._dst_haptics_compat.duplicate_events == 1)
assert(native_enable_calls[#native_enable_calls] == false)

local player_emitter = Emitter(player)
local a, b, c = SoundEmitter.PlaySound(player_emitter, "not/matched")
assert(a == "sound-ok" and b == nil and c == "tail")
assert(#vibrations == 0)

SoundEmitter.PlaySound(player_emitter, "test/player")
assert(#vibrations == 1 and vibrations[1].magnitude > 0)
RunDelayed()

now = now + 1
local before = #vibrations
assert(api.Emit("test/player", player, { source = "test_bridge", semantic_key = "bridge-1" }))
assert(#vibrations == before + 1, "bridge event was not emitted")
local xbox_duration = vibrations[#vibrations].duration

local family_duration = {}
for _, device_type in ipairs({ 2, 7, 11 }) do
    controller_type = device_type -- DS4, PS5 controller, DualSense
    now = now + 1
    before = #vibrations
    assert(api.Emit("test/player", player, { source = "controller_matrix", semantic_key = "device-" .. device_type }))
    assert(#vibrations == before + 1, "PlayStation controller type was rejected: " .. device_type)
    family_duration[device_type] = vibrations[#vibrations].duration
end
assert(family_duration[2] > xbox_duration, "DS4 pulse calibration was not applied")
assert(family_duration[7] > family_duration[2], "DualSense pulse calibration was not applied")
assert(math.abs(family_duration[7] - family_duration[11]) < 0.0001, "PS5 controller aliases diverged")
controller_type = 0
now = now + 1
before = #vibrations
assert(not api.Emit("test/player", player, { source = "controller_matrix", semantic_key = "keyboard" }))
assert(#vibrations == before, "keyboard device was treated as a controller")
controller_type = 1

api.ApplyConfig({ player_scale = 0 })
now = now + 1
before = #vibrations
assert(api.Emit("test/player", player, { source = "runtime_config", semantic_key = "player-muted" }))
assert(#vibrations == before, "runtime category scale did not mute output")
api.ApplyConfig({ player_scale = 1, response_mode = "soft", controller_profile = "xbox" })
now = now + 1
assert(api.Emit("test/player", player, { source = "runtime_config", semantic_key = "soft" }))
local soft_magnitude = vibrations[#vibrations].magnitude
api.ApplyConfig({ response_mode = "detail" })
now = now + 1
assert(api.Emit("test/player", player, { source = "runtime_config", semantic_key = "detail" }))
assert(vibrations[#vibrations].magnitude > soft_magnitude, "runtime response mode was not applied")

before = #vibrations
api.ApplyConfig({ compatibility = false })
assert(native_enable_calls[#native_enable_calls] == true, "runtime bypass did not restore native TheHaptics")
now = now + 1
assert(not api.Emit("test/player", player, { source = "runtime_config", semantic_key = "disabled" }))
assert(#vibrations == before, "runtime compatibility OFF still emitted vibration")
api.ApplyConfig({ compatibility = true })
assert(native_enable_calls[#native_enable_calls] == false, "runtime re-enable did not suppress native TheHaptics")

before = #vibrations
SoundEmitter.PlaySound(Emitter(other_player), "test/player")
assert(#vibrations == before, "player_only accepted a nonlocal player")

now = now + 1
SoundEmitter.PlaySound(frontend_emitter, "test/player")
assert(#vibrations == before + 1, "local HUD player_only event was rejected")

now = now + 1
SoundEmitter.PlaySound(Emitter(near_boss), "test/boss/step")
local near_magnitude = vibrations[#vibrations].magnitude
now = now + 1
before = #vibrations
SoundEmitter.PlaySound(Emitter(far_boss), "test/boss/step")
assert(#vibrations == before, "far boss was not filtered")

now = now + 1
SoundEmitter.PlaySound(Emitter(nil), "test/ui/click")
assert(vibrations[#vibrations].magnitude > 0, "UI event with no entity was filtered")

now = now + 1
SoundEmitter.PlaySound(player_emitter, "test/strong")
local strong_magnitude = vibrations[#vibrations].magnitude
assert(strong_magnitude > near_magnitude, "native intensity mapping is not monotonic")

now = now + 1
SoundEmitter.PlaySound(player_emitter, "test/duplicate")
assert(vibrations[#vibrations].magnitude > 0.3, "duplicate event did not use final native definition")

now = now + 1
before = #vibrations
SoundEmitter.PlaySound(player_emitter, "test/player")
SoundEmitter.PlaySound(player_emitter, "test/player")
assert(#vibrations == before + 1, "same-frame duplicate was not suppressed")

profile_enabled = false
now = now + 1
before = #vibrations
SoundEmitter.PlaySound(player_emitter, "test/player")
assert(#vibrations == before, "profile vibration OFF was ignored")
profile_enabled = true

controller_enabled = false
now = now + 1
SoundEmitter.PlaySound(player_emitter, "test/player")
assert(#vibrations == before, "controller disconnect was ignored")
controller_enabled = true

paused = true
now = now + 1
SoundEmitter.PlaySound(player_emitter, "test/player")
assert(#vibrations == before, "pause was ignored")
paused = false

now = now + 1
local loop_emitter = Emitter(near_boss)
SoundEmitter.PlaySound(loop_emitter, "test/loop_LP", "beam", 1)
assert(next(SoundEmitter._dst_haptics_compat.loops) ~= nil)
periodic[1].fn()
assert(vibrations[#vibrations].channel == 2, "loop did not use its dedicated channel")
SoundEmitter.SetVolume(loop_emitter, "beam", 0)
periodic[1].fn()
assert(removes[#removes] == 2, "muted loop did not stop its channel")
SoundEmitter.KillSound(loop_emitter, "beam")
assert(next(SoundEmitter._dst_haptics_compat.loops) == nil)

local world = { ListenForEvent = function(self, event, fn) assert(event == "onremove"); self.onremove = fn end }
world_postinit(world)
local stops_before_unload = stop_count
world.onremove()
assert(stop_count == stops_before_unload + 1, "world unload did not stop all vibration")

print("adapter behavior tests passed")
