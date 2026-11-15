local G = GLOBAL
local pcall = G.pcall
local tostring = G.tostring

local Bridge = {}

local function IsValid(entity)
    return entity ~= nil
        and (entity.IsValid == nil or entity:IsValid())
        and (entity.IsInLimbo == nil or not entity:IsInLimbo())
end

local function HasTag(entity, tag)
    return IsValid(entity) and entity.HasTag ~= nil and entity:HasTag(tag)
end

local function HasAnyTag(entity, ...)
    if not IsValid(entity) then return false end
    if entity.HasAnyTag ~= nil then return entity:HasAnyTag(...) end
    for i = 1, G.select("#", ...) do
        if HasTag(entity, G.select(i, ...)) then return true end
    end
    return false
end

local function IsDeadPlayer(inst)
    if HasAnyTag(inst, "dead", "playerghost", "ghost") then return true end
    local health = inst.replica ~= nil and inst.replica.health or nil
    return health ~= nil and health.IsDead ~= nil and health:IsDead()
end

local function IsHost(inst)
    return G.TheWorld ~= nil and G.TheWorld.ismastersim == true
        or inst.components ~= nil and inst.components.combat ~= nil
end

local function EquippedHands(inst)
    local inventory = inst.replica ~= nil and inst.replica.inventory or nil
    return inventory ~= nil and inventory.GetEquippedItem ~= nil
        and G.EQUIPSLOTS ~= nil and inventory:GetEquippedItem(G.EQUIPSLOTS.HANDS) or nil
end

local function CaptureWeapon(inst, action, kind)
    if kind == "attack" then
        local combat = inst.replica ~= nil and inst.replica.combat or nil
        -- A nil result is meaningful, e.g. the mounted player's weapon is not
        -- their held melee item. Do not substitute invobject or a hand-slot item.
        if combat ~= nil and combat.GetWeapon ~= nil then return combat:GetWeapon() end
    end
    return action.invobject or EquippedHands(inst)
end

local function AttackIsMelee(inst, weapon)
    local sg = inst.sg
    if sg ~= nil and sg.HasStateTag ~= nil then
        for _, tag in G.ipairs({ "propattack", "thrusting", "helmsplitting", "aoeattack" }) do
            if sg:HasStateTag(tag) then return false end
        end
    end
    -- These weapons enter other native states or resolve their damage later.
    -- A successful ATTACK action is not evidence of their material impact.
    return not HasAnyTag(weapon, "projectile", "complexprojectile", "rangedweapon",
        "slingshot", "blowdart", "blowpipe", "thrown", "pillow", "propweapon",
        "multithruster", "helmsplitter", "aoeweapon_lunge", "aoeweapon_leap")
end

local function ResolveImpactSound(target, weapon)
    if not IsValid(target) then return nil end
    local combat = target.components ~= nil and target.components.combat or nil
    if combat ~= nil and combat.GetImpactSound ~= nil then
        local ok, event = pcall(combat.GetImpactSound, combat, target, weapon)
        return ok and event or nil
    end
    -- Other players' inventory replica can report an empty equipment table
    -- without a classified. Material tags cannot prove an item has armor, so
    -- neither an empty table nor a metal hand item proves an armor impact.
    if target.replica ~= nil and target.replica.inventory ~= nil then return nil end
    local resolver = HasTag(target, "wall") and G.GetWallImpactSound
        or HasTag(target, "object") and G.GetObjectImpactSound
        or G.GetCreatureImpactSound
    if resolver == nil then return nil end
    local ok, event = pcall(resolver, target, HasTag(weapon, "sharp") and "sharp" or "dull")
    -- No invented flesh event when a client-side native resolver cannot run.
    return ok and event or nil
end

local function CanResolveMeleeHit(inst, target)
    if not (IsValid(inst) and IsValid(target)) or HasAnyTag(target, "dead", "INLIMBO") then return false end
    local combat = inst.replica ~= nil and inst.replica.combat or nil
    local target_combat = target.replica ~= nil and target.replica.combat or nil
    if combat == nil or target_combat == nil or target_combat.CanBeAttacked == nil
        or not target_combat:CanBeAttacked(inst) then return false end
    if inst.Transform == nil or target.Transform == nil then return false end
    local radius = target.GetPhysicsRadius ~= nil and target:GetPhysicsRadius(0) or 0
    local range = combat.GetAttackRangeWithWeapon ~= nil and combat:GetAttackRangeWithWeapon()
        or combat.GetAttackRange ~= nil and combat:GetAttackRange() or 0
    range = G.math.max(radius + range - 0.5, 0)
    local ax, ay, az = inst.Transform:GetWorldPosition()
    local bx, by, bz = target.Transform:GetWorldPosition()
    return (ax - bx)^2 + (ay - by)^2 + (az - bz)^2 <= range^2
