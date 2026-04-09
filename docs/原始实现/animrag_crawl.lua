include("autorun/server/animrag_allconvar.lua")
include("autorun/server/animrag_allfunctions.lua")

--[====[ 全局状态表：挣扎/爬行/复活动画中的布娃娃 ]====]
-- 用途：存储所有正在播放挣扎、爬行或复活动画的 Ragdoll 实体。
-- 抽象建议：可抽象为动画状态管理器。
Orgn_Rag_Tb_Crawl = {}

--[====[ 全局状态表：挣扎/爬行/复活动画中的动画代理 ]====]
-- 用途：存储与挣扎/爬行/复活动画对应的 Anim_Rag 实体。
Anim_Rag_Tb_Crawl = {}

--[====[ 数据配置：爬行运动骨骼表（动态）]====]
-- 用途：决定爬行时哪些骨骼跟随动画运动。
-- 抽象建议：可设计为策略模式，不同预设对应不同肢体瘫痪程度。
local MoveTb_C = {}

--[====[ 数据配置：正常骨骼名称列表 ]====]
-- 用途：存储标准人形骨骼名称。
-- 抽象建议：可定义为常量模块。
local NrmTb = {
    -- 包含骨盆、脊椎、四肢、头部等骨骼...
}

--[====[ 数据配置：爬行运动骨骼表预设1（面朝上）]====]
local MoveTb_1 = {
    -- 部分骨骼被注释（不跟随运动）...
}

--[====[ 数据配置：爬行运动骨骼表预设2（面朝下，不瘫）]====]
local MoveTb_2_1 = {
    -- 不瘫配置...
}

-- 其他类似 MoveTb_2_2 ~ MoveTb_2_6 结构相同，仅骨骼集合不同，略。

local MoveTb_2 = {
    MoveTb_2_1,
    -- MoveTb_2_2, MoveTb_2_3, MoveTb_2_4, MoveTb_2_5, MoveTb_2_6 ...
}

--[====[ 数据配置：爬行运动骨骼表预设3（面朝下，简化）]====]
local MoveTb_3_1 = {
    -- 不瘫配置...
}

-- 其他类似 MoveTb_3_2 ~ MoveTb_3_3 结构相同，仅骨骼集合不同，略。

local MoveTb_3 = {
    MoveTb_3_1,
    -- MoveTb_3_2, MoveTb_3_3 ...
}

--[====[ 辅助函数：决定播放挣扎还是爬行动画 ]====]
-- 功能说明：基于预设概率选择动画类型（已简化，直接返回爬行）。
-- 抽象建议：属于“动画选择策略”，可提取为独立的决策器模块。
function Animrag_CaculateAnimationChance()
    return "Crawl"
end

--[====[ 核心函数：从死亡动画过渡到爬行/挣扎 ]====]
-- 功能说明：当死亡动画结束后，根据条件决定是否启动爬行或挣扎。
-- 抽象建议：属于“动画生命周期管理”中的“状态转移”环节。
function AnimRag_Death_T_Crawl(Orgn_Rag, OverRideTime)
    --[====[ 第1步：玩家特殊处理（绕过挣扎，直接爬行）]====]
    if Orgn_Rag:GetNW2Bool("isPlayer") then
        Animrag_Crawl_StartCrawlAnimation(Orgn_Rag, OverRideTime)
        return
    end

    --[====[ 第2步：直接开始爬行（简化概率逻辑）]====]
    Animrag_Crawl_StartCrawlAnimation(Orgn_Rag, OverRideTime)
end

--[====[ 辅助函数：循环播放爬行动画 ]====]
-- 功能说明：当爬行动画结束时，重新定位Anim_Rag并重新播放。
-- 抽象建议：属于“动画循环”逻辑，可提取为AnimationLooper。
function Animrag_Crawl_RepeatCrawlAnimation(ORag, ARag)
    local tr_pos = util.TraceLine({
        start = ORag:GetPos(),
        endpos = ORag:GetPos() - Vector(0, 0, 100),
        mask = MASK_SOLID,
        filter = { ORag, ARag }
    })

    ARag:Fire("SetAnimation", ORag.Anim_Nm, 0)
    ARag:SetPos(tr_pos.HitPos)
    ORag.Anim_St = CurTime() + ORag.Anim_Tm
    ORag.StartCrawlAway = CurTime() + 1
end

