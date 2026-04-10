--[[
    Scheduler 公开接口模块
    路径: lua/modules/scheduler/public.lua
    用法: local scheduler = include("modules/scheduler/public.lua")
]]

-- 加载私有实现
local private           = include("modules/scheduler/private.lua")

-- 创建公开模块表，仅暴露需要对外使用的 API
local scheduler         = {}

-- 核心 API
scheduler.Start         = private.Start
scheduler.Stop          = private.Stop
scheduler.Wait          = private.Wait
scheduler.WaitForFrame  = private.WaitForFrame
scheduler.WaitUntil     = private.WaitUntil
scheduler.WaitForEvent  = private.WaitForEvent
scheduler.Yield         = private.Yield

-- 辅助 API
scheduler.GetBlackboard = private.GetBlackboard
scheduler.SetCleanup    = private.SetCleanup
scheduler.IsRunning     = private.IsRunning
scheduler.OnError       = private.OnError
scheduler.GetVersion    = private.GetVersion

-- 可选：暴露版本号
scheduler._VERSION      = private._version

-- 返回公开模块
return scheduler
