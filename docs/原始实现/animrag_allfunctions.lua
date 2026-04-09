--[====[ 数据配置：肢解部位映射表 ]====]
-- 用途：将骨骼名称映射到肢解分组 ID。
-- 抽象建议：可移至独立的配置模块（如 gib_config.lua）。
Animrag_Gib_Tb = {
    -- 躯干组（1）...
    -- 右腿组（2.1）...
    -- 左腿组（2.2）...
    -- 右臂组（2.3）...
    -- 左臂组（2.4）...
}

--[====[ 数据配置：有效受击骨骼表 ]====]
-- 用途：定义哪些骨骼被视为有效受击部位，防止选择头发等无关骨骼。
-- 抽象建议：可移至独立的配置模块（如 hitbox_config.lua）。
local Hitbox_Tb = {
    -- 脊椎与骨盆...
    -- 四肢近端骨骼...
    -- 四肢远端骨骼...
    -- 头部...
}

--[====[ 数据配置：物理控制参数模板 ]====]
-- 用途：为 ComputeShadowControl 提供默认的运动参数。
-- 抽象建议：可移至独立的配置模块（如 physics_config.lua）。
Animrag_CSC = {
    secondstoarrive = 0.01,
    pos = Vector(0, 0, 0),
    angle = Angle(0, 0, 0),
    maxangular = 400,
    maxangulardamp = 200,
    maxspeed = 400,
    maxspeeddamp = 300,
    teleportdistance = 0
}

--[====[ 工具函数：深拷贝表 ]====]
-- 功能说明：递归复制表，返回一个内容相同但独立的新表。
-- 抽象建议：通用工具函数，可置于工具模块（如 table_utils.lua）。
function Animrag_CopyTable(tb)
    local newTb = {}
    for k, v in pairs(tb) do
        if istable(v) then
            newTb[k] = Animrag_CopyTable(v)
        else
            newTb[k] = v
        end
    end
    return newTb
end

--[====[ 工具函数：防止连续选择相同随机结果 ]====]
-- 功能说明：在二选一的随机中，若连续两次选中同一结果，则第三次强制选另一个，避免重复。
-- 抽象建议：通用随机辅助函数，可置于工具模块（如 random_utils.lua）。
function Animrag_PreventSameChoose(lastChoose, sameChooseNum)
    local x = math.random(0, 1)

    if x == lastChoose then
        sameChooseNum = sameChooseNum + 1
    end

    if sameChooseNum >= 2 then
        x = 1 - x
        sameChooseNum = 0
    end

    return x, sameChooseNum
end

--[====[ 动画结束处理函数 ]====]
-- 功能说明：结束当前动画状态，清理相关实体引用，并根据传入类型设置后续状态（死亡转爬行、彻底死亡标记等）。
-- 抽象建议：该函数混合了状态转移和资源清理，未来可将状态转移逻辑提取为状态机模块（如 AnimationStateMachine）。
function Animrag_EndAnimation(ORag, Orgn_Rag_Tb, Anim_Rag_Tb, Type)
    --[====[ 第1步：根据动画类型设置后续状态 ]====]
    -- 功能说明：根据传入的 Type 参数（Death/Crawl/Writhe）设置 ORag 上的相应标记，决定是否进入爬行动画或标记彻底死亡。
    -- 抽象建议：属于动画状态机中的状态迁移逻辑，可抽离为独立的状态转换处理方法。
    if Type == "Death" then
        ORag.Isdead_d = true
        AnimRag_Death_T_Crawl(ORag, false)
        Animrag_Debug(10, true, { ORag })
    elseif Type == "Crawl" then
        ORag.Isdead_c = true
        ORag:SetNW2Int("Animation_State", 0)
    elseif Type == "Writhe" then
        ORag.Isdead_c = true
        ORag:SetNW2Int("Animation_State", 0)
        ORag.IsWrithing = false
        ORag.IsTwitching = false
    end

    --[====[ 第2步：从管理表中移除实体引用 ]====]
    -- 功能说明：从原始 Ragdoll 表和动画 Ragdoll 表中移除对当前实体的引用，并销毁动画实体。
    -- 抽象建议：属于实体生命周期管理，可封装为专门的清理函数或集成到实体管理器中。
    if Orgn_Rag_Tb then
        for k, v in pairs(Orgn_Rag_Tb) do
            if v == ORag then
                table.remove(Orgn_Rag_Tb, k)
            end
        end
    end

    if Anim_Rag_Tb then
        for k, v in pairs(Anim_Rag_Tb) do
            if v == ORag.ARag then
                table.remove(Anim_Rag_Tb, k)
                v:Remove()
            end
        end
    end

    --[====[ 第3步：处理肢解骨骼的碰撞以避免鬼畜 ]====]
    -- 功能说明：遍历所有被缩放到零的骨骼（即肢解骨骼），禁用其物理对象的碰撞。
    -- 抽象建议：属于肢解后物理状态修正，可归入肢解系统模块（如 GibSystem）。
    for i = 0, ORag:GetPhysicsObjectCount() - 1 do
        if ORag:GetManipulateBoneScale(ORag:TranslatePhysBoneToBone(i)) == Vector(0, 0, 0) then
            local phyObj = ORag:GetPhysicsObjectNum(i)
            phyObj:EnableCollisions(false)
        end
    end