--[====[ 核心函数：启动爬行动画 ]====]
-- 功能说明：创建Anim_Rag，播放爬行动画，并初始化所有运动参数。
-- 抽象建议：属于“动画映射引擎”的核心启动流程。
function Animrag_Crawl_StartCrawlAnimation(Orgn_Rag, OverRideTime)
    --[====[ 第1步：计算爬行生命值（简化：禁用超杀）]====]
    Orgn_Rag.Hp_c = 9999
    Orgn_Rag.PreStop = false

    --[====[ 第2步：等待延迟后开始（简化延迟）]====]
    local WaitTime = 2
    if OverRideTime then WaitTime = 1.25 end

    timer.Simple(WaitTime, function()
        --[====[ 第3步：获取胸部朝向，决定动画类型和运动骨骼表 ]====]
        local body_index = Orgn_Rag:LookupBone("ValveBiped.Bip01_Spine4") or
            Orgn_Rag:LookupBone("ValveBiped.Bip01_Spine2") or
            Orgn_Rag:LookupBone("ValveBiped.Bip01_Spine1") or
            Orgn_Rag:LookupBone("ValveBiped.Bip01_Spine")
        local body_ang = Angle(0, 0, 0)
        local Animation_startAng = Angle(0, 0, 0)

        if body_index then
            body_ang = Orgn_Rag:GetBoneMatrix(body_index):GetAngles():Forward():Angle()
            Animation_startAng = Angle(0, body_ang.y, 0)
        else
            Animation_startAng = Angle(0, math.Rand(0, 360), 0)
        end

        -- 判断胸部朝向（正面朝上还是朝下）
        local Atta_chest = Orgn_Rag:LookupAttachment("chest")
        local Atta_eyes  = Orgn_Rag:LookupAttachment("eyes")
        local Facing
        if Atta_chest > 0 then
            Facing = Orgn_Rag:GetAttachment(Atta_chest).Ang:Forward().z
        elseif Atta_eyes > 0 then
            Facing = Orgn_Rag:GetAttachment(Atta_eyes).Ang:Forward().z
        else
            Facing = -1
        end

        local Animation
        if Facing >= 0 then
            Animation = "crawling1"
            MoveTb_C = MoveTb_1
        else
            local rand = math.random(5, 6)
            Animation = "crawling" .. rand
            if rand == 5 then
                MoveTb_C = MoveTb_2[math.random(1, 6)]
            else
                MoveTb_C = MoveTb_3[math.random(1, 3)]
            end
        end

        --[====[ 第4步：玩家死亡时的第一人称摄像头兼容（简化）]====]
        if Orgn_Rag:GetNW2Bool("isPlayer") then
            MoveTb_C = NrmTb
            -- 移除头部和脊椎骨骼，以便玩家控制视角
            MoveTb_C["ValveBiped.Bip01_Head1"] = nil
            MoveTb_C["ValveBiped.Bip01_Spine4"] = nil
        end

        --[====[ 第5步：获取动画播放的地面位置 ]====]
        local Apos = util.TraceLine({
            start = Orgn_Rag:GetPos(),
            endpos = Orgn_Rag:GetPos() - Vector(0, 0, 100),
            mask = MASK_SOLID,
            filter = Orgn_Rag
        })

        --[====[ 第6步：创建Anim_Rag并播放动画 ]====]
        local Anim_Rag = ents.Create("prop_dynamic")
        Anim_Rag:SetModel("models/brutal_deaths/model_anim_modify.mdl")
        Anim_Rag:SetPos(Apos.HitPos)
        Anim_Rag:SetAngles(Animation_startAng)
        Anim_Rag:Spawn()
        Anim_Rag:SetCollisionGroup(COLLISION_GROUP_WORLD)

        Animrag_ScaleAnimRag(Orgn_Rag, Anim_Rag)

        local _, Animation_Tm = Anim_Rag:LookupSequence(Animation)
        Anim_Rag:Fire("SetAnimation", Animation)

        --[====[ 第7步：初始化Ragdoll运动参数 ]====]
        Anim_Rag.ORag = Orgn_Rag
        Orgn_Rag.ARag = Anim_Rag
        Orgn_Rag:SetNW2Int("Animation_State", 3)
        Orgn_Rag.arMoveTb = MoveTb_C
        Orgn_Rag.arMoveBone = {}
        for boneName, _ in pairs(Orgn_Rag.arMoveTb) do
            Orgn_Rag.arMoveBone[boneName] = {}
            Orgn_Rag.arMoveBone[boneName]["random"] = Angle(math.Rand(-15, 15), math.Rand(-15, 15), 0)
            Orgn_Rag.arMoveBone[boneName]["addpos"] = Vector(0, 0, 0)
            Orgn_Rag.arMoveBone[boneName]["lastAdd"] = Vector(0, 0, 0)
            Orgn_Rag.arMoveBone[boneName]["lastHit"] = Vector(0, 0, 0)
            Orgn_Rag.arMoveBone[boneName]["Fall"] = false
            Orgn_Rag.arMoveBone[boneName]["HitWall"] = false
            Orgn_Rag.arMoveBone[boneName]["Gibbed"] = false
        end
        Orgn_Rag.FacingUp = Facing >= 0
        Orgn_Rag.arRepeat = true
        Orgn_Rag.Anim_Nm = Animation
        Orgn_Rag.Anim_Tm = Animation_Tm
        Orgn_Rag.Anim_St = Animation_Tm + CurTime()
        Orgn_Rag.arHeadID = Orgn_Rag:LookupBone("ValveBiped.Bip01_Head1")
        Orgn_Rag.Isdead_c = false
        Orgn_Rag.arFall = 0
        Orgn_Rag.arHitWall = 0
        Orgn_Rag.arDelay = 0
        Orgn_Rag.arDelay2 = false
        Orgn_Rag.Blood_Enable = true
        Orgn_Rag.Blood_UseTime = false -- 简化为按距离留血迹
        Orgn_Rag.Blood_Time = 0
        Orgn_Rag.Blood_Dist = 50
        Orgn_Rag.Blood_LastPos = Orgn_Rag:GetBonePosition(0)
        Orgn_Rag.AllowSelfRevive = true
        Orgn_Rag.StartCrawlAway = CurTime() + 1

        --[====[ 第8步：延迟后加入动画队列 ]====]
        timer.Simple(0.1, function()
            table.insert(Orgn_Rag_Tb_Crawl, Orgn_Rag)
            table.insert(Anim_Rag_Tb_Crawl, Anim_Rag)
        end)
    end)
