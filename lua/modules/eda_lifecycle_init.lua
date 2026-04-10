-- lua/autorun/server/eda_lifecycle_init.lua

-- 引入生命周期模块
local Lifecycle = include("modules/eda_lifecycle.lua")

-- 引入动画选择器（需要你自己实现或从原模块提取）
local GetAnimation = include("modules/getAnimation.lua") -- 假设存在

--[[
    为生成的布娃娃创建上下文并启动生命周期协程
    @param owner 死亡前的实体（NPC或玩家）
    @param physRag 生成的布娃娃实体
--]]
local function StartRagdollLifecycle(owner, physRag)
    -- 从 owner 提取必要信息
    local damageType = owner.arDmg or "Bullet"   -- 伤害类型
    local hitGroup = owner.arHit or 0            -- 击中部位
    local isHeadshot = owner.arHeadshot or false -- 是否爆头

    -- 选择死亡动画
    local animName = GetAnimation(damageType, hitGroup, isHeadshot)
    if not animName then
        animName = "dying_default" -- 保底动画
    end

    -- 判断是否可以进入挣扎阶段
    local canStruggle = true
    if isHeadshot and GetConVar("eda_no_crawl_after_headshot"):GetBool() then
        canStruggle = false
    end
    if damageType == "Fire" then
        canStruggle = false -- 被烧死不再挣扎
    end

    -- 创建上下文表
    local ctx = {
        -- 实体引用
        owner              = owner,
        physRag            = physRag,
        animRag            = nil,

        -- 动画配置
        animName           = animName,
        dyingDuration      = 3.0, -- 可从动画配置获取，这里简化为固定值

        -- 血量（从原模块获取或设默认值）
        health_d           = 100,
        health_c           = 100,

        -- 状态标志
        overkill           = false,
        canStruggle        = canStruggle,
        shouldRevive       = false,
        reviver            = nil,
        reviveRequested    = false,
        reviveConditionMet = false,

        -- 子状态控制
        desiredSubState    = nil,
        currentSubState    = nil,
        pendingSubState    = nil,

        -- 其他原始数据（用于后续的敌友关系等）
        hostiles           = owner.arHostiles or {},
        friends            = owner.arFriends or {},
    }

    -- 启动生命周期协程
    local co = coroutine.create(function()
        Lifecycle.LifecycleCoroutine(ctx)
    end)

    -- 将上下文和协程挂载到布娃娃实体上，便于外部访问
    physRag.EDA_Context = ctx
    physRag.EDA_Co = co

    -- 注册到调度器（假设调度器提供 Add 方法）
    -- 实际调度器可能通过标签管理，这里简化演示
    if EDA_Scheduler then
        EDA_Scheduler.Add(co, physRag)
    end

    -- 可选：记录调试信息
    print(string.format("[EDA] Started lifecycle for ragdoll %d, anim: %s", physRag:EntIndex(), animName))
end

--[[
    钩子：当实体死亡并生成布娃娃时触发
--]]
hook.Add("CreateEntityRagdoll", "EDA_Lifecycle_OnRagdoll", function(owner, physRag)
    -- 有效性检查
    if not IsValid(owner) or not IsValid(physRag) then return end

    -- 只处理玩家和NPC（排除其他可能生成布娃娃的实体）
    if not owner:IsPlayer() and not owner:IsNPC() then return end

    -- 检查是否应该启用本系统（可通过 ConVar 控制）
    if GetConVar("eda_enable"):GetBool() == false then return end

    -- 启动生命周期
    StartRagdollLifecycle(owner, physRag)
end)

--[[
    全局 Tick 钩子：驱动所有协程
    如果你的调度器已经包含 Tick 逻辑，这里只需要调用调度器的 Tick 方法。
    这里提供一个最简实现作为备用。
--]]
local coroutines = {}

function EDA_Scheduler_Add(co, ragdoll)
    coroutines[ragdoll] = co
end

function EDA_Scheduler_Tick()
    for ragdoll, co in pairs(coroutines) do
        if not IsValid(ragdoll) then
            coroutines[ragdoll] = nil
        elseif coroutine.status(co) == "dead" then
            coroutines[ragdoll] = nil
        else
            local ok, err = coroutine.resume(co)
            if not ok then
                ErrorNoHalt("[EDA] Coroutine error: " .. tostring(err) .. "\n")
                coroutines[ragdoll] = nil
            end
        end
    end
end

hook.Add("Tick", "EDA_Scheduler_Tick", EDA_Scheduler_Tick)

-- 将调度器注册函数暴露给启动代码
EDA_Scheduler = EDA_Scheduler or {}
EDA_Scheduler.Add = EDA_Scheduler_Add

print("[EDA] Lifecycle hooks initialized.")
