local G = GLOBAL
local pcall = G.pcall
local type = G.type

local Observers = {}

-- Audited in game 762172: these handles are exclusive to the two beam sounds
-- on this prefab. Its native Lua producers run on the master simulation.
-- Querying the client emitter never starts or changes a native sound. A true
-- result is required; smoke/wide replication and animations are not evidence
-- that a sound is currently playing. Remote engine visibility still needs an
-- in-game check, and polling does not preserve frame-exact start/stop timing.
local BEAM_LOOPS =
{
    { event = "rifts8/shrouden/opticblast_LP", name = "loop" },
    { event = "rifts8/shrouden/opticblast_big_LP", name = "bigloop" },
}

function Observers.Install(api)
    if type(api) ~= "table" or type(api.GetEffect) ~= "function"
        or type(api.ObserveLoop) ~= "function" or type(api.CanObserve) ~= "function" then
        return false
    end

    local state = type(api.GetState) == "function" and api.GetState() or api
    if type(state) ~= "table" or state._dst_haptics_observers_installed then
        return false
    end

    local mappings = {}
    for i = 1, #BEAM_LOOPS do
        local mapping = BEAM_LOOPS[i]
        local effect = api.GetEffect(mapping.event)
        if type(effect) == "table" and effect.vibration == true then
            mappings[#mappings + 1] = mapping
        end
    end
    if #mappings == 0 then
        return false
    end

    state._dst_haptics_observers_installed = true
    local instances = G.setmetatable({}, { __mode = "k" })
    if api.AddCleanup ~= nil then
        api.AddCleanup(function()
            for inst in G.pairs(instances) do
                if inst._dst_haptics_loop_observer_owner == state then
                    local task = inst._dst_haptics_loop_observer_task
                    if task ~= nil and task.Cancel ~= nil then task:Cancel() end
                    inst._dst_haptics_loop_observer_task = nil
                    inst._dst_haptics_loop_observer_owner = nil
                end
            end
        end)
    end
    AddPrefabPostInit("shrouden_optic_blast_fx", function(inst)
        if state.installed == false then return end
        if inst._dst_haptics_loop_observer_task ~= nil or type(inst.DoPeriodicTask) ~= "function" then
            return
        end
        inst._dst_haptics_loop_observer_owner = state
        instances[inst] = true

        -- Entity-owned tasks are cancelled by the engine on removal. The
        -- adapter's common loop manager owns false/removal/output-gating cleanup.
        inst._dst_haptics_loop_observer_task = inst:DoPeriodicTask(0.10, function()
            if inst.IsValid ~= nil and not inst:IsValid() then
                return
            end
            local allowed, can_observe = pcall(api.CanObserve)
            if not allowed or can_observe ~= true then
                return
            end
            local emitter = inst.SoundEmitter
            if emitter == nil or type(emitter.PlayingSound) ~= "function" then
                return
            end
            for i = 1, #mappings do
                local mapping = mappings[i]
                local ok, playing = pcall(emitter.PlayingSound, emitter, mapping.name)
                if ok and playing == true then
                    -- ObserveLoop rechecks PlayingSound and reuses the same
                    -- emitter/name record as the sound hook without resetting it.
                    pcall(api.ObserveLoop, mapping.event, emitter, inst, mapping.name)
                end
            end
        end)
    end)
    return true
end

return Observers
