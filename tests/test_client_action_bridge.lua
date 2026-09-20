GLOBAL = _G
FRAMES = 1 / 30

local stategraph_postinit
local world_postinit
local queued = {}
local emitted = {}
local game_time = 10
local special_hurt = false

function GetTime() return game_time end

function AddStategraphPostInit(name, fn)
    assert(name == "wilson_client")
    stategraph_postinit = fn
end

function AddPrefabPostInit(name, fn)
    assert(name == "world")
    world_postinit = fn
end

function GetWallImpactSound(_, weaponmod)
    return "dontstarve/impacts/impact_wood_wall_" .. weaponmod
end
function GetObjectImpactSound(_, weaponmod)
    return "dontstarve/impacts/impact_stone_object_" .. weaponmod
end
function GetCreatureImpactSound(_, weaponmod)
    return "dontstarve/impacts/impact_flesh_med_" .. weaponmod
end

local known =
{
    ["dontstarve/wilson/use_axe_tree"] = true,
    ["dontstarve/wilson/use_axe_mushroom"] = true,
    ["dontstarve/wilson/use_pick_rock"] = true,
    ["dontstarve/wilson/dig"] = true,
    ["dontstarve/wilson/hit"] = true,
    ["dontstarve/wilson/hungry"] = true,
    ["dontstarve/impacts/impact_flesh_med_sharp"] = true,
}
local api =
{
    GetEffect = function(event) return known[event] and { event = event } or nil end,
    Emit = function(event, entity, context)
        table.insert(emitted, { event = event, entity = entity, source = context.source })
        return true
    end,
    HasRecentSpecialHurt = function() return special_hurt end,
}

local function Transform(x, z)
    return { GetWorldPosition = function() return x, 0, z end }
end

local target_valid = true
local target =
{
    GUID = 20,
    prefab = "evergreen",
    tags = { tree = true },
    Transform = Transform(1, 0),
    IsValid = function() return target_valid end,
    IsInLimbo = function() return false end,
    HasTag = function(self, tag) return self.tags[tag] == true end,
    HasAnyTag = function(self, ...)
        for i = 1, select("#", ...) do if self.tags[select(i, ...)] then return true end end
        return false
    end,
    GetPhysicsRadius = function() return 0.5 end,
    replica =
    {
        combat = { CanBeAttacked = function() return true end },
    },
}
local weapon =
{
    tags = { sharp = true, weapon = true },
    HasTag = function(self, tag) return self.tags[tag] == true end,
}
local current_anim = "idle"
local current_frame = 0
local player =
{
    GUID = 10,
    tags = {},
    Transform = Transform(0, 0),
    replica =
    {
        combat =
        {
            GetAttackRangeWithWeapon = function() return 2 end,
            CanExtinguishTarget = function() return false end,
            CanLightTarget = function() return false end,
        },
    },
    sg = { statemem = {}, HasStateTag = function(_, tag) return tag == "attack" end },
    IsValid = function() return true end,
    IsInLimbo = function() return false end,
    HasTag = function(self, tag) return self.tags[tag] == true end,
    GetBufferedAction = function(self) return self.bufferedaction end,
    DoTaskInTime = function(self, delay, fn) table.insert(queued, { delay = delay, fn = fn }) end,
    DoPeriodicTask = function(self, _, fn) self.monitor = fn end,
    ListenForEvent = function(self, event, fn) self.listeners = self.listeners or {}; self.listeners[event] = fn end,
    AnimState =
    {
        IsCurrentAnimation = function(_, name) return current_anim == name end,
        GetCurrentAnimationFrame = function() return current_frame end,
    },
}
ThePlayer = player

local source = assert(os.getenv("DST_HAPTICS_MOD_ROOT"), "DST_HAPTICS_MOD_ROOT is required")
    .. "/scripts/client_action_bridge.lua"
local fn, err = loadfile(source)
assert(fn, err)
setfenv(fn, _G)
local Bridge = fn()
Bridge.Install(api, {})

local function EmptyState()
    return { onenter = function() return "ok" end }
end

local function RunQueued()
    local pending = queued
    queued = {}
    for i = 1, #pending do pending[i].fn() end
end
local sg =
{
    states =
    {
        chop_start = EmptyState(),
        mine_start = EmptyState(),
        hammer_start = EmptyState(),
        dig_start = EmptyState(),
        attack = EmptyState(),
    },
}
stategraph_postinit(sg)

player.bufferedaction = { target = target, invobject = weapon }
sg.states.chop_start.onenter(player)
player.listeners.performaction(player)
assert(emitted[#emitted].event == "dontstarve/wilson/use_axe_tree", "chop hit was not bridged")
local count = #emitted
player.listeners.performaction(player)
assert(#emitted == count, "same confirmed action emitted twice")

player.bufferedaction = { target = target, invobject = weapon }
sg.states.mine_start.onenter(player)
player.listeners.performaction(player)
assert(emitted[#emitted].event == "dontstarve/wilson/use_pick_rock", "mine hit was not bridged")

player.listeners.attacked(player, {})
RunQueued()
assert(emitted[#emitted].event == "dontstarve/wilson/hit", "server-confirmed attack was not bridged")
local hurt_count = #emitted
special_hurt = true
player.listeners.attacked(player, {})
RunQueued()
assert(#emitted == hurt_count, "special hurt signal did not suppress generic hit fallback")
special_hurt = false

current_anim = "hungry"
player.monitor(player)
assert(emitted[#emitted].event == "dontstarve/wilson/hungry", "replicated hungry state was not bridged")
count = #emitted
player.monitor(player)
assert(#emitted == count, "hungry animation emitted more than once per entry")

player.tags.premine = nil
player.bufferedaction = { target = target, invobject = weapon }
sg.states.attack.onenter(player)
player.listeners.performaction(player)
assert(emitted[#emitted].event == "dontstarve/impacts/impact_flesh_med_sharp", "combat material hit was not bridged")

player.bufferedaction = { target = target, invobject = weapon }
sg.states.attack.onenter(player)
target.Transform = Transform(20, 0)
count = #emitted
player.listeners.performaction(player)
assert(#emitted == count, "out-of-range melee attack incorrectly emitted an impact")
target.Transform = Transform(1, 0)

player.bufferedaction = { target = target, invobject = weapon }
sg.states.attack.onenter(player)
target_valid = false
player.listeners.performaction(player)
assert(emitted[#emitted].event == "dontstarve/impacts/impact_flesh_med_sharp", "confirmed killing hit lost its captured material impact")
assert(emitted[#emitted].entity == player, "removed hit target was not rebound to the local player for safe output")
target_valid = true

local world =
{
    ListenForEvent = function(self, event, fn) self[event] = fn end,
    DoTaskInTime = function(_, _, fn) fn() end,
}
world_postinit(world)
assert(world.playeractivated ~= nil, "world lifecycle hook was not installed")

print("client action bridge tests passed")
