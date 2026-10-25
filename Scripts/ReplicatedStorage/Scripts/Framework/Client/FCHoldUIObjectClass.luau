--[[
    FCHoldUIObjectClass - 长按 UI 对象，按满时长触发完成，松手未满触发取消
    适用于任意带 TouchBegin/TouchEnd 的 UI 元素（按钮、图片、面板等）
    定时器每 1/30 秒 tick 一次，用计数比例更新进度 (0~1)

    用法：
        local holdUI = FC.FCHoldUIObjectClass.New(uiElement)
        holdUI:SetHoldDuration(1)
        holdUI:SetHoldStartCallback(function() end)      -- 长按开始
        holdUI:SetHoldCompleteCallback(function() end)   -- 长按完成
        holdUI:SetHoldCancelCallback(function() end)    -- 长按取消（松手未满）
        holdUI:SetProgressCallback(function(progress)    -- 更新进度条 progress 0~1
            ProgressBarImg.CompletionImg.Scale = FXMath:GetProgressX(progress)
        end)
--]]

local FX, FC = _G.FX, _G.FC
local FXTask = FX.Task

local FCHoldUIObjectClass = FX.Class("FCHoldUIObjectClass")
FC.HoldUIObjectClass = FCHoldUIObjectClass

function FCHoldUIObjectClass:Ctor(ui)
    self._ui = ui
    self._touchBeginConn = nil
    self._touchEndConn = nil
    self._holdDuration = 1
    self._timerInterval = 1 / 30 -- 每次定时器间隔
    self._timer = nil
    self._holdCounter = 0 -- 当前计数（每次 tick +1）
    self._totalTicks = nil -- 总次数 = holdDuration / timerInterval，在 StartHold 时计算
    self._progressCallback = nil -- 更新进度回调 function(progress 0~1)
    self._holdStartCallback = nil -- 长按开始回调
    self._holdCompleteCallback = nil -- 长按完成回调
    self._holdCancelCallback = nil -- 长按取消回调（松手未满时）
    self:RegisterEvents()
end

function FCHoldUIObjectClass:Dtor()
    self:StopHold()
    if self._touchBeginConn then
        self._touchBeginConn:Disconnect()
    end
    if self._touchEndConn then
        self._touchEndConn:Disconnect()
    end
    self._touchBeginConn = nil
    self._touchEndConn = nil
    self._ui = nil
    self._progressCallback = nil
    self._holdStartCallback = nil
    self._holdCompleteCallback = nil
    self._holdCancelCallback = nil
end

function FCHoldUIObjectClass:RegisterEvents()
    self._touchBeginConn = self._ui.InputBegan:Connect(function(input)
        if self._input then
            return
        end
        if
            input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1
        then
            self._input = input
            self:OnTouchBegin()
        end
    end)
    self._touchEndConn = game:GetService("UserInputService").InputEnded:Connect(function(input)
        if input == self._input then
            self._input = nil
            self:OnTouchEnd()
        end
    end)
end

function FCHoldUIObjectClass:OnTouchBegin()
    self:StartHold()
end

function FCHoldUIObjectClass:OnTouchEnd()
    self:StopHold(true) -- true = 用户松手，未满则触发长按取消
end

-- 开始长按计时，每 1/30 秒计数 +1，用计数比例更新进度
function FCHoldUIObjectClass:StartHold()
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
function FCHoldUIObjectClass:StopHold(fromUserRelease)
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
function FCHoldUIObjectClass:SetProgressCallback(callback)
    self._progressCallback = callback
end

-- 长按开始回调
function FCHoldUIObjectClass:SetHoldStartCallback(callback)
    self._holdStartCallback = callback
end

-- 长按完成回调
function FCHoldUIObjectClass:SetHoldCompleteCallback(callback)
    self._holdCompleteCallback = callback
end

-- 长按取消回调（松手时未满进度）
function FCHoldUIObjectClass:SetHoldCancelCallback(callback)
    self._holdCancelCallback = callback
end

function FCHoldUIObjectClass:SetHoldDuration(duration)
    self._holdDuration = duration
end

return FCHoldUIObjectClass
