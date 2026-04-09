local helpers = include("modules/helpers.lua")
local getAnimation = include("modules/getAnimation.lua")

-- 创建用于播放动画的实体（无物理），并预先对齐到目标物理布娃娃
local function createAnimRag(targetPhysRag)
    local animRag = ents.Create("prop_dynamic")
    animRag:SetModel("models/brutal_deaths/model_anim_modify.mdl")
    animRag:SetBodygroup(animRag:FindBodygroupByName("barney"), 1)
    animRag:SetCollisionGroup(COLLISION_GROUP_WORLD)
    helpers.AlignRagdoll(animRag, targetPhysRag, helpers.AlignStrategy.FeetToHead)
    animRag:Spawn()
    return animRag
end

-- 禁用物理布娃娃的运动（冻结位置）
local function disableMotion(physRag)
    if not IsValid(physRag) then return end
    for i = 0, physRag:GetPhysicsObjectCount() - 1 do
        local physObj = physRag:GetPhysicsObjectNum(i)
        if IsValid(physObj) then
            physObj:EnableMotion(false)
        end
    end
end

-- 启用物理布娃娃的运动（恢复物理模拟）
local function enableMotion(physRag)
    if not IsValid(physRag) then return end
    for i = 0, physRag:GetPhysicsObjectCount() - 1 do
        local physObj = physRag:GetPhysicsObjectNum(i)
        if IsValid(physObj) then
            physObj:EnableMotion(true)
            physObj:Wake()
        end
    end
end

-- 将动画实体的骨骼姿态应用到物理布娃娃的对应物理骨骼上
local function applyBoneTransform(animRag, physRag)
    for i = 0, physRag:GetPhysicsObjectCount() - 1 do
        local physObj = physRag:GetPhysicsObjectNum(i)
        if not IsValid(physObj) then continue end

        local boneID = physRag:TranslatePhysBoneToBone(i)
        local boneName = physRag:GetBoneName(boneID)
        local animBoneID = animRag:LookupBone(boneName)
        if not animBoneID then continue end

        local targetPos, targetAng = animRag:GetBonePosition(animBoneID)

        local controlParams = {
            secondstoarrive  = 0.015,     -- 移动到目标位置/角度的理想时间
            delta            = 0.15,      -- 时间步长（通常来自 PhysicsSimulate）
            pos              = targetPos, -- 目标世界位置
            angle            = targetAng, -- 目标世界角度
            maxangular       = 256,       -- 最大角力
            maxangulardamp   = 128,       -- 开始阻尼旋转的力/速度阈值
            maxspeed         = 256,       -- 最大线性力
            maxspeeddamp     = 128,       -- 开始阻尼线性运动的力/速度阈值
            dampfactor       = 1.0,       -- 达到最大值时的阻尼百分比（1.0 = 无额外阻尼）
            teleportdistance = 0          -- 超过此距离直接传送（0 禁用传送）
        }
        physObj:ComputeShadowControl(controlParams)
    end
end

local co = nil

hook.Add("CreateEntityRagdoll", "TestCreateEntityRagdoll", function(owner, physRag)
    co = coroutine.create(function()
        -- 1. 创建动画实体并对齐到物理布娃娃
        local animRag = createAnimRag(physRag)

        -- 2. 暂时冻结物理布娃娃，防止外力干扰对齐姿态
        disableMotion(physRag)
        coroutine.yield()

        -- 3. 恢复物理模拟，并开始播放随机死亡动画
        enableMotion(physRag)
        -- local animName = getAnimation()
        local animName = "bd_death_rightleg_single_02"

        animRag:Fire("SetAnimation", animName, 0)

        -- 4. 获取动画持续时间
        local seqID = animRag:LookupSequence(animName)
        local duration = animRag:SequenceDuration(seqID) or 3.0
        local startTime = CurTime()

        -- 5. 主循环：逐帧将动画姿态应用到物理布娃娃
        while true do
            if not IsValid(animRag) or not IsValid(physRag) then break end
            if CurTime() - startTime > duration then break end

            applyBoneTransform(animRag, physRag)

            coroutine.yield()
        end

        -- 6. 清理
        if IsValid(animRag) then animRag:Remove() end
        if IsValid(physRag) then
            enableMotion(physRag)
        end
    end)
end)

hook.Add("Tick", "MyVeryUniqueTestTickHook", function()
    if co then
        local success, err = coroutine.resume(co)
        if not success then
            print("Coroutine error: " .. tostring(err))
            co = nil
        elseif coroutine.status(co) == "dead" then
            print("co finished normally")
            co = nil
        end
    end
end)
