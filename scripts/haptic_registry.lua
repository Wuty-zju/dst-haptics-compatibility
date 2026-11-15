-- Native data is indexed once; full native records remain the source of truth.
local pairs = GLOBAL.pairs
local type = GLOBAL.type
local Registry = {}
function Registry.Populate(state, native_effects, Profiles)
    for i = 1, #native_effects do
        local effect = native_effects[i]
        if type(effect) == "table" and type(effect.event) == "string" then
            state.definitions = state.definitions + 1
            if state.effects[effect.event] ~= nil then
                state.duplicate_events = state.duplicate_events + 1
            end
            -- RegisterEffect is called in file order by the game. A keyed native
            -- registry consequently resolves duplicate event names to the final
            -- definition; mirroring that also avoids accidental double rumble.
            state.effects[effect.event] = effect
        end
    end

    local unique_count = 0
    for _ in pairs(state.effects) do
        unique_count = unique_count + 1
    end
    -- Resolve immutable event envelopes once, including the final duplicate
    -- definition. User tuning is applied at output time without mutating them.
    for event, effect in pairs(state.effects) do
        state.profiles[event] = Profiles.Get(effect)
    end

    return unique_count
end
return Registry
