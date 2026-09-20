-- Native categories and semantic types are separate, composable axes. Unknown
-- future categories inherit PLAYER so every dynamically loaded event is tunable.
local M = {}
local category_keys = { DANGER = "danger", BOSS = "boss", ENVIRONMENT = "environment", UI = "ui" }

local function Ratio(value)
    if type(value) ~= "number" or value ~= value then return 1 end
    return math.max(0, math.min(2, value))
end

function M.Scale(config, effect, profile, suffix, ui)
    suffix = suffix or "_scale"
    local category = category_keys[effect.category] or (ui and "ui") or "player"
    local result = Ratio(config[category .. suffix])
    if profile.kind == "tool" or profile.kind == "combat" then
        result = result * Ratio(config[profile.kind .. suffix])
    end
    if profile.loop then
        result = result * Ratio(config["loop" .. suffix])
    end
    return result
end

return M
