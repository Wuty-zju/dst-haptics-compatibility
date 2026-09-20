-- One reader for startup and live settings. Values from old installations
-- receive defaults; non-finite values cannot escape into engine calls.
local M = {}
local numeric =
{
    "strength", "duration", "spatial_scale",
    "tool_scale", "combat_scale", "danger_scale", "player_scale",
    "boss_scale", "environment_scale", "ui_scale", "loop_scale",
    "tool_duration", "combat_duration", "danger_duration", "player_duration",
    "boss_duration", "environment_duration", "ui_duration", "loop_duration",
}

function M.Read(read)
    local config =
    {
        compatibility = read("compatibility", true) ~= false,
        controller_adaptation = read("controller_adaptation", true) ~= false,
        language = read("language", true) or "zh",
        output_mode = read("output_mode", true) or "compatibility",
        controller_profile = read("controller_profile", true) or "auto",
        response_mode = read("response_mode", true) or "detail",
        calibration_test = read("calibration_test", true) or "off",
        debug = read("debug", true) == true,
    }
    for i = 1, #numeric do
        local name = numeric[i]
        local value = read(name, true)
        if type(value) ~= "number" or value ~= value then
            value = 1
        elseif value < 0 then
            value = 0
        elseif value > 2 then
            value = 2
        end
        config[name] = value
    end
    return config
end

return M
