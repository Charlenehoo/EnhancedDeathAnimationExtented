local bodyPartToAnimationsMap = include("bodyPartToAnimationsMap.lua")

local function getAnimation()
    local allAnimations = {}

    local function collect(t)
        for _, v in pairs(t) do
            if type(v) == "string" then
                table.insert(allAnimations, v)
            elseif type(v) == "table" then
                collect(v)
            end
        end
    end

    collect(bodyPartToAnimationsMap)

    if #allAnimations == 0 then
        return nil
    end

    local chosenAnimation = allAnimations[math.random(#allAnimations)]

    print("chosenAnimation is " .. chosenAnimation)

    return chosenAnimation
end

return getAnimation
