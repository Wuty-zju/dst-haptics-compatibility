GLOBAL = _G

local source = assert(os.getenv("DST_HAPTICS_MOD_ROOT"), "DST_HAPTICS_MOD_ROOT is required")
    .. "/scripts/haptic_observers.lua"
local function LoadObservers()
    local fn, err = loadfile(source)
    assert(fn, err)
    setfenv(fn, _G)
    return fn()
end

local BASIC = "rifts8/shrouden/opticblast_LP"
local BIG = "rifts8/shrouden/opticblast_big_LP"
local registrations = {}
function AddPrefabPostInit(name, fn)
    assert(name == "shrouden_optic_blast_fx", "only the audited prefab may be observed")
    registrations[#registrations + 1] = fn
end

local function Entity()
    local inst = { valid = true, tasks = {}, queries = 0, playing = {}, errors = {} }
    inst.SoundEmitter =
    {
        PlayingSound = function(_, name)
            inst.queries = inst.queries + 1
            if inst.errors[name] then error("unavailable engine handle") end
            return inst.playing[name]
        end,
        PlaySound = function() error("observer must never play a sound") end,
        KillSound = function() error("observer must never kill a sound") end,
        SetParameter = function() error("observer must never change sound parameters") end,
    }
    function inst:IsValid() return self.valid end
    function inst:DoPeriodicTask(period, fn)
        assert(period == 0.10)
        local task = { fn = fn, cancelled = false }
        function task:Cancel() self.cancelled = true end
        self.tasks[#self.tasks + 1] = task
        return task
    end
    function inst:Tick()
        for i = 1, #self.tasks do
            if not self.tasks[i].cancelled then self.tasks[i].fn(self) end
        end
    end
    function inst:Remove()
        self.valid = false
        for i = 1, #self.tasks do self.tasks[i]:Cancel() end
    end
    return inst
end

local function Harness(effects)
    local h = { state = {}, allowed = true, attempts = {}, records = {}, starts = 0, cleanups = {} }
    h.api =
    {
        GetState = function() return h.state end,
        AddCleanup = function(fn) h.cleanups[#h.cleanups + 1] = fn end,
        GetEffect = function(event) return effects[event] end,
        CanObserve = function()
            if h.gate_error then error("gate unavailable") end
            return h.allowed
        end,
        ObserveLoop = function(event, emitter, entity, name)
            h.attempts[#h.attempts + 1] = { event = event, emitter = emitter, entity = entity, name = name }
            if h.observe_error then error("adapter unavailable") end
            -- Adapter contract: double-check the engine and share sound-hook keys.
            if emitter:PlayingSound(name) ~= true then return false end
            local key = tostring(emitter) .. "|" .. name
            if h.records[key] == nil then
                h.starts = h.starts + 1
                h.records[key] = { event = event, entity = entity, started = h.starts }
            end
            return true
        end,
    }
    function h:Refresh(inst)
        for key in pairs(self.records) do
            local name = key:match("|([^|]+)$")
            local ok, playing = pcall(inst.SoundEmitter.PlayingSound, inst.SoundEmitter, name)
            if not inst.valid or not ok or playing ~= true or self.allowed ~= true then
                self.records[key] = nil
            end
        end
    end
    return h
end

local both = { [BASIC] = { vibration = true }, [BIG] = { vibration = true } }
local module = LoadObservers()
assert(module.Install(nil) == false)
assert(module.Install({}) == false)
local unknown = Harness({})
assert(module.Install(unknown.api) == false and #registrations == 0)
local disabled = Harness({ [BASIC] = { vibration = false }, [BIG] = { vibration = 1 } })
assert(module.Install(disabled.api) == false and #registrations == 0, "only literal vibration=true is eligible")

local h = Harness(both)
assert(module.Install(h.api) == true and #registrations == 1)
assert(module.Install(h.api) == false)
assert(LoadObservers().Install(h.api) == false, "reload must share the install guard")
local inst = Entity()
registrations[1](inst)
registrations[1](inst)
assert(#inst.tasks == 1, "one entity owns one observer task")
inst:Tick()
assert(#h.attempts == 0 and h.starts == 0, "missing handles cannot produce output")
inst.playing.loop = false
inst.playing.bigloop = "true"
inst:Tick()
assert(#h.attempts == 0, "truthy non-boolean engine results must not count")

inst.playing.loop = true
inst.playing.bigloop = false
inst:Tick()
assert(#h.attempts == 1 and h.starts == 1)
assert(h.attempts[1].event == BASIC and h.attempts[1].name == "loop")
assert(h.attempts[1].entity == inst and h.attempts[1].emitter == inst.SoundEmitter)
local basic_key = tostring(inst.SoundEmitter) .. "|loop"
local existing = h.records[basic_key]
-- The sound hook and observer use the same API-owned record. Repeated polls
-- must not reset it; production integration is verified by adapter tests too.
existing.source = "sound"
inst:Tick()
assert(h.starts == 1 and h.records[basic_key] == existing and existing.source == "sound")

local sound_inst = Entity()
sound_inst.playing.loop = true
registrations[1](sound_inst)
local sound_key = tostring(sound_inst.SoundEmitter) .. "|loop"
local sound_record = { event = BASIC, source = "sound", started = -1, entity = sound_inst }
h.records[sound_key] = sound_record
sound_inst:Tick()
assert(h.starts == 1 and h.records[sound_key] == sound_record and sound_record.started == -1,
    "a sound-hook record that predates the first observer poll must keep its lifetime")
h.records[sound_key] = nil
sound_inst:Remove()

local race_inst = Entity()
local race_reads = 0
race_inst.SoundEmitter.PlayingSound = function(_, name)
    if name ~= "loop" then return false end
    race_reads = race_reads + 1
    return race_reads == 1
end
registrations[1](race_inst)
race_inst:Tick()
assert(h.records[tostring(race_inst.SoundEmitter) .. "|loop"] == nil and h.starts == 1,
    "the adapter recheck must reject a handle that stops between observation and registration")
race_inst:Remove()

inst.playing.loop = false
inst.playing.bigloop = true
inst:Tick()
h:Refresh(inst)
local big_key = tostring(inst.SoundEmitter) .. "|bigloop"
assert(h.records[basic_key] == nil and h.records[big_key].event == BIG and h.starts == 2)
inst.playing.bigloop = false
local attempts = #h.attempts
inst:Tick()
h:Refresh(inst)
assert(#h.attempts == attempts and next(h.records) == nil, "false is cleaned up by the common manager")

inst.playing.loop = true
inst.errors.loop = true
inst:Tick()
assert(#h.attempts == attempts, "query errors fail closed")
inst.errors.loop = nil
inst.playing.bigloop = true
inst.errors.loop = true
inst:Tick()
assert(h.attempts[#h.attempts].event == BIG, "one handle error must not block the other")
inst.errors.loop = nil
for _, gate in ipairs({ false, "true" }) do
    h.allowed = gate
    local queries = inst.queries
    inst:Tick()
    assert(inst.queries == queries, "disabled/native/diagnostic gating skips all engine queries")
end
h.allowed = true
h.gate_error = true
local queries = inst.queries
inst:Tick()
assert(inst.queries == queries, "gate errors also fail closed")
h.gate_error = nil
h.observe_error = true
assert(pcall(function() inst:Tick() end), "adapter errors must not escape an entity task")
h.observe_error = nil

inst:Remove()
attempts = #h.attempts
inst:Tick()
inst.tasks[1].fn(inst) -- stale invocation is harmless even before engine cancellation takes effect.
h:Refresh(inst)
assert(#h.attempts == attempts and next(h.records) == nil)

local partial = Harness({ [BIG] = { vibration = true } })
assert(module.Install(partial.api) == true and #registrations == 2)
local partial_inst = Entity()
partial_inst.playing.loop = true
partial_inst.playing.bigloop = true
registrations[2](partial_inst)
partial_inst:Tick()
assert(#partial.attempts == 1 and partial.attempts[1].event == BIG,
    "an absent table event cannot be inferred from the handle")
partial_inst.SoundEmitter = nil
assert(pcall(function() partial_inst:Tick() end))
partial_inst.SoundEmitter = {}
assert(pcall(function() partial_inst:Tick() end))

-- Old prefab callbacks persist in the engine across a development reload.
local retired = Harness(both)
retired.state.installed = true
assert(module.Install(retired.api))
local old_callback = registrations[#registrations]
local old_fx = Entity()
old_callback(old_fx)
for _, cleanup in ipairs(retired.cleanups) do cleanup() end
retired.state.installed = false
assert(old_fx.tasks[1].cancelled and old_fx._dst_haptics_loop_observer_task == nil)
local fresh = Harness(both)
fresh.state.installed = true
assert(module.Install(fresh.api))
local new_callback = registrations[#registrations]
local new_fx = Entity()
new_fx.playing.loop = true
old_callback(new_fx)
new_callback(new_fx)
new_fx:Tick()
assert(#new_fx.tasks == 1 and fresh.starts == 1 and retired.starts == 0,
    "retired observer callback claimed a new entity after reload")
print("haptic observer tests passed (simulated engine; no remote visibility or motor claim)")
