-- Small pure helpers shared by the client pipeline.
local select = GLOBAL.select
local function Pack(...)
    return { n = select("#", ...), ... }
end

local function Clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    elseif value > maximum then
        return maximum
    end
    return value
end

local function NumberOr(value, fallback)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge and value or fallback
end


return { Pack = Pack, Clamp = Clamp, NumberOr = NumberOr }
