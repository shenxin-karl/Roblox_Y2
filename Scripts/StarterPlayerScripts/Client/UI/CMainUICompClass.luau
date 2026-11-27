-- 项目主界面：绑定 Studio 原生 HUD，并保留通用道具说明。
local GuiService = game:GetService("GuiService")
local SocialService = game:GetService("SocialService")
local TextService = game:GetService("TextService")
local FX, FC = _G.FX, _G.FC
local FXLoader = FX.Loader
local Text = FX.Text
local FCItemDescription = FXLoader:RequireShared("Scripts.Framework.Client.FCItemDescription")
local ActionButton = FXLoader:RequireFromParent(script, "CActionButton")
local DiamondPurchase = FXLoader:RequireFromParent(script, "CDiamondPurchase")
local ItemConfig = FXLoader:RequireShared("Scripts.Game.Configs.ItemConfig")
local GameUtility = FXLoader:RequireShared("Scripts.Game.Shared.GameUtility")
local SwordRules = FXLoader:RequireShared("Scripts.Game.Shared.SwordRules")
local MoneyMultiplier = FXLoader:RequireShared("Scripts.Game.Shared.MoneyMultiplierRules")
local PlayerDataConfig = _G.PlayerDataConfig
local TranslationTexts = Text.Define("MainItemDescription", {
    Traits = "{description}\nMutation: {mutation}\nBlank luck level: {blankLuckLevel:int}",
    GM = "GM",
    Multiplier = "×{rate} Cash",
    MultiplierMaxed = "Max level",
})
local Component = FX.Class("CMainUICompClass", "FCUICompClass")

local NAVIGATION_ICON_INSET = 38

--- 返回项目主界面组件协作名。
--- @return string 主界面组件名。
function Component:GetCompName()
    return "CMainUIComp"
end

--- 绑定 Studio 主界面、余额、传送与升级工坊入口，装备说明沿用现有展示。
function Component:OnReady()
    self._rootNode = FXLoader:PlayerGui("Main.HUD")
    self._topNav = FXLoader:Here(self._rootNode, "TopNav")
    self._topNavDefaultPosition = self._topNav.Position
    if FX.IsDeveloper(self:GetPlayerNode().UserId) then
        self:CreateGMButton()
    end
    self._moneyLabel = FXLoader:Here(self._rootNode, "Wallet.CashStat.Money")
    self:WatchDataChanged(PlayerDataConfig.Money, function()
        self:RefreshMoney()
    end)
    self:TrackConnection(FXLoader:Here(self._rootNode, "TopNav.Home").Activated:Connect(function()
        FX.Network:SendMsgToServer("C2S_ReturnHome")
    end))
    self:BindCommerceNavigation()
    self:BindMoneyMultiplierButton()
    self:BindEarningsHUD()
    -- 侧栏只打开工坊组件，关闭及重复打开的刷新由生成 View 负责。
    self:TrackConnection(FXLoader:Here(self._rootNode, "SideNav.Upgrade").Activated:Connect(function()
        self:GetOwner():RequireComponent("CUpgradeWorkshopUICompClass"):Show()
    end))
    self._itemDescription = FCItemDescription.New()
    self._itemDescription.Root.Parent = ActionButton.GetWorldLayer()
    for index, property in ipairs({"AbsolutePosition", "AbsoluteSize"}) do
        self:TrackConnection(self._topNav:GetPropertyChangedSignal(property):Connect(function()
            self:PositionItemDescription()
        end))
    end
    self:PositionItemDescription()
    self._itemDescriptionScale = Instance.new("UIScale")
    self._itemDescriptionScale.Name = "ResponsiveScale"
    self._itemDescriptionScale.Parent = self._itemDescription.Root
    self:TrackConnection(self._rootNode:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        self:RefreshLayout()
    end))
    self:TrackConnection(GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(function()
        self:RefreshLayout()
    end))
    self:RefreshLayout()
    self:ConfigureHudTextSizing()
    self._selectedToolConnections = {}
    self:TrackConnection(self._rootNode:GetPropertyChangedSignal("Visible"):Connect(function()
        self:RefreshSelectedTool()
    end))
    self:TrackConnection(FC.Localization.Changed:Connect(function()
        self:RefreshSelectedTool()
    end))
    --- 角色重生后替换装备监听。
    --- @param character Model 当前玩家角色。
    self:TrackConnection(self:GetPlayerNode().CharacterAdded:Connect(function(character)
        self:BindCharacterTools(character)
    end))
    self:TrackConnection(self:GetPlayerNode().CharacterRemoving:Connect(function()
        self:SetSelectedTool(nil)
    end))
    local character = self:GetPlayerNode().Character
    if character then
        self:BindCharacterTools(character)
    end
    self:Show()
