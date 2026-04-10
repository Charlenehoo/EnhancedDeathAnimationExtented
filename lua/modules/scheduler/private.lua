--[[
    Scheduler 私有实现模块
    路径: lua/modules/scheduler/private.lua
    注意: 此文件不应被外部直接引用，请使用 public.lua
]]

local private = {}

-- 环境检查（仅在服务端运行）
if not SERVER then
    error("[Scheduler] 此调度器仅可在服务端环境中运行")
end

-- 获取高精度时间（SysTime 不受游戏暂停影响）
local function getTime()
    return SysTime()
end

-- 获取 Tick 计数
local function getTickCount()
    return engine.TickCount()
end

--[[
    内部数据结构定义
]]

-- 任务控制块弱表（键为协程对象，值为 Task 表）
private.tasks = setmetatable({}, { __mode = "k" })

-- 时间等待队列（按唤醒时间升序排列）
local timeQueue = {}

-- Tick 等待队列（按目标 Tick 升序排列）
local tickQueue = {} -- 元素: { targetTick = number, co = thread }

-- 条件等待列表
local conditionList = {}

-- 事件监听映射表: eventName -> array of coroutines
local eventMap = {}

-- 全局错误处理器
private.errorHandler = function(err, co, blackboard)
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
    -- Tick 队列
    for i = #tickQueue, 1, -1 do
        if tickQueue[i].co == co then
            table.remove(tickQueue, i)
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
    -- 事件映射
    for eventName, cos in pairs(eventMap) do
        for i = #cos, 1, -1 do
            if cos[i] == co then
                table.remove(cos, i)
                if #cos == 0 then
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

    if task.cleanup then
        local success, err = pcall(task.cleanup, task.co, task.blackboard)
        if not success then
            ErrorNoHalt("[Scheduler] 清理回调错误: " .. tostring(err))
        end
    end

    private.tasks[task.co] = nil
end

-- 内部函数：恢复协程（核心入口）
local function resumeTask(co, ...)
    local task = private.tasks[co]
    if not task then return end

    if task.stopped then
        finalizeTask(task)
        return
    end

    local success, err = coroutine.resume(co, ...)

    if not success then
        if private.errorHandler then
            private.errorHandler(err, co, task.blackboard)
        end
        finalizeTask(task)
        return
    end

    if coroutine.status(co) == "dead" then
        finalizeTask(task)
    end
end

