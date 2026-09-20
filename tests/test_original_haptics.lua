GLOBAL = _G

local original_scripts = assert(os.getenv("DST_ORIGINAL_SCRIPTS"), "DST_ORIGINAL_SCRIPTS is required")
local mod_root = assert(os.getenv("DST_HAPTICS_MOD_ROOT"), "DST_HAPTICS_MOD_ROOT is required")
local haptics_path = original_scripts .. "/haptics.lua"
local profiles_path = mod_root .. "/scripts/haptic_profiles.lua"

local load_haptics, haptics_error = loadfile(haptics_path)
assert(load_haptics, haptics_error)
local effects = load_haptics()
assert(type(effects) == "table" and #effects >= 490)

local load_profiles, profiles_error = loadfile(profiles_path)
assert(load_profiles, profiles_error)
local Profiles = load_profiles()

local indexed = {}
local Tuning = dofile(mod_root .. "/scripts/haptic_tuning.lua")
local tuning_checks = 0
local vibrating = 0
for i = 1, #effects do
    local effect = effects[i]
    indexed[effect.event] = effect
    if effect.vibration == true then
        vibrating = vibrating + 1
        local profile = Profiles.Get(effect)
        assert(type(profile) == "table", "no profile for " .. effect.event)
        assert(profile.loop == true or type(profile.pulses) == "table", "invalid profile for " .. effect.event)
        local category = ({ DANGER = "danger", BOSS = "boss", ENVIRONMENT = "environment", UI = "ui" })[effect.category] or "player"
        for _, suffix in ipairs({ "_scale", "_duration" }) do
            for step = 0, 40 do
                local ratio = step / 20
                local value = Tuning.Scale({ [category .. suffix] = ratio }, effect, profile, suffix, false)
                assert(math.abs(value - ratio) < 1e-9, effect.event .. " native category tuning failed")
                tuning_checks = tuning_checks + 1
            end
        end
    end
end

local required =
{
    "dontstarve/wilson/use_axe_tree",
    "dontstarve/wilson/use_pick_rock",
    "dontstarve/wilson/dig",
    "dontstarve/wilson/hit",
    "dontstarve/impacts/impact_flesh_med_dull",
    "dontstarve/impacts/impact_flesh_med_sharp",
}
for i = 1, #required do
    assert(indexed[required[i]] ~= nil, "original event missing: " .. required[i])
end

local chop = Profiles.Get(indexed["dontstarve/wilson/use_axe_tree"])
local mine = Profiles.Get(indexed["dontstarve/wilson/use_pick_rock"])
local swing = Profiles.Get(indexed["dontstarve/wilson/attack_whoosh"])
local hit_large = Profiles.Get(indexed["dontstarve/impacts/impact_flesh_lrg_sharp"])
local hit_small = Profiles.Get(indexed["dontstarve/impacts/impact_flesh_sml_dull"])
assert(mine.total > chop.total, "mining waveform family lost its longer decay")
assert(swing.factor < hit_large.factor, "swing and hit were not separated")
assert(hit_large.factor > hit_small.factor, "target size did not affect material impact")

print(string.format("original haptics profile test passed: definitions=%d vibrating=%d", #effects, vibrating))
print(string.format("original event tuning checks passed: %d", tuning_checks))
