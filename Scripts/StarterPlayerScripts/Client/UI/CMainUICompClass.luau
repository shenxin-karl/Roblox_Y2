-- 项目主界面扩展：仅保留通用道具说明接入，不依赖旧地图或玩法节点。
local FX, FC = _G.FX, _G.FC
local FXLoader = FX.Loader
local Text = FX.Text
local FCUIRoot = FXLoader:RequireShared("Scripts.Framework.Client.FCUIRoot")
local FCItemDescription = FXLoader:RequireShared("Scripts.Framework.Client.FCItemDescription")
local ItemConfig = FXLoader:RequireShared("Scripts.Game.Configs.ItemConfig")
local Component = FX.Class("CMainUICompClass", "FCUICompClass")

--- 返回项目主界面组件协作名。
--- @return string 主界面组件名。
function Component:GetCompName()
    return "CMainUIComp"
end

--- 复用框架画布创建自有容器，装备说明无需 Studio 预制节点。
function Component:OnReady()
    self._rootNode = Instance.new("Frame")
    self._rootNode.Name = "MainUI"
    self._rootNode.Size = UDim2.fromScale(1, 1)
    self._rootNode.BackgroundTransparency = 1
    self._rootNode.ZIndex = 0
    self._rootNode.Parent = FCUIRoot.Get()
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

--- 清理装备监听和组件自有界面，保留框架共享画布。
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
        self._rootNode:Destroy()
    end
    Component.Super.Dtor(self)
end

return Component
