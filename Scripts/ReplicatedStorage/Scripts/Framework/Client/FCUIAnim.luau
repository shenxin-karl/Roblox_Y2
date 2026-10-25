local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local Anim = { _active = setmetatable({}, { __mode = "k" }), _popupOwners = {} }
_G.FC.UIAnim = Anim

--- @param node GuiObject 动画根节点。
--- @return UIScale 统一缩放节点。
local function Scale(node)
    local scale = node:FindFirstChildOfClass("UIScale")
    if not scale then
        scale = Instance.new("UIScale", node)
    end

    return scale
end

--- 只有当前动画成功完成时才执行回调，避免被替换的动画继续关闭窗口。
--- @param node Instance 被插值的对象。
--- @param goals table 目标属性。
--- @param duration number 秒数。
--- @param callback function 可选的成功完成回调。
--- @param info TweenInfo 可选的插值参数。
--- @return Tween 可取消的原生动画。
function Anim:_Play(node, goals, duration, callback, info)
    self:StopProgress(node)
    local tween = TweenService:Create(node, info or TweenInfo.new(duration or 0.2), goals)
    self._active[node] = tween
    tween.Completed:Once(function(state)
        if self._active[node] ~= tween then
            return
        end
        self._active[node] = nil
        tween:Destroy()
        if state == Enum.PlaybackState.Completed and callback then
            callback()
        end
    end)

    tween:Play()
    return tween
end

