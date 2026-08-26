--[[
    标签协程调度器 (Tagged Coroutine Scheduler)
    - 每个协程可附加多个标签（字符串）。
    - 提供按标签恢复、按标签取消的功能。
    - 在全局 Tick 中统一恢复所有协程。
]]
local Scheduler = {}
Scheduler._coroutines = {} -- [co] = { tags = { [tag] = true } }
Scheduler._tagIndex = {}   -- [tag] = { [co] = true }

-- 为协程添加标签
function Scheduler.AddTag(co, tag)
    if not Scheduler._coroutines[co] then
        Scheduler._coroutines[co] = { tags = {} }
    end
    Scheduler._coroutines[co].tags[tag] = true

    if not Scheduler._tagIndex[tag] then
        Scheduler._tagIndex[tag] = {}
    end
    Scheduler._tagIndex[tag][co] = true
end

-- 移除协程的所有标签（协程死亡时自动调用）
local function removeAllTags(co)
    local data = Scheduler._coroutines[co]
    if not data then return end
    for tag in pairs(data.tags) do
        if Scheduler._tagIndex[tag] then
            Scheduler._tagIndex[tag][co] = nil
            if next(Scheduler._tagIndex[tag]) == nil then
                Scheduler._tagIndex[tag] = nil
            end
        end
    end
    Scheduler._coroutines[co] = nil
end

-- 杀死所有带指定标签的协程（从调度器中移除，协程将在下次 resume 时死亡）
function Scheduler.KillByTag(tag)
    local set = Scheduler._tagIndex[tag]
    if not set then return end
    for co in pairs(set) do
        removeAllTags(co)
    end
end

-- 每帧恢复所有活跃协程
function Scheduler.Tick()
    for co, data in pairs(Scheduler._coroutines) do
        if coroutine.status(co) == "dead" then
            removeAllTags(co)
        else
            local success, err = coroutine.resume(co)
            if not success then
                print("[Scheduler] Coroutine error: " .. tostring(err))
                removeAllTags(co)
            end
        end
    end
end

-- 创建并启动一个协程，自动附加给定标签
function Scheduler.Start(tags, func, ...)
    local co = coroutine.create(func)
    for _, tag in ipairs(tags) do
        Scheduler.AddTag(co, tag)
    end
    -- 立即执行第一段（直到首次 yield）
    local success, err = coroutine.resume(co, ...)
    if not success then
        print("[Scheduler] Coroutine startup error: " .. tostring(err))
        removeAllTags(co)
        return nil
    end
    return co
end

return Scheduler
