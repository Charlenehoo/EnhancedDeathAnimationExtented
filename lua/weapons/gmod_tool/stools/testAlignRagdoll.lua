local AlignRagdoll, AlignStrategy = include("modules/helpers.lua")

TOOL.Category = "Test"
TOOL.Name = "Test AlignRagdoll"

--- 打印两个 Ragdoll 对应骨骼之间的欧几里得距离
--- @param RagWithPhys Entity 带物理对象的源 Ragdoll
--- @param Rag Entity 目标参考 Ragdoll（用于获取骨骼位置）
local function PrintBoneDistances(RagWithPhys, Rag)
    if not IsValid(RagWithPhys) or not IsValid(Rag) then
        print("Invalid ragdoll entities")
        return
    end

    local physCount = RagWithPhys:GetPhysicsObjectCount()
    if physCount <= 0 then
        print("Source ragdoll has no physics objects")
        return
    end

    print("=== Bone Distances between " ..
        RagWithPhys:GetModel() .. " (physics) and " .. Rag:GetModel() .. " (bones) ===")

    for i = 0, physCount - 1 do
        local phyObj = RagWithPhys:GetPhysicsObjectNum(i)
        if not IsValid(phyObj) then
            print("  Phys " .. i .. ": invalid physics object in source")
            continue
        end

        -- 获取物理对象的世界位置
        local physPos = phyObj:GetPos()
        if not physPos then
            print("  Phys " .. i .. ": failed to get physics position")
            continue
        end

        -- 将物理骨骼索引转换为骨骼 ID
        local boneID = RagWithPhys:TranslatePhysBoneToBone(i)
        if not boneID then
            print("  Phys " .. i .. ": failed to translate phys bone index")
            continue
        end

        local boneName = RagWithPhys:GetBoneName(boneID)
        if not boneName then
            print("  Phys " .. i .. ": bone ID " .. boneID .. " has no name")
            continue
        end

        local boneID2 = Rag:LookupBone(boneName)
        if not boneID2 then
            print("  Bone '" .. boneName .. "': not found in target ragdoll")
            continue
        end

        local bonePos, _ = Rag:GetBonePosition(boneID)
        if not bonePos then
            print("  Bone '" .. boneName .. "': failed to get bone position from target")
            continue
        end

        local dist = physPos:Distance(bonePos)
        print(string.format("  %-30s | distance: %.2f units", boneName, dist))
    end

    print("=== End of bone distances ===")
end

function TOOL:LeftClick(tr)
    local clickPos = tr.HitPos

    -- 创建参考 Ragdoll（固定不动）
    local ORag = ents.Create("prop_ragdoll")
    ORag:SetModel("models/player/tfa_cso2/ct_choi.mdl")
    ORag:SetPos(clickPos + Vector(0, 0, 4))
    ORag:Spawn()

    for i = 0, ORag:GetPhysicsObjectCount() - 1 do
        local phyObj = ORag:GetPhysicsObjectNum(i)
        if IsValid(phyObj) then
            phyObj:EnableMotion(false)
        end
    end

    -- 创建动画 Ragdoll（将被对齐）
    local Anim_Rag = ents.Create("prop_dynamic")
    Anim_Rag:SetModel("models/brutal_deaths/model_anim_modify.mdl")
    Anim_Rag:SetBodygroup(Anim_Rag:FindBodygroupByName("barney"), 1)
    Anim_Rag:Spawn()
    Anim_Rag:SetCollisionGroup(COLLISION_GROUP_WORLD)

    -- 执行对齐（策略：双脚中点 -> 头部）
    local success = AlignRagdoll(Anim_Rag, ORag, AlignStrategy.FeetToHead)
    if success then
        print("Alignment succeeded.")
    else
        print("Alignment failed.")
    end

    -- 打印对齐后的骨骼距离（验证对齐效果）
    PrintBoneDistances(ORag, Anim_Rag)
end

function TOOL:RightClick(tr)
    -- 可添加其他测试逻辑
end