end

--[====[ 主Tick：爬行/挣扎/复活动画的骨骼映射与行为逻辑 ]====]
-- 功能说明：每帧计算Anim_Rag的骨骼位置/角度，应用到Ragdoll；同时处理血迹、动画循环、爬离敌人等行为。
-- 抽象建议：属于“动画映射引擎”的核心循环，可拆分为骨骼求解、行为决策、特效管理三个子模块。
hook.Add("Tick", "Animrag_MainTick_C", function()
    for k, ORag in pairs(Orgn_Rag_Tb_Crawl) do
        local ARag = ORag.ARag

        --[====[ 终止条件：坠落或撞墙过多 ]====]
        if ORag.arFall >= 5 or ORag.arHitWall >= table.Count(ORag.arMoveTb) then
            if not ORag.arDelay2 then
                ORag.arDelay = CurTime() + math.random(6, 8)
                ORag.arDelay2 = true
                ORag.arRepeat = false
            end
            if CurTime() >= ORag.arDelay then
                Animrag_EndAnimation(ORag, Orgn_Rag_Tb_Crawl, Anim_Rag_Tb_Crawl, "Crawl")
            end
        end

        --[====[ 终止条件：头部被肢解 ]====]
        if ORag.arHeadID then
            if ORag:GetManipulateBoneScale(ORag.arHeadID) == Vector(0, 0, 0) then
                Animrag_EndAnimation(ORag, Orgn_Rag_Tb_Crawl, Anim_Rag_Tb_Crawl, "Crawl")
            end
        end

        --[====[ 核心骨骼映射 ]====]
        Animrag_ComputeShadowControl(ORag)

        --[====[ 血迹效果（按距离）]====]
        if ORag.Blood_Enable then
            local CurPos = ORag:GetBonePosition(0)
            if CurPos then
                local MoveDist = CurPos:DistToSqr(ORag.Blood_LastPos)
                if MoveDist >= math.pow(ORag.Blood_Dist, 2) then
                    ORag.Blood_LastPos = CurPos
                    util.Decal("Blood", ORag:GetBonePosition(0), ORag:GetBonePosition(0) - Vector(0, 0, 32),
                        { ORag, ARag })
                end
            end
        end

        --[====[ 动画循环逻辑 ]====]
        if ORag.Anim_St and CurTime() >= ORag.Anim_St and ORag.arRepeat then
            if ORag:GetNW2Bool("isPlayer") and ORag.OwnerPLY and not ORag.OwnerPLY:Alive() then
                Animrag_Crawl_RepeatCrawlAnimation(ORag, ARag)
                if ORag.OwnerPLY:Alive() then
                    Animrag_EndAnimation(ORag, Orgn_Rag_Tb_Crawl, Anim_Rag_Tb_Crawl, "Crawl")
                end
            else
                Animrag_Crawl_RepeatCrawlAnimation(ORag, ARag)
            end
        end

        --[====[ 爬离敌人（NPC）或玩家控制（Player）]====]
        if ORag.StartCrawlAway and CurTime() > ORag.StartCrawlAway and ARag:GetBonePosition(0) then
            if not ORag:GetNW2Bool("isPlayer") then
                -- NPC：爬离所有敌对单位
                local MixPos = Vector(0, 0, 0)
                local ARagPos = ARag:GetPos()
                local ORagPos = ARag:GetBonePosition(0)
                ORagPos.z = ARagPos.z

                if ORag.arHostile then
                    for _, enemy in pairs(ORag.arHostile) do
                        local EnemPos = enemy:GetPos()
                        local E_O_Pos = EnemPos - ORagPos
                        local E_O_Dist = E_O_Pos:LengthSqr()
                        if E_O_Dist < 10000 then
                            MixPos = MixPos + E_O_Pos
                        end
                    end
                end

                MixPos = MixPos + ORagPos
                local N_O_Pos = MixPos - ORagPos
                local N_O_Ang = N_O_Pos:Angle()
                local A_O_Pos = ARagPos - ORagPos
                local A_O_Ang = A_O_Pos:Angle()
                local NewPos = ORagPos + N_O_Ang:Forward() * A_O_Pos:Length()
                local NewAng = Angle(0, (ORagPos - MixPos):Angle().yaw, 0)

                if N_O_Pos:LengthSqr() < math.pow(300, 2) and N_O_Pos:LengthSqr() > 0 then
                    ARag:SetPos(NewPos)
                    ARag:SetAngles(NewAng)
                end
            else
                -- 玩家：使用左右键控制爬行方向
                local ply = ORag.OwnerPLY
                local rotateSpeed = nil
                if ply:KeyDown(IN_MOVELEFT) then
                    rotateSpeed = 30
                elseif ply:KeyDown(IN_MOVERIGHT) then
                    rotateSpeed = -30
                end

                if rotateSpeed then
                    local dt = FrameTime()
                    local angleStep = math.rad(rotateSpeed * dt)
                    local vecOffset = ARag:GetPos() - ORag:GetPos()
                    local x = vecOffset.x * math.cos(angleStep) - vecOffset.y * math.sin(angleStep)
                    local y = vecOffset.x * math.sin(angleStep) + vecOffset.y * math.cos(angleStep)
                    local rotatedOffset = Vector(x, y, 0)
                    local newPos = ORag:GetPos() + rotatedOffset
                    ARag:SetPos(newPos)
                    local lookDir = (ORag:GetPos() - newPos):Angle()
                    lookDir.r = 0
                    ARag:SetAngles(lookDir)
                end
            end
        end
    end
end)

