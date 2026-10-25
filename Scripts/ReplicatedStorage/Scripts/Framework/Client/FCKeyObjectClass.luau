--[[
    FCKeyObjectClass - 长按键盘按键，按满时长触发完成，松手未满触发取消
    适用于任意键盘按键的长按检测
    定时器每 1/30 秒 tick 一次，用计数比例更新进度 (0~1)

    用法：
        local keyObj = FC.FCKeyObjectClass.New(Enum.KeyCode.W)
        keyObj:SetHoldDuration(1)
        keyObj:SetHoldStartCallback(function() end)      -- 长按开始
        keyObj:SetHoldCompleteCallback(function() end)   -- 长按完成
        keyObj:SetHoldCancelCallback(function() end)     -- 长按取消（松手未满）
        keyObj:SetProgressCallback(function(progress)    -- 更新进度条 progress 0~1
            ProgressBarImg.CompletionImg.Scale = FXMath:GetProgressX(progress)
        end)
--]]

local FX, FC = _G.FX, _G.FC
local FXTask = FX.Task
local ContextActionService = game:GetService("ContextActionService")

local FCKeyObjectClass = FX.Class("FCKeyObjectClass")
FC.KeyObjectClass = FCKeyObjectClass

function FCKeyObjectClass:Ctor(keyCode)
    self._keyCode = keyCode
    self._actionName = "FCKeyObject_" .. tostring(keyCode) .. "_" .. tostring(math.random(10000, 99999))
    self._holdDuration = 0
    self._timerInterval = 1 / 30 -- 每次定时器间隔
    self._timer = nil
    self._holdCounter = 0 -- 当前计数（每次 tick +1）
    self._totalTicks = nil -- 总次数 = holdDuration / timerInterval，在 StartHold 时计算
    self._progressCallback = nil -- 更新进度回调 function(progress 0~1)
    self._holdStartCallback = nil -- 长按开始回调
    self._holdCompleteCallback = nil -- 长按完成回调
    self._holdCancelCallback = nil -- 长按取消回调（松手未满时）
    self._isHolding = false -- 是否正在长按
    self._enabled = true
    self:RegisterEvents()
end

function FCKeyObjectClass:Dtor()
    self:StopHold()
    if self._actionName then
        ContextActionService:UnbindAction(self._actionName)
    end
    self._actionName = nil
    self._keyCode = nil
    self._progressCallback = nil
    self._holdStartCallback = nil
    self._holdCompleteCallback = nil
    self._holdCancelCallback = nil
end

function FCKeyObjectClass:RegisterEvents()
    ContextActionService:BindAction(self._actionName, function(actionName, inputState, inputObj)
        if not self._enabled then
            return
        end
        if inputState == Enum.UserInputState.Begin then
            self:OnKeyDown()
        elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
            self:OnKeyUp()
        end
    end, false, self._keyCode)
end

function FCKeyObjectClass:OnKeyDown()
    if not self._isHolding then
        self._isHolding = true
        self:StartHold()
    end
end

function FCKeyObjectClass:OnKeyUp()
    if self._isHolding then
        self._isHolding = false
        self:StopHold(true) -- true = 用户松手，未满则触发长按取消
    end
end

-- 开始长按计时，每 1/30 秒计数 +1，用计数比例更新进度
function FCKeyObjectClass:StartHold()
    self:StopHold()
    self._holdCounter = 0
    if self._holdStartCallback then
        self._holdStartCallback()
    end
    -- 时长为 0 时立即触发完成回调，不启动定时器
    if self._holdDuration <= 0 then
        if self._holdCompleteCallback then
            self._holdCompleteCallback()
        end
        return
    end
    self._holdStartedAt = os.clock()
    self._totalTicks = math.floor(self._holdDuration / self._timerInterval)
    self._totalTicks = math.max(1, self._totalTicks)
    self._timer = FXTask:Interval(self._timerInterval, function()
        self._holdCounter = self._holdCounter + 1
        local progress = math.min(1, (os.clock() - self._holdStartedAt) / self._holdDuration)
        if self._progressCallback then
            self._progressCallback(progress)
        end
        if progress >= 1 then
            self._timer = nil
            if self._holdCompleteCallback then
                self._holdCompleteCallback()
            end
            return false -- 停止定时器
        end
        return true
    end)
end

-- 停止长按计时并重置计数
-- fromUserRelease: true 表示用户松手，未满进度时触发长按取消回调
function FCKeyObjectClass:StopHold(fromUserRelease)
    if self._timer then
        if fromUserRelease and self._holdCancelCallback then
            self._holdCancelCallback()
        end
        FXTask:Cancel(self._timer)
        self._timer = nil
    end
    self._holdCounter = 0
    if self._progressCallback then
        self._progressCallback(0)
    end
end

-- 更新进度回调 function(progress 0~1)
function FCKeyObjectClass:SetProgressCallback(callback)
    self._progressCallback = callback
end

-- 长按开始回调
function FCKeyObjectClass:SetHoldStartCallback(callback)
    self._holdStartCallback = callback
end

-- 长按完成回调
function FCKeyObjectClass:SetHoldCompleteCallback(callback)
    self._holdCompleteCallback = callback
end

-- 长按取消回调（松手时未满进度）
function FCKeyObjectClass:SetHoldCancelCallback(callback)
    self._holdCancelCallback = callback
end

-- 设置长按时长（秒）
function FCKeyObjectClass:SetHoldDuration(duration)
    self._holdDuration = duration
end

-- 设置要监听的按键
function FCKeyObjectClass:SetKeyCode(keyCode)
    if self._keyCode == keyCode then
        return
    end
    if self._actionName then
        ContextActionService:UnbindAction(self._actionName)
    end
    -- 更新按键代码
    self._keyCode = keyCode
    self._actionName = "FCKeyObject_" .. tostring(keyCode) .. "_" .. tostring(math.random(10000, 99999))
    self:RegisterEvents()
end

function FCKeyObjectClass:SetEnabled(enabled)
    self._enabled = enabled
    if not enabled then
        self:OnKeyUp()
    end
end

return FCKeyObjectClass
