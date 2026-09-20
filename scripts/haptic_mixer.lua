-- Max-envelope mixing: a short strong pulse must never borrow a weak pulse's
-- longer lifetime. Values are calibrated before entering this pure function.
local M = {}

function M.Build(contributions)
    local sorted = {}
    for i = 1, #contributions do
        local pulse = contributions[i]
        if pulse.duration > 0 and pulse.magnitude > 0 then
            sorted[#sorted + 1] = pulse
        end
    end
    table.sort(sorted, function(a, b) return a.duration < b.duration end)
    -- Suffix maxima make mixing O(n log n), not a scan of all contributions
    -- at every boundary. No input profile or contribution is mutated.
    local peaks, peak = {}, 0
    for i = #sorted, 1, -1 do
        peak = math.max(peak, sorted[i].magnitude)
        peaks[i] = peak
    end
    local result, start = {}, 0
    for i = 1, #sorted do
        local finish, magnitude = sorted[i].duration, peaks[i]
        if finish > start then
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
