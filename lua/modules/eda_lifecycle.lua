-- 主状态（线性推进）
local MAIN_STATE = {
    DYING      = 1,
    STRUGGLING = 2,
    DEAD       = 3,
    DONE       = 4
}

-- 子状态（仅在 STRUGGLING 中有效）
local SUB_STATE = {
    CRAWL  = 1,
    WRITHE = 2,
    TWITCH = 3,
    REVIVE = 4
}

-- 子状态执行结果枚举
local SUB_RESULT = {
    OVERKILL         = "overkill",         -- 血量归零，立即死亡
    REVIVE_SUCCESS   = "revive_success",   -- 复活动画完整播放，复活成功
    REVIVE_CANCELLED = "revive_cancelled", -- 复活被取消，回退到之前的子状态
    REVIVE_REQUESTED = "revive_requested", -- 在非复活子状态中收到复活请求
    SUBSTATE_CHANGED = "substate_changed", -- 被其他事件切换子状态（如受伤触发 writhe）
    COMPLETED        = "completed"         -- 非无限动画正常结束（除复活外）
}

--[[
    执行一个子状态的完整周期
    返回值见 SUB_RESULT 枚举。
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
        -- 最高优先级：overkill 直接死亡
        if ctx.overkill then
            return SUB_RESULT.OVERKILL
        end

        -- 对于复活子状态，检查取消条件
        if targetSubState == SUB_STATE.REVIVE then
            if not ctx.reviveConditionMet then
                return SUB_RESULT.REVIVE_CANCELLED
            end
        else
            -- 非复活子状态，检查是否有复活请求
            if ctx.reviveRequested then
                return SUB_RESULT.REVIVE_REQUESTED
            end
        end

        -- 检查是否有子状态切换请求
        if ctx.desiredSubState and ctx.desiredSubState ~= targetSubState then
            return SUB_RESULT.SUBSTATE_CHANGED
        end

        -- 动画结束判断
        if not isInfinite and CurTime() >= deadline then
            break
        end

        -- 正常的骨骼驱动逻辑（留空）
        coroutine.yield()
    end

    -- 非无限动画正常结束
    if targetSubState == SUB_STATE.REVIVE then
        return SUB_RESULT.REVIVE_SUCCESS
    else
        return SUB_RESULT.COMPLETED
    end
end

-- 生命周期协程（仅展示 STRUGGLING 部分）
local function LifecycleCoroutine(ctx)
    local physRag = ctx.physRag
    local mainState = MAIN_STATE.DYING
    local subState = nil
    local previousSubState = nil -- 用于复活取消时回退

    while mainState ~= MAIN_STATE.DONE do
        if mainState == MAIN_STATE.DYING then
            -- ...（DYING 阶段代码保持不变）...
        elseif mainState == MAIN_STATE.STRUGGLING then
            -- 初始化 struggling 阶段
            if not ctx.animRag then
                ctx.animRag = CreateAnimRag(physRag)
            end

            -- 确定当前要执行的子状态
            local activeSub = subState or SUB_STATE.CRAWL
            if ctx.desiredSubState then
                activeSub = ctx.desiredSubState
                ctx.desiredSubState = nil
            end

            -- 如果是复活请求，切换到复活子状态并保存回退状态
            if ctx.reviveRequested and activeSub ~= SUB_STATE.REVIVE then
                previousSubState = activeSub
                activeSub = SUB_STATE.REVIVE
                ctx.reviveRequested = false   -- 消费请求
                ctx.reviveConditionMet = true -- 初始条件满足
            end

            local result = RunSubState(ctx, activeSub, previousSubState)

            if result == "overkill" then
                CleanupStruggling(ctx)
                mainState = MAIN_STATE.DEAD
                subState = nil
                ctx.reviveConditionMet = false
            elseif result == "revive_success" then
                -- 复活成功：创建新 NPC，移除旧 Ragdoll
                PerformRevive(ctx.reviver, ctx.owner)
                return -- 协程结束
            elseif result == "revive_cancelled" then
                -- 复活取消：回退到之前的子状态
                subState = previousSubState
                previousSubState = nil
                ctx.reviveConditionMet = false
            elseif result == "revive_requested" then
                -- 从无限循环子状态中收到复活请求，下一循环处理
                subState = activeSub
            elseif result == "substate_changed" then
                -- 子状态被切换，下一循环使用新的 desiredSubState
                subState = nil
            elseif result == "completed" then
                -- 理论上只有非无限动画会到这里，目前只有 REVIVE 已经处理
                subState = nil
            end
        elseif mainState == MAIN_STATE.DEAD then
            -- ...（DEAD 阶段代码保持不变）...
        end
    end
end
