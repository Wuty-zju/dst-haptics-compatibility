-- Chain engine calls unchanged. All compatibility side effects are protected.
local G = GLOBAL
local Hooks = {}
function Hooks.Install(state, callbacks, Util, onerror)
    local installed = {}
    local function Wrap(object, name, observe)
        local original = object ~= nil and object[name] or nil
        if type(original) ~= "function" then return end
        local wrapper = function(...)
            local result = Util.Pack(original(...))
            if state.installed then
                local ok, err = G.pcall(observe, ...)
                if not ok then onerror(err) end
            end
            return G.unpack(result, 1, result.n)
        end
        object[name] = wrapper
        installed[#installed + 1] = { object = object, name = name, original = original, wrapper = wrapper }
    end
    Wrap(G.SoundEmitter, "PlaySound", function(emitter, event, name, volume)
        callbacks.play(emitter, event, name, volume)
    end)
    Wrap(G.SoundEmitter, "PlaySoundWithParams", function(emitter, event, params, volume)
        callbacks.play(emitter, event, nil, volume, params)
    end)
    Wrap(G.SoundEmitter, "KillSound", callbacks.kill)
    Wrap(G.SoundEmitter, "KillAllSounds", callbacks.kill_all)
    Wrap(G.SoundEmitter, "SetVolume", callbacks.volume)
    Wrap(G.SoundEmitter, "SetParameter", callbacks.parameter)
    Wrap(G.Sim, "SetListener", function(_, x, y, z)
        state.listener_position = { Util.NumberOr(x, 0), Util.NumberOr(y, 0), Util.NumberOr(z, 0) }
    end)
    return function()
        -- Do not remove another mod's later wrapper. Our nested wrapper becomes inert.
        state.installed = false
        for i = #installed, 1, -1 do
            local hook = installed[i]
            if hook.object[hook.name] == hook.wrapper then hook.object[hook.name] = hook.original end
        end
    end
end
return Hooks
