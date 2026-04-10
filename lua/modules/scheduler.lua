--[[
    Scheduler - 功能完善的 GMod 协程调度器（纯服务端版本）
    版本: 1.0.1
    依赖: GMod 服务端 (Lua 5.1)
    放置路径: lua/modules/scheduler.lua
    使用方式: local scheduler = include("modules/scheduler.lua")
]]

local scheduler = {}
scheduler._version = "1.0.1"

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
scheduler.tasks = setmetatable({}, { __mode = "k" })

-- 时间等待队列（按唤醒时间升序排列）
local timeQueue = {}

-- 下一帧等待队列（此处为等待下一个 Tick）
local frameQueue = {}

-- 条件等待列表
local conditionList = {}

-- 事件监听映射表: eventName -> array of coroutines
local eventMap = {}

-- 全局错误处理器
scheduler.errorHandler = function(err, co, blackboard)
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
    -- 帧队列（Tick 队列）
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

    scheduler.tasks[task.co] = nil
end

-- 内部函数：恢复协程（核心入口）
local function resumeTask(co, ...)
    local task = scheduler.tasks[co]
    if not task then return end

    if task.stopped then
        finalizeTask(task)
        return
    end

    local success, err = coroutine.resume(co, ...)

    if not success then
        if scheduler.errorHandler then
            scheduler.errorHandler(err, co, task.blackboard)
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
    if scheduler._inTick then return end
    scheduler._inTick = true

    local now = getTime()

    -- 1. 处理时间等待队列
    while #timeQueue > 0 and timeQueue[1].time <= now do
        local entry = table.remove(timeQueue, 1)
        resumeTask(entry.co)
    end

    -- 2. 处理 Tick 等待队列（相当于原来的 WaitForFrame）
    if #frameQueue > 0 then
        local frameCos = {}
        for i = 1, #frameQueue do
            frameCos[i] = frameQueue[i]
        end
        frameQueue = {}
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
                    resumeTask(entry.co)
                else
                    remaining[#remaining + 1] = entry
                end
            end
        end
        conditionList = remaining
    end

    scheduler._inTick = false
end

hook.Add("Tick", "Scheduler_MainLoop", onTick)

--[[
    公开 API 实现
]]

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

    resumeTask(co)
    return co
end

function scheduler.Stop(co)
    local task = scheduler.tasks[co]
    if not task then return end

    task.stopped = true
    removeFromAllQueues(co)

    if coroutine.status(co) == "suspended" then
        finalizeTask(task)
    end
end

function scheduler.Wait(seconds)
    local co = coroutine.running()
    if not co then error("[Scheduler] Wait 必须在协程内调用", 2) end
    local task = scheduler.tasks[co]
    if not task then error("[Scheduler] 当前协程未由调度器管理", 2) end

    if task.stopped then
        error("[Scheduler] 协程已被停止", 2)
    end

    local wakeTime = getTime() + seconds

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

function scheduler.Yield(...)
    local co = coroutine.running()
    if not co then error("[Scheduler] Yield 必须在协程内调用", 2) end
    return coroutine.yield(...)
end

function scheduler.GetBlackboard(co)
    if co == nil then
        co = coroutine.running()
        if not co then return nil end
    end
    local task = scheduler.tasks[co]
    return task and task.blackboard
end

function scheduler.SetCleanup(co, cleanupFunc)
    local task = scheduler.tasks[co]
    if not task then return end
    if type(cleanupFunc) ~= "function" then
        error("[Scheduler] SetCleanup 的第二个参数必须是函数", 2)
    end
    task.cleanup = cleanupFunc
end

function scheduler.IsRunning(co)
    local task = scheduler.tasks[co]
    if not task then return false end
    if task.stopped then return false end
    return coroutine.status(co) ~= "dead"
end

function scheduler.OnError(callback)
    if callback ~= nil and type(callback) ~= "function" then
        error("[Scheduler] OnError 参数必须是函数或 nil", 2)
    end
    scheduler.errorHandler = callback
end

function scheduler.GetVersion()
    return scheduler._version
end

return scheduler
