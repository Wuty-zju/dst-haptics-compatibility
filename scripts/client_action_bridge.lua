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
    if adapter_state ~= nil and adapter_state.client_action_bridge_installed then
        return adapter_state.client_action_bridge_cleanup
    end
    local closed = false
    local owner = {}
    local captures = G.setmetatable({}, { __mode = "k" })
    local work_contexts = G.setmetatable({}, { __mode = "k" })
    local serials = G.setmetatable({}, { __mode = "k" })
    local attached = G.setmetatable({}, { __mode = "k" })
    local records, listeners, tasks = {}, {}, {}
    local function IsInstalled()
        if closed then return false end
        if api.IsInstalled ~= nil then return api.IsInstalled() == true end
        return adapter_state == nil or adapter_state.installed ~= false
    end
    local function Generation()
        return api.GetGeneration ~= nil and api.GetGeneration() or nil
    end
    local function CanObserve()
        return IsInstalled() and (api.CanObserve == nil or api.CanObserve() == true)
    end
    local function ShouldBridge(kind)
        return IsInstalled() and api.ShouldBridge ~= nil and api.ShouldBridge(kind) == true
    end
    local function Now()
        return G.GetTime ~= nil and G.GetTime() or 0
    end
    local function NextSerial(inst)
        serials[inst] = (serials[inst] or 0) + 1
        return serials[inst]
    end
    local function ServerState(inst)
        local classified = inst.player_classified
        local current = classified ~= nil and classified.currentstate or nil
        if current == nil or current.value == nil or G.hash == nil then return nil end
        return current:value()
    end
    local function WorkStateMatches(inst, kind)
        local state = ServerState(inst)
        -- These eight states exist in the audited SGwilson snapshot. No state
        -- hash means no server-initiated repeat can be confirmed on this client.
        return state ~= nil and (kind == "chop" or kind == "mine" or kind == "hammer" or kind == "dig")
            and (state == G.hash(kind) or state == G.hash(kind .. "_start"))
    end
    local function Listen(entity, event, fn)
        entity:ListenForEvent(event, fn)
        listeners[#listeners + 1] = { entity = entity, event = event, fn = fn }
    end
    local function BindObserver(object, key, marker, observe)
        local record = object[marker]
        if G.type(record) ~= "table" then
            record = { original = object[key] }
            record.wrapper = function(...)
                if record.observe ~= nil then pcall(record.observe, ...) end
                return record.original(...)
            end
            object[marker] = record
            object[key] = record.wrapper
        end
        record.observe, record.owner = observe, owner
        records[record] = true
    end
    local function CaptureBufferedAction(inst, kind)
        if not IsInstalled() or inst ~= G.ThePlayer then return end
        captures[inst], work_contexts[inst] = nil, nil
        if not CanObserve() or kind == "attack" and not ShouldBridge("combat") then return end
        local action = inst.GetBufferedAction ~= nil and inst:GetBufferedAction() or nil
        if action == nil then return end
        local capture =
        {
            action = action, kind = kind, target = action.target,
            weapon = CaptureWeapon(inst, action, kind), awaiting_preview = true,
            captured_at = Now(), generation = Generation(),
        }
        if kind ~= "attack" then
            capture.work_event = ResolveWorkEvent(kind, inst, capture.target, capture.weapon)
        end
        captures[inst] = capture
        if action.AddFailAction ~= nil then
            action:AddFailAction(function()
                local function ClearFailedCapture()
                    if IsInstalled() and captures[inst] == capture then captures[inst] = nil end
                end
                -- Successful classified acknowledgements call Fail through
                -- ClearBufferedAction, then performaction in the same tick.
                if inst.DoTaskInTime ~= nil then inst:DoTaskInTime(0, ClearFailedCapture)
                else ClearFailedCapture() end
            end)
        end
    end
    local function WrapState(sg, name, kind)
        local state = sg.states ~= nil and sg.states[name] or nil
        if state == nil or state.onenter == nil then return end
        BindObserver(state, "onenter", "_dst_haptics_bridge", function(inst)
            CaptureBufferedAction(inst, kind)
        end)
    end
    local function ConfigureGraph(sg)
        if not IsInstalled() then return end
        WrapState(sg, "chop_start", "chop")
        WrapState(sg, "mine_start", "mine")
        WrapState(sg, "hammer_start", "hammer")
        WrapState(sg, "dig_start", "dig")
        WrapState(sg, "attack", "attack")
    end
    AddStategraphPostInit("wilson_client", ConfigureGraph)

    local function AttachPlayer(player)
        if not IsInstalled() or player == nil or player ~= G.ThePlayer or attached[player] then return end
        attached[player] = true
        -- A same-VM reinstall may reuse an already loaded stategraph without
        -- executing any newly registered postinit callbacks.
        local graph = player.sg ~= nil and player.sg.sg or nil
        if graph ~= nil and graph.name == "wilson_client" then ConfigureGraph(graph) end
        local monitor = { cycle = 0, hungry = false, attacked = 0 }
        if player.PerformPreviewBufferedAction ~= nil then
            BindObserver(player, "PerformPreviewBufferedAction", "_dst_haptics_preview", function(inst)
                if not IsInstalled() then return end
                -- All new previews end a previous server-repeat context, even
                -- when they are instant actions outside the five wrapped states.
                work_contexts[inst] = nil
                local capture = captures[inst]
                captures[inst] = nil
                if inst == G.ThePlayer and capture ~= nil and capture.awaiting_preview
                    and inst:GetBufferedAction() == capture.action then
                    capture.awaiting_preview = false
                    captures[inst] = capture
                end
            end)
        end
        Listen(player, "actionfailed", function(inst, data)
            if not IsInstalled() then return end
            local capture, context = captures[inst], work_contexts[inst]
            if capture ~= nil and (data == nil or data.action == nil or data.action == capture.action) then
                captures[inst] = nil
            end
            if context ~= nil and (data == nil or data.action == nil or data.action == context.action) then
                work_contexts[inst] = nil
            end
        end)
        local monitor_periodic = player.DoStaticPeriodicTask or player.DoPeriodicTask
        local monitor_task = monitor_periodic(player, 0.10, function(inst)
            if not IsInstalled() or inst ~= G.ThePlayer or not IsValid(inst) then return end
            -- funnyidle's audited hungry branch plays this exact event. Its
            -- state hash alone also covers shivering/overheating/sanity idles;
            -- require the replicated hungry animation to identify the branch.
            local hungry = G.hash ~= nil and ServerState(inst) == G.hash("funnyidle")
                and inst.AnimState ~= nil and inst.AnimState:IsCurrentAnimation("hungry") or false
            if hungry and not monitor.hungry and not IsHost(inst) and CanObserve() then
                monitor.cycle = monitor.cycle + 1
                api.Emit("dontstarve/wilson/hungry", inst,
                    { source = "replicated_player_state", semantic_key = "hungry|" .. tostring(monitor.cycle) })
            end
            -- Updating this while disabled/paused prevents a stale edge on resume.
            monitor.hungry = hungry
            local context = work_contexts[inst]
            if context ~= nil and (context.generation ~= Generation() or Now() - context.last_ack > 2
                or not IsValid(context.target)) then work_contexts[inst] = nil end
        end)
        if monitor_task ~= nil then tasks[#tasks + 1] = monitor_task end
        Listen(player, "performaction", function(inst, data)
            if not IsInstalled() or inst ~= G.ThePlayer then return end
            local capture = captures[inst]
            captures[inst] = nil
            local repeated = capture == nil
            if repeated then capture = work_contexts[inst] end
            work_contexts[inst] = nil
            if capture == nil or not IsValid(inst) or not CanObserve()
                or capture.generation ~= Generation()
                or data ~= nil and data.action ~= nil and data.action ~= capture.action then return end
            local now = Now()
            if now - (repeated and capture.last_ack or capture.captured_at) > 2 then return end
            if repeated and (not IsValid(capture.target) or not WorkStateMatches(inst, capture.kind)) then return end
            local sequence = NextSerial(inst)
            local event, emitter, source
            if capture.kind == "attack" then
                -- ATTACK.fn succeeds even on a miss or projectile launch.
                if not ShouldBridge("combat") or IsHost(inst) or IsDeadPlayer(inst)
                    or capture.weapon ~= nil and not IsValid(capture.weapon)
                    or CaptureWeapon(inst, capture.action, "attack") ~= capture.weapon
                    or not AttackIsMelee(inst, capture.weapon)
                    or not CanResolveMeleeHit(inst, capture.target) then return end
                event = ResolveImpactSound(capture.target, capture.weapon)
                emitter, source = capture.target, "server_confirmed_combat_approx"
            else
                event = IsValid(capture.target)
                    and ResolveWorkEvent(capture.kind, inst, capture.target, capture.weapon) or capture.work_event
                emitter = capture.kind == "chop" and capture.target or inst
                if not IsValid(emitter) then emitter = inst end
                source = "server_confirmed_work"
                -- The audited server repeat reuses this action/target. Require
                -- the matching authoritative work state on every later ack.
                if IsValid(capture.target) then
                    capture.last_ack = now
                    work_contexts[inst] = capture
                end
            end
            if event ~= nil and api.GetEffect ~= nil and api.GetEffect(event) ~= nil then
                api.Emit(event, emitter, { source = source,
                    semantic_key = capture.kind .. "|" .. tostring(sequence) })
            end
        end)
        Listen(player, "attacked", function(inst, data)
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
            if inst.DoTaskInTime ~= nil then inst:DoTaskInTime(0.05, EmitGenericHit) end
        end)
    end
    AddPrefabPostInit("world", function(world)
        if not IsInstalled() then return end
        Listen(world, "playeractivated", function(_, player) AttachPlayer(player) end)
        world:DoTaskInTime(0, function() AttachPlayer(G.ThePlayer) end)
    end)
    local function Cleanup()
        if closed then return end
        closed = true
        for record in G.pairs(records) do
            if record.owner == owner then record.observe, record.owner = nil, nil end
        end
        for i = 1, #listeners do
            local binding = listeners[i]
            if binding.entity.RemoveEventCallback ~= nil then
                pcall(binding.entity.RemoveEventCallback, binding.entity, binding.event, binding.fn)
            end
        end
        for i = 1, #tasks do
            local task = tasks[i]
            if task.Cancel ~= nil then pcall(task.Cancel, task) end
        end
        for inst in G.pairs(captures) do captures[inst] = nil end
        for inst in G.pairs(work_contexts) do work_contexts[inst] = nil end
        records, listeners, tasks = {}, {}, {}
        if adapter_state ~= nil and adapter_state.client_action_bridge_cleanup == Cleanup then
            adapter_state.client_action_bridge_installed = false
            adapter_state.client_action_bridge_cleanup = nil
        end
    end
    if adapter_state ~= nil then
        adapter_state.client_action_bridge_installed = true
        adapter_state.client_action_bridge_cleanup = Cleanup
    end
    if G.ThePlayer ~= nil then AttachPlayer(G.ThePlayer) end
    return Cleanup
end

return Bridge
