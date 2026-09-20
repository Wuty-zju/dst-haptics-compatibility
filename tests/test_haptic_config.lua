local root = os.getenv("DST_HAPTICS_MOD_ROOT") or "."
local Config = dofile(root .. "/scripts/haptic_config.lua")
local info = {}
local chunk = assert(loadfile(root .. "/modinfo.lua"))
setfenv(chunk, setmetatable(info, { __index = _G }))
chunk()
local seen = {}
for _, option in ipairs(info.configuration_options) do
    assert(not seen[option.name], "duplicate config: " .. option.name)
    seen[option.name] = option
end
local axes = { "strength", "duration" }
for _, family in ipairs({ "tool", "combat", "danger", "player", "boss", "environment", "ui", "loop" }) do
    axes[#axes + 1] = family .. "_scale"
    axes[#axes + 1] = family .. "_duration"
end
for _, name in ipairs(axes) do
    local option = assert(seen[name], "missing axis: " .. name)
    assert(option.default == 1 and #option.options == 41, name)
    for i = 1, 41 do
        local expected = (i - 1) * 5 / 100
        assert(option.options[i].data == expected, name .. " percentage")
        local config = Config.Read(function(key) if key == name then return expected end end)
        assert(config[name] == expected, name .. " read")
    end
end
assert(Config.Read(function() end).controller_adaptation == true)
assert(Config.Read(function(key) if key == "controller_adaptation" then return false end end).controller_adaptation == false)
for _, bad in ipairs({ "invalid", 0/0, -1, 3 }) do
    local value = Config.Read(function(key) if key == "duration" then return bad end end).duration
    assert(value >= 0 and value <= 2 and value == value)
end
print("configuration tests passed: 18 tuning axes, 41 steps, migration and invalid values")
