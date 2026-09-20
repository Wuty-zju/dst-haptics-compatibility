GLOBAL = _G

local root = assert(os.getenv("DST_HAPTICS_MOD_ROOT"), "DST_HAPTICS_MOD_ROOT is required")
local fn, err = loadfile(root .. "/scripts/haptic_parameters.lua")
assert(fn, err)
setfenv(fn, _G)
local Parameters = fn()

local function Scale(event, params)
    local value = Parameters.GetScale(event, params)
    return value
end

assert(Scale("dontstarve/characters/walter/woby/big/footstep", { intensity = 0.1 })
    < Scale("dontstarve/characters/walter/woby/big/footstep", { intensity = 1 }))
assert(Scale("dontstarve_DLC001/common/iceboulder_hit", { intensity = 0.1 })
    < Scale("dontstarve_DLC001/common/iceboulder_hit", { intensity = 0.3 }))
assert(Scale("dontstarve/creatures/together/antlion/sfx/ground_break", { size = 0 })
    < Scale("dontstarve/creatures/together/antlion/sfx/ground_break", { size = 1 }))
assert(Scale("dontstarve/creatures/together/antlion/sfx/ground_break", { size = 1 })
    < Scale("dontstarve/creatures/together/antlion/sfx/ground_break", { size = 2 }))
assert(Scale("moonstorm/creatures/boss/alterguardian2/spike", { intensity = 0.1 })
    < Scale("moonstorm/creatures/boss/alterguardian2/spike", { intensity = 1 }))
assert(Scale("hookline_2/creatures/boss/crabking/magic_LP", { intensity = 0 }) == 0)
assert(Scale("hookline_2/creatures/boss/crabking/magic_LP", { intensity = 1 }) == 1)
assert(Scale("rifts5/lunar_boss/supernova_burst_LP", { blocked = 0.05 })
    > Scale("rifts5/lunar_boss/supernova_burst_LP", { blocked = 0.35 }))
assert(Scale("dontstarve/characters/wormwood/fertalize_LP", { start = 0.5 }) == 1)
assert(Scale("future/event", { intensity = 0 }) == 1, "unknown parameters must remain neutral")

local original = { intensity = 0.5, label = "ignored" }
local copy = Parameters.Copy(original)
original.intensity = 1
assert(copy.intensity == 0.5 and copy.label == nil, "parameter snapshots are not isolated")

print("haptic parameter policy tests passed")
