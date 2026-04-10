--[[
    Scheduler 公开接口模块
    路径: lua/modules/scheduler/public.lua
    用法: local scheduler = include("modules/scheduler/public.lua")
]]

local private           = include("modules/scheduler/private.lua")

local scheduler         = {}

-- 核心 API
scheduler.Start         = private.Start
scheduler.Stop          = private.Stop
scheduler.Wait          = private.Wait
scheduler.WaitForTick   = private.WaitForTick
scheduler.WaitUntil     = private.WaitUntil
scheduler.WaitForEvent  = private.WaitForEvent
scheduler.Yield         = private.Yield

-- 辅助 API
scheduler.GetBlackboard = private.GetBlackboard
scheduler.SetCleanup    = private.SetCleanup
scheduler.IsRunning     = private.IsRunning
scheduler.OnError       = private.OnError
scheduler.GetVersion    = private.GetVersion

scheduler._VERSION      = private._version

return scheduler
