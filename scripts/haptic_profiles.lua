local M = {}

-- These envelopes are down-sampled RMS traces from the vibration WAV files
-- shipped with this exact DST installation (882 Hz source, 100 ms bins). They
-- preserve the original rise/decay far more closely than a fixed rectangle.
-- AddVibration cannot ingest a WAV, so each value becomes one short pulse.
local ASSET_ENVELOPES =
{
    chop_tree = { 1.000, 0.050 },
    chop_mushroom = { 1.000, 0.164 },
    mine_rock = { 1.000, 0.449, 0.137, 0.030, 0.019, 0.019, 0.006, 0.006 },
    mine_ice = { 1.000, 0.291, 0.068, 0.062, 0.017, 0.013, 0.009, 0.006, 0.002, 0.001 },
    mine_moonglass = { 1.000, 0.161, 0.053, 0.036, 0.046 },
    dig = { 1.000, 0.083, 0.044 },
    impact = { 1.000, 0.512, 0.201, 0.165, 0.091 },
    attack_whoosh = { 0.641, 0.958, 0.395, 0.307, 0.180, 0.104, 0.031 },
    hungry = { 0.167, 0.574, 0.581, 0.562, 0.830, 1.000, 0.601, 0.413, 0.392, 0.119, 0.048, 0.031 },
    freeze = { 0.887, 0.952, 0.588, 0.623, 0.734, 0.440, 0.347, 0.284, 0.255, 0.234, 0.145, 0.108, 0.080, 0.050, 0.027, 0.021 },
    heat = { 0.593, 0.743, 0.737, 0.864, 0.884, 0.770, 0.624, 0.440, 0.250, 0.115, 0.079, 0.056, 0.044, 0.039, 0.027 },
}

local function AssetProfile(name, factor, kind, step)
    local envelope = ASSET_ENVELOPES[name]
    step = step or 0.10
    local pulses = {}
    for i = 1, #envelope do
        if envelope[i] >= 0.02 then
            pulses[#pulses + 1] = { (i - 1) * step, step + 0.005, envelope[i] }
        end
    end
    return
    {
        pulses = pulses,
        factor = factor,
        kind = kind,
        total = #envelope * step,
        asset_derived = true,
        asset_family = name,
    }
end

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

    -- audio=false does not mean haptics=false. Hungry has no sound callback at
    -- all, but the original package contains a long, multi-crest waveform.
    if Contains(event, "wilson/hungry") then
        return AssetProfile("hungry", 0.82, "danger")
    end

    if Contains(event, "/freeze_") then
        return AssetProfile("freeze", 0.78, "danger")
    elseif Contains(event, "hud_hot_level") then
        return AssetProfile("heat", 0.72, "danger", 0.20)
    end

    if Any(event, { "use_axe_tree", "beaver_chop_tree", "rock_tree/chop" }) then
        return AssetProfile("chop_tree", 0.82, "tool")
    elseif Contains(event, "use_axe_mushroom") then
        return AssetProfile("chop_mushroom", 0.82, "tool")
    end

    if Contains(event, "use_pick_rock") then
        return AssetProfile("mine_rock", 0.96, "tool")
    elseif Contains(event, "iceboulder_hit") then
        return AssetProfile("mine_ice", 0.96, "tool")
    elseif Contains(event, "moon_glass/mine") then
        return AssetProfile("mine_moonglass", 0.96, "tool")
    end

    if Contains(event, "/dig") then
        return AssetProfile("dig", 0.68, "tool")
    end

    if Contains(event, "/impacts/impact_") then
        local size_factor = Contains(event, "_lrg_") and 1.00
            or Contains(event, "_sml_") and 0.58
            or Contains(event, "_med_") and 0.78
            or Contains(event, "_wet_") and 0.72
            or 0.90
        local material_factor = Contains(event, "_sharp") and 1.00 or 0.88
        return AssetProfile("impact", size_factor * material_factor, "combat")
    end

    if Any(event, { "attack_whoosh", "attack_weapon", "/swing", "_swing" }) then
        return AssetProfile("attack_whoosh", Contains(event, "attack_weapon") and 0.68 or 0.52, "combat")
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