end

--- 绑定 Studio 的好友加成条，右侧加号打开好友邀请。
function Component:BindEarningsHUD()
    local friendRow = FXLoader:Here(self._rootNode, "Wallet.FriendBoost")
    local friendLabel = FXLoader:Here(friendRow, "Bonus")
    local inviteButton = FXLoader:Here(friendRow, "InviteFriend")
    self:TrackConnection(inviteButton.Activated:Connect(function()
        local player = self:GetPlayerNode()
        local success, message = pcall(function()
            if SocialService:CanSendGameInviteAsync(player) and inviteButton.Parent then
                SocialService:PromptGameInvite(player)
            end
        end)
        if not success then
            warn("Unable to open friend invite:", message)
        end
    end))

    local friend = self:RequireComponent("FCFriendComp")
    --- 好友人数变化后，更新图标旁的加成百分比。
    local function RefreshFriendBoost()
        local bonus = MoneyMultiplier.GetFriendBonus(friend:GetFriendCountInRoom())
        friendLabel.Text = string.format("+%d%%", bonus * 100)
    end
    self:SubscribeEvent("FriendStateChanged", RefreshFriendBoost)
    RefreshFriendBoost()
end

--- 复用原生 HUD 的左上商店、右上导航和侧栏福利入口。
function Component:BindCommerceNavigation()
    local left = FXLoader:Here(self._topNav, "Center")
    local right = FXLoader:Here(self._topNav, "Shop")
    self:TrackConnection(left.Activated:Connect(DiamondPurchase.Open))

    FXLoader:Here(right, "NavigationIcon").Visible = true
    self:TrackConnection(right.Activated:Connect(function()
        FX.Network:SendMsgToServer("C2S_TeleportToMine")
    end))

    local welfare = FXLoader:Here(self._rootNode, "SideNav.Shop")
    local welfareCaption = FXLoader:Here(welfare, "Caption")
    local welfareEnabled = table.find(_G.NetworkProtocol.ClientMsgID, "C2S_ClaimWelfare") ~= nil
    welfareCaption.Visible = welfareEnabled
    FXLoader:Here(welfare, "Icon").Visible = welfareEnabled
    if welfareEnabled then
        self:TrackConnection(welfare.Activated:Connect(function()
            self:GetOwner():RequireComponent("CWelfareUICompClass"):Show()
        end))
    end
end

