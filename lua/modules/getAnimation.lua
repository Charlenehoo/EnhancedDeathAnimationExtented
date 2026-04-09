local bodyPartToAnimationsMap = include("bodyPartToAnimationsMap.lua")

local function getAnimation()
    local all_animations = {}

    local function collect(t)
        for _, v in pairs(t) do
            if type(v) == "string" then
                table.insert(all_animations, v)
            elseif type(v) == "table" then
                collect(v)
            end
        end
    end

    collect(bodyPartToAnimationsMap)

    if #all_animations == 0 then
        return nil
    end

    return all_animations[math.random(#all_animations)]
end

return getAnimation