--- @param node GuiObject 面板。
--- @param duration number 可选秒数。
--- @param callback function 可选完成回调。
--- @return Tween 打开动画。
function Anim:Open(node, duration, callback)
    local scale = Scale(node)
    scale.Scale = 0.7
    return self:_Play(
        scale,
        { Scale = 1 },
        duration,
        callback,
        TweenInfo.new(duration or 0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    )
end

--- @param node GuiObject 面板。
--- @param callback function 在动画后隐藏面板的回调。
--- @param duration number 可选秒数。
--- @return Tween 关闭动画。
function Anim:Close(node, callback, duration)
    local scale = Scale(node)
    return self:_Play(scale, { Scale = 0.8 }, duration, function()
        if callback then
            callback()
        end

        scale.Scale = 1
    end)
end

--- @param node GuiObject 面板。
--- @param duration number 可选秒数。
--- @param callback function 可选完成回调。
--- @param offset Vector2 可选滑入像素偏移。
--- @return Tween 滑入动画。
function Anim:Show1(node, duration, callback, offset)
    offset = offset or Vector2.new(1200, 0)
    local origin = node.Position
    node.Position = origin - UDim2.fromOffset(offset.X, offset.Y)
    return self:_Play(node, { Position = origin }, duration, callback)
end

--- @param node GuiObject 面板。
--- @param callback function 完成后隐藏节点的回调。
--- @param duration number 可选秒数。
--- @param offset Vector2 可选滑出偏移。
--- @return Tween 滑出动画。
function Anim:Close1(node, callback, duration, offset)
    offset = offset or Vector2.new(1200, 0)
    local origin = node.Position
    return self:_Play(node, { Position = origin + UDim2.fromOffset(offset.X, offset.Y) }, duration, function()
        if callback then
            callback()
        end

        node.Position = origin
    end)
end

--- @param node GuiObject 面板。
--- @param offset Vector2 像素位移。
--- @param duration number 秒数。
--- @param callback function 完成回调。
--- @return Tween 移动动画。
function Anim:Move(node, offset, duration, callback)
    return self:_Play(node, { Position = node.Position + UDim2.fromOffset(offset.X, offset.Y) }, duration, callback)
end

--- @param node CanvasGroup 淡入需要原生 CanvasGroup 以覆盖子节点。
--- @param duration number 秒数。
--- @param callback function 完成回调。
--- @return Tween 淡入动画。
function Anim:FadeIn(node, duration, callback)
    node.GroupTransparency = 1
    return self:_Play(node, { GroupTransparency = 0 }, duration, callback)
end

--- 整组淡出文字、背景和描边，可先停留指定秒数再开始。
--- @param node CanvasGroup 淡出根节点。
--- @param callback function 完成后隐藏节点的回调。
--- @param duration number 秒数。
--- @param delay number? 淡出前的停留秒数，默认不等待。
--- @return Tween 淡出动画。
function Anim:FadeOut(node, callback, duration, delay)
    return self:_Play(node, { GroupTransparency = 1 }, duration, callback,
        TweenInfo.new(duration or 0.2, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, delay or 0))
end

--- @param node GuiObject 抖动节点。
--- @param intensity number 像素振幅。
--- @param duration number 总秒数。
--- @param shakes number 往返次数。
--- @return Tween 抖动动画。
function Anim:Shake(node, intensity, duration, shakes)
    local origin = node.Position
    return self:_Play(
        node,
        { Position = origin + UDim2.fromOffset(intensity or 5, 0) },
        duration,
        function()
            node.Position = origin
        end,
        TweenInfo.new(
            (duration or 0.3) / ((shakes or 3) * 2),
            Enum.EasingStyle.Sine,
            Enum.EasingDirection.InOut,
            (shakes or 3) - 1,
            true
        )
    )
end

--- @param node GuiObject 脉冲节点。
--- @param scalePercent number 相对放大量，例如 0.1。
--- @param repeatCount number 往返次数。
--- @param duration number 单程秒数。
--- @return Tween 脉冲动画。
function Anim:Pulse(node, scalePercent, repeatCount, duration)
    local scale = Scale(node)
    return self:_Play(
        scale,
        { Scale = 1 + (scalePercent or 0.1) },
        duration,
        nil,
        TweenInfo.new(duration or 0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, (repeatCount or 1) - 1, true)
    )
end

--- @param node Instance 需要停止的插值对象。
function Anim:StopProgress(node)
    local tween = self._active[node]
    if tween then
        self._active[node] = nil
        tween:Cancel()
        tween:Destroy()
    end
end

--- 将弹窗缩放叠加到布局缩放上，不占用自适应脚本的基础比例。
--- @param popup table 弹窗动画状态。
local function ApplyPopupScale(popup)
    popup.WritingScale = true
    popup.Scale.Scale = popup.BaseScale * popup.Factor.Value
    popup.ExpectedScale = popup.Scale.Scale
    popup.WritingScale = false
end

--- 记录已有 UIScale 的所有权；布局变化时继续保留当前动画倍率。
--- @param node GuiObject 以中心 AnchorPoint 排版的弹窗面板。
--- @return table 必须在组件析构时释放的动画状态。
function Anim:CreatePopup(node)
    assert(node:IsA("GuiObject"), "Popup animation requires a GuiObject")
    local existing = node:FindFirstChildOfClass("UIScale")
    local scale = existing or Scale(node)
    local popup = {
        Scale = scale,
        OwnScale = existing == nil,
        BaseScale = scale.Scale,
        ExpectedScale = scale.Scale,
        Factor = Instance.new("NumberValue"),
        State = "Hidden",
    }
    popup.Factor.Value = 1
    popup.FactorConnection = popup.Factor.Changed:Connect(function()
        ApplyPopupScale(popup)
    end)
    popup.ScaleConnection = scale:GetPropertyChangedSignal("Scale"):Connect(function()
        if popup.WritingScale or scale.Scale == popup.ExpectedScale then
            return
        end
        popup.BaseScale = scale.Scale
        ApplyPopupScale(popup)
    end)
    return popup
end

--- 用一个共享插值倍率同步背景模糊与视野，保持弹窗本身清晰。
function Anim:_ApplyPopupBackground()
    local value = self._popupBlend.Value
    self._popupBlur.Size = 16 * value
    if self._popupCamera then
        self._popupCamera.FieldOfView = math.clamp(self._popupFov + 8 * value, 1, 120)
    end
end

--- 相机替换时恢复旧相机，并记录新相机原来的视野。
function Anim:_BindPopupCamera()
    if self._popupCamera then
        self._popupCamera.FieldOfView = self._popupFov
    end
    self._popupCamera = Workspace.CurrentCamera
    self._popupFov = self._popupCamera and self._popupCamera.FieldOfView
    self:_ApplyPopupBackground()
end

--- 最后一个弹窗完成背景恢复后，清理框架自建的实例和连接。
function Anim:_ClearPopupBackground()
    self._popupBlendConnection:Disconnect()
    self._popupCameraConnection:Disconnect()
    if self._popupCamera then
        self._popupCamera.FieldOfView = self._popupFov
    end
    self._popupBlur:Destroy()
    self._popupBlend:Destroy()
    self._popupBlur = nil
    self._popupBlend = nil
    self._popupCamera = nil
    self._popupFov = nil
    self._popupBlendConnection = nil
    self._popupCameraConnection = nil
end

--- 多个弹窗共用背景效果；关闭过程中重新打开时从当前倍率续播。
--- @param popup table 持有背景效果的弹窗。
function Anim:_AcquirePopupBackground(popup)
    if self._popupOwners[popup] then
        return
    end
    self._popupOwners[popup] = true
    if not self._popupBlend then
        self._popupBlend = Instance.new("NumberValue")
        self._popupBlur = Instance.new("BlurEffect")
        self._popupBlur.Name = "FCUIPopupBlur"
        self._popupBlur.Size = 0
        self._popupBlur.Parent = Lighting
        self._popupBlendConnection = self._popupBlend.Changed:Connect(function()
            self:_ApplyPopupBackground()
        end)
        self._popupCameraConnection = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
            self:_BindPopupCamera()
        end)
        self:_BindPopupCamera()
    end
    self:_Play(self._popupBlend, { Value = 1 }, 0.25, nil,
        TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
end

--- 只有最后一个弹窗关闭时恢复背景，避免叠加窗口提前解除模糊。
--- @param popup table 释放背景效果的弹窗。
function Anim:_ReleasePopupBackground(popup)
    if not self._popupOwners[popup] then
        return
    end
    self._popupOwners[popup] = nil
    if next(self._popupOwners) then
        return
    end
    self:_Play(self._popupBlend, { Value = 0 }, 0.18, function()
        self:_ClearPopupBackground()
    end, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
end

--- 小尺寸从中心展开并轻微回弹；重复打开不重新跳到起始尺寸。
--- @param popup table CreatePopup 返回的状态。
function Anim:OpenPopup(popup)
    if popup.State == "Open" then
        return
    end
    self:StopProgress(popup.Factor)
    if popup.State == "Hidden" then
        popup.Factor.Value = 0.65
    end
    popup.State = "Open"
    self:_AcquirePopupBackground(popup)
    self:_Play(popup.Factor, { Value = 1.03 }, 0.18, function()
        self:_Play(popup.Factor, { Value = 1 }, 0.07, nil,
            TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
    end, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
end

--- 关闭动画完成才隐藏；取消关闭后不会执行旧的隐藏回调。
--- @param popup table CreatePopup 返回的状态。
--- @param callback function 动画成功完成后的隐藏回调。
function Anim:ClosePopup(popup, callback)
    if popup.State ~= "Open" then
        return
    end
    popup.State = "Closing"
    self:_ReleasePopupBackground(popup)
    self:_Play(popup.Factor, { Value = 0.65 }, 0.18, function()
        popup.State = "Hidden"
        callback()
        if popup.State == "Hidden" then
            popup.Factor.Value = 1
        end
    end, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In))
end

--- 析构时停止动画并恢复布局缩放，只销毁框架自己创建的 UIScale。
--- @param popup table CreatePopup 返回的状态。
function Anim:DestroyPopup(popup)
    self:StopProgress(popup.Factor)
    self:_ReleasePopupBackground(popup)
    popup.FactorConnection:Disconnect()
    popup.ScaleConnection:Disconnect()
    popup.Scale.Scale = popup.BaseScale
    if popup.OwnScale then
        popup.Scale:Destroy()
    end
    popup.Factor:Destroy()
end

--- @param node GuiObject 进度填充节点，水平 Size.Scale 表示进度。
--- @param progress number 0 到 1。
--- @param duration number 秒数。
--- @param callback function 完成回调。
--- @return Tween 进度动画。
function Anim:Progress(node, progress, duration, callback)
    return self:_Play(
        node,
        { Size = UDim2.new(math.clamp(progress, 0, 1), 0, node.Size.Y.Scale, node.Size.Y.Offset) },
        duration,
        callback
    )
end

return Anim
