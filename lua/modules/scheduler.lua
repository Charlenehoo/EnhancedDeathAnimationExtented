--[[
    Scheduler - 功能完善的 GMod 协程调度器
    版本: 1.0.0
    依赖: GMod (Lua 5.1)
    放置路径: lua/modules/scheduler.lua
    使用方式: local scheduler = include("modules/scheduler.lua")
]]

local scheduler = {}
scheduler._version = "1.0.0"

-- 环境检查（确保在 GMod 环境中运行）
if not CLIENT and not SERVER then
    error("[Scheduler] 必须在 GMod 客户端或服务端环境中运行")
end

-- 获取安全的时间函数（客户端用 CurTime，服务端也用 CurTime，两者均存在）
local function getTime()
    return CurTime()
end

-- 获取帧计数（用于 WaitForFrame 的优化，非必须）
local function getFrameCount()
    return FrameNumber()
end

--[[
    内部数据结构定义
]]

-- 任务控制块弱表（键为协程对象，值为 Task 表）
scheduler.tasks = setmetatable({}, { __mode = "k" })

-- 时间等待队列（按唤醒时间升序排列）
local timeQueue = {}

-- 下一帧等待队列
local frameQueue = {}

-- 条件等待列表
local conditionList = {}

-- 事件监听映射表: eventName -> array of coroutines
local eventMap = {}

-- 全局错误处理器
scheduler.errorHandler = function(err, co, blackboard)
    -- 默认输出到控制台
    local coStr = tostring(co):match("thread: (%x+)") or "unknown"
    ErrorNoHalt(string.format("[Scheduler] 协程 %s 发生错误: %s\n", coStr, tostring(err)))
end

-- 内部函数：从所有队列中移除指定协程
local function removeFromAllQueues(co)
    -- 时间队列
    for i = #timeQueue, 1, -1 do
        if timeQueue[i].co == co then
            table.remove(timeQueue, i)
            break
        end
    end
    -- 帧队列
    for i = #frameQueue, 1, -1 do
        if frameQueue[i] == co then
            table.remove(frameQueue, i)
            break
        end
    end
    -- 条件队列
    for i = #conditionList, 1, -1 do
        if conditionList[i].co == co then
            table.remove(conditionList, i)
            break
        end
    end
    -- 事件映射（需要遍历所有事件名）
    for eventName, cos in pairs(eventMap) do
        for i = #cos, 1, -1 do
            if cos[i] == co then
                table.remove(cos, i)
                if #cos == 0 then
                    -- 若该事件下已无等待协程，移除钩子以节省性能
                    hook.Remove(eventName, "Scheduler_Event_" .. eventName)
                    eventMap[eventName] = nil
                end
                break
            end
        end
    end
end

-- 内部函数：执行清理回调并终结任务
local function finalizeTask(task)
    if task._finalized then return end
    task._finalized = true

    -- 调用清理回调
    if task.cleanup then
        local success, err = pcall(task.cleanup, task.co, task.blackboard)
        if not success then
            ErrorNoHalt("[Scheduler] 清理回调错误: " .. tostring(err))
        end
    end

    -- 从调度器任务表中移除
    scheduler.tasks[task.co] = nil
end

-- 内部函数：恢复协程（核心入口）
local function resumeTask(co, ...)
    local task = scheduler.tasks[co]
    if not task then return end

    -- 检查是否已被标记停止
    if task.stopped then
        finalizeTask(task)
        return
    end

    -- 调用原生 resume
    local success, err = coroutine.resume(co, ...)

    if not success then
        -- 协程内部错误
        if scheduler.errorHandler then
            scheduler.errorHandler(err, co, task.blackboard)
        end
        -- 出错后视为死亡，执行清理
        finalizeTask(task)
        return
    end

    -- 检查协程是否已自然死亡
    if coroutine.status(co) == "dead" then
        finalizeTask(task)
    end
end

