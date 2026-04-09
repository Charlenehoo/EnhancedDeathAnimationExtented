TOOL.Category = "Test"
TOOL.Name = "Test AnimPlay"

function TOOL:LeftClick(tr)
    -- 创建一个目标布娃娃用于测试
    local rag = ents.Create("prop_ragdoll")
    rag:SetModel("models/player/tfa_cso2/ct_choi.mdl")
    rag:SetPos(tr.HitPos + Vector(0, 0, 4))
    rag:Spawn()
    -- 可选：固定它以便观察对齐效果
    for i = 0, rag:GetPhysicsObjectCount() - 1 do
        local phys = rag:GetPhysicsObjectNum(i)
        if IsValid(phys) then phys:EnableMotion(false) end
    end
end

function TOOL:RightClick(tr)
    -- 可留空
end