-- 内部函数：确保事件钩子已注册
local function ensureEventHook(eventName)
    if eventMap[eventName] then return end

    eventMap[eventName] = {}
    local hookName = "Scheduler_Event_" .. eventName

    hook.Add(eventName, hookName, function(...)
        local cos = eventMap[eventName]
        if not cos then return end

        local toResume = {}
        for _, co in ipairs(cos) do
            toResume[#toResume + 1] = co
        end

        eventMap[eventName] = nil
        hook.Remove(eventName, hookName)

        for _, co in ipairs(toResume) do
            resumeTask(co, ...)
        end
    end)
end

--[[
    调度器主循环 (Tick 钩子)
]]
local function onTick()
    if private._inTick then return end
    private._inTick = true

    local now = getTime()
    local currentTick = getTickCount()

    -- 1. 处理时间等待队列
    while #timeQueue > 0 and timeQueue[1].time <= now do
        local entry = table.remove(timeQueue, 1)
        resumeTask(entry.co)
    end

    -- 2. 处理 Tick 等待队列
    while #tickQueue > 0 and tickQueue[1].targetTick <= currentTick do
        local entry = table.remove(tickQueue, 1)
        resumeTask(entry.co)
    end

    -- 3. 处理条件等待队列
    if #conditionList > 0 then
        local remaining = {}
        for _, entry in ipairs(conditionList) do
            local task = private.tasks[entry.co]
            if task and not task.stopped then
                local ok, result = pcall(entry.predicate)
                if ok and result then
                    resumeTask(entry.co)
                else
                    remaining[#remaining + 1] = entry
                end
            end
        end
        conditionList = remaining
    end

    private._inTick = false
end

hook.Add("Tick", "Scheduler_MainLoop", onTick)

--[[
    公开 API 实现（挂载到 private 表上，供 public.lua 选择性暴露）
]]

function private.Start(blackboard, mainFunc, ...)
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
    private.tasks[co] = task

    resumeTask(co)
    return co
end

function private.Stop(co)
    local task = private.tasks[co]
    if not task then return end

    task.stopped = true
    removeFromAllQueues(co)

    if coroutine.status(co) == "suspended" then
        finalizeTask(task)
    end
end

function private.Wait(seconds)
    local co = coroutine.running()
    if not co then error("[Scheduler] Wait 必须在协程内调用", 2) end
    local task = private.tasks[co]
    if not task then error("[Scheduler] 当前协程未由调度器管理", 2) end

    if task.stopped then
        error("[Scheduler] 协程已被停止", 2)
    end

    local wakeTime = getTime() + seconds

    -- 按时间升序插入队列
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

    return coroutine.yield()
end

function private.WaitForTick(ticks)
    local ticks = ticks or 1
    if type(ticks) ~= "number" or ticks < 1 then
        error("[Scheduler] WaitForTick 参数必须为正整数", 2)
    end

    local co = coroutine.running()
    if not co then error("[Scheduler] WaitForTick 必须在协程内调用", 2) end
    local task = private.tasks[co]
    if not task then error("[Scheduler] 当前协程未由调度器管理", 2) end

    if task.stopped then
        error("[Scheduler] 协程已被停止", 2)
    end

    local targetTick = getTickCount() + ticks

    -- 按目标 Tick 升序插入队列
    local inserted = false
    for i = 1, #tickQueue do
        if tickQueue[i].targetTick > targetTick then
            table.insert(tickQueue, i, { targetTick = targetTick, co = co })
            inserted = true
            break
        end
    end
    if not inserted then
        table.insert(tickQueue, { targetTick = targetTick, co = co })
    end

    return coroutine.yield()
end

function private.WaitUntil(predicate)
    if type(predicate) ~= "function" then
        error("[Scheduler] WaitUntil 需要一个函数参数", 2)
    end
    local co = coroutine.running()
    if not co then error("[Scheduler] WaitUntil 必须在协程内调用", 2) end
    local task = private.tasks[co]
    if not task then error("[Scheduler] 当前协程未由调度器管理", 2) end

    if task.stopped then
        error("[Scheduler] 协程已被停止", 2)
    end

    conditionList[#conditionList + 1] = { co = co, predicate = predicate }
    return coroutine.yield()
end

function private.WaitForEvent(eventName)
    if type(eventName) ~= "string" then
        error("[Scheduler] WaitForEvent 需要一个字符串事件名", 2)
    end
    local co = coroutine.running()
    if not co then error("[Scheduler] WaitForEvent 必须在协程内调用", 2) end
    local task = private.tasks[co]
    if not task then error("[Scheduler] 当前协程未由调度器管理", 2) end

    if task.stopped then
        error("[Scheduler] 协程已被停止", 2)
    end

    ensureEventHook(eventName)
    table.insert(eventMap[eventName], co)

    return coroutine.yield()
end

function private.Yield(...)
    local co = coroutine.running()
    if not co then error("[Scheduler] Yield 必须在协程内调用", 2) end
    return coroutine.yield(...)
end

function private.GetBlackboard(co)
    if co == nil then
        co = coroutine.running()
        if not co then return nil end
    end
    local task = private.tasks[co]
    return task and task.blackboard
end

function private.SetCleanup(co, cleanupFunc)
    local task = private.tasks[co]
    if not task then return end
    if type(cleanupFunc) ~= "function" then
        error("[Scheduler] SetCleanup 的第二个参数必须是函数", 2)
    end
    task.cleanup = cleanupFunc
end

function private.IsRunning(co)
    local task = private.tasks[co]
    if not task then return false end
    if task.stopped then return false end
    return coroutine.status(co) ~= "dead"
end

function private.OnError(callback)
    if callback ~= nil and type(callback) ~= "function" then
        error("[Scheduler] OnError 参数必须是函数或 nil", 2)
    end
    private.errorHandler = callback
end

function private.GetVersion()
    return private._version or "1.0.2"
end

private._version = "1.0.2"

return private