--- 绑定 Studio 倍率入口；价格放在按钮上方，倍率标题沿用 Y1 快捷入口的布局。
function Component:BindMoneyMultiplierButton()
    if not table.find(_G.NetworkProtocol.ClientMsgID, "C2S_BuyMoneyMultiplier") then
        local button = FXLoader:Find(self._rootNode, "MoneyMultiplier")
        if button then
            button.Visible = false
        end
        return
    end
    local button = FXLoader:Here(self._rootNode, "MoneyMultiplier")
    self._multiplierScale = FXLoader:Here(button, "ResponsiveScale")
    local titleLabel = FXLoader:Here(button, "Background.Title")
    local priceLabel = FXLoader:Here(button, "PriceRow.Price")
    local diamondIcon = FXLoader:Here(button, "PriceRow.Diamond")
    self:TrackConnection(button.Activated:Connect(function()
        self:GetOwner():RequireComponent("CMoneyMultiplierUICompClass"):OpenPurchase()
    end))

    --- 等级和语言变化时，显示下一档真实费用；满级仅保留状态提示。
    local function RefreshOffer()
        local tier = self:GetNumber(PlayerDataConfig.PaidMultiplierTier)
        local price = MoneyMultiplier.GetNextPrice(tier)
        local rate = MoneyMultiplier.GetMultiplier(price and tier + 1 or tier)
        titleLabel.Text = Text.Tr(TranslationTexts.Multiplier, {rate = GameUtility.NumberToText(rate)})
        priceLabel.Text = price and GameUtility.NumberToText(price) or Text.Tr(TranslationTexts.MultiplierMaxed)
        diamondIcon.Visible = price ~= nil
    end
    self:WatchDataChanged(PlayerDataConfig.PaidMultiplierTier, RefreshOffer)
    self:TrackConnection(FC.Localization.Changed:Connect(RefreshOffer))
end

--- 道具说明贴在顶部导航下方，并随安全区域与导航缩放一起移动。
function Component:PositionItemDescription()
    local description = self._itemDescription.Root
    local top = self._topNav.AbsolutePosition.Y - description.Parent.AbsolutePosition.Y
    local bottom = top + self._topNav.AbsoluteSize.Y
    description.Position = UDim2.new(0.5, 0, 0, math.max(0, bottom) + 12)
end

--- 复用 Y1 主界面右上角 GM 入口的外观；与 HUD 同级，锻造时仍可打开。
function Component:CreateGMButton()
    local button = Instance.new("TextButton")
    button.Name = "GMButton"
    button.AutoLocalize = false
    button.Text = Text.Tr(TranslationTexts.GM)
    button.Font = Enum.Font.GothamBold
    button.TextSize = 16
    button.TextColor3 = Color3.new(1, 1, 1)
    button.BackgroundColor3 = Color3.fromRGB(45, 49, 60)
    button.BorderSizePixel = 0
    button.AnchorPoint = Vector2.new(1, 0)
    button.Position = UDim2.new(1, -68, 0, 10)
    button.Size = UDim2.fromOffset(56, 32)
    button:SetAttribute("BlocksTrainingClick", true)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = button
    self:TrackConnection(button.Activated:Connect(function()
        self:GetOwner():RequireComponent("CGMPanelUIComp"):Show()
    end))
    button.Parent = self._rootNode.Parent
    self._gmButton = button
end

--- 各组使用相同倍率；顶部菜单优先放进原生顶栏空位，放不下就下移。
function Component:RefreshLayout()
    local size = self._rootNode.AbsoluteSize
    if size.X <= 0 or size.Y <= 0 then
        return
    end
    local scale = math.min(size.X / 1280, size.Y / 720, 1.25)
    for index, name in ipairs({"TopNav", "SideNav", "Wallet"}) do
        FXLoader:Here(self._rootNode, name .. ".ResponsiveScale").Scale = scale
    end
    FXLoader:Here(self._rootNode, "Wallet").Position = UDim2.new(0, 16 * scale, 1, -24 * scale)
    self._itemDescriptionScale.Scale = scale
    if self._multiplierScale then
        self._multiplierScale.Scale = scale
    end

    -- Main.HUD 从 CoreUISafeInsets 原点开始；GetInsetArea 在同一坐标系内返回顶栏区域。
    local topbarArea = GuiService:GetInsetArea(Enum.ScreenInsets.TopbarSafeInsets)
    if topbarArea.Height <= 0 then
        self._topNav.Position = self._topNavDefaultPosition
        return
    end

    local topbarPadding = 12
    local leftEdge = math.max(0, topbarArea.Min.X) + topbarPadding
    local rightEdge = math.min(size.X, topbarArea.Max.X) - topbarPadding
    local width = self._topNav.Size.X.Offset * scale
    local height = self._topNav.Size.Y.Offset * scale
    if width > rightEdge - leftEdge or height > topbarArea.Height then
        local position = self._topNavDefaultPosition
        local designY = size.Y * position.Y.Scale + position.Y.Offset
        local topY = math.max(designY, topbarArea.Max.Y + topbarPadding)
        self._topNav.Position = UDim2.new(position.X.Scale, position.X.Offset, 0, topY)
        return
    end

    local halfWidth = width / 2
    local minCenterX = leftEdge + halfWidth
    local maxCenterX = rightEdge - halfWidth
    local centerX = math.clamp(size.X / 2, minCenterX, maxCenterX)
    local topY = topbarArea.Min.Y + (topbarArea.Height - height) / 2
    self._topNav.Position = UDim2.fromOffset(centerX, topY)