--[====[ 网络接收：玩家第一人称死亡镜头下的头部旋转 ]====]
-- 功能说明：根据玩家视角方向，实时旋转Ragdoll的头部骨骼，增强沉浸感。
-- 抽象建议：属于“玩家控制反馈”模块，可提取为FirstPersonDeathCamHandler。
net.Receive("PlayerRag_RotateHead", function()
    local eye_ang = net.ReadAngle()
    local PRag = Entity(net.ReadInt(32))

    local canRotateHead = (PRag:GetNW2Int("Animation_State") == 2 or PRag:GetNW2Int("Animation_State") == 3)

    if canRotateHead then
        -- 转换坐标系
        eye_ang:RotateAroundAxis(eye_ang:Right(), 90)
        eye_ang:RotateAroundAxis(eye_ang:Forward(), 90)

        local head_phyobj = PRag:GetPhysicsObjectNum(PRag:TranslateBoneToPhysBone(PRag:LookupBone(
            "ValveBiped.Bip01_Head1")))
        local body_phyobj = PRag:GetPhysicsObjectNum(PRag:TranslateBoneToPhysBone(PRag:LookupBone(
            "ValveBiped.Bip01_Spine4")))

        local p_head = {}
        p_head.secondstoarrive = 0.01
        p_head.pos = head_phyobj:GetPos()
        p_head.angle = eye_ang
        p_head.maxangular = 400
        p_head.maxangulardamp = 200
        p_head.maxspeed = 400
        p_head.maxspeeddamp = 300
        p_head.teleportdistance = 0

        head_phyobj:Wake()
        head_phyobj:ComputeShadowControl(p_head)

        local p_body = {}
        p_body.secondstoarrive = 0.01
        p_body.pos = head_phyobj:GetPos()
        p_body.angle = eye_ang
        p_body.maxangular = 20
        p_body.maxangulardamp = 10
        p_body.maxspeed = 0
        p_body.maxspeeddamp = 0
        p_body.teleportdistance = 0

        body_phyobj:Wake()
        body_phyobj:ComputeShadowControl(p_body)
    end
end)