-- 内部函数：将协程注册到事件钩子（若尚未注册）
local function ensureEventHook(eventName)
    if eventMap[eventName] then return end

    eventMap[eventName] = {}
    local hookName = "Scheduler_Event_" .. eventName

    hook.Add(eventName, hookName, function(...)
        local cos = eventMap[eventName]
        if not cos then return end

        -- 复制列表，防止在回调中修改原表导致跳过元素
        local toResume = {}
        for _, co in ipairs(cos) do
            toResume[#toResume + 1] = co
        end

        -- 清空原列表（这些协程将被恢复，不再等待此事件）
        eventMap[eventName] = nil
        hook.Remove(eventName, hookName)

        -- 恢复所有等待该事件的协程，传递事件参数
        for _, co in ipairs(toResume) do
            resumeTask(co, ...)
        end
    end)
end

--[[
    调度器主循环 (Think 钩子)
]]
local function onThink()
    -- 防止重入（例如在 resume 过程中触发了新的 Think）
    if scheduler._inThink then return end
    scheduler._inThink = true

    local now = getTime()

    -- 1. 处理时间等待队列
    while #timeQueue > 0 and timeQueue[1].time <= now do
        local entry = table.remove(timeQueue, 1)
        resumeTask(entry.co)
    end

    -- 2. 处理帧等待队列
    if #frameQueue > 0 then
        local frameCos = {}
        for i = 1, #frameQueue do
            frameCos[i] = frameQueue[i]
        end
        frameQueue = {} -- 清空
        for _, co in ipairs(frameCos) do
            resumeTask(co)
        end
    end

    -- 3. 处理条件等待队列
    if #conditionList > 0 then
        local remaining = {}
        for _, entry in ipairs(conditionList) do
            local task = scheduler.tasks[entry.co]
            if task and not task.stopped then
                local ok, result = pcall(entry.predicate)
                if ok and result then
                    -- 条件满足，恢复
                    resumeTask(entry.co)
                else
                    -- 条件不满足或检查出错，保留在队列中
                    remaining[#remaining + 1] = entry
                end
            else
                -- 任务已被停止或不存在，忽略
            end
        end
        conditionList = remaining
    end

    scheduler._inThink = false
end

hook.Add("Think", "Scheduler_MainLoop", onThink)

--[[
    公开 API 实现
]]

--- 启动一个新协程
--- @param blackboard any 注入到协程的上下文对象（可选）
--- @param mainFunc function 协程主函数，签名: function(blackboard, ...)
--- @param ... any 额外参数，传递给 mainFunc
--- @return thread co 协程句柄
function scheduler.Start(blackboard, mainFunc, ...)
    if type(mainFunc) ~= "function" then
        error("[Scheduler] Start 的第二个参数必须是函数", 2)
    end

    local args = { ... }

    local co = coroutine.create(function()
        mainFunc(blackboard, unpack(args))
    end)

    local task = {
        co = co,
        blackboard = blackboard,
        stopped = false,
        cleanup = nil,
        _finalized = false,
    }
    scheduler.tasks[co] = task

    -- 立即启动协程（首次 resume）
    resumeTask(co)

    return co
end

--- 请求终止指定协程
--- @param co thread 协程句柄
function scheduler.Stop(co)
    local task = scheduler.tasks[co]
    if not task then return end

    task.stopped = true

    -- 立即从所有等待队列中移除，防止未来被调度器恢复
    removeFromAllQueues(co)

    -- 如果协程当前处于挂起状态，立即终结（因为不会再被恢复了）
    local status = coroutine.status(co)
    if status == "suspended" then
        finalizeTask(task)
    end
    -- 若为 running 状态，只能等待其自然 yield 后由调度器拦截
end

--- 挂起当前协程指定秒数（仅可在协程内调用）
--- @param seconds number 等待秒数
function scheduler.Wait(seconds)
    local co = coroutine.running()
    if not co then
        error("[Scheduler] Wait 必须在协程内调用", 2)
    end
    local task = scheduler.tasks[co]
    if not task then
        error("[Scheduler] 当前协程未由调度器管理", 2)
    end

    -- 在挂起前检查停止标志（快速响应）
    if task.stopped then
        -- 主动抛出错误，让调度器捕获并清理
        error("[Scheduler] 协程已被停止", 2)
    end

    local wakeTime = getTime() + seconds

    -- 插入有序时间队列
    local inserted = false
    for i = 1, #timeQueue do
        if timeQueue[i].time > wakeTime then
            table.insert(timeQueue, i, { time = wakeTime, co = co })
            inserted = true
            break
        end
    end
    if not inserted then
        table.insert(timeQueue, { time = wakeTime, co = co })
    end

    -- 挂起协程
    return coroutine.yield()
end

--- 挂起当前协程，下一帧恢复
function scheduler.WaitForFrame()
    local co = coroutine.running()
    if not co then error("[Scheduler] WaitForFrame 必须在协程内调用", 2) end
    local task = scheduler.tasks[co]
    if not task then error("[Scheduler] 当前协程未由调度器管理", 2) end

    if task.stopped then
        error("[Scheduler] 协程已被停止", 2)
    end

    frameQueue[#frameQueue + 1] = co
    return coroutine.yield()
end

--- 挂起当前协程，直到条件函数返回 true
--- @param predicate function 条件函数，应返回布尔值
function scheduler.WaitUntil(predicate)
    if type(predicate) ~= "function" then
        error("[Scheduler] WaitUntil 需要一个函数参数", 2)
    end
    local co = coroutine.running()
    if not co then error("[Scheduler] WaitUntil 必须在协程内调用", 2) end
    local task = scheduler.tasks[co]
    if not task then error("[Scheduler] 当前协程未由调度器管理", 2) end

    if task.stopped then
        error("[Scheduler] 协程已被停止", 2)
    end

    conditionList[#conditionList + 1] = { co = co, predicate = predicate }
    return coroutine.yield()
end

--- 挂起当前协程，等待指定游戏事件触发
--- @param eventName string 事件名称（如 "PlayerSpawn"）
--- @return ... any 事件触发时传入的参数
function scheduler.WaitForEvent(eventName)
    if type(eventName) ~= "string" then
        error("[Scheduler] WaitForEvent 需要一个字符串事件名", 2)
    end
    local co = coroutine.running()
    if not co then error("[Scheduler] WaitForEvent 必须在协程内调用", 2) end
    local task = scheduler.tasks[co]
    if not task then error("[Scheduler] 当前协程未由调度器管理", 2) end

    if task.stopped then
        error("[Scheduler] 协程已被停止", 2)
    end

    ensureEventHook(eventName)
    table.insert(eventMap[eventName], co)

    return coroutine.yield()
end

--- 主动让出执行权（可传递返回值给调度器的恢复调用者，但通常由调度器内部使用）
--- @param ... any 返回值
function scheduler.Yield(...)
    local co = coroutine.running()
    if not co then error("[Scheduler] Yield 必须在协程内调用", 2) end
    return coroutine.yield(...)
end

--- 获取协程关联的黑板对象
--- @param co thread|nil 协程句柄，默认当前运行协程
--- @return any|nil
function scheduler.GetBlackboard(co)
    if co == nil then
        co = coroutine.running()
        if not co then return nil end
    end
    local task = scheduler.tasks[co]
    return task and task.blackboard
end

--- 为协程设置清理回调（若 Start 时未提供，或需要动态更改）
--- @param co thread 协程句柄
--- @param cleanupFunc function 清理函数，签名为 function(co, blackboard)
function scheduler.SetCleanup(co, cleanupFunc)
    local task = scheduler.tasks[co]
    if not task then return end
    if type(cleanupFunc) ~= "function" then
        error("[Scheduler] SetCleanup 的第二个参数必须是函数", 2)
    end
    task.cleanup = cleanupFunc
end

--- 检查协程是否仍在运行（未被停止且未死亡）
--- @param co thread 协程句柄
--- @return boolean
function scheduler.IsRunning(co)
    local task = scheduler.tasks[co]
    if not task then return false end
    if task.stopped then return false end
    local status = coroutine.status(co)
    return status ~= "dead"
end

--- 设置全局错误处理器
--- @param callback function 错误处理函数，签名: function(err, co, blackboard)
function scheduler.OnError(callback)
    if callback ~= nil and type(callback) ~= "function" then
        error("[Scheduler] OnError 参数必须是函数或 nil", 2)
    end
    scheduler.errorHandler = callback
end

--- 获取调度器版本
function scheduler.GetVersion()
    return scheduler._version
end

-- 返回模块表
return scheduler