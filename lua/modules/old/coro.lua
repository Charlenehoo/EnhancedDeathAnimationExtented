--[[
    函数式协程原语库 (coro.lua)
    命名风格：camelCase，所有公开函数见下方列表。

    时间原语：
        waitSeconds(sec)          -- 暂停执行指定秒数
        waitFrames(n)             -- 暂停执行 n 帧（默认 1 帧）
        waitUntil(predicate)      -- 持续等待，直到条件为 true
        waitWhile(predicate)      -- 当条件为 true 时持续等待
        waitUntilTimeout(sec, predicate) -- 超时等待条件，返回是否成功
        waitForEvent(poller)      -- 等待事件，返回事件数据
        repeatEvery(interval, action) -- 每隔 interval 秒执行 action，直到 action 返回 true
]]

local coro = {}

local function now()
    return SysTime()
end

-- 按秒等待
function coro.waitSeconds(seconds)
    local deadline = now() + seconds
    while now() < deadline do
        coroutine.yield()
    end
end

-- 按帧等待（yield n 次）
function coro.waitFrames(n)
    n = n or 1
    for _ = 1, n do
        coroutine.yield()
    end
end

-- 等待条件成立
function coro.waitUntil(predicate)
    while not predicate() do
        coroutine.yield()
    end
end

-- 等待条件不成立（即条件为真时阻塞）
function coro.waitWhile(predicate)
    while predicate() do
        coroutine.yield()
    end
end

-- 超时等待条件，返回 true 表示条件满足，false 表示超时
function coro.waitUntilTimeout(seconds, predicate)
    local deadline = now() + seconds
    while now() < deadline do
        if predicate() then
            return true
        end
        coroutine.yield()
    end
    return false
end

-- 等待事件（poller 返回非 nil 时触发）
function coro.waitForEvent(poller)
    while true do
        local result = poller()
        if result ~= nil then
            return result
        end
        coroutine.yield()
    end
end

-- 每隔 interval 秒重复执行 action，直到 action 返回 true
function coro.repeatEvery(interval, action)
    while true do
        local shouldStop = action()
        if shouldStop then
            break
        end
        coro.waitSeconds(interval)
    end
end

-- 启动协程的便捷包装（如需与调度器集成，可在此处添加标签逻辑）
function coro.start(func, ...)
    local co = coroutine.create(func)
    local args = { ... }
    local success, err = coroutine.resume(co, unpack(args))
    if not success then
        error("[coro] Startup error: " .. tostring(err))
    end
    return co
end

return coro
