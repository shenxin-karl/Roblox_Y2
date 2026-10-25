local FX = _G.FX
local FXTask = FX.Task

--- 延迟调用工具类。
--- 用于将“触发操作”延后执行，并支持在重复触发时重置计时（通过 `Restart` 实现防抖效果）。
--- @class FXDelayedInvokeClass
---
--- 简单使用：
--- local delayed = FX.DelayedInvokeClass.New(0.5, function()
---     print("do something after delay")
--- end)
--- delayed:Restart() -- 0.5 秒后执行回调
--- delayed:Cancel()  -- 在执行前取消

local FXDelayedInvokeClass = FX.Class("FXDelayedInvokeClass")
FX.DelayedInvokeClass = FXDelayedInvokeClass

function FXDelayedInvokeClass:Ctor(delay, callback)
    self._delay = delay
    self._callback = callback
    self._delayTimer = nil
end

function FXDelayedInvokeClass:Dtor()
    self:Cancel()
end

function FXDelayedInvokeClass:SetDelay(delay)
    self._delay = delay
end

function FXDelayedInvokeClass:SetCallback(callback, this)
    if this then
        self._callback = function()
            callback(this)
        end
    else
        self._callback = callback
    end
end

function FXDelayedInvokeClass:Restart()
    self:Cancel()
    if not self._callback then
        return
    end
    self._delayTimer = FXTask:Delay(self._delay, function()
        self._callback()
    end)
end

function FXDelayedInvokeClass:Cancel()
    if self._delayTimer then
        FXTask:Cancel(self._delayTimer)
        self._delayTimer = nil
    end
end

return true
