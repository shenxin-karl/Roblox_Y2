-- 框架按钮悬停效果：实例由 FClient 统一持有。
local TweenService = game:GetService("TweenService")
local ButtonHover = {}
ButtonHover.__index = ButtonHover

local HOVER_SCALE = 1.05
local ENTER_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LEAVE_TWEEN = TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--- 取消旧动画后切换比例，快速进出时从当前比例继续。
--- @param state table 按钮绑定及原始缩放。
--- @param hovered boolean 是否进入悬停状态。
local function Animate(state, hovered)
    if state.tween then
        state.tween:Cancel()
    end
    state.tween = TweenService:Create(state.scale, hovered and ENTER_TWEEN or LEAVE_TWEEN, {
        Scale = state.baseScale * (hovered and HOVER_SCALE or 1),
    })
    state.tween:Play()
end

--- 隐藏或禁用时立即复位，不依赖引擎是否补发 MouseLeave。
--- @param state table 需要恢复的按钮状态。
local function Reset(state)
    if state.tween then
        state.tween:Cancel()
        state.tween = nil
    end
    state.scale.Scale = state.baseScale
end

--- 释放一组事件，防止界面重建后旧节点仍被持有。
--- @param connections table 当前持有的事件连接。
local function Disconnect(connections)
    for index, connection in ipairs(connections) do
        connection:Disconnect()
    end
    table.clear(connections)
end

--- 检查实际显示链，隐藏或禁用的按钮不播放进入动画。
--- @param button GuiButton 当前鼠标进入的按钮。
--- @param playerGui PlayerGui 全局效果的所属界面容器。
--- @return boolean 按钮是否处于可交互的显示链中。
local function CanHover(button, playerGui)
    if button:GetAttribute("HoverEnabled") == false or not button.Active or not button.Interactable then
        return false
    end
    local node = button
    while node and node ~= playerGui do
        if node:IsA("GuiObject") and not node.Visible then
            return false
        end
        if node:IsA("ScreenGui") and not node.Enabled then
            return false
        end
        node = node.Parent
    end
    return node == playerGui
end

--- 层级变化后更新显示监听，关闭任意父容器都能复位。
--- @param button GuiButton 需要更新祖先监听的按钮。
--- @param state table 按钮的缩放与连接状态。
function ButtonHover:_WatchVisibility(button, state)
    Disconnect(state.visibilityConnections)
    Reset(state)
    local node = button
    while node and node ~= self._playerGui do
        local property
        if node:IsA("GuiObject") then
            property = "Visible"
        elseif node:IsA("ScreenGui") then
            property = "Enabled"
        end
        if property then
            table.insert(state.visibilityConnections, node:GetPropertyChangedSignal(property):Connect(function()
                Reset(state)
            end))
        end
        node = node.Parent
    end
end

--- 默认覆盖所有项目按钮；遮罩可关闭，透明点击区可指定缩放父容器。
--- @param button Instance 新增或初次扫描到的界面节点。
function ButtonHover:_Bind(button)
    if not button:IsA("GuiButton") or self._buttons[button] or button:GetAttribute("HoverEnabled") == false then
        return
    end
    local target = button
    if button:GetAttribute("HoverTargetParent") == true and button.Parent:IsA("GuiObject") then
        target = button.Parent
    end
    local scale = target:FindFirstChildOfClass("UIScale")
    local ownsScale = scale == nil
    if ownsScale then
        scale = Instance.new("UIScale")
        scale.Name = "ButtonHoverScale"
        scale.Parent = target
    end
    local state = {
        scale = scale, baseScale = scale.Scale, ownsScale = ownsScale,
        connections = {}, visibilityConnections = {},
    }
    self._buttons[button] = state
    self:_WatchVisibility(button, state)
    table.insert(state.connections, button.MouseEnter:Connect(function()
        if CanHover(button, self._playerGui) then
            Animate(state, true)
        end
    end))
    table.insert(state.connections, button.MouseLeave:Connect(function()
        Animate(state, false)
    end))
    table.insert(state.connections, button:GetPropertyChangedSignal("Active"):Connect(function()
        Reset(state)
    end))
    table.insert(state.connections, button:GetPropertyChangedSignal("Interactable"):Connect(function()
        Reset(state)
    end))
    table.insert(state.connections, button.AncestryChanged:Connect(function()
        self:_WatchVisibility(button, state)
    end))
end

--- 移出 PlayerGui 后解除绑定，只删除本模块创建的缩放节点。
--- @param button Instance 本次移除的节点；非绑定按钮直接忽略。
function ButtonHover:_Unbind(button)
    local state = self._buttons[button]
    if not state then
        return
    end
    self._buttons[button] = nil
    Disconnect(state.connections)
    Disconnect(state.visibilityConnections)
    Reset(state)
    if state.ownsScale then
        state.scale:Destroy()
    end
end

--- 一次初始化同时覆盖已有 UI、后续克隆的弹窗和动态按钮。
--- @param playerGui PlayerGui 当前本地玩家的游戏 UI 容器。
--- @return table 全局按钮效果实例，由所属组件负责 Destroy。
function ButtonHover.New(playerGui)
    local self = setmetatable({_playerGui = playerGui, _buttons = {}, _connections = {}}, ButtonHover)
    --- 动态界面进入玩家 UI 树后立即绑定，非按钮节点由绑定入口忽略。
    --- @param node Instance 本次新增的后代节点。
    table.insert(self._connections, playerGui.DescendantAdded:Connect(function(node)
        self:_Bind(node)
    end))
    --- 界面移除时释放按钮监听，允许后续重新挂入时重新绑定。
    --- @param node Instance 即将移出的后代节点。
    table.insert(self._connections, playerGui.DescendantRemoving:Connect(function(node)
        self:_Unbind(node)
    end))
    for index, node in ipairs(playerGui:GetDescendants()) do
        self:_Bind(node)
    end
    return self
end

--- 随通用 UI 组件结束监听，恢复仍存在按钮的原始比例。
function ButtonHover:Destroy()
    Disconnect(self._connections)
    for button, state in pairs(self._buttons) do
        self:_Unbind(button)
    end
end

return ButtonHover
