-- 骨骼名称常量
local BONE_PELVIS   = "ValveBiped.Bip01_Pelvis"
local BONE_HEAD     = "ValveBiped.Bip01_Head1"
local BONE_L_FOOT   = "ValveBiped.Bip01_L_Foot"
local BONE_R_FOOT   = "ValveBiped.Bip01_R_Foot"

--- 对齐策略枚举（原点在低位，方向从低指向高）
--- @enum AlignStrategy
local AlignStrategy = {
    PelvisToHead = 1, -- 低位:骨盆, 高位:头部
    FeetToPelvis = 2, -- 低位:双脚中点, 高位:骨盆
    FeetToHead   = 3  -- 低位:双脚中点, 高位:头部
}

--- 获取实体在指定策略下的低位位置和高位矩阵
--- 若任何必需骨骼不存在，返回 nil
--- @param ent Entity
--- @param strategy AlignStrategy
--- @return Vector|nil lowPos
--- @return VMatrix|nil highMat
local function GetBoneData(ent, strategy)
    if strategy == AlignStrategy.PelvisToHead then
        local idxPelvis = ent:LookupBone(BONE_PELVIS)
        local idxHead   = ent:LookupBone(BONE_HEAD)
        if not idxPelvis or not idxHead then
            return nil, nil
        end
        local lowPos, _ = ent:GetBonePosition(idxPelvis)
        local highMat   = ent:GetBoneMatrix(idxHead)
        return lowPos, highMat
    elseif strategy == AlignStrategy.FeetToPelvis then
        local idxL = ent:LookupBone(BONE_L_FOOT)
        local idxR = ent:LookupBone(BONE_R_FOOT)
        local idxPelvis = ent:LookupBone(BONE_PELVIS)
        if not idxL or not idxR or not idxPelvis then
            return nil, nil
        end
        local posL, _ = ent:GetBonePosition(idxL)
        local posR, _ = ent:GetBonePosition(idxR)
        local lowPos = (posL + posR) * 0.5
        local highMat = ent:GetBoneMatrix(idxPelvis)
        return lowPos, highMat
    elseif strategy == AlignStrategy.FeetToHead then
        local idxL = ent:LookupBone(BONE_L_FOOT)
        local idxR = ent:LookupBone(BONE_R_FOOT)
        local idxHead = ent:LookupBone(BONE_HEAD)
        if not idxL or not idxR or not idxHead then
            return nil, nil
        end
        local posL, _ = ent:GetBonePosition(idxL)
        local posR, _ = ent:GetBonePosition(idxR)
        local lowPos = (posL + posR) * 0.5
        local highMat = ent:GetBoneMatrix(idxHead)
        return lowPos, highMat
    else
        return nil, nil -- 未知策略
    end
end

--- 将源 Ragdoll 对齐到目标 Ragdoll
--- @param source Entity 源实体
--- @param target Entity 目标实体
--- @param strategy? AlignStrategy 对齐策略，默认 PelvisToHead
--- @return boolean 对齐是否成功
local function AlignRagdoll(source, target, strategy)
    -- 1. 检查实体有效性
    if not IsValid(source) or not IsValid(target) then
        return false
    end

    strategy = strategy or AlignStrategy.FeetToHead

    -- 2. 获取源和目标的骨骼数据
    local lowPosSource, highMatSource = GetBoneData(source, strategy)
    local lowPosTarget, highMatTarget = GetBoneData(target, strategy)

    if not lowPosSource or not highMatSource or not lowPosTarget or not highMatTarget then
        return false -- 骨骼缺失或策略无效
    end

    -- 3. 构建正交基矩阵（原点在低位，Z轴指向高位，X轴取自高位骨骼的右向）
    local function BuildMatrix(lowPos, highMat)
        local highPos = highMat:GetTranslation()
        local vec = highPos - lowPos
        local len = vec:Length()

        -- 防止零长度向量（例如源和目标骨骼位置重合）
        if len == 0 then
            return nil
        end

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

    if not matrixSource or not matrixTarget then
        return false -- 向量长度为零
    end

    -- 4. 计算变换矩阵 T = M_target * M_source⁻¹
    local matrixSourceInv = Matrix()
    matrixSourceInv:Set(matrixSource)
    if not matrixSourceInv:Invert() then
        return false -- 矩阵不可逆（理论上不应发生，但安全处理）
    end

    local matrixTransform = Matrix()
    matrixTransform:Set(matrixTarget)
    matrixTransform:Mul(matrixSourceInv)

    -- 5. 应用变换
    local newPos = matrixTransform:GetTranslation()
    local newAng = matrixTransform:GetAngles()
    local newScaleVec = matrixTransform:GetScale()
    local scaleFactor = newScaleVec.x

    if source.SetModelScale then
        source:SetModelScale(scaleFactor, 0)
    end

    source:SetPos(newPos)
    source:SetAngles(newAng)

    if source.PhysWake then
        source:PhysWake()
    end

    return true
end

return {
    AlignRagdoll = AlignRagdoll,
    AlignStrategy = AlignStrategy
}
