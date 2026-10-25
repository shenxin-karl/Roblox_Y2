local FX, FC = _G.FX, _G.FC
local FCUIRoot = FX.Loader:Require(script.Parent.Parent, "FCUIRoot")
local UI = FX.Class("FCCommonUICompClass", "FCPlayerCompClass")
FC.CommonUICompClass = UI

local function Node(className, name, parent, properties)
    local node = Instance.new(className)
    node.Name = name
    for key, value in pairs(properties or {}) do
        node[key] = value
    end
    node.Parent = parent
    return node
end

local function Text(className, name, parent, properties)
    properties.Font = Enum.Font.Gotham
    properties.TextSize = 18
    properties.TextColor3 = Color3.fromRGB(240, 243, 250)
    properties.TextWrapped = true
    properties.BorderSizePixel = 0
    return Node(className, name, parent, properties)
end

--- 初始化通用 UI，并在客户端就绪前注册提示与购买协议。
--- @param owner table 所属客户端玩家对象。
function UI:Ctor(owner)
    UI.Super.Ctor(self, owner)
    self.Root = FCUIRoot.Get()
    self.Tips = Text("TextLabel", "Tips", self.Root, {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.fromScale(0.5, 0.08),
        Size = UDim2.new(0.86, 0, 0, 64),
        BackgroundColor3 = Color3.fromRGB(8, 10, 14),
        BackgroundTransparency = 0.35,
        Visible = false,
        Text = "",
        ZIndex = 10,
    })
    self.Tips.Font = Enum.Font.GothamBlack
    self.Tips.TextSize = 28
    self.Tips.TextScaled = true
    self.Tips.TextWrapped = false
    self.Tips.TextColor3 = Color3.new(1, 1, 1)
    Node("UITextSizeConstraint", "TextSizeLimit", self.Tips, { MaxTextSize = 28 })
    Node("UISizeConstraint", "MaxWidth", self.Tips, { MaxSize = Vector2.new(900, 120) })
    Node("UIStroke", "TextStroke", self.Tips, {
        ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
        Color = Color3.new(0, 0, 0),
        Thickness = 2,
    })
    local fade = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.15, 0),
        NumberSequenceKeypoint.new(0.85, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    Node("UIGradient", "EdgeFade", self.Tips, { Transparency = fade })
    for index, position in ipairs({UDim2.new(), UDim2.new(0, 0, 1, -2)}) do
        local line = Node("Frame", "Line" .. index, self.Tips, {
            Position = position,
            Size = UDim2.new(1, 0, 0, 2),
            BackgroundColor3 = Color3.fromRGB(20, 24, 30),
            BackgroundTransparency = 0.3,
            BorderSizePixel = 0,
            ZIndex = 10,
        })
        Node("UIGradient", "EdgeFade", line, { Transparency = fade })
    end
    -- 全屏按钮消费遮罩区域的鼠标/触摸输入，避免弹窗后方的场景被点击。
    self.Modal = Text("TextButton", "Modal", self.Root, {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 0.4,
        AutoButtonColor = false,
        Modal = true,
        Selectable = false,
        Visible = false,
        Text = "",
    })
    local panel = Node("Frame", "Panel", self.Modal, {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(0.86, 0.65),
        BackgroundColor3 = Color3.fromRGB(28, 34, 48),
        BorderSizePixel = 0,
        Active = true,
    })
    Node("UISizeConstraint", "MaxSize", panel, { MaxSize = Vector2.new(520, 360) })
    Node("UICorner", "Corner", panel, { CornerRadius = UDim.new(0, 16) })
    local scroll = Node("ScrollingFrame", "Content", panel, {
        Position = UDim2.new(0, 20, 0, 16),
        Size = UDim2.new(1, -40, 1, -88),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 4,
    })
    self.Description = Text("TextLabel", "Description", scroll, {
        Size = UDim2.new(1, -8, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        TextYAlignment = Enum.TextYAlignment.Top,
        Text = "",
    })
    self.Cancel = Text("TextButton", "Cancel", panel, {
        Position = UDim2.new(0, 20, 1, -64),
        Size = UDim2.new(0.5, -30, 0, 44),
        BackgroundColor3 = Color3.fromRGB(64, 73, 92),
        Text = "取消",
    })
    self.Confirm = Text("TextButton", "Confirm", panel, {
        Position = UDim2.new(0.5, 10, 1, -64),
        Size = UDim2.new(0.5, -30, 0, 44),
        BackgroundColor3 = Color3.fromRGB(54, 104, 220),
        Text = "确定",
    })
    for _, button in ipairs({ self.Cancel, self.Confirm }) do
        Node("UICorner", "Corner", button, { CornerRadius = UDim.new(0, 10) })
    end
    self:TrackConnection(self.Confirm.Activated:Connect(function()
        self:_Finish(true)
    end))
    self:TrackConnection(self.Cancel.Activated:Connect(function()
        self:_Finish(false)
    end))
    self:SubscribeEvent("ShowTips", self.ShowTips)
    --- 将服务端提示广播给玩家组件，保持 ShowTips 事件的现有接法。
    --- @param message string 提示内容。
    --- @param duration number 可选显示时长，单位为秒。
    FX.Network:RegServerMsgCallback("S2C_ShowTips", function(message, duration)
        self:GetPlayerObject():PublishEvent("ShowTips", message, duration)
    end)
    FX.Network:RegServerMsgCallback("S2C_ShowDeveloperBuyUI", self.ShowDeveloperBuyUI, self)
    FX.Network:RegServerMsgCallback("S2C_ShowLocalizedTips", self.ShowLocalizedTips, self)
    --- 仅刷新正在显示的文案，不重建提示或重置关闭计时。
    self:TrackConnection(FC.Localization.Changed:Connect(function()
        if self._tipKey and self._tipLabel then
            self._tipLabel.Text = FX.Text.Tr(self._tipKey, self._tipArguments)
        end
    end))
end

function UI:GetCompName()
    return "FCCommonUIComp"
end

--- @param productId number Roblox Developer Product ID。
--- @return boolean 是否通过服务端预检并发起购买提示。
function UI:ShowDeveloperBuyUI(productId)
    if not FX.Network:InvokeServer("C2S_BuyCheck", productId) then
        return false
    end

    game:GetService("MarketplaceService"):PromptProductPurchase(self:GetPlayerNode(), productId)
    return true
end

--- 清理本次提示的动画和显示节点，保留隐藏模板供下次克隆。
function UI:_ClearTip()
    self._tipKey, self._tipArguments = nil, nil
    if self._tipGroup then
        FC.UIAnim:StopProgress(self._tipGroup)
        self._tipGroup:Destroy()
        self._tipGroup = nil
        self._tipLabel = nil
    end
end

--- 提示固定在原位，默认显示 2 秒后用 1 秒整组淡出并销毁。
--- @param message string 已准备好的提示文案。
--- @param duration number? 淡出前的显示时长，默认 2 秒。
function UI:ShowTips(message, duration)
    self:_ClearTip()
    local group = Node("CanvasGroup", "ActiveTip", self.Tips.Parent, {
        AnchorPoint = self.Tips.AnchorPoint,
        Position = self.Tips.Position,
        Size = self.Tips.Size,
        BackgroundTransparency = 1,
        ZIndex = self.Tips.ZIndex,
    })
    self.Tips.MaxWidth:Clone().Parent = group
    local label = self.Tips:Clone()
    label.AnchorPoint = Vector2.zero
    label.Position = UDim2.new()
    label.Size = UDim2.fromScale(1, 1)
    label.AutoLocalize = false
    label.Text = tostring(message)
    label.Visible = true
    label.Parent = group
    self._tipGroup, self._tipLabel = group, label
    FC.UIAnim:FadeOut(group, function()
        self:_ClearTip()
    end, 1, duration or 2)
end

--- 显示本地化提示并保存来源，以便语言变化时刷新。
--- @param key table Key/Source 文案定义。
--- @param arguments table? 文案模板参数。
--- @param duration number? 淡出前显示秒数。
function UI:ShowLocalizedTips(key, arguments, duration)
    FX.Text.ValidateDefinition(key)
    self:ShowTips(FX.Text.Tr(key, arguments), duration)
    self._tipKey, self._tipArguments = key, arguments
end

-- 保留 Y3 参数：Desc、ConfirmBtnTxt、ConfirmCB；新增可选取消按钮与回调。
function UI:ShowTooltips(params)
    self:HideTooltips()
    local selection = game:GetService("GuiService")
    self._previousSelection = selection.SelectedObject
    self.Description.Text = params.Desc or ""
    self.Confirm.Text = params.ConfirmBtnTxt or "确定"
    self.Cancel.Text = params.CancelBtnTxt or "取消"
    self.Cancel.Visible = params.ShowCancel == true
    self._confirmCB, self._cancelCB = params.ConfirmCB, params.CancelCB
    self.Modal.Visible = true
    if game:GetService("UserInputService").GamepadEnabled then
        selection.SelectedObject = self.Confirm
    end
end

function UI:ShowConfirm(params)
    local options = table.clone(params)
    options.ShowCancel = true
    self:ShowTooltips(options)
end

function UI:_Finish(confirmed)
    if not self.Modal.Visible then
        return
    end
    local callback
    if confirmed then
        callback = self._confirmCB
    else
        callback = self._cancelCB
    end
    -- 先清空回调，避免重复点击，以及回调打开新弹窗后被旧弹窗关闭。
    self:HideTooltips()
    if callback then
        callback()
    end
end

function UI:HideTooltips()
    self._confirmCB, self._cancelCB = nil, nil
    self.Modal.Visible = false
    local selection = game:GetService("GuiService")
    local selected = selection.SelectedObject
    if selected and selected:IsDescendantOf(self.Modal) then
        local previous = self._previousSelection
        selection.SelectedObject = previous and previous.Parent and previous or nil
    end
    self._previousSelection = nil
end

--- 释放组件拥有的协议回调、提示动画和子节点，保留框架共享画布。
function UI:Dtor()
    FX.Network:UnRegServerMsgCallback("S2C_ShowTips")
    FX.Network:UnRegServerMsgCallback("S2C_ShowDeveloperBuyUI")
    FX.Network:UnRegServerMsgCallback("S2C_ShowLocalizedTips")
    self:_ClearTip()
    self:HideTooltips()
    UI.Super.Dtor(self)
    self.Tips:Destroy()
    self.Modal:Destroy()
end

return UI
