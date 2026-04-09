-- lua/modules/coroutine_scheduler.lua
local Scheduler = {}
Scheduler.__index = Scheduler

-- 私有数据
local coroutines = {}   -- [co] = { tags = { [tag] = true } }
local tagIndex = {}     -- [tag] = { [co] = true }
local activeGroups = {} -- [groupKey] = group  （预留，用于组级别的状态）

-- 创建新调度器实例（通常全局单例即可）
function Scheduler.New()
    local self = setmetatable({}, Scheduler)
    self.coroutines = {}
    self.tagIndex = {}
    return self
end

-- 添加协程并打标签
function Scheduler:Add(co, tags)
    if not coroutines[co] then
        coroutines[co] = { tags = {} }
    end
    local coData = coroutines[co]
    for _, tag in ipairs(tags) do
        coData.tags[tag] = true
        if not tagIndex[tag] then
            tagIndex[tag] = {}
        end
        tagIndex[tag][co] = true
    end
end

-- 移除协程（内部使用）
function Scheduler:_removeCoroutine(co)
    local coData = coroutines[co]
    if not coData then return end
    for tag in pairs(coData.tags) do
        if tagIndex[tag] then
            tagIndex[tag][co] = nil
            if next(tagIndex[tag]) == nil then
                tagIndex[tag] = nil
            end
        end
    end
    coroutines[co] = nil
end

-- 按标签终止所有匹配的协程
function Scheduler:KillByTag(tag)
    local set = tagIndex[tag]
    if not set then return end
    for co in pairs(set) do
        -- 标记为死亡，实际清理将在 Tick 中处理
        self:_removeCoroutine(co)
    end
end

-- 恢复所有协程（在 Tick 中调用）
function Scheduler:Tick()
    for co, coData in pairs(coroutines) do
        local status = coroutine.status(co)
        if status == "dead" then
            self:_removeCoroutine(co)
        elseif status == "suspended" then
            local success, err = coroutine.resume(co)
            if not success then
                ErrorNoHalt("[Scheduler] Coroutine error: " .. tostring(err) .. "\n")
                self:_removeCoroutine(co)
            end
        end
    end
end

-- 获取活跃协程数量（调试用）
function Scheduler:Count()
    local count = 0
    for _ in pairs(coroutines) do count = count + 1 end
    return count
end

-- 全局单例（推荐直接使用此实例）
local GlobalScheduler = Scheduler.New()

-- 注册 Tick 钩子
hook.Add("Tick", "EDA_CoroutineScheduler", function()
    GlobalScheduler:Tick()
end)

return GlobalScheduler
