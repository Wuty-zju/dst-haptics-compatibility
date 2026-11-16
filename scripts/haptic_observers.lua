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
    local closed = false
    local instances = G.setmetatable({}, { __mode = "k" })
    local function IsInstalled()
        return not closed and state.installed ~= false
    end
    if api.AddCleanup ~= nil then
        api.AddCleanup(function()
            if closed then return end
            closed = true
            for inst in G.pairs(instances) do
                if inst._dst_haptics_loop_observer_owner == state then
                    local task = inst._dst_haptics_loop_observer_task
                    if task ~= nil and task.Cancel ~= nil then pcall(task.Cancel, task) end
                    inst._dst_haptics_loop_observer_task = nil
                    inst._dst_haptics_loop_observer_owner = nil
                end
            end
            state._dst_haptics_observers_installed = false
        end)
    end
    local function Attach(inst)
        if not IsInstalled() or type(inst.DoPeriodicTask) ~= "function"
            or inst.IsValid ~= nil and not inst:IsValid() then return end
        local current = inst._dst_haptics_loop_observer_task
        if current ~= nil then
            local previous_owner = inst._dst_haptics_loop_observer_owner
            -- Preserve live/later owners. Only retire a known inactive API's
            -- task, including reloads where its cleanup was not called yet.
            if type(previous_owner) ~= "table" or previous_owner.installed ~= false then return end
            if current.Cancel ~= nil then pcall(current.Cancel, current) end
        end
        inst._dst_haptics_loop_observer_owner = state
        instances[inst] = true

        -- Entity-owned tasks are cancelled by the engine on removal. The
        -- adapter's common loop manager owns false/removal/output-gating cleanup.
        inst._dst_haptics_loop_observer_task = inst:DoPeriodicTask(0.10, function()
            if not IsInstalled() or inst._dst_haptics_loop_observer_owner ~= state
                or inst.IsValid ~= nil and not inst:IsValid() then
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
    end
    AddPrefabPostInit("shrouden_optic_blast_fx", Attach)
    -- Native mainfunctions keeps live EntityScripts in Ents (register/remove
    -- at lines 519/543 in the audited snapshot). Existing prefabs do not rerun
    -- postinit after a same-VM reinstall, so visit this registry once, never in
    -- the periodic observer. Sound eligibility still requires PlayingSound.
    if type(G.Ents) == "table" then
        for _, inst in G.pairs(G.Ents) do
            if inst.prefab == "shrouden_optic_blast_fx" then Attach(inst) end
        end
    end
    return true
end

return Observers
