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

local function Transform(x, z, y)
    return { GetWorldPosition = function() return x, y or 0, z end }
end
local player = { GUID = 1, prefab = "wilson", Transform = Transform(0, 0), IsValid = function() return true end }
local other_player = { GUID = 2, prefab = "willow", Transform = Transform(0, 0), IsValid = function() return true end }
local near_boss = { GUID = 3, prefab = "deerclops", Transform = Transform(14, 0), IsValid = function() return true end }
local far_boss = { GUID = 4, prefab = "deerclops", Transform = Transform(100, 0), IsValid = function() return true end }
local focal_entity = { GUID = 5, prefab = "focalpoint", Transform = Transform(100, 0), IsValid = function() return true end }
ThePlayer = player

local function Emitter(entity)
    local e = { entity = entity, playing = {} }
    function e:GetEntity() return self.entity end
    function e:PlayingSound(name) return self.playing[name] == true end
    return e
end

local frontend_emitter = Emitter(nil)
local focal_emitter = Emitter(focal_entity)
TheFrontEnd = { GetSound = function() return frontend_emitter end }
TheFocalPoint = { SoundEmitter = focal_emitter }
Sim = { SetListener = function(_, x, y, z) return "listener-ok", x, y, z end }

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
function SoundEmitter.SetParameter(emitter, name, parameter, value)
    return "parameter-ok", parameter, value
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
        { event = "test/environment/local", vibration = true, vibration_intensity = 1, category = "ENVIRONMENT" },
        { event = "test/boss/attack", vibration = true, vibration_intensity = 1, category = "BOSS" },
        { event = "dontstarve/characters/walter/woby/big/footstep", vibration = true, vibration_intensity = 1, category = "PLAYER" },
        { event = "hookline_2/creatures/boss/crabking/magic_LP", vibration = true, vibration_intensity = 1, category = "BOSS" },
        { event = "dontstarve/wilson/equip_item", vibration = true, vibration_intensity = 1, category = "PLAYER" },
        { event = "dontstarve/common/nightmareAddFuel", vibration = true, vibration_intensity = 1, category = "ENVIRONMENT" },
        { event = "dontstarve/wilson/burned", vibration = true, vibration_intensity = 1, category = "ENVIRONMENT" },
        { event = "dontstarve/common/teleportworm/travel", vibration = true, vibration_intensity = 1, category = "ENVIRONMENT" },
        { event = "rifts4/worm_boss/beingdigested_lp", vibration = true, vibration_intensity = 1, category = "BOSS" },
        { event = "rifts5/lunar_boss/supernova_burst_LP", vibration = true, vibration_intensity = 1, category = "BOSS" },
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
assert(SoundEmitter._dst_haptics_compat.definitions == 17)
assert(SoundEmitter._dst_haptics_compat.duplicate_events == 1)
assert(native_enable_calls[#native_enable_calls] == false)

local calibration_before = #vibrations
assert(api.TestPulse("weak"))
assert(#vibrations == calibration_before + 1, "explicit calibration pulse did not run")
assert(not api.TestPulse("unknown"), "unknown calibration level was accepted")
vibrations = {}

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

api.ApplyConfig({ output_mode = "diagnostic" })
now = now + 1
before = #vibrations
assert(api.Emit("test/player", player, { source = "diagnostic", semantic_key = "diagnostic" }))
assert(#vibrations == before, "diagnostic mode emitted motor output")
assert(native_enable_calls[#native_enable_calls] == false, "diagnostic mode did not suppress native output")
api.ApplyConfig({ output_mode = "native" })
now = now + 1
assert(not api.Emit("test/player", player, { source = "native", semantic_key = "native" }))
assert(native_enable_calls[#native_enable_calls] == true, "native mode did not restore TheHaptics")
api.ApplyConfig({ output_mode = "compatibility" })
assert(native_enable_calls[#native_enable_calls] == false, "compatibility mode did not suppress native TheHaptics")

before = #vibrations
SoundEmitter.PlaySound(Emitter(other_player), "test/player")
assert(#vibrations == before, "player_only accepted a nonlocal player")

now = now + 1
SoundEmitter.PlaySound(frontend_emitter, "test/player")
assert(#vibrations == before + 1, "local HUD player_only event was rejected")

now = now + 1
before = #vibrations
SoundEmitter.PlaySound(focal_emitter, "test/environment/local")
assert(#vibrations == before + 1, "listener-local FocalPoint event was spatially filtered")

for _, event in ipairs({
    "dontstarve/wilson/equip_item",
    "dontstarve/common/nightmareAddFuel",
    "dontstarve/wilson/burned",
    "dontstarve/common/teleportworm/travel",
}) do
    now = now + 1
    before = #vibrations
    SoundEmitter.PlaySound(focal_emitter, event)
    assert(#vibrations == before + 1, "native FocalPoint event was filtered: " .. event)
end

SoundEmitter.PlaySound(focal_emitter, "rifts4/worm_boss/beingdigested_lp", "worm_boss_digest")
SoundEmitter.PlaySound(focal_emitter, "rifts5/lunar_boss/supernova_burst_LP", "lunarburn_supernova")
assert(next(SoundEmitter._dst_haptics_compat.loops) ~= nil, "native FocalPoint loops were not registered")
SoundEmitter.KillSound(focal_emitter, "worm_boss_digest")
SoundEmitter.KillSound(focal_emitter, "lunarburn_supernova")

now = now + 1
before = #vibrations
SoundEmitter.PlaySound(Emitter(nil), "test/environment/local")
assert(#vibrations == before, "unowned non-UI event bypassed spatial filtering")

now = now + 1
SoundEmitter.PlaySound(Emitter(near_boss), "test/boss/step")
local near_magnitude = vibrations[#vibrations].magnitude
now = now + 1
before = #vibrations
SoundEmitter.PlaySound(Emitter(far_boss), "test/boss/step")
assert(#vibrations == before, "far boss was not filtered")

local listener_a, listener_b = Sim:SetListener(100, 20, 0)
assert(listener_a == "listener-ok" and listener_b == 100, "Sim.SetListener return values changed")
now = now + 1
before = #vibrations
SoundEmitter.PlaySound(Emitter(near_boss), "test/boss/step")
assert(#vibrations == before, "3D audio listener position was ignored")
Sim:SetListener(0, 0, 0)

now = now + 1
SoundEmitter.PlaySound(Emitter(nil), "test/ui/click")
assert(vibrations[#vibrations].magnitude > 0, "UI event with no entity was filtered")

now = now + 1
SoundEmitter.PlaySound(player_emitter, "test/strong")
local strong_magnitude = vibrations[#vibrations].magnitude
assert(strong_magnitude > near_magnitude, "native intensity mapping is not monotonic")

now = now + 1
SoundEmitter.PlaySoundWithParams(player_emitter, "dontstarve/characters/walter/woby/big/footstep", { intensity = 0.1 })
local weak_parameter_magnitude = vibrations[#vibrations].magnitude
now = now + 1
SoundEmitter.PlaySoundWithParams(player_emitter, "dontstarve/characters/walter/woby/big/footstep", { intensity = 1 })
assert(vibrations[#vibrations].magnitude > weak_parameter_magnitude, "PlaySoundWithParams intensity was discarded")

api.ApplyConfig({ boss_scale = 0, combat_scale = 1 })
now = now + 1
before = #vibrations
SoundEmitter.PlaySound(Emitter(near_boss), "test/boss/attack")
assert(#vibrations == before, "Boss category scale did not apply to a combat-family event")
api.ApplyConfig({ boss_scale = 1, combat_scale = 0 })
now = now + 1
SoundEmitter.PlaySound(Emitter(near_boss), "test/boss/attack")
assert(#vibrations == before, "Combat semantic scale did not apply to a Boss event")
api.ApplyConfig({ boss_scale = 1, combat_scale = 1 })

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

now = now + 1
local crab_emitter = Emitter(near_boss)
SoundEmitter.PlaySound(crab_emitter, "hookline_2/creatures/boss/crabking/magic_LP", "crabmagic", 1)
local p1, p2, p3 = SoundEmitter.SetParameter(crab_emitter, "crabmagic", "intensity", 0)
assert(p1 == "parameter-ok" and p2 == "intensity" and p3 == 0, "SetParameter return values changed")
before = #vibrations
periodic[1].fn()
assert(#vibrations == before, "zero loop parameter still produced vibration")
SoundEmitter.SetParameter(crab_emitter, "crabmagic", "intensity", 1)
periodic[1].fn()
assert(#vibrations == before + 1, "live loop parameter did not restore vibration")
SoundEmitter.KillSound(crab_emitter, "crabmagic")

local world = { ListenForEvent = function(self, event, fn) assert(event == "onremove"); self.onremove = fn end }
world_postinit(world)
local stops_before_unload = stop_count
world.onremove()
assert(stop_count == stops_before_unload + 1, "world unload did not stop all vibration")

print("adapter behavior tests passed")