end

--[====[ 核心动画函数：将 Ragdoll 的物理骨骼驱动至动画目标位置 ]====]
-- 功能说明：通过 ComputeShadowControl 使 ORag 的各物理骨骼跟随 ARag（动画用实体）的骨骼位置，同时处理地形适应、肢解、碰撞检测等。
-- 抽象建议：该函数是动画系统的核心驱动逻辑，可考虑将地形适应、障碍检测、肢解处理分别提取为独立策略模块（如 TerrainAdapter、ObstacleHandler、GibHandler）。
function Animrag_ComputeShadowControl(ORag)
    for i = 0, ORag:GetPhysicsObjectCount() - 1 do
        local boneName = ORag:GetBoneName(ORag:TranslatePhysBoneToBone(i))

        --[====[ 第1步：过滤需要驱动的骨骼 ]====]
        -- 功能说明：仅处理在 arMoveTb 中标记且未被手部抓取逻辑覆盖的骨骼。
        -- 抽象建议：骨骼驱动过滤条件可配置化，形成驱动策略表。
        if ORag.arMoveTb[boneName] and not (ORag.GrabHandTb and ORag.GrabHandTb[boneName]) then
            local phyObj = ORag:GetPhysicsObjectNum(i)

            --[====[ 第2步：肢解状态检查与传播 ]====]
            -- 功能说明：若骨骼被肢解（缩放为0），根据映射表将该肢体整组标记为已肢解，并禁用对应物理碰撞。
            -- 抽象建议：肢解组管理可封装为 GibGroupManager，负责状态传播与物理禁用。
            if ORag:GetManipulateBoneScale(ORag:TranslatePhysBoneToBone(i)) == Vector(0, 0, 0) and Animrag_Gib_Tb[boneName] and not ORag.arMoveBone[boneName]["Gibbed"] then
                if Animrag_Gib_Tb[boneName] == 2.1 then
                    for k, v in pairs(Animrag_Gib_Tb) do
                        if v == 2.1 and ORag.arMoveBone[k] then
                            ORag.arMoveBone[k]["Gibbed"] = true
                        end
                    end
                elseif Animrag_Gib_Tb[boneName] == 2.2 then
                    for k, v in pairs(Animrag_Gib_Tb) do
                        if v == 2.2 and ORag.arMoveBone[k] then
                            ORag.arMoveBone[k]["Gibbed"] = true
                        end
                    end
                elseif Animrag_Gib_Tb[boneName] == 2.3 then
                    for k, v in pairs(Animrag_Gib_Tb) do
                        if v == 2.3 and ORag.arMoveBone[k] then
                            ORag.arMoveBone[k]["Gibbed"] = true
                        end
                    end
                elseif Animrag_Gib_Tb[boneName] == 2.4 then
                    for k, v in pairs(Animrag_Gib_Tb) do
                        if v == 2.4 and ORag.arMoveBone[k] then
                            ORag.arMoveBone[k]["Gibbed"] = true
                        end
                    end
                end
                phyObj:EnableCollisions(false)
            end

            --[====[ 第3步：骨骼驱动条件判断 ]====]
            -- 功能说明：仅当骨骼未被肢解且未处于坠落状态时，才进行驱动计算。
            -- 抽象建议：驱动条件可归入骨骼状态检查器。
            if not ORag.arMoveBone[boneName]["Gibbed"] and not ORag.arMoveBone[boneName]["Fall"] then
                local pos0, bone_ang = ORag.ARag:GetBonePosition(ORag.ARag:LookupBone(boneName))
                bone_ang = bone_ang + ORag.arMoveBone[boneName]["random"]

                local refer = Vector(pos0.x, pos0.y, ORag.ARag:GetPos().z)

                --[====[ 第4步：地形适应 - 计算目标位置修正量 ]====]
                -- 功能说明：通过射线检测获取目标位置到地面的距离，计算高度差以修正目标位置，防止骨骼浮空或穿地。
                -- 抽象建议：地形适应逻辑可提取为 TerrainAdapter 模块，负责每帧计算高度修正。
                local tr1 = util.TraceLine({
                    start = refer + Vector(0, 0, 10),
                    endpos = refer - Vector(0, 0, 100),
                    mask = MASK_SOLID,
                    filter = { ORag, ORag.ARag }
                })

                local Diff = (refer.z - tr1.HitPos.z) - ORag.arMoveBone[boneName]["lastHit"].z

                if Diff < 20 then
                    ORag.arMoveBone[boneName]["addpos"] = Vector(0, 0, Diff + ORag.arMoveBone[boneName]["lastAdd"].z)
                else
                    ORag.arMoveBone[boneName]["addpos"] = Vector(0, 0, Diff + ORag.arMoveBone[boneName]["lastAdd"].z)
                    ORag.arMoveBone[boneName]["Fall"] = true
                    ORag.arFall = ORag.arFall + 1
                end

                ORag.arMoveBone[boneName]["lastAdd"] = ORag.arMoveBone[boneName]["addpos"]
                ORag.arMoveBone[boneName]["lastHit"] = refer - tr1.HitPos

                local bone_pos = pos0 - ORag.arMoveBone[boneName]["addpos"]

                --[====[ 第5步：障碍物检测 ]====]
                -- 功能说明：检测当前物理位置到目标位置之间是否存在障碍物，若存在则标记撞墙。
                -- 抽象建议：障碍物检测可提取为 ObstacleHandler 模块，负责碰撞检测与撞墙计数。
                local tr2 = util.TraceLine({
                    start = phyObj:GetPos(),
                    endpos = bone_pos,
                    mask = MASK_ALL,
                    filter = { ORag, ORag.ARag }
                })

                if tr2.Hit then
                    if not ORag.arMoveBone[boneName]["HitWall"] then
                        ORag.arHitWall = ORag.arHitWall + 1
                        ORag.arMoveBone[boneName]["HitWall"] = true
                    end
                end

                --[====[ 第6步：执行物理驱动 ]====]
                -- 功能说明：当无碰撞且未坠落时，调用 ComputeShadowControl 将物理骨骼移动到计算好的目标位置和角度。
                -- 抽象建议：物理驱动调用可封装为 PhysicsDriver，集中管理 CSC 参数设置。
                if ! tr2.Hit and not ORag.arMoveBone[boneName]["Fall"] then
                    Animrag_CSC.pos = bone_pos
                    Animrag_CSC.angle = bone_ang

                    phyObj:Wake()
                    phyObj:ComputeShadowControl(Animrag_CSC)
                end
            end
        end
    end

    --[====[ 第7步：手指骨骼同步（客户端） ]====]
    -- 功能说明：若启用手指动画，则通过网络消息通知客户端同步手指骨骼姿势。
    -- 抽象建议：网络同步部分可封装为 NetworkSync 模块。
    if CVAR_ARag_finger:GetBool() then
        net.Start("AnimRag_PoseFingerBone_sTc")
        net.WriteInt(ORag:EntIndex(), 32)
        net.WriteInt(ORag.ARag:EntIndex(), 32)
        net.Broadcast()
    end
