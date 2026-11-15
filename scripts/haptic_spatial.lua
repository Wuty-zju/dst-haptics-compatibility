-- Ownership and listener-relative spatial policy; never changes game audio.
local G = GLOBAL
local pcall = G.pcall
local Spatial = {}
function Spatial.New(state, Util)
    local Clamp, NumberOr = Util.Clamp, Util.NumberOr
    local function GetEntity(emitter)
        if emitter == nil or emitter.GetEntity == nil then
            return nil
        end
        local success, entity = pcall(emitter.GetEntity, emitter)
        return success and entity or nil
    end

    local DISTANCE_POLICY =
    {
        PLAYER = { near = 5, far = 26 },
        DANGER = { near = 7, far = 34 },
        ENVIRONMENT = { near = 8, far = 46 },
        BOSS = { near = 12, far = 64 },
    }

    local function IsUIEffect(effect)
        return effect.category == "UI" or string.find(string.lower(effect.event), "/hud/", 1, true) ~= nil
    end

    local function SpatialFactor(effect, entity, local_context)
        -- Ownership precedes non-spatial policy: a UI category does not grant
        -- an unrelated world emitter permission to play player-only feedback.
        if effect.player_only == true and not local_context
            and (G.ThePlayer == nil or entity ~= G.ThePlayer) then
            return 0, nil, "player_only_nonlocal"
        end
        if IsUIEffect(effect) then
            return 1, nil, nil
        end
        -- FrontEnd and FocalPoint emitters are native proof that the sound is
        -- listener-local. Equip, burn, worm travel/digestion and lunar-burn
        -- feedback use this path despite not belonging to the UI category.
        if local_context then
            return 1, nil, nil
        end
        -- Native weather attaches rain to the world emitter. Its transform is
        -- not a sound origin; the weather profile explicitly marks this route.
        local profile = state.profiles[effect.event]
        if entity == G.TheWorld and entity ~= nil and profile ~= nil and profile.listener_local then
            return 1, nil, nil
        end
        if G.ThePlayer == nil or G.ThePlayer.Transform == nil then
            return 0, nil, "no_local_player"
        end
        if effect.player_only == true then return 1, 0, nil end
        if entity == G.ThePlayer then
            return 1, 0, nil
        end
        -- Freeze/overheat and similar HUD danger events are played through the
        -- frontend SoundEmitter, which intentionally has no world entity.
        if entity == nil or entity.Transform == nil then
            return 0, nil, "no_spatial_entity"
        end

        local px, py, pz
        if state.listener_position ~= nil then
            px, py, pz = state.listener_position[1], state.listener_position[2], state.listener_position[3]
        else
            px, py, pz = G.ThePlayer.Transform:GetWorldPosition()
        end
        local ex, ey, ez = entity.Transform:GetWorldPosition()
        local dx, dy, dz = ex - px, ey - py, ez - pz
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
        local policy = DISTANCE_POLICY[effect.category] or DISTANCE_POLICY.PLAYER
        local spatial_scale = Clamp(NumberOr(state.config.spatial_scale, 1), 0.5, 2)
        local far = policy.near + (policy.far - policy.near) * spatial_scale
        if distance <= policy.near then
            return 1, distance, nil
        elseif distance >= far then
            return 0, distance, "outside_spatial_range"
        end
        local t = (distance - policy.near) / (far - policy.near)
        -- Cubic smoothstep avoids a hard audible edge while reaching exact zero.
        local smooth = t * t * (3 - 2 * t)
        return 1 - smooth, distance, nil
    end

    return { GetEntity = GetEntity, IsUIEffect = IsUIEffect, Factor = SpatialFactor }
end
return Spatial
