-- 项目背包适配：存档、堆叠和容量复用框架，仅维护所属玩家的原生 Tool 展示。
local FX = _G.FX
local Fields = _G.PlayerDataConfig
local Items = _G.ItemConfig
local Comp = FX.Class("SInventoryCompClass", "FSInventoryCompClass")

--- 固定容量在组件创建时读取，剑只复制外观，不复制资源内执行脚本。
--- @param owner table 当前服务端玩家对象。
function Comp:Ctor(owner)
    Comp.Super.Ctor(self, owner)
    local config = _G.Provider:GetNativeBackpackConfig()
    local shortcut = config.ShortcutEnabled and math.min(10, config.InventoryCapacity) or 0
    self._config = {
        storeTableVarEnum = Fields.Inventory,
        shortcutCapacity = shortcut,
        inventoryCapacity = config.InventoryCapacity - shortcut,
    }
    self._shortcutEnabled = config.ShortcutEnabled
    self._tools = {}
    self._swordHandle = FX.Loader:Shared("Assets.Decorations.Sword.ClassicSword.Handle")
end

--- 与统一奖励组件共用同一私有背包字段，不新增库存存档。
--- @return table 框架背包配置。
function Comp:GetConfig()
    return self._config
end

--- 数据和角色就绪后同步道具；背包替换、重生均从真实存档重建。
function Comp:OnPlayerLogin()
    self._active = true
    self:WatchDataChanged(Fields.Inventory, function()
        self:SyncTools()
    end)
    --- 仅响应引擎新建的背包容器，不等待角色或在奖励提交中让出执行。
    --- @param child Instance 玩家直接新增的节点。
    self:TrackConnection(self:GetPlayerNode().ChildAdded:Connect(function(child)
        if child:IsA("Backpack") then
            self:SyncTools()
        end
    end))
    self:TrackConnection(self:GetPlayerNode().CharacterAdded:Connect(function()
        self:SyncTools()
    end))
    self:SyncTools()
end

--- 仅为已拥有的道具创建手持外观；本轮矿石和剑没有点击使用效果。
--- @param itemId number 已配置的道具 ID。
--- @return Tool 不包含业务脚本的手持道具。
function Comp:CreateTool(itemId)
    local tool = Instance.new("Tool")
    tool.CanBeDropped = false
    tool.Enabled = false
    tool:SetAttribute("FrameworkItemId", itemId)
    local icon = Items.Display[itemId].IconId
    if icon ~= "rbxassetid://0" then
        tool.TextureId = icon
    end
    local handle
    if Items.Data[itemId].HeldHandler == "Sword" then
        handle = self._swordHandle:Clone()
    else
        handle = Instance.new("Part")
        handle.Size = Vector3.new(1.2, 1, 1.2)
        handle.Color = Color3.fromRGB(107, 110, 115)
        handle.Material = Enum.Material.Slate
    end
    handle.Name = "Handle"
    handle.Anchored = false
    handle.CanCollide = false
    handle.CanTouch = false
    handle.CanQuery = false
    handle.Massless = true
    handle.Parent = tool
    return tool
end

--- 数据提交后只更新变动格子，避免矿石堆叠时反复收起玩家装备。
function Comp:SyncTools()
    if not self._active or not self._shortcutEnabled then
        return
    end
    local player = self:GetPlayerNode()
    local backpack = player and player:FindFirstChildOfClass("Backpack")
    if not backpack then
        return
    end
    local data = self:GetData()
    for grid = 1, self:GetTotalCapacity() do
        local entry = data[grid]
        local tool = self._tools[grid]
        if tool and (not entry or tool:GetAttribute("FrameworkItemId") ~= entry.itemId
            or (tool.Parent ~= backpack and tool.Parent ~= player.Character)) then
            tool:Destroy()
            self._tools[grid] = nil
            tool = nil
        end
        if entry then
            if not tool then
                tool = self:CreateTool(entry.itemId)
                self._tools[grid] = tool
                tool.Name = Items.Display[entry.itemId].Name
                tool.Parent = backpack
            end
            tool:SetAttribute("FrameworkGrid", grid)
            tool:SetAttribute("WeaponLevel", entry.extraData and entry.extraData.Level)
            tool:SetAttribute("FrameworkStackCount", entry.stackCount)
        end
    end
end

--- 从本组件创建的实例确认手持格子，不信任客户端提交的 Tool 属性。
--- @return number? 本人当前装备的背包格号。
function Comp:GetEquippedGrid()
    local character = self:GetPlayerNode().Character
    if character then
        for grid, tool in pairs(self._tools) do
            if tool.Parent == character then
                return grid
            end
        end
    end
    return nil
end

--- 框架整理等全量变更仍走同一展示更新。
function Comp:OnAllChanged()
    self:SyncTools()
end

--- 离服后不再创建展示；库存始终由框架持久化。
function Comp:OnPlayerLogout()
    self._active = false
end

--- 只销毁本组件创建的道具，不触碰其他来源的 Tool。
function Comp:Dtor()
    self._active = false
    for grid, tool in pairs(self._tools) do
        tool:Destroy()
    end
    Comp.Super.Dtor(self)
end

return Comp