end

--[====[ 受击骨骼检测函数 ]====]
-- 功能说明：根据击中位置找到距离最近的有效骨骼，并存储相关信息供后续伤害处理使用。
-- 抽象建议：该函数属于伤害判定系统的前置步骤，可置于 DamageResolver 模块中。
function Animrag_GetDamagedBone(ent, HitPos)
    local closestBoneName
    local closestPhyObj
    local closestPhyID
    local minDist

    --[====[ 第1步：遍历所有物理骨骼寻找最近者 ]====]
    -- 功能说明：计算每个物理骨骼到击中点的距离，选择距离最小且未被肢解、在有效骨骼表中的骨骼。
    -- 抽象建议：搜索逻辑可优化为空间分区查询，但当前属于功能教学范畴。
    for i = 0, ent:GetPhysicsObjectCount() - 1 do
        if ent.ZippyGoreMod3_PhysBoneHPs and ent.ZippyGoreMod3_PhysBoneHPs[i] == -1 then
            -- 兼容 ZippyGoreMod 肢解标记，跳过已肢解骨骼
            goto continue
        end

        local phyObj = ent:GetPhysicsObjectNum(i)
        local boneName = ent:GetBoneName(ent:TranslatePhysBoneToBone(i))
        local dist = phyObj:GetPos():DistToSqr(HitPos)

        if (not minDist or dist < minDist) and Hitbox_Tb[boneName] and ent:GetManipulateBoneScale(ent:TranslatePhysBoneToBone(i)) ~= Vector(0, 0, 0) then
            minDist = dist
            closestBoneName = boneName
            closestPhyObj = phyObj
            closestPhyID = i
        end

        ::continue::
    end

    --[====[ 第2步：存储检测结果 ]====]
    -- 功能说明：将找到的最近骨骼信息存入实体字段，供后续逻辑使用。
    -- 抽象建议：结果存储属于临时状态，可考虑封装为 DamageContext 对象。
    ent.ClosestHitPos = HitPos
    ent.ClosestBoneName = closestBoneName
    ent.ClosestPhyObj = closestPhyObj
    ent.ClosestPhyID = closestPhyID
end

--[====[ 动画实体缩放函数 ]====]
-- 功能说明：根据原始 Ragdoll 的身体高度调整动画用实体的模型比例，使动画贴合。
-- 抽象建议：属于动画适配预处理，可归入 AnimationAdapter 模块。
function Animrag_ScaleAnimRag(ORag, ARag)
    if not CVAR_ARag_scalerag:GetBool() or not ORag.BodyHeight then
        return
    end

    local scale = ORag.BodyHeight / 67.01953125
    ARag:SetModelScale(scale, 0)
end
