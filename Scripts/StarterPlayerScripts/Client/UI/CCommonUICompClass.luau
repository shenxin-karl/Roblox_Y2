local FX, FC = _G.FX, _G.FC
local FXLoader = FX.Loader
local Text = FXLoader:RequireShared("Scripts.Framework.Shared.Core.FXText")
local UI = FX.Class("CCommonUICompClass", "FCCommonUICompClass")

--- 接入通用浮窗与道具名称翻译，不预设玩法联动。
--- @param owner table 所属客户端玩家对象。
function UI:Ctor(owner)
    UI.Super.Ctor(self, owner)
    self.Localization = FC.Localization
    for index, node in ipairs({self.Tips, self.Description}) do
        node.AutoLocalize = false
    end
    --- 语言变化后刷新已显示的翻译文案。
    self:TrackConnection(self.Localization.Changed:Connect(function()
        self:RefreshLocalization()
    end))
    self:RefreshLocalization()
    --- 新复制或在角色与背包之间移动的 Tool 按当前语言更新显示名。
    --- @param node Instance 玩家子树中新复制的节点，包含 Backpack 内的 Tool。
    self:TrackConnection(self:GetPlayerNode().DescendantAdded:Connect(function(node)
        if node:IsA("Tool") then
            self:LocalizeTool(node)
        end
    end))
    --- 角色不在 Player 子树内，装备时需单独监听其 Tool。
    --- @param character Model 引擎创建的当前玩家角色。
    self:TrackConnection(self:GetPlayerNode().CharacterAdded:Connect(function(character)
        self:BindCharacterTools(character)
    end))
    if self:GetPlayerNode().Character then
        self:BindCharacterTools(self:GetPlayerNode().Character)
    end
end

--- 显示前按屏幕缩小提示，并清除旧 Key，避免语言变化恢复旧提示。
--- @param message string 已准备好的提示内容。
--- @param duration number? 显示时长，单位为秒。
function UI:ShowTips(message, duration)
    self._tipKey, self._tipArguments = nil, nil
    local viewport = self.Root.AbsoluteSize
    local scale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.65, 1)
    self.Tips.Size = UDim2.new(0.86, 0, 0, 64 * scale)
    self.Tips.TextSize = math.round(28 * scale)
    self.Tips.TextSizeLimit.MaxTextSize = math.round(28 * scale)
    self.Tips.TextStroke.Thickness = 2 * scale
    self.Tips.Line1.Size = UDim2.new(1, 0, 0, 2 * scale)
    self.Tips.Line2.Size = UDim2.new(1, 0, 0, 2 * scale)
    self.Tips.Line2.Position = UDim2.new(0, 0, 1, -2 * scale)
    UI.Super.ShowTips(self, message, duration)
end

--- 弹窗保存文案定义以便刷新；其余沿用框架文本和回调参数。
--- @param params table DescKey/ConfirmKey/CancelKey 为文案定义；Arguments 为模板参数。
function UI:ShowTooltips(params)
    self._descriptionKey, self._descriptionArguments = params.DescKey, params.Arguments
    self._confirmKey = params.ConfirmKey
    self._cancelKey = params.CancelKey
    local options = table.clone(params)
    if self._descriptionKey then
        options.Desc = Text.Tr(self._descriptionKey, self._descriptionArguments)
    end
    self.Confirm.AutoLocalize = self._confirmKey == nil
    self.Cancel.AutoLocalize = self._cancelKey == nil
    if self._confirmKey then
        options.ConfirmBtnTxt = Text.Tr(self._confirmKey)
    end
    if self._cancelKey then
        options.CancelBtnTxt = Text.Tr(self._cancelKey)
    end
    UI.Super.ShowTooltips(self, options)
    self.TooltipParams = params
end

--- 清除当前弹窗来源，防止语言变化时恢复已关闭或被替换的弹窗。
function UI:HideTooltips()
    self.TooltipParams = nil
    UI.Super.HideTooltips(self)
end

--- 翻译加载完成或玩家切换语言时更新当前文案，不重置提示关闭计时。
function UI:RefreshLocalization()
    for index, node in ipairs(self:GetPlayerNode():GetDescendants()) do
        if node:IsA("Tool") then
            self:LocalizeTool(node)
        end
    end
    local character = self:GetPlayerNode().Character
    if character then
        for index, node in ipairs(character:GetChildren()) do
            if node:IsA("Tool") then
                self:LocalizeTool(node)
            end
        end
    end
    if self._descriptionKey then
        self.Description.Text = Text.Tr(self._descriptionKey, self._descriptionArguments)
    end
    if self._confirmKey then
        self.Confirm.Text = Text.Tr(self._confirmKey)
    end
    if self._cancelKey then
        self.Cancel.Text = Text.Tr(self._cancelKey)
    end
end

--- 原生背包不依赖自动文本采集，显示名与查找属性、存档模板名分离。
--- @param tool Tool 服务器通过 DisplayNameSource 提供配置原文的背包或装备道具。
function UI:LocalizeTool(tool)
    local source = tool:GetAttribute("DisplayNameSource")
    if not source then
        return
    end
    tool.Name = Text.TrSource(source)
    tool.ToolTip = tool.Name
end

--- 每次重生替换角色监听，确保云端加载前后及装备切换都能刷新道具文案。
--- @param character Model 当前玩家的角色，旧角色的连接在重新绑定时释放。
function UI:BindCharacterTools(character)
    if self._characterToolConnection then
        self._characterToolConnection:Disconnect()
    end
    --- Tool 已由服务器设置文案属性后才复制到角色。
    --- @param node Instance 角色新增的直接子节点。
    self._characterToolConnection = character.ChildAdded:Connect(function(node)
        if node:IsA("Tool") then
            self:LocalizeTool(node)
        end
    end)
    for index, node in ipairs(character:GetChildren()) do
        if node:IsA("Tool") then
            self:LocalizeTool(node)
        end
    end
end

--- 清理项目道具翻译监听，框架持有的翻译和按钮服务不随项目组件销毁。
function UI:Dtor()
    if self._characterToolConnection then
        self._characterToolConnection:Disconnect()
    end
    UI.Super.Dtor(self)
end

return UI
