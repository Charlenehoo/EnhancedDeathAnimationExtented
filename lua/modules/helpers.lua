-- 骨骼名称常量
local BONE_PELVIS   = "ValveBiped.Bip01_Pelvis"
local BONE_HEAD     = "ValveBiped.Bip01_Head1"
local BONE_L_FOOT   = "ValveBiped.Bip01_L_Foot"
local BONE_R_FOOT   = "ValveBiped.Bip01_R_Foot"

--- 对齐策略枚举
--- @enum AlignStrategy
local AlignStrategy = {
    PelvisToHead = 1, -- 低位:骨盆, 高位:头部
    PelvisToFeet = 2, -- 低位:双脚中点, 高位:骨盆
    HeadToFeet   = 3  -- 低位:双脚中点, 高位:头部
}

--- 获取实体在指定策略下的低位位置和高位矩阵
--- @param ent Entity
--- @param strategy AlignStrategy
--- @return Vector lowPos
--- @return VMatrix highMat
local function GetBoneData(ent, strategy)
    if strategy == AlignStrategy.PelvisToHead then
        local idxPelvis = ent:LookupBone(BONE_PELVIS)
        local idxHead   = ent:LookupBone(BONE_HEAD)
        local lowPos, _ = ent:GetBonePosition(idxPelvis)
        local highMat   = ent:GetBoneMatrix(idxHead)
        return lowPos, highMat
    elseif strategy == AlignStrategy.PelvisToFeet then
        local idxL = ent:LookupBone(BONE_L_FOOT)
        local idxR = ent:LookupBone(BONE_R_FOOT)
        local posL, _ = ent:GetBonePosition(idxL)
        local posR, _ = ent:GetBonePosition(idxR)
        local lowPos = (posL + posR) * 0.5
        local idxPelvis = ent:LookupBone(BONE_PELVIS)
        local highMat = ent:GetBoneMatrix(idxPelvis)
        return lowPos, highMat
    elseif strategy == AlignStrategy.HeadToFeet then
        local idxL = ent:LookupBone(BONE_L_FOOT)
        local idxR = ent:LookupBone(BONE_R_FOOT)
        local posL, _ = ent:GetBonePosition(idxL)
        local posR, _ = ent:GetBonePosition(idxR)
        local lowPos = (posL + posR) * 0.5
        local idxHead = ent:LookupBone(BONE_HEAD)
        local highMat = ent:GetBoneMatrix(idxHead)
        return lowPos, highMat
    end
end

--- 将源 Ragdoll 对齐到目标 Ragdoll（教学版本，无防御检查）
--- @param source Entity 源实体
--- @param target Entity 目标实体
--- @param strategy? AlignStrategy 对齐策略，默认 PelvisToHead
--- @return boolean true
local function AlignRagdoll(source, target, strategy)
    strategy = strategy or AlignStrategy.PelvisToHead

    local lowPosSource, highMatSource = GetBoneData(source, strategy)
    local lowPosTarget, highMatTarget = GetBoneData(target, strategy)

    -- 构建正交基矩阵（内部计算向量和长度）
    local function BuildMatrix(lowPos, highMat)
        local highPos = highMat:GetTranslation()
        local vec = highPos - lowPos
        local len = vec:Length()

        local zAxis = vec:GetNormalized()
        local xAxis = highMat:GetRight():GetNormalized()
        xAxis = (xAxis - zAxis * xAxis:Dot(zAxis)):GetNormalized()
        local yAxis = zAxis:Cross(xAxis):GetNormalized()

        local M = Matrix()
        M:SetTranslation(lowPos)
        M:SetForward(zAxis)
        M:SetRight(xAxis)
        M:SetUp(yAxis)
        M:SetScale(Vector(len, len, len))
        return M
    end

    local matrixSource = BuildMatrix(lowPosSource, highMatSource)
    local matrixTarget = BuildMatrix(lowPosTarget, highMatTarget)

    -- 变换矩阵 T = M_target * M_source⁻¹
    local matrixSourceInv = Matrix()
    matrixSourceInv:Set(matrixSource)
    matrixSourceInv:Invert()

    local matrixTransform = Matrix()
    matrixTransform:Set(matrixTarget)
    matrixTransform:Mul(matrixSourceInv)

    -- 应用变换
    local newPos = matrixTransform:GetTranslation()
    local newAng = matrixTransform:GetAngles()
    local scaleFactor = matrixTransform:GetScale().x

    source:SetModelScale(scaleFactor, 0)
    source:SetPos(newPos)
    source:SetAngles(newAng)
    source:PhysWake()

    return true
end

return AlignRagdoll, AlignStrategy