end

local function ResolveWorkEvent(kind, inst, target, weapon)
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
        return weapon ~= nil and weapon.hit_skin_sound or "dontstarve/wilson/hit"
    elseif kind == "dig" then
        return "dontstarve/wilson/dig"
    end
end

function Bridge.Install(api)
    if api == nil or api.Emit == nil then return end
    local adapter_state = api.GetState ~= nil and api.GetState() or nil
    if adapter_state ~= nil and adapter_state.client_action_bridge_installed then return end
    if adapter_state ~= nil then adapter_state.client_action_bridge_installed = true end

    local captures = G.setmetatable({}, { __mode = "k" })
    local serials = G.setmetatable({}, { __mode = "k" })
    local attached = G.setmetatable({}, { __mode = "k" })
    local function Generation()
        return api.GetGeneration ~= nil and api.GetGeneration() or nil
    end
    local function CanObserve()
        return api.CanObserve == nil or api.CanObserve() == true
    end
    local function ShouldBridge(kind)
        return api.ShouldBridge ~= nil and api.ShouldBridge(kind) == true
    end
    local function CaptureBufferedAction(inst, kind)
        if inst ~= G.ThePlayer then return end
        captures[inst] = nil
        if not CanObserve() or kind == "attack" and not ShouldBridge("combat") then return end
        local action = inst.GetBufferedAction ~= nil and inst:GetBufferedAction() or nil
        if action == nil then return end
        serials[inst] = (serials[inst] or 0) + 1
        local capture =
        {
            action = action, kind = kind, target = action.target,
            weapon = CaptureWeapon(inst, action, kind), sequence = serials[inst],
            captured_at = G.GetTime ~= nil and G.GetTime() or 0,
            generation = Generation(),
        }
        if kind ~= "attack" then
            capture.work_event = ResolveWorkEvent(kind, inst, capture.target, capture.weapon)
        end
        captures[inst] = capture
        if action.AddFailAction ~= nil then
            action:AddFailAction(function()
                local function ClearFailedCapture()
                    if captures[inst] == capture then captures[inst] = nil end
                end
                -- Successful replicated acknowledgements also call Fail through
                -- ClearBufferedAction, then push performaction in the same tick.
                if inst.DoTaskInTime ~= nil then inst:DoTaskInTime(0, ClearFailedCapture)
                else ClearFailedCapture() end
            end)
        end
    end
    local function WrapState(sg, name, kind)
        local state = sg.states ~= nil and sg.states[name] or nil
        if state == nil or state.onenter == nil or state._dst_haptics_bridge then return end
        state._dst_haptics_bridge = true
        local original = state.onenter
        state.onenter = function(inst, ...)
            local ok = pcall(CaptureBufferedAction, inst, kind)
            if not ok then captures[inst] = nil end
            return original(inst, ...)
        end
    end
    AddStategraphPostInit("wilson_client", function(sg)
        WrapState(sg, "chop_start", "chop")
        WrapState(sg, "mine_start", "mine")
        WrapState(sg, "hammer_start", "hammer")
        WrapState(sg, "dig_start", "dig")
        WrapState(sg, "attack", "attack")
    end)

    local function AttachPlayer(player)
        if player == nil or player ~= G.ThePlayer or attached[player] then return end
        attached[player] = true
        local monitor = { cycle = 0, hungry = false, attacked = 0 }
        local original_preview = player.PerformPreviewBufferedAction
        if original_preview ~= nil then
            player.PerformPreviewBufferedAction = function(inst, ...)
                local function ObservePreview()
                    local capture = captures[inst]
                    if capture ~= nil and (inst ~= G.ThePlayer
                        or inst:GetBufferedAction() ~= capture.action) then captures[inst] = nil end
                end
                local ok = pcall(ObservePreview)
                if not ok then captures[inst] = nil end
                return original_preview(inst, ...)
            end
        end
        player:ListenForEvent("actionfailed", function(inst, data)
            local capture = captures[inst]
            if capture ~= nil and (data == nil or data.action == nil or data.action == capture.action) then
                captures[inst] = nil
            end
        end)
        player:DoPeriodicTask(0.10, function(inst)
            if inst ~= G.ThePlayer or not IsValid(inst) then return end
            local hungry = inst.AnimState ~= nil and inst.AnimState:IsCurrentAnimation("hungry")
            if hungry and not monitor.hungry then
                monitor.cycle = monitor.cycle + 1
                api.Emit("dontstarve/wilson/hungry", inst,
                    { source = "replicated_player_state", semantic_key = "hungry|" .. tostring(monitor.cycle) })
            end
            monitor.hungry = hungry
        end)
        player:ListenForEvent("performaction", function(inst, data)
            if inst ~= G.ThePlayer then return end
            local capture = captures[inst]
            captures[inst] = nil
            if capture == nil or not IsValid(inst) or not CanObserve()
                or capture.generation ~= Generation()
                or data ~= nil and data.action ~= nil and data.action ~= capture.action then return end
            local now = G.GetTime ~= nil and G.GetTime() or capture.captured_at
            if now - capture.captured_at > 2 then return end
            local event, emitter, source
            if capture.kind == "attack" then
                -- ATTACK.fn returns true even when DoAttack misses or launches a
                -- projectile. Range and replicated tags only support an estimate.
                if not ShouldBridge("combat") or IsHost(inst) or IsDeadPlayer(inst)
                    or capture.weapon ~= nil and not IsValid(capture.weapon)
                    or CaptureWeapon(inst, capture.action, "attack") ~= capture.weapon
                    or not AttackIsMelee(inst, capture.weapon)
                    or not CanResolveMeleeHit(inst, capture.target) then return end
                event = ResolveImpactSound(capture.target, capture.weapon)
                emitter, source = capture.target, "server_confirmed_combat_approx"
            else
                event = IsValid(capture.target)
                    and ResolveWorkEvent(capture.kind, inst, capture.target, capture.weapon)
                    or capture.work_event
                emitter = capture.kind == "chop" and capture.target or inst
                if not IsValid(emitter) then emitter = inst end
                source = "server_confirmed_work"
            end
            if event ~= nil and api.GetEffect ~= nil and api.GetEffect(event) ~= nil then
                api.Emit(event, emitter, { source = source,
                    semantic_key = capture.kind .. "|" .. tostring(capture.sequence) })
            end
        end)
        player:ListenForEvent("attacked", function(inst, data)
            if inst ~= G.ThePlayer or not IsValid(inst) or IsHost(inst) or IsDeadPlayer(inst)
                or data ~= nil and (data.redirected or data.noimpactsound)
                or not ShouldBridge("hurt") or not CanObserve() or api.GetGeneration == nil then return end
            monitor.attacked = monitor.attacked + 1
            local sequence, generation = monitor.attacked, Generation()
            local function EmitGenericHit()
                if inst ~= G.ThePlayer or not IsValid(inst) or IsHost(inst) or IsDeadPlayer(inst)
                    or not ShouldBridge("hurt") or not CanObserve() or generation ~= Generation() then return end
                if api.HasRecentSpecialHurt ~= nil and api.HasRecentSpecialHurt(0.12) then return end
                api.Emit("dontstarve/wilson/hit", inst,
                    { source = "replicated_hurt_approx", semantic_key = "attacked|" .. tostring(sequence) })
            end
            -- attacked lacks stimuli and noimpactsound on remote clients. This
            -- explicitly enabled fallback cannot prove a native Wilson hit event.
            if inst.DoTaskInTime ~= nil then inst:DoTaskInTime(0.05, EmitGenericHit) end
        end)
    end
    AddPrefabPostInit("world", function(world)
        world:ListenForEvent("playeractivated", function(_, player) AttachPlayer(player) end)
        world:DoTaskInTime(0, function() AttachPlayer(G.ThePlayer) end)
    end)
    if G.ThePlayer ~= nil then AttachPlayer(G.ThePlayer) end
end

return Bridge
