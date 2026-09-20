local G = GLOBAL
local pcall = G.pcall
local pairs = G.pairs
local tostring = G.tostring
local unpack = G.unpack

local Bridge = {}

local function Pack(...)
    return { n = G.select("#", ...), ... }
end

local function IsValid(entity)
    return entity ~= nil
        and (entity.IsValid == nil or entity:IsValid())
        and (entity.IsInLimbo == nil or not entity:IsInLimbo())
end

local function HasTag(entity, tag)
    return IsValid(entity) and entity.HasTag ~= nil and entity:HasTag(tag)
end

local function HasAnyTag(entity, ...)
    if not IsValid(entity) then
        return false
    end
    if entity.HasAnyTag ~= nil then
        return entity:HasAnyTag(...)
    end
    for i = 1, G.select("#", ...) do
        if HasTag(entity, G.select(i, ...)) then
            return true
        end
    end
    return false
end

local function CaptureBufferedAction(inst, kind, captures)
    local action = inst.GetBufferedAction ~= nil and inst:GetBufferedAction() or nil
    captures[inst] =
    {
        kind = kind,
        target = action ~= nil and action.target or nil,
        invobject = action ~= nil and action.invobject or nil,
        sequence = (captures[inst] ~= nil and captures[inst].sequence or 0) + 1,
        captured_at = G.GetTime ~= nil and G.GetTime() or 0,
    }
end

local function WrapState(sg, name, kind, captures)
    local state = sg.states ~= nil and sg.states[name] or nil
    if state == nil or state.onenter == nil or state._dst_haptics_bridge then
        return
    end
    state._dst_haptics_bridge = true
    local original = state.onenter
    state.onenter = function(inst, ...)
        CaptureBufferedAction(inst, kind, captures)
        local results = Pack(original(inst, ...))
        return unpack(results, 1, results.n)
    end
end

local function ResolveWorkEvent(kind, inst, target, invobject)
    if kind == "chop" then
        if HasTag(inst, "beaver") then
            return "dontstarve/characters/woodie/beaver_chop_tree"
        elseif HasTag(target, "mushtree") or (target ~= nil and target.prefab == "toadstool_cap") then
            return "dontstarve/wilson/use_axe_mushroom"
        elseif HasTag(target, "rock_tree") then
            return "rifts6/rock_tree/chop_normal"
        end
        return "dontstarve/wilson/use_axe_tree"
    elseif kind == "mine" then
        if HasTag(target, "frozen") then
            return "dontstarve_DLC001/common/iceboulder_hit"
        elseif HasAnyTag(target, "moonglass", "LunarBuildup", "crystal") then
            return "turnoftides/common/together/moon_glass/mine"
        end
        return "dontstarve/wilson/use_pick_rock"
    elseif kind == "hammer" then
        return invobject ~= nil and invobject.hit_skin_sound or "dontstarve/wilson/hit"
    elseif kind == "dig" then
        return "dontstarve/wilson/dig"
    end
end

local function DistanceSq3D(a, b)
    if a == nil or b == nil or a.Transform == nil or b.Transform == nil then
        return nil
    end
    local ax, ay, az = a.Transform:GetWorldPosition()
    local bx, by, bz = b.Transform:GetWorldPosition()
    local dx, dy, dz = ax - bx, ay - by, az - bz
    return dx * dx + dy * dy + dz * dz
end

local ARMOR_TAGS =
{
    { "forcefield", "forcefield_armour_" },
    { "sanity", "sanity_armour_" },
    { "lunarplant", "lunarplant_armour_" },
    { "dreadstone", "dreadstone_armour_" },
    { "metal", "metal_armour_" },
    { "marble", "marble_armour_" },
    { "shell", "shell_armour_" },
    { "wood", "wood_armour_" },
    { "grass", "straw_armour_" },
    { "fur", "fur_armour_" },
    { "cloth", "shadowcloth_armour_" },
}

local function ResolveArmorImpactSound(target, weaponmod)
    local inventory = target ~= nil and target.replica ~= nil and target.replica.inventory or nil
    local equips = inventory ~= nil and inventory.GetEquips ~= nil and inventory:GetEquips() or nil
    if equips == nil then
        return nil
    end
    -- Mirrors GetArmorImpactSound's documented priority using replicated
    -- equipped-item tags. NPC server-only armour still falls through safely.
    for i = 1, #ARMOR_TAGS do
        local tag = ARMOR_TAGS[i][1]
        for _, item in pairs(equips) do
            if HasTag(item, tag) then
                return "dontstarve/impacts/impact_" .. ARMOR_TAGS[i][2] .. weaponmod
            end
        end
    end
    return nil
end

local function ResolveImpactSound(target, weapon)
    if not IsValid(target) then
        return nil
    end
    local weaponmod = HasTag(weapon, "sharp") and "sharp" or "dull"
    local armor_event = ResolveArmorImpactSound(target, weaponmod)
    if armor_event ~= nil then
        return armor_event
    end
    local resolver = HasTag(target, "wall") and G.GetWallImpactSound
        or HasTag(target, "object") and G.GetObjectImpactSound
        or G.GetCreatureImpactSound
    if resolver == nil then
        return nil
    end
    local ok, event = pcall(resolver, target, weaponmod)
    if ok and event ~= nil then
        return event
    end
    -- Some server-only fields used by the native resolver are absent on a
    -- remote client. Keep the fallback inside the original impact namespace;
    -- GetEffect still rejects it if the current haptics.lua does not define it.
    return "dontstarve/impacts/impact_flesh_med_" .. weaponmod
end

local function AttackIsMelee(weapon)
    return weapon == nil
        or not (HasTag(weapon, "projectile")
            or HasTag(weapon, "complexprojectile")
            or HasTag(weapon, "rangedweapon"))
