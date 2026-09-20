-- Max-envelope mixing: a short strong pulse must never borrow a weak pulse's
-- longer lifetime. Values are calibrated before entering this pure function.
local M = {}

function M.Build(contributions)
    local ends, seen = {}, {}
    for i = 1, #contributions do
        local pulse = contributions[i]
        if pulse.duration > 0 and pulse.magnitude > 0 and not seen[pulse.duration] then
            seen[pulse.duration] = true
            ends[#ends + 1] = pulse.duration
        end
    end
    table.sort(ends)
    local result, start = {}, 0
    for i = 1, #ends do
        local finish, magnitude = ends[i], 0
        for j = 1, #contributions do
            local pulse = contributions[j]
            if pulse.duration >= finish then
                magnitude = math.max(magnitude, pulse.magnitude)
            end
        end
        if magnitude > 0 then
            local previous = result[#result]
            if previous and previous.magnitude == magnitude then
                previous.duration = finish - previous.delay
            else
                result[#result + 1] = { delay = start, duration = finish - start, magnitude = magnitude }
            end
        end
        start = finish
    end
    return result
end

return M