end

--- 常驻文字随分组缩放；余额、倒计时和译文变化时只在溢出时降低设计字号。
function Component:ConfigureHudTextSizing()
    for groupIndex, groupName in ipairs({"TopNav", "SideNav", "Wallet"}) do
        local group = FXLoader:Here(self._rootNode, groupName)
        local responsiveScale = FXLoader:Here(group, "ResponsiveScale")
        for labelIndex, label in ipairs(group:GetDescendants()) do
            if not (label:IsA("TextLabel") or label:IsA("TextButton")) then
                continue
            end
            local designSize = label.TextSize
            local navigationIcon = label:FindFirstChild("NavigationIcon")
            local hasNavigationIcon = navigationIcon and navigationIcon.Visible
            label.TextScaled = false
            local constraint = label:FindFirstChildOfClass("UITextSizeConstraint")
            if constraint then
                constraint:Destroy()
            end

            --- 在设计坐标中检查文字是否放得下，避免把分组倍率重复应用到字号。
            local function FitText()
                local scale = responsiveScale.Scale
                if scale <= 0 then
                    return
                end
                local available = label.AbsoluteSize / scale
                if available.X <= 0 or available.Y <= 0 then
                    return
                end
                local content = label.ContentText
                -- 文字仍居中，两侧等量留空，避免长译文遮住左侧图标。
                local availableWidth = hasNavigationIcon and (available.X - 2 * NAVIGATION_ICON_INSET) or available.X
                if availableWidth <= 0 then
                    return
                end
                local measureWidth = label.TextWrapped and availableWidth or 100000

                --- 允许换行的文字先按当前字号换行，再检查宽度和行高。
                --- @param textSize number 待测量的设计字号。
                --- @return boolean 文字能否完整放入当前文本框。
                local function Fits(textSize)
                    local bounds = TextService:GetTextSize(content, textSize, label.Font,
                        Vector2.new(measureWidth, 100000))
                    return bounds.X <= availableWidth and bounds.Y * label.LineHeight <= available.Y
                end

                if content == "" or Fits(designSize) then
                    label.TextSize = designSize
                    return
                end
                local lower, upper = 1, math.floor(designSize)
                while lower < upper do
                    local middle = math.ceil((lower + upper) / 2)
                    if Fits(middle) then
                        lower = middle
                    else
                        upper = middle - 1
                    end
                end
                label.TextSize = lower
            end

            self:TrackConnection(label:GetPropertyChangedSignal("ContentText"):Connect(FitText))
            self:TrackConnection(label:GetPropertyChangedSignal("AbsoluteSize"):Connect(FitText))
            self:TrackConnection(responsiveScale:GetPropertyChangedSignal("Scale"):Connect(FitText))
            FitText()
        end
    end
end

--- 余额只取玩家同步字段，缩写统一使用项目数量格式化方法。
function Component:RefreshMoney()
    self._moneyLabel.Text = "$" .. GameUtility.NumberToText(self:GetNumber(PlayerDataConfig.Money))
