-- 项目主界面：绑定 Studio 原生 HUD，并保留通用道具说明。
local FX, FC = _G.FX, _G.FC
local FXLoader = FX.Loader
local Text = FX.Text
local FCItemDescription = FXLoader:RequireShared("Scripts.Framework.Client.FCItemDescription")
local ItemConfig = FXLoader:RequireShared("Scripts.Game.Configs.ItemConfig")
local GameUtility = FXLoader:RequireShared("Scripts.Game.Shared.GameUtility")
local PlayerDataConfig = _G.PlayerDataConfig
local Component = FX.Class("CMainUICompClass", "FCUICompClass")

--- 返回项目主界面组件协作名。
--- @return string 主界面组件名。
function Component:GetCompName()
    return "CMainUIComp"
end

--- 绑定 Studio 主界面、真实余额与回家请求，装备说明沿用现有展示。
function Component:OnReady()
    self._rootNode = FXLoader:PlayerGui("Main.HUD")
    self._moneyLabel = FXLoader:Here(self._rootNode, "Wallet.Money")
    self:TrackConnection(self._rootNode:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        self:RefreshLayout()
    end))
    self:WatchDataChanged(PlayerDataConfig.Money, function()
        self:RefreshMoney()
    end)
    self:TrackConnection(FXLoader:Here(self._rootNode, "TopNav.Home").Activated:Connect(function()
        FX.Network:SendMsgToServer("C2S_ReturnHome")
    end))
    self:RefreshLayout()
    self._itemDescription = FCItemDescription.New()
    self._itemDescription.Root.Parent = self._rootNode
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

--- 常驻 HUD 按参考画布等比缩小，顶部、侧栏与钱包保持各自的屏幕锚点。
function Component:RefreshLayout()
    local size = self._rootNode.AbsoluteSize
    local scale = math.min(size.X / 1174, size.Y / 622)
    for index, name in ipairs({"TopNav", "SideNav", "Wallet"}) do
        FXLoader:Here(self._rootNode, name .. ".ResponsiveScale").Scale = scale
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
    self._itemDescription:Show({
        Title = tool.Name,
        Description = Text.TrSource(ItemConfig.Display[itemId].Desc),
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
        table.insert(self._selectedToolConnections, tool:GetAttributeChangedSignal("FrameworkItemId"):Connect(function()
            self:RefreshSelectedTool()
        end))
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

--- 清理装备监听和自有道具说明，仅隐藏 Studio 提供的 HUD 模板副本。
function Component:Dtor()
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
