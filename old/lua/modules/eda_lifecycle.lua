-- 主状态枚举
local MAIN_STATE = {
    DYING      = 1,
    STRUGGLING = 2,
    DEAD       = 3,
    DONE       = 4
}

-- 子状态枚举（仅在 STRUGGLING 中有效）
local SUB_STATE = {
    CRAWL  = 1,
    WRITHE = 2,
    TWITCH = 3,
    REVIVE = 4
}

-- 子状态执行结果枚举
local SUB_RESULT = {
    OVERKILL         = "overkill",
    REVIVE_SUCCESS   = "revive_success",
    REVIVE_CANCELLED = "revive_cancelled",
    REVIVE_REQUESTED = "revive_requested",
    SUBSTATE_CHANGED = "substate_changed",
    COMPLETED        = "completed"
}

-- 占位函数（实际由外部实现）
local function CreateAnimRag(physRag) end
local function CleanupDying(ctx) end
local function CleanupStruggling(ctx) end
local function ReleasePhysicsControl(physRag) end
local function PerformRevive(reviver, owner) end

--[[
    执行单个子状态的动画循环
    @param ctx 上下文表
    @param targetSubState 目标子状态
    @param previousSubState 前一个子状态（用于复活取消时回退）
    @return SUB_RESULT 枚举值
--]]
local function RunSubState(ctx, targetSubState, previousSubState)
    local animName, duration, isInfinite

    if targetSubState == SUB_STATE.CRAWL then
        animName = "crawl_loop"
        isInfinite = true
    elseif targetSubState == SUB_STATE.WRITHE then
        animName = "writhe_loop"
        isInfinite = true
    elseif targetSubState == SUB_STATE.TWITCH then
        animName = "twitch_loop"
        isInfinite = true
    elseif targetSubState == SUB_STATE.REVIVE then
        animName = "revive_anim"
        duration = 3.0
        isInfinite = false
    else
        return SUB_RESULT.COMPLETED
    end

    ctx.animRag:Fire("SetAnimation", animName)
    local deadline = not isInfinite and (CurTime() + duration) or nil

    while true do
        -- 最高优先级：overkill
        if ctx.overkill then
            return SUB_RESULT.OVERKILL
        end

        -- 复活子状态：检查取消条件
        if targetSubState == SUB_STATE.REVIVE then
            if not ctx.reviveConditionMet then
                return SUB_RESULT.REVIVE_CANCELLED
            end
        else
            -- 非复活子状态：检查是否有复活请求
            if ctx.reviveRequested then
                return SUB_RESULT.REVIVE_REQUESTED
            end
        end

        -- 子状态切换请求
        if ctx.desiredSubState and ctx.desiredSubState ~= targetSubState then
            return SUB_RESULT.SUBSTATE_CHANGED
        end

        -- 动画结束判断
        if not isInfinite and CurTime() >= deadline then
            break
        end

        -- 正常的骨骼驱动逻辑（此处填充实际的 CSC 更新）
        -- 例如：ApplyBoneTransforms(ctx.animRag, ctx.physRag)
        coroutine.yield()
    end

    -- 非无限动画正常结束
    if targetSubState == SUB_STATE.REVIVE then
        return SUB_RESULT.REVIVE_SUCCESS
    else
        return SUB_RESULT.COMPLETED
    end
end

--[[
    主生命周期协程
    流程：DYING → STRUGGLING → DEAD → DONE
--]]
local function LifecycleCoroutine(ctx)
    local physRag = ctx.physRag
    local mainState = MAIN_STATE.DYING
    local subState = nil
    local previousSubState = nil

    while mainState ~= MAIN_STATE.DONE do
        -- ========== DYING 阶段 ==========
        if mainState == MAIN_STATE.DYING then
            if not ctx.animRag then
                ctx.animRag = CreateAnimRag(physRag)
                ctx.animRag:Fire("SetAnimation", ctx.animName)
                ctx.animDeadline = CurTime() + (ctx.dyingDuration or 3.0)
            end

            if ctx.overkill then
                CleanupDying(ctx)
                mainState = MAIN_STATE.DEAD
            elseif CurTime() >= ctx.animDeadline then
                CleanupDying(ctx)
                if ctx.canStruggle then
                    mainState = MAIN_STATE.STRUGGLING
                    subState = SUB_STATE.CRAWL
                else
                    mainState = MAIN_STATE.DEAD
                end
            else
                -- 正常的死亡动画帧逻辑
                -- 例如：ApplyBoneTransforms(ctx.animRag, physRag)
                coroutine.yield()
            end

            -- ========== STRUGGLING 阶段 ==========
        elseif mainState == MAIN_STATE.STRUGGLING then
            if not ctx.animRag then
                ctx.animRag = CreateAnimRag(physRag)
            end

            -- 确定当前要执行的子状态
            local activeSub = subState or SUB_STATE.CRAWL
            if ctx.desiredSubState then
                activeSub = ctx.desiredSubState
                ctx.desiredSubState = nil
            end

            -- 处理复活请求（切换到复活子状态并保存回退状态）
            if ctx.reviveRequested and activeSub ~= SUB_STATE.REVIVE then
                previousSubState = activeSub
                activeSub = SUB_STATE.REVIVE
                ctx.reviveRequested = false
                ctx.reviveConditionMet = true
            end

            local result = RunSubState(ctx, activeSub, previousSubState)

            if result == SUB_RESULT.OVERKILL then
                CleanupStruggling(ctx)
                mainState = MAIN_STATE.DEAD
                subState = nil
                ctx.reviveConditionMet = false
            elseif result == SUB_RESULT.REVIVE_SUCCESS then
                PerformRevive(ctx.reviver, ctx.owner)
                return -- 协程结束
            elseif result == SUB_RESULT.REVIVE_CANCELLED then
                subState = previousSubState
                previousSubState = nil
                ctx.reviveConditionMet = false
            elseif result == SUB_RESULT.REVIVE_REQUESTED then
                subState = activeSub -- 保持当前子状态，下一循环处理复活请求
            elseif result == SUB_RESULT.SUBSTATE_CHANGED then
                subState = nil -- 下一循环使用新的 desiredSubState
            elseif result == SUB_RESULT.COMPLETED then
                subState = nil -- 理论上无限动画不会执行到这里
            end

            -- ========== DEAD 阶段 ==========
        elseif mainState == MAIN_STATE.DEAD then
            ReleasePhysicsControl(physRag)
            while IsValid(physRag) do
                coroutine.yield()
            end
            mainState = MAIN_STATE.DONE

            -- 未知状态，安全退出
        else
            break
        end
    end

    -- DONE 状态：协程结束
end

-- 返回函数供外部调用
return {
    MAIN_STATE = MAIN_STATE,
    SUB_STATE = SUB_STATE,
    SUB_RESULT = SUB_RESULT,
    LifecycleCoroutine = LifecycleCoroutine
}