end

--- 仅在主界面可见且装备属于道具配置时显示，翻译与装备判断留在项目层。
function Component:RefreshSelectedTool()
    local tool = self._selectedTool
    local itemId = tool and tool:GetAttribute("FrameworkItemId")
    if not self._rootNode.Visible or not itemId or not ItemConfig.Data[itemId] then
        self._itemDescription:Hide()
        return
    end
    local description = Text.TrSource(ItemConfig.Display[itemId].Desc)
    local mutationId, blankLuckLevel = tool:GetAttribute("MutationId"), tool:GetAttribute("blankLuckLevel")
    if mutationId and blankLuckLevel ~= nil then
        description = Text.Tr(TranslationTexts.Traits, {
            description = description,
            mutation = Text.TrSource(SwordRules.GetMutation(mutationId).MutationName),
            blankLuckLevel = blankLuckLevel,
        })
    end
    self._itemDescription:Show({
        Title = tool.Name,
        Description = description,
        Icon = tool.TextureId,
    })
end

--- 装备变化时替换道具属性监听，避免旧道具继续覆盖当前说明。
--- @param tool Tool? 当前角色持有的道具。
function Component:SetSelectedTool(tool)
    for index, connection in ipairs(self._selectedToolConnections) do
        connection:Disconnect()
    end
    table.clear(self._selectedToolConnections)
    self._selectedTool = tool
    if tool then
        for index, property in ipairs({"Name", "ToolTip", "TextureId"}) do
            table.insert(self._selectedToolConnections, tool:GetPropertyChangedSignal(property):Connect(function()
                self:RefreshSelectedTool()
            end))
        end
        for index, attribute in ipairs({"FrameworkItemId", "MutationId", "blankLuckLevel"}) do
            table.insert(self._selectedToolConnections, tool:GetAttributeChangedSignal(attribute):Connect(function()
                self:RefreshSelectedTool()
            end))
        end
    end
    self:RefreshSelectedTool()
end

--- 角色重生时替换装备监听，道具名称翻译仍由通用 UI 负责。
--- @param character Model 当前玩家角色，旧角色监听在重新绑定时释放。
function Component:BindCharacterTools(character)
    if self._characterToolConnection then
        self._characterToolConnection:Disconnect()
    end
    if self._characterToolRemovedConnection then
        self._characterToolRemovedConnection:Disconnect()
    end
    self:SetSelectedTool(nil)
    --- 装备新道具时切换说明及属性监听。
    --- @param node Instance 角色新增的直接子节点。
    self._characterToolConnection = character.ChildAdded:Connect(function(node)
        if node:IsA("Tool") then
            self:SetSelectedTool(node)
        end
    end)
    --- 收起、消耗或销毁装备时刷新为剩余道具，无道具则隐藏。
    --- @param node Instance 从角色移出的直接子节点。
    self._characterToolRemovedConnection = character.ChildRemoved:Connect(function(node)
        if node == self._selectedTool then
            self:SetSelectedTool(character:FindFirstChildOfClass("Tool"))
        end
    end)
    for index, node in ipairs(character:GetChildren()) do
        if node:IsA("Tool") then
            self:SetSelectedTool(node)
        end
    end
end

--- 清理自建界面节点和装备监听，仅隐藏 Studio 提供的 HUD 模板副本。
function Component:Dtor()
    if self._gmButton then
        self._gmButton:Destroy()
    end
    if self._characterToolConnection then
        self._characterToolConnection:Disconnect()
    end
    if self._characterToolRemovedConnection then
        self._characterToolRemovedConnection:Disconnect()
    end
    for index, connection in ipairs(self._selectedToolConnections or {}) do
        connection:Disconnect()
    end
    if self._itemDescription then
        self._itemDescription:Destroy()
    end
    if self._rootNode then
        self._rootNode.Visible = false
    end
    Component.Super.Dtor(self)
end

return Component
