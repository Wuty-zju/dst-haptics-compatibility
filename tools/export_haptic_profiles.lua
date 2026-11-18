-- Offline data adapter. The mod's registry and loop manager resolve envelopes.
GLOBAL = _G
local root = assert(os.getenv("DST_HAPTICS_MOD_ROOT"))
local native = assert(os.getenv("DST_ORIGINAL_SCRIPTS"))
local export_path = assert(os.getenv("DST_HAPTICS_REPORT_EXPORT"))
local Profiles = dofile(root .. "/scripts/haptic_profiles.lua")
local Registry = dofile(root .. "/scripts/haptic_registry.lua")
local Loops = dofile(root .. "/scripts/haptic_loops.lua")
local effects = dofile(native .. "/haptics.lua")
local state = { definitions = 0, duplicate_events = 0, effects = {}, profiles = {} }
assert(Registry.Populate(state, effects, Profiles) > 0, "native haptics table must be nonempty")

local counts = {}
for _, effect in ipairs(effects) do
    if type(effect) == "table" and type(effect.event) == "string" then
        counts[effect.event] = (counts[effect.event] or 0) + 1
    end
end

local anonymous
local loops = Loops.New({}, {
    Util = dofile(root .. "/scripts/haptic_util.lua"),
    SpatialFactor = function() return 1 end,
    ScheduleProfile = function(_, _, profile) anonymous = profile end,
})

dofile(root .. "/modinfo.lua")
local defaults = {}
for _, option in ipairs(configuration_options) do
    defaults[option.name] = option.default
end

local function Json(value)
    local kind = type(value)
    if kind == "string" then
        return '"' .. value:gsub('[%z\1-\31\\"]', function(character)
            if character == '"' or character == '\\' then return '\\' .. character end
            return string.format("\\u%04x", character:byte())
        end) .. '"'
    elseif kind == "number" then
        return string.format("%.17g", value)
    elseif kind == "boolean" then
        return tostring(value)
    end

    assert(kind == "table", "unsupported export value " .. kind)
    local items = {}
    if #value > 0 then
        for i, item in ipairs(value) do items[i] = Json(item) end
        return "[" .. table.concat(items, ",") .. "]"
    end
    for name, item in pairs(value) do
        items[#items + 1] = Json(name) .. ":" .. Json(item)
    end
    return "{" .. table.concat(items, ",") .. "}"
end

local events = {}
for event, effect in pairs(state.effects) do
    local profile = state.profiles[event]
    anonymous = nil
    if profile.loop then
        loops.Register(effect, nil, nil, nil, 1, profile)
        assert(anonymous, "missing anonymous loop profile for " .. event)
    end
    events[event] = {
        native = {
            event = event, category = effect.category, vibration = effect.vibration,
            vibration_intensity = effect.vibration_intensity, audio = effect.audio,
            audio_intensity = effect.audio_intensity, player_only = effect.player_only,
        },
        definition_count = counts[event],
        profile = profile,
        anonymous = anonymous,
    }
end

local file = assert(io.open(export_path, "wb"))
assert(file:write(Json({
    version = version, definitions = state.definitions, events = events,
    defaults = { hurt_fallback = defaults.hurt_fallback, combat_fallback = defaults.combat_fallback },
})))
assert(file:close())
