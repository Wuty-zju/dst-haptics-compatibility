GLOBAL = _G
FRAMES = 1 / 30
EQUIPSLOTS = { HANDS = "hands" }
TheWorld = { ismastersim = false }
local stategraph_postinit, world_postinit
local queued, emitted, preview_calls = {}, {}, {}
local game_time, generation = 10, 0
local flags = { combat = false, hurt = false }
local special_hurt, can_observe = false, true
local installed, authoritative_state = true, "idle"
function hash(name) return "hash:" .. name end
function GetTime() return game_time end
function AddStategraphPostInit(name, fn) assert(name == "wilson_client"); stategraph_postinit = fn end
function AddPrefabPostInit(name, fn) assert(name == "world"); world_postinit = fn end
function GetWallImpactSound(_, mod) return "dontstarve/impacts/impact_wood_wall_" .. mod end
function GetObjectImpactSound(_, mod) return "dontstarve/impacts/impact_stone_object_" .. mod end
function GetCreatureImpactSound(_, mod) return "dontstarve/impacts/impact_flesh_med_" .. mod end
local native_creature_sound = GetCreatureImpactSound
local known = {}
for _, event in ipairs({
    "dontstarve/wilson/use_axe_tree", "dontstarve/wilson/use_axe_mushroom",
    "dontstarve/wilson/use_pick_rock", "dontstarve/wilson/dig", "dontstarve/wilson/hit",
    "dontstarve/wilson/hungry", "turnoftides/common/together/moon_glass/mine",
    "dontstarve/impacts/impact_flesh_med_sharp", "dontstarve/impacts/impact_flesh_med_dull",
    "dontstarve/impacts/impact_metal_armour_sharp", "test/hammer_skin",
}) do known[event] = true end
local api =
{
    GetEffect = function(event) return known[event] and { event = event } or nil end,
    Emit = function(event, entity, context)
        emitted[#emitted + 1] = { event = event, entity = entity, source = context.source, key = context.semantic_key }
        return true
    end,
    ShouldBridge = function(kind) return flags[kind] == true end,
    GetGeneration = function() return generation end,
    CanObserve = function() return can_observe end,
    IsInstalled = function() return installed end,
    HasRecentSpecialHurt = function() return special_hurt end,
    -- GetState is deliberately absent: the bridge API permits this.
}
local function Transform(x, z) return { GetWorldPosition = function() return x, 0, z end } end
local function Entity(tags)
    return {
        tags = tags or {}, valid = true,
        IsValid = function(self) return self.valid end,
        IsInLimbo = function() return false end,
        HasTag = function(self, tag) return self.tags[tag] == true end,
        HasAnyTag = function(self, ...)
            for i = 1, select("#", ...) do if self.tags[select(i, ...)] then return true end end
            return false
        end,
    }
end
local target = Entity({ tree = true })
target.GUID, target.prefab, target.Transform = 20, "evergreen", Transform(1, 0)
target.GetPhysicsRadius = function() return 0.5 end
target.replica = { combat = { CanBeAttacked = function() return true end } }
local weapon = Entity({ sharp = true, weapon = true })
local hand, current_weapon = weapon, weapon
local current_anim, state_tags = "idle", { attack = true }
local player = Entity()
player.GUID, player.Transform = 10, Transform(0, 0)
player.replica =
{
    combat = {
        GetAttackRangeWithWeapon = function() return 2 end,
        GetWeapon = function() return current_weapon end,
    },
    inventory = { GetEquippedItem = function(_, slot) assert(slot == "hands"); return hand end },
    health = { IsDead = function() return player.tags.dead == true end },
}
player.sg = { HasStateTag = function(_, tag) return state_tags[tag] == true end }
player.GetBufferedAction = function(self) return self.bufferedaction end
player.DoTaskInTime = function(_, delay, fn) queued[#queued + 1] = { delay = delay, fn = fn } end
local monitor_tasks = {}
player.DoPeriodicTask = function(self, _, fn)
    self.monitor = fn
    local task = { fn = fn, Cancel = function(self) self.cancelled = true end }
    monitor_tasks[#monitor_tasks + 1] = task
    return task
end
player.ListenForEvent = function(self, event, fn)
    self.callbacks = self.callbacks or {}; self.callbacks[event] = self.callbacks[event] or {}
    self.callbacks[event][#self.callbacks[event] + 1] = fn
    self.listeners = self.listeners or {}
    self.listeners[event] = function(...)
        for _, callback in ipairs(self.callbacks[event]) do callback(...) end
    end
end
player.RemoveEventCallback = function(self, event, fn)
    for i = #self.callbacks[event], 1, -1 do
        if self.callbacks[event][i] == fn then table.remove(self.callbacks[event], i) end
    end
end
player.player_classified = { currentstate = { value = function() return hash(authoritative_state) end } }
player.AnimState = { IsCurrentAnimation = function(_, name) return current_anim == name end }
player.PerformPreviewBufferedAction = function(self, ...)
    preview_calls[#preview_calls + 1] = { n = select("#", ...), ... }
    if self.bufferedaction ~= nil then self.bufferedaction.ispreviewing = true end
    return "preview", nil, false
end
player.ClearBufferedAction = function(self)
    if self.bufferedaction ~= nil then self.bufferedaction:Fail(); self.bufferedaction = nil end
end
ThePlayer = player
local root = assert(os.getenv("DST_HAPTICS_MOD_ROOT"), "DST_HAPTICS_MOD_ROOT is required")
local Bridge = dofile(root .. "/scripts/client_action_bridge.lua")
local cleanup = assert(Bridge.Install(api))
local original_postinit = stategraph_postinit
local function EmptyState()
    return { onenter = function(inst, ...)
        inst:PerformPreviewBufferedAction(...)
        return "state", nil, false
    end }
end
local sg = { name = "wilson_client", states = {} }
player.sg.sg = sg
for _, state in ipairs({ "chop_start", "mine_start", "hammer_start", "dig_start", "attack" }) do
    sg.states[state] = EmptyState()
end
stategraph_postinit(sg)
local function Action(kind, invobject)
    return {
        action = kind, target = target, invobject = invobject, onfail = {},
        AddFailAction = function(self, fn) self.onfail[#self.onfail + 1] = fn end,
        Fail = function(self)
            for i = 1, #self.onfail do self.onfail[i]() end
            self.onfail = {}
        end,
    }
end
local function Start(state, kind, invobject)
    local action = Action(kind, invobject)
    player.bufferedaction = action
    authoritative_state = string.lower(kind)
    sg.states[state].onenter(player)
    return action
end
local function Ack(action)
    player:ClearBufferedAction() -- player_classified success does this first!
    player.listeners.performaction(player, action ~= nil and { action = action } or nil)
end
local function RunQueued()
    local pending = queued; queued = {}
    for i = 1, #pending do pending[i].fn() end
end
local function ExpectNoOutput(fn, message)
    local count = #emitted
    fn()
    assert(#emitted == count, message)
end

-- Wrapper argument count, nil holes and all original returns are preserved.
player.bufferedaction = Action("PICK")
local a, b, c = player:PerformPreviewBufferedAction("arg", nil, 3)
assert(a == "preview" and b == nil and c == false)
assert(preview_calls[#preview_calls].n == 3 and preview_calls[#preview_calls][3] == 3)
a, b, c = sg.states.chop_start.onenter(player, "statearg", nil, 4)
assert(a == "state" and b == nil and c == false)
assert(preview_calls[#preview_calls].n == 3 and preview_calls[#preview_calls][3] == 4)
player:ClearBufferedAction(); RunQueued()

-- Ordinary work still uses the native action acknowledgement and repeats.
for i = 1, 3 do
    Start("chop_start", "CHOP", weapon); Ack(); RunQueued()
    assert(emitted[#emitted].event == "dontstarve/wilson/use_axe_tree")
    assert(emitted[#emitted].source == "server_confirmed_work")
    if i > 1 then assert(emitted[#emitted].key ~= emitted[#emitted - 1].key, "serial reset after consumption") end
end
authoritative_state = "idle"
ExpectNoOutput(function() Ack() end, "ack outside an authoritative work state repeated output")
Start("mine_start", "MINE", weapon); Ack(); RunQueued()
assert(emitted[#emitted].event == "dontstarve/wilson/use_pick_rock")

-- Removed final work targets keep their captured native material event.
target.tags.mushtree = true
Start("chop_start", "CHOP", weapon); target.valid = false; Ack(); RunQueued()
assert(emitted[#emitted].event == "dontstarve/wilson/use_axe_mushroom")
assert(emitted[#emitted].entity == player)
target.valid, target.tags.mushtree, target.tags.moonglass = true, nil, true
Start("mine_start", "MINE", weapon); target.valid = false; Ack(); RunQueued()
assert(emitted[#emitted].event == "turnoftides/common/together/moon_glass/mine")
target.valid, target.tags.moonglass = true, nil
weapon.hit_skin_sound = "test/hammer_skin"
Start("hammer_start", "HAMMER"); Ack(); RunQueued()
assert(emitted[#emitted].event == "test/hammer_skin", "hand-slot tool skin sound was lost")
weapon.hit_skin_sound = nil

-- Neither a successful ATTACK action nor attacked implies a native hit sound.
ExpectNoOutput(function()
    Start("attack", "ATTACK"); Ack()
    player.listeners.attacked(player, {}); RunQueued()
end, "strict defaults emitted approximate combat or hurt feedback")
local should_bridge = api.ShouldBridge
api.ShouldBridge = nil
ExpectNoOutput(function() Start("attack", "ATTACK"); Ack(); player.listeners.attacked(player, {}); RunQueued() end,
    "missing opt-in API enabled approximations")
api.ShouldBridge = should_bridge
flags.combat, flags.hurt = true, true
Start("attack", "ATTACK"); Ack(); RunQueued()
assert(emitted[#emitted].event == "dontstarve/impacts/impact_flesh_med_sharp", "normal ATTACK has no invobject; equipped weapon must resolve sharp")
assert(emitted[#emitted].source == "server_confirmed_combat_approx")
Start("attack", "ATTACK"); flags.combat = false
ExpectNoOutput(function() Ack(); RunQueued() end, "disabled combat approximation survived acknowledgement")
flags.combat = true
Start("attack", "ATTACK"); current_weapon = nil
ExpectNoOutput(function() Ack(); RunQueued() end, "weapon replacement changed a captured material estimate")
current_weapon = weapon

-- An intentional nil GetWeapon result must not fall back to the sharp hand item.
current_weapon = nil
Start("attack", "ATTACK", weapon); Ack(); RunQueued()
assert(emitted[#emitted].event == "dontstarve/impacts/impact_flesh_med_dull")
current_weapon = weapon
for _, tag in ipairs({ "rangedweapon", "projectile", "complexprojectile", "slingshot", "propweapon", "multithruster", "helmsplitter", "pillow", "aoeweapon_leap" }) do
    weapon.tags[tag] = true
    ExpectNoOutput(function() Start("attack", "ATTACK"); Ack(); RunQueued() end, tag .. " emitted an estimated melee impact")
    weapon.tags[tag] = nil
end
for _, tag in ipairs({ "propattack", "thrusting", "helmsplitting" }) do
    state_tags[tag] = true
    ExpectNoOutput(function() Start("attack", "ATTACK"); Ack(); RunQueued() end, tag .. " emitted an estimated melee impact")
    state_tags[tag] = nil
end
Start("attack", "ATTACK"); target.Transform = Transform(20, 0)
ExpectNoOutput(function() Ack(); RunQueued() end, "out-of-range target emitted an estimated impact")
target.Transform = Transform(1, 0)

-- A metal umbrella in a hand slot has no armor component. Remote inventory
-- replicas cannot prove armor identity (or even equipment absence).
target.replica.inventory = { GetEquips = function() return { hands = Entity({ metal = true }) } end }
ExpectNoOutput(function() Start("attack", "ATTACK"); Ack(); RunQueued() end, "metal non-armor item fabricated an armor impact")
target.replica.inventory.GetEquips = function() return {} end
ExpectNoOutput(function() Start("attack", "ATTACK"); Ack(); RunQueued() end, "empty remote equipment proved armor absence")
target.replica.inventory = nil
GetCreatureImpactSound = function() error("server-only field unavailable") end
ExpectNoOutput(function() Start("attack", "ATTACK"); Ack(); RunQueued() end, "failed native resolver fabricated default flesh impact")
GetCreatureImpactSound = native_creature_sound
Start("attack", "ATTACK"); target.valid = false
ExpectNoOutput(function() Ack(); RunQueued() end, "removed combat target fabricated a killing hit")
target.valid = true

-- A new preview of any kind invalidates a cancelled capture, even when the old
-- Fail callback has not run yet. Every successful ack also calls Fail first.
Start("chop_start", "CHOP", weapon)
player:ClearBufferedAction()
player.bufferedaction = Action("PICK")
player:PerformPreviewBufferedAction()
ExpectNoOutput(function() Ack(); RunQueued() end, "unrelated action ack consumed cancelled work capture")
Start("mine_start", "MINE", weapon)
player.listeners.actionfailed(player, { action = player.bufferedaction })
ExpectNoOutput(function() Ack(); RunQueued() end, "failed action retained its capture")
Start("mine_start", "MINE", weapon)
player.listeners.actionfailed(player, { action = Action("PICK") })
Ack(); RunQueued()
assert(emitted[#emitted].event == "dontstarve/wilson/use_pick_rock", "unrelated failure erased a new capture")
Start("chop_start", "CHOP", weapon); player:ClearBufferedAction()
Start("mine_start", "MINE", weapon)
RunQueued() -- old deferred failure must not erase the new capture
Ack(); RunQueued()
assert(emitted[#emitted].event == "dontstarve/wilson/use_pick_rock")
Start("chop_start", "CHOP", weapon)
ExpectNoOutput(function() player.listeners.performaction(player, { action = Action("PICK") }); RunQueued() end,
    "mismatched action identity emitted feedback")
Start("chop_start", "CHOP", weapon); generation = generation + 1
ExpectNoOutput(function() Ack(); RunQueued() end, "old-generation work survived lifecycle change")

player.listeners.attacked(player, {}); RunQueued()
assert(emitted[#emitted].event == "dontstarve/wilson/hit")
assert(emitted[#emitted].source == "replicated_hurt_approx")
for _, data in ipairs({ { redirected = true }, { noimpactsound = true } }) do
    ExpectNoOutput(function() player.listeners.attacked(player, data); RunQueued() end, "suppressed hurt event emitted approximate hit")
end
for _, tag in ipairs({ "dead", "playerghost", "ghost" }) do
    player.tags[tag] = true
    ExpectNoOutput(function() player.listeners.attacked(player, {}); RunQueued() end, tag .. " emitted hurt feedback")
    player.tags[tag] = nil
end
TheWorld.ismastersim = true
ExpectNoOutput(function() player.listeners.attacked(player, {}); Start("attack", "ATTACK"); Ack(); RunQueued() end,
    "host added approximate feedback alongside accurate sound hooks")
TheWorld.ismastersim = false
special_hurt = true
ExpectNoOutput(function() player.listeners.attacked(player, {}); RunQueued() end, "special hurt did not suppress generic hit")
special_hurt = false
player.listeners.attacked(player, {}); generation = generation + 1
ExpectNoOutput(RunQueued, "old-generation hurt survived pause/disconnect/config change")
player.listeners.attacked(player, {}); flags.hurt = false
ExpectNoOutput(RunQueued, "disabling hurt fallback left queued generic hit")
flags.hurt = true
player.listeners.attacked(player, {}); player.tags.playerghost = true
ExpectNoOutput(RunQueued, "queued generic hit survived becoming a ghost")
player.tags.playerghost = nil
player.listeners.attacked(player, {}); can_observe = false
ExpectNoOutput(RunQueued, "queued generic hit ignored output gating")
can_observe = true
player.listeners.attacked(player, {}); local previous_player = ThePlayer; ThePlayer = nil
ExpectNoOutput(RunQueued, "queued generic hit survived player removal")
ThePlayer = previous_player

-- Server-initiated work repeats require a current matching state and live
-- target; no fresh client preview is fabricated for these acknowledgements.
for _, kind in ipairs({ "chop", "mine", "hammer", "dig" }) do
    Start(kind .. "_start", string.upper(kind), weapon); Ack(); RunQueued()
    local previous_key = emitted[#emitted].key
    authoritative_state = kind .. "_start"
    local before_repeat = #emitted
    Ack(); RunQueued()
    assert(#emitted == before_repeat + 1 and emitted[#emitted].key ~= previous_key)
    authoritative_state = kind
    before_repeat = #emitted
    Ack(); RunQueued()
    assert(#emitted == before_repeat + 1, kind .. " server repeat was lost after successful ClearBufferedAction")
    player.listeners.actionfailed(player)
end
Start("chop_start", "CHOP", weapon); Ack(); RunQueued()
player.bufferedaction = Action("PICK"); player:PerformPreviewBufferedAction()
ExpectNoOutput(function() Ack(); RunQueued() end, "new unrelated preview retained the old repeat context")
Start("chop_start", "CHOP", weapon); Ack(); RunQueued()
game_time = game_time + 2.01
ExpectNoOutput(function() Ack() end, "expired repeat context emitted")
Start("chop_start", "CHOP", weapon); Ack(); RunQueued(); generation = generation + 1
ExpectNoOutput(function() Ack() end, "repeat context survived generation change")
Start("chop_start", "CHOP", weapon); Ack(); RunQueued(); target.valid = false
ExpectNoOutput(function() Ack() end, "repeat context used a removed target")
target.valid = true
Start("chop_start", "CHOP", weapon); Ack(); RunQueued(); authoritative_state = "mine"
ExpectNoOutput(function() Ack() end, "different authoritative state repeated old work")
Start("chop_start", "CHOP", weapon); Ack(); RunQueued()
local classified = player.player_classified
player.player_classified = nil
ExpectNoOutput(function() Ack() end, "missing classified guessed a server repeat")
player.player_classified = classified

-- Hungry is funnyidle's audited animation branch, never a guessed hungry SG.
current_anim, authoritative_state = "hungry", "idle"
ExpectNoOutput(function() player.monitor(player) end, "hungry animation alone was treated as authoritative")
authoritative_state, TheWorld.ismastersim = "funnyidle", true
api.Emit("dontstarve/wilson/hungry", player, { source = "sound" })
ExpectNoOutput(function() player.monitor(player) end, "host duplicated its exact hungry sound")
TheWorld.ismastersim = false
authoritative_state = "idle"; player.monitor(player)
authoritative_state = "funnyidle"; player.monitor(player)
assert(emitted[#emitted].event == "dontstarve/wilson/hungry")
ExpectNoOutput(function() player.monitor(player) end, "hungry state/animation branch emitted repeatedly")
player.player_classified = nil
ExpectNoOutput(function() player.monitor(player) end, "missing classified guessed hungry feedback")
player.player_classified = classified
local native_hash = hash
hash = nil
ExpectNoOutput(function() player.monitor(player) end, "missing hash API guessed hungry feedback")
hash = native_hash
authoritative_state = "idle"; player.monitor(player)
authoritative_state, can_observe = "funnyidle", false
ExpectNoOutput(function() player.monitor(player) end, "disabled hungry edge emitted")
can_observe = true
ExpectNoOutput(function() player.monitor(player) end, "enabling replayed the old hungry edge")
local world = {
    ListenForEvent = function(self, event, fn) self[event] = fn end,
    DoTaskInTime = function(_, _, fn) fn() end,
    RemoveEventCallback = function(self, event, fn) if self[event] == fn then self[event] = nil end end,
}
world_postinit(world)
assert(world.playeractivated ~= nil)

-- Rebinding replaces observers, rather than nesting SG/preview wrappers. Old
-- postinit callbacks/listeners cannot reclaim them after their API shuts down.
local state_wrapper, preview_wrapper = sg.states.mine_start.onenter, player.PerformPreviewBufferedAction
local old_monitor = player.monitor
player.listeners.attacked(player, {}) -- queue an old API's delayed fallback
installed = false
local fresh_state = { installed = true }
local fresh_api = {}
for key, value in pairs(api) do fresh_api[key] = value end
fresh_api.IsInstalled = nil -- exercise the GetState().installed fallback
fresh_api.GetState = function() return fresh_state end
local fresh_cleanup = assert(Bridge.Install(fresh_api))
assert(Bridge.Install(fresh_api) == fresh_cleanup, "same installation did not return its cleanup")
original_postinit(sg) -- an old mod callback must not take back the observer
assert(sg.states.mine_start.onenter == state_wrapper and player.PerformPreviewBufferedAction == preview_wrapper,
    "bridge reinstall stacked wrappers")
ExpectNoOutput(function() old_monitor(player); RunQueued() end, "old API retained an active task or hurt callback")
local before_reinstall = #emitted
Start("mine_start", "MINE", weapon); Ack(); RunQueued()
assert(#emitted == before_reinstall + 1, "same-VM reinstall lost work captures or duplicated listeners")
stategraph_postinit(sg)
assert(sg.states.mine_start.onenter == state_wrapper, "later postinit nested the already rebound graph")
cleanup() -- late old cleanup must preserve the fresh installation's records
assert(monitor_tasks[1].cancelled == true and world.playeractivated == nil)
before_reinstall = #emitted
Start("mine_start", "MINE", weapon); Ack(); RunQueued()
assert(#emitted == before_reinstall + 1, "old cleanup removed the new observer")
fresh_cleanup(); fresh_cleanup()
assert(monitor_tasks[#monitor_tasks].cancelled == true)
ExpectNoOutput(function() Start("mine_start", "MINE", weapon); Ack(); player.monitor(player); RunQueued() end,
    "cleaned bridge retained output side effects")
assert(#player.callbacks.performaction == 0 and #player.callbacks.attacked == 0)
print("client action bridge tests passed: strict defaults, explicit approximations, action identity, native weapon resolution and lifecycle")
