local AlignRagdoll = include("modules/helpers.lua")

TOOL.Category = "Test"
TOOL.Name = "Test AlignRagdoll"

function TOOL:LeftClick(tr)
    local clickPos = tr.HitPos

    local ORag = ents.Create("prop_ragdoll")
    ORag:SetModel("models/player/tfa_cso2/ct_choi.mdl")
    ORag:SetPos(clickPos + Vector(0, 0, 64))
    ORag:Spawn()

    for i = 0, ORag:GetPhysicsObjectCount() - 1 do
        local phyObj = ORag:GetPhysicsObjectNum(i)
        if IsValid(phyObj) then
            phyObj:EnableMotion(false)
        end
    end

    local Anim_Rag = ents.Create("prop_dynamic")
    Anim_Rag:SetModel("models/brutal_deaths/model_anim_modify.mdl")
    Anim_Rag:SetBodygroup(Anim_Rag:FindBodygroupByName("barney"), 1) --If you don't understand how this addon works, enable this line and you may see.
    Anim_Rag:Spawn()
    Anim_Rag:SetCollisionGroup(COLLISION_GROUP_WORLD)

    AlignRagdoll(Anim_Rag, ORag, 1)
end

function TOOL:RightClick(tr)

end
