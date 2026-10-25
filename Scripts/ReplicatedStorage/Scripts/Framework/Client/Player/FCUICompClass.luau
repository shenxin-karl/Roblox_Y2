local FX, FC = _G.FX, _G.FC
local UI = FX.Class("FCUICompClass", "FCPlayerCompClass")
FC.UICompClass = UI

--- @param owner table 本地玩家对象。
function UI:Ctor(owner)
    UI.Super.Ctor(self, owner)
end

--- @return string 默认组件名，项目子类应覆盖。
function UI:GetCompName()
    return "FCUIComp"
end

--- @return Instance 项目提供的 ScreenGui 或 GuiObject 根节点。
function UI:GetRootNode()
    return assert(self._rootNode, "Set _rootNode or override GetRootNode")
end

--- 按需启用通用弹窗效果；在 OnReady 中指定面板，常驻 HUD 不调用。
--- @param panel GuiObject 以中心 AnchorPoint 排版的动画面板。
function UI:SetOpenAnimation(panel)
    assert(not self._openAnimation, "Popup animation already configured")
    self._openAnimation = FC.UIAnim:CreatePopup(panel)
end

--- 析构时解除弹窗动画和共享背景占用，再交给基类清理连接。
function UI:Dtor()
    if self._openAnimation then
        FC.UIAnim:DestroyPopup(self._openAnimation)
        self._openAnimation = nil
    end
    UI.Super.Dtor(self)
end

--- 展示节点并调用一次本次打开钩子；不重新绑定按钮。
function UI:Show()
    local node = self:GetRootNode()
    if node:IsA("ScreenGui") then
        node.Enabled = true
    else
        node.Visible = true
    end

    if self._openAnimation then
        FC.UIAnim:OpenPopup(self._openAnimation)
    end

    if self.OnShow then
        self:OnShow()
    end
end

--- 实际隐藏节点并通知业务层；动画弹窗在关闭完成后调用。
function UI:_HideImmediately()
    local node = self:GetRootNode()
    if node:IsA("ScreenGui") then
        node.Enabled = false
    else
        node.Visible = false
    end

    if self.OnHide then
        self:OnHide()
    end
end

--- 启用动画的弹窗播完再隐藏，未启用的界面保持立即隐藏。
function UI:Hide()
    if not self._openAnimation or self._openAnimation.State == "Hidden" then
        self:_HideImmediately()
        return
    end
    FC.UIAnim:ClosePopup(self._openAnimation, function()
        self:_HideImmediately()
    end)
end

return UI
