local G = GLOBAL
local type = G.type

local M = {}

local function Clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    elseif value > maximum then
        return maximum
    end
    return value
end

local function Linear(value, input_max, output_min)
    if type(value) ~= "number" or value ~= value then
        return 1
    end
    local normalized = input_max > 0 and Clamp(value / input_max, 0, 1) or 1
    return (output_min or 0) + (1 - (output_min or 0)) * normalized
end

-- These policies are deliberately small. They cover only parameters whose
-- meaning and value range are visible in the current native call sites. Unknown
-- FMOD parameters stay neutral instead of accidentally becoming motor gain.
local POLICIES =
{
    ["dontstarve_DLC001/common/iceboulder_hit"] = function(params)
        return Linear(params.intensity, 1, 0)
    end,
    ["dontstarve/characters/walter/woby/big/footstep"] = function(params)
        return Linear(params.intensity, 1, 0)
    end,
    ["dontstarve/creatures/together/antlion/sfx/ground_break"] = function(params)
        -- Native call sites use size 0..2. A non-zero floor preserves the tiny
        -- crack event while keeping the full observed ordering monotonic.
        return Linear(params.size, 2, 0.20)
    end,
    ["moonstorm/creatures/boss/alterguardian2/spike"] = function(params)
        return Linear(params.intensity, 1, 0)
    end,
    ["hookline_2/creatures/boss/crabking/magic_LP"] = function(params)
        return Linear(params.intensity, 1, 0)
    end,
    ["dontstarve/wilson/lighter_LP"] = function(params)
        return Linear(params.intensity, 1, 0)
    end,
    ["rifts6/whirlpool/whirlpool_LP"] = function(params)
        -- The current native source fixes this loop at size=.5.
        return Linear(params.size, 0.5, 0)
    end,
    ["rifts5/lunar_boss/supernova_burst_LP"] = function(params)
        if type(params.blocked) ~= "number" then
            return 1
        end
        -- Native level two moves "blocked" from .35 toward .05: less blocked
        -- means more local exposure. This is an event-specific inverse mapping.
        return Clamp(1 - params.blocked, 0, 1)
    end,
}

function M.GetScale(event, params)
    if type(params) ~= "table" then
        return 1, nil
    end
    local policy = POLICIES[event]
    if policy == nil then
        return 1, nil
    end
    local ok, scale = G.pcall(policy, params)
    if not ok or type(scale) ~= "number" or scale ~= scale then
        return 1, "parameter_policy_failed"
    end
    return Clamp(scale, 0, 1), "native_parameter"
end

function M.Copy(params)
    if type(params) ~= "table" then
        return nil
    end
    local copy = {}
    for key, value in G.pairs(params) do
        if type(key) == "string" and type(value) == "number" then
            copy[key] = value
        end
    end
    return copy
end

return M
