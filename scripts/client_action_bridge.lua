local G = GLOBAL
local pcall = G.pcall
local tostring = G.tostring
local type = G.type
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
    }
end

local function WrapState(sg, name, kind, captures, after_enter)
    local state = sg.states ~= nil and sg.states[name] or nil
    if state == nil or state.onenter == nil or state._dst_haptics_bridge then
        return
    end
    state._dst_haptics_bridge = true
    local original = state.onenter
    state.onenter = function(inst, ...)
        CaptureBufferedAction(inst, kind, captures)
        local results = Pack(original(inst, ...))
        if after_enter ~= nil then
            after_enter(inst, captures[inst])
        end
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

local function DetectWork(inst)
    if inst.AnimState == nil then
        return nil
    end
    if HasTag(inst, "prechop")
        and (inst.AnimState:IsCurrentAnimation("chop_loop") or inst.AnimState:IsCurrentAnimation("woodie_chop_loop")) then
        return "chop", 2
    elseif HasTag(inst, "premine") and inst.AnimState:IsCurrentAnimation("pickaxe_loop") then
        return "mine", 7
    elseif HasTag(inst, "prehammer") and inst.AnimState:IsCurrentAnimation("pickaxe_loop") then
        return "hammer", 7
    elseif HasTag(inst, "predig") and inst.AnimState:IsCurrentAnimation("shovel_loop") then
        return "dig", 15
    end
    return nil
end

local function DistanceSq(a, b)
    if a == nil or b == nil or a.Transform == nil or b.Transform == nil then
        return nil
    end
    local ax, _, az = a.Transform:GetWorldPosition()
    local bx, _, bz = b.Transform:GetWorldPosition()
    local dx, dz = ax - bx, az - bz
    return dx * dx + dz * dz
end

local function ResolveImpactSound(target, weapon)
    if not IsValid(target) then
        return nil
    end
    local weaponmod = HasTag(weapon, "sharp") and "sharp" or "dull"
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

function Bridge.Install(api, config)
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
        WrapState(sg, "attack", "attack", captures, function(inst, capture)
            if inst.sg == nil or inst.sg.HasStateTag == nil or not inst.sg:HasStateTag("attack") then
                return
            end
            local weapon = capture ~= nil and capture.invobject or nil
            local target = capture ~= nil and capture.target or nil
            if not AttackIsMelee(weapon) or not IsValid(target) then
                return
            end

            -- Match the current SGwilson attack timeline. This is not input
            -- feedback: it runs at the server action frame, then requires the
            -- replicated combat target and a still-valid melee range.
            local memory = inst.sg ~= nil and inst.sg.statemem or nil
            local frames = memory ~= nil and memory.isbeaver and 6
                or memory ~= nil and memory.ismoose and 7
                or memory ~= nil and (memory.iswhip or memory.isbook or memory.ispocketwatch) and 10
                or 8
            inst:DoTaskInTime(frames * G.FRAMES, function()
                if inst ~= G.ThePlayer or not IsValid(inst) or not IsValid(target) or HasTag(target, "dead") then
                    return
                end
                local combat = inst.replica ~= nil and inst.replica.combat or nil
                local replicated_target = combat ~= nil and combat.GetTarget ~= nil and combat:GetTarget() or nil
                if replicated_target ~= target then
                    return
                end
                local distance_sq = DistanceSq(inst, target)
                local radius = target.GetPhysicsRadius ~= nil and target:GetPhysicsRadius(0) or 0
                local range = combat.GetAttackRangeWithWeapon ~= nil and combat:GetAttackRangeWithWeapon(weapon)
                    or combat.GetAttackRange ~= nil and combat:GetAttackRange()
                    or 3
                if distance_sq ~= nil and distance_sq > (range + radius + 0.75) * (range + radius + 0.75) then
                    return
                end
                local event = ResolveImpactSound(target, weapon)
                if event ~= nil and api.GetEffect(event) ~= nil then
                    api.Emit(event, target,
                    {
                        source = "replicated_combat",
                        semantic_key = "attack|" .. tostring(capture.sequence) .. "|" .. tostring(target.GUID or target),
                    })
                end
            end)
        end)
    end)

    local function AttachPlayer(player)
        if player == nil or player ~= G.ThePlayer or attached[player] then
            return
        end
        attached[player] = true
        local monitor = { kind = nil, frame = -1, cycle = 0, fired = false, hungry = false }

        player:DoPeriodicTask(G.FRAMES, function(inst)
            if inst ~= G.ThePlayer or not IsValid(inst) then
                return
            end
            local hungry = inst.AnimState ~= nil and inst.AnimState:IsCurrentAnimation("hungry")
            if hungry and not monitor.hungry then
                api.Emit("dontstarve/wilson/hungry", inst,
                {
                    source = "replicated_player_state",
                    semantic_key = "hungry|" .. tostring(monitor.cycle),
                })
            end
            monitor.hungry = hungry

            local kind, impact_frame = DetectWork(inst)
            if kind == nil then
                monitor.kind = nil
                monitor.frame = -1
                monitor.fired = false
                return
            end

            local frame = inst.AnimState:GetCurrentAnimationFrame()
            if monitor.kind ~= kind or frame < monitor.frame then
                monitor.kind = kind
                monitor.cycle = monitor.cycle + 1
                monitor.fired = false
            end
            monitor.frame = frame

            if not monitor.fired and frame >= impact_frame then
                monitor.fired = true
                local capture = captures[inst]
                if capture ~= nil and capture.kind == kind then
                    local event = ResolveWorkEvent(kind, inst, capture.target, capture.invobject)
                    if event ~= nil and api.GetEffect(event) ~= nil then
                        local emitter_entity = kind == "chop" and capture.target or inst
                        api.Emit(event, emitter_entity,
                        {
                            source = "replicated_work",
                            semantic_key = "work|" .. tostring(capture.sequence) .. "|" .. tostring(monitor.cycle),
                        })
                    end
                end
            end
        end)

        player:ListenForEvent("healthdelta", function(inst, data)
            if inst ~= G.ThePlayer or type(data) ~= "table" or data.overtime == true then
                return
            end
            if type(data.oldpercent) == "number" and type(data.newpercent) == "number" and data.newpercent < data.oldpercent then
                api.Emit("dontstarve/wilson/hit", inst,
                {
                    source = "replicated_health",
                    semantic_key = "health|" .. tostring(data.oldpercent) .. "|" .. tostring(data.newpercent),
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
