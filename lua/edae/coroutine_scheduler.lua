local MODULE_NAME = "CoroutineScheduler"

_EnhancedDeathAnimationExtendedSingletons = _EnhancedDeathAnimationExtendedSingletons or {}
if _EnhancedDeathAnimationExtendedSingletons[MODULE_NAME] then
    return _EnhancedDeathAnimationExtendedSingletons[MODULE_NAME]
end

local Constants = include("autorun/edae_sh_constants.lua")

local Scheduler = {}
Scheduler._activeCoros = {}         -- { co1, co2, ... }                             -- 等待下一帧的协程数组
Scheduler._eventNameToCorosMap = {} -- { eventName1 = { co1, co2, ... }, ... }       -- 每个事件对应的等待协程列表
Scheduler._eventNameToQueueMap = {} -- { eventName1 = { args1, args2, ... }, ... }   -- 每个事件对应的待处理参数队列, 密集表中每一个 args 来自一次发射
Scheduler._isRegistered = {}        -- { eventName1 = true, eventName2 = true, ... } -- 标记已注册监听的事件

function Scheduler:_handleYield(coro, msg)
    if coroutine.status(coro) == "dead" then return end

    if msg == nil then
        table.insert(self._activeCoros, coro)
    elseif type(msg) == "table" and msg.type == "event" then
        local eventName = msg.name

        Scheduler._eventNameToCorosMap[eventName] = Scheduler._eventNameToCorosMap[eventName] or {}
        table.insert(Scheduler._eventNameToCorosMap[eventName], coro)

        if not Scheduler._isRegistered[eventName] then
            Scheduler._isRegistered[eventName] = true

            local identifier = Constants.ADDON_NAME .. MODULE_NAME .. eventName
            hook.Add(eventName, identifier, function(...)
                local args = { ... }
                Scheduler._pendingEvents[eventName] = Scheduler._pendingEvents[eventName] or {}
                table.insert(Scheduler._pendingEvents[eventName], args)
            end)
        end
    else
        table.insert(Scheduler._frameWaitCoroutines, co)
    end
end

local function _resume(co, ...)
    local ok, yielded = coroutine.resume(co, ...)
    if not ok then
        ErrorNoHalt("Coroutine error: " .. tostring(yielded) .. "\n")
        return false
    end
    _handleYield(co, yielded)
    return true
end

function Scheduler:Start(fn)
    local co = coroutine.create(fn)
    _resume(co)
    return co
end

function Scheduler:WaitForEvent(eventName)
    return coroutine.yield({ type = "event", name = eventName })
end

function Scheduler:Think()
    -- 1. 处理所有等待下一帧的协程
    local frameWait = self._frameWaitCoroutines
    self._frameWaitCoroutines = {}
    for _, co in ipairs(frameWait) do
        _resume(co)
    end

    -- 2. 处理事件：为每个有等待者的事件分发一个待处理事件
    for eventName, waiters in pairs(self._eventWaitCoroutines) do
        local queue = self._pendingEvents[eventName]
        if queue and #queue > 0 and #waiters > 0 then
            local args = table.remove(queue, 1) -- 取出最早的事件参数
            local co = table.remove(waiters, 1) -- 取出一个等待者
            ResumeCoroutine(co, unpack(args))   -- 恢复协程并传入参数
        end
    end

    -- 3. 清理：如果某个事件没有等待者且队列为空，取消监听以释放资源
    for eventName, waiters in pairs(self._eventWaitCoroutines) do
        local queue = self._pendingEvents[eventName]
        if #waiters == 0 and (not queue or #queue == 0) and self._registeredEvents[eventName] then
            hook.Remove(eventName, Constants.ADDON_NAME .. "_Event_" .. eventName)
            self._registeredEvents[eventName] = nil
            self._eventWaitCoroutines[eventName] = nil
            self._pendingEvents[eventName] = nil
        end
    end
end

hook.Add("Think", Constants.ADDON_NAME .. MODULE_NAME .. "Think", function()
    Scheduler:Think()
end)

_EnhancedDeathAnimationExtendedSingletons[MODULE_NAME] = Scheduler
return Scheduler