end

local function CanResolveMeleeHit(inst, target, weapon)
    if not (IsValid(inst) and IsValid(target)) or HasAnyTag(target, "dead", "INLIMBO") then
        return false
    end
    local combat = inst.replica ~= nil and inst.replica.combat or nil
    if combat == nil then
        return false
    end
    local target_combat = target.replica ~= nil and target.replica.combat or nil
    local hittable = combat.CanExtinguishTarget ~= nil and combat:CanExtinguishTarget(target, weapon)
        or combat.CanLightTarget ~= nil and combat:CanLightTarget(target, weapon)
        or target_combat ~= nil
            and target_combat.CanBeAttacked ~= nil
            and target_combat:CanBeAttacked(inst)
    if not hittable then
        return false
    end

    local radius = target.GetPhysicsRadius ~= nil and target:GetPhysicsRadius(0) or 0
    local range = combat.GetAttackRangeWithWeapon ~= nil and combat:GetAttackRangeWithWeapon()
        or combat.GetAttackRange ~= nil and combat:GetAttackRange()
        or 0
    -- This is the release-build combat_replica:CanHitTarget calculation:
    -- three-dimensional distance and a conservative 0.5 prediction margin.
    range = G.math.max(radius + range - 0.5, 0)
    local distance_sq = DistanceSq3D(inst, target)
    return distance_sq ~= nil and distance_sq <= range * range
end

function Bridge.Install(api)
    if api == nil or api.Emit == nil then
        return
    end

    local adapter_state = api.GetState ~= nil and api.GetState() or nil
    if adapter_state ~= nil and adapter_state.client_action_bridge_installed then
        return
    end
    if adapter_state ~= nil then
        adapter_state.client_action_bridge_installed = true
    end

    local captures = G.setmetatable({}, { __mode = "k" })
    local attached = G.setmetatable({}, { __mode = "k" })

    AddStategraphPostInit("wilson_client", function(sg)
        WrapState(sg, "chop_start", "chop", captures)
        WrapState(sg, "mine_start", "mine", captures)
        WrapState(sg, "hammer_start", "hammer", captures)
        WrapState(sg, "dig_start", "dig", captures)
        WrapState(sg, "attack", "attack", captures)
    end)

    local function AttachPlayer(player)
        if player == nil or player ~= G.ThePlayer or attached[player] then
            return
        end
        attached[player] = true
        local monitor = { cycle = 0, hungry = false }

        -- Hungry is one of only three world events whose original definition
        -- deliberately has audio=false. No sound call exists to hook, so use a
        -- low-frequency animation edge monitor rather than polling every frame.
        player:DoPeriodicTask(0.10, function(inst)
            if inst ~= G.ThePlayer or not IsValid(inst) then
                return
            end
            local hungry = inst.AnimState ~= nil and inst.AnimState:IsCurrentAnimation("hungry")
            if hungry and not monitor.hungry then
                monitor.cycle = monitor.cycle + 1
                api.Emit("dontstarve/wilson/hungry", inst,
                {
                    source = "replicated_player_state",
                    semantic_key = "hungry|" .. tostring(monitor.cycle),
                })
            end
            monitor.hungry = hungry
        end)

        -- player_classified only forwards this after the server-side buffered
        -- action path has resolved. It replaces the old animation-frame guess,
        -- preventing cancelled or rejected work actions from rumbling.
        player:ListenForEvent("performaction", function(inst)
            if inst ~= G.ThePlayer then
                return
            end
            local capture = captures[inst]
            captures[inst] = nil
            if capture == nil then
                return
            end
            local now = G.GetTime ~= nil and G.GetTime() or capture.captured_at
            if now - capture.captured_at > 2 then
                return
            end

            if capture.kind == "attack" then
                if AttackIsMelee(capture.invobject)
                    and CanResolveMeleeHit(inst, capture.target, capture.invobject) then
                    local event = ResolveImpactSound(capture.target, capture.invobject)
                    if event ~= nil and api.GetEffect(event) ~= nil then
                        api.Emit(event, capture.target,
                        {
                            source = "server_confirmed_combat",
                            semantic_key = "attack|" .. tostring(capture.sequence) .. "|" .. tostring(capture.target.GUID or capture.target),
                        })
                    end
                end
                return
            end

            local event = ResolveWorkEvent(capture.kind, inst, capture.target, capture.invobject)
            if event ~= nil and api.GetEffect(event) ~= nil then
                local emitter_entity = capture.kind == "chop" and capture.target or inst
                if not IsValid(emitter_entity) then
                    emitter_entity = inst
                end
                api.Emit(event, emitter_entity,
                {
                    source = "server_confirmed_work",
                    semantic_key = "work|" .. tostring(capture.sequence) .. "|" .. tostring(capture.kind),
                })
            end
        end)

        -- This net pulse originates in Combat:GetAttacked_Internal's successful
        -- (non-blocked) attacked event. Unlike healthdelta it excludes hunger,
        -- temperature, construction costs and healing, which are not Wilson hit
        -- haptics. The native sound hook remains authoritative when available.
        player:ListenForEvent("attacked", function(inst)
            if inst == G.ThePlayer then
                api.Emit("dontstarve/wilson/hit", inst,
                {
                    source = "server_confirmed_attacked",
                    semantic_key = "attacked|" .. tostring(G.GetTime ~= nil and G.GetTime() or 0),
                })
            end
        end)
    end

    AddPrefabPostInit("world", function(world)
        world:ListenForEvent("playeractivated", function(_, player)
            AttachPlayer(player)
        end)
        world:DoTaskInTime(0, function()
            AttachPlayer(G.ThePlayer)
        end)
    end)

    if G.ThePlayer ~= nil then
        AttachPlayer(G.ThePlayer)
    end
end

return Bridge
