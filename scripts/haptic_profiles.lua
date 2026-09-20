local M = {}

local function Contains(text, pattern)
    return string.find(text, pattern, 1, true) ~= nil
end

local function Any(text, patterns)
    for i = 1, #patterns do
        if Contains(text, patterns[i]) then
            return true
        end
    end
    return false
end

function M.IsLoopEvent(event)
    local lower = string.lower(event or "")
    return string.find(lower, "_lp", 1, true) ~= nil
        or string.find(lower, "/loop", 1, true) ~= nil
        or string.find(lower, "loop_", 1, true) ~= nil
end

-- Pulse entries are { delay, duration, relative magnitude }. They intentionally
-- describe broad envelopes, not a hand-authored event allow-list. New Klei events
-- still enter through haptics.lua and receive the closest semantic envelope.
function M.Get(effect)
    local event = string.lower(effect.event or "")
    local category = effect.category or (Contains(event, "/hud/") and "UI" or "PLAYER")

    if M.IsLoopEvent(event) then
        return { loop = true, interval = 0.085, duration = 0.10, factor = 0.72, total = -1 }
    end

    if category == "UI" or Contains(event, "/hud/") then
        if Any(event, { "click", "mouseover", "dropdown", "pageflip" }) then
            return { pulses = { { 0, 0.045, 0.56 } }, total = 0.045 }
        elseif Any(event, { "worlddeathtick", "gift_animation", "weave", "purchase" }) then
            return { pulses = { { 0, 0.075, 0.90 }, { 0.085, 0.065, 0.55 } }, total = 0.15 }
        end
        return { pulses = { { 0, 0.060, 0.72 } }, total = 0.060 }
    end

    -- These families are backed by the shipped 882 Hz vibration WAV assets.
    -- AddVibration cannot play those samples, so the pulse envelopes preserve
    -- their measured duration/decay and relative character instead.
    if Any(event, { "use_axe_tree", "use_axe_mushroom", "beaver_chop_tree", "rock_tree/chop" }) then
        return { pulses = { { 0, 0.055, 1.00 }, { 0.045, 0.045, 0.28 } }, factor = 0.82, kind = "tool", total = 0.09 }
    end

    if Any(event, { "use_pick_rock", "iceboulder_hit", "moon_glass/mine" }) then
        return
        {
            pulses =
            {
                { 0, 0.045, 1.00 },
                { 0.04, 0.045, 0.68 },
                { 0.08, 0.050, 0.39 },
                { 0.125, 0.055, 0.20 },
                { 0.175, 0.060, 0.09 },
            },
            factor = 0.96,
            kind = "tool",
            total = 0.235,
        }
    end

    if Contains(event, "/dig") then
        return { pulses = { { 0.025, 0.050, 1.00 }, { 0.07, 0.045, 0.16 } }, factor = 0.68, kind = "tool", total = 0.115 }
    end

    if Contains(event, "/impacts/impact_") then
        local size_factor = Contains(event, "_lrg_") and 1.00
            or Contains(event, "_sml_") and 0.58
            or Contains(event, "_med_") and 0.78
            or Contains(event, "_wet_") and 0.72
            or 0.90
        local material_factor = Contains(event, "_sharp") and 1.00 or 0.88
        return
        {
            pulses = { { 0, 0.050, 1.00 }, { 0.045, 0.055, 0.54 }, { 0.095, 0.060, 0.16 } },
            factor = size_factor * material_factor,
            kind = "combat",
            total = 0.155,
        }
    end

    if Any(event, { "attack_whoosh", "attack_weapon", "/swing", "_swing" }) then
        return
        {
            pulses = { { 0.030, 0.050, 0.42 }, { 0.070, 0.060, 1.00 }, { 0.125, 0.055, 0.36 } },
            factor = Contains(event, "attack_weapon") and 0.68 or 0.52,
            kind = "combat",
            total = 0.18,
        }
    end

    if Any(event, { "roar", "taunt", "scream", "supernova", "finale" }) then
        return { pulses = { { 0, 0.13, 0.75 }, { 0.12, 0.18, 1.00 }, { 0.29, 0.12, 0.55 } }, total = 0.41 }
    end

    if Any(event, { "explode", "explosion", "slam", "groundpound", "ground_pound", "death_fall", "bodyfall", "smash", "breach" }) then
        return { pulses = { { 0, 0.095, 1.00 }, { 0.075, 0.13, 0.64 }, { 0.20, 0.09, 0.38 } }, total = 0.29 }
    end

    if category == "DANGER" or Any(event, { "/hit", "hurt", "shocked", "freeze_", "hot_level", "hungry" }) then
        return { pulses = { { 0, 0.085, 1.00 }, { 0.09, 0.075, 0.62 }, { 0.18, 0.06, 0.36 } }, total = 0.24 }
    end

    if Any(event, { "chop", "use_axe", "use_pick", "hammer", "/dig", "plant" }) then
        return { pulses = { { 0, 0.062, 1.00 }, { 0.055, 0.050, 0.35 } }, kind = "tool", total = 0.105 }
    end

    if Any(event, { "impact_", "_hit", "/hit_" }) then
        return { pulses = { { 0, 0.062, 1.00 }, { 0.055, 0.050, 0.35 } }, kind = "combat", total = 0.105 }
    end

    if Any(event, { "footstep", "/step", "_step", "land" }) then
        return { pulses = { { 0, 0.062, 1.00 }, { 0.055, 0.050, 0.35 } }, total = 0.105 }
    end

    if Any(event, { "whoosh", "swing", "attack_weapon", "attack_", "/attack" }) then
        return { pulses = { { 0, 0.10, 0.70 }, { 0.09, 0.055, 0.32 } }, factor = 0.58, kind = "combat", total = 0.145 }
    end

    if category == "BOSS" then
        return { pulses = { { 0, 0.11, 0.88 }, { 0.10, 0.08, 0.44 } }, total = 0.18 }
    elseif category == "ENVIRONMENT" then
        return { pulses = { { 0, 0.085, 0.78 }, { 0.08, 0.055, 0.30 } }, total = 0.135 }
    end

    return { pulses = { { 0, 0.075, 0.75 } }, total = 0.075 }
end

return M
