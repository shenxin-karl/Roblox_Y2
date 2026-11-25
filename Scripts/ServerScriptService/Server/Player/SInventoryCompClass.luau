-- 项目背包适配：存档、堆叠和容量复用框架，仅维护所属玩家的原生 Tool 展示。
local FX = _G.FX
local Fields = _G.PlayerDataConfig
local Items = _G.ItemConfig
local WeaponVisual = FX.Loader:RequireShared("Scripts.Game.Shared.WeaponVisual")
local SwordRules = FX.Loader:RequireShared("Scripts.Game.Shared.SwordRules")
local Comp = FX.Class("SInventoryCompClass", "FSInventoryCompClass")
-- 握点按模型高度归一；弯柄和短柄使用源模型中量出的偏移。
local DefaultSwordGripPoint = Vector3.new(0, -0.33, 0)
local SwordGripPointOverrides = {
    [4] = Vector3.new(0.02, -0.33, 0),
    [10] = Vector3.new(0.025, -0.33, 0),
    [19] = Vector3.new(-0.09, -0.33, 0),
    [24] = Vector3.new(0, -0.35, 0),
    [28] = Vector3.new(-0.03, -0.33, 0),
    [29] = Vector3.new(0, -0.36, 0),
    [32] = Vector3.new(0, -0.37, 0),
}
-- Grip 是手部握点在 Handle 中的坐标系；反转后让剑刃朝前、剑尖略偏向右侧。
local SwordGripRotation = CFrame.Angles(0, -math.pi / 2, 0) * CFrame.Angles(0, 0, math.rad(25))

--- 固定容量在组件创建时读取，矿石按掉落配置复用对应品级的外观模板。
--- @param owner table 当前服务端玩家对象。
function Comp:Ctor(owner)
    Comp.Super.Ctor(self, owner)
    local config = _G.Provider:GetInventoryConfig()
    self._config = {
        storeTableVarEnum = Fields.Inventory,
        shortcutCapacity = config.ShortcutCapacity,
        inventoryCapacity = config.BackpackCapacity,
    }
    self._tools = {}
    self._oreModels = {}
    for grade, rockType in pairs(_G.GameConfig.MiningRockData) do
        self._oreModels[rockType.OreItemId] = FX.Loader:Shared(rockType.ModelPath)
    end
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

--- 创建手持外观；将手对齐实际剑柄，并让剑尖稍向外倾斜，避开角色面部。
--- @param itemId number 已配置的道具 ID。
--- @param extra table? 武器变异用于光环；成品品质用于选择模型和图标。
--- @return Tool 不包含业务脚本的手持道具。
function Comp:CreateTool(itemId, extra)
    local tool = Instance.new("Tool")
    tool.CanBeDropped = false
    tool.Enabled = false
    tool:SetAttribute("FrameworkItemId", itemId)
    local mutationId = extra and extra.MutationId
    tool:SetAttribute("MutationId", mutationId)
    local icon = Items.Display[itemId].IconId
    if icon ~= "rbxassetid://0" then
        tool.TextureId = icon
    end
    local handle
    if Items.Data[itemId].HeldHandler == "Sword" then
        local quality = itemId == SwordRules.ItemId and extra.Quality or 1
        tool.TextureId = _G.GameConfig.WeaponData[quality].IconId
        handle = WeaponVisual.Create(quality, 4, mutationId)
        tool:SetAttribute("Quality", quality)
        local gripPoint = SwordGripPointOverrides[quality] or DefaultSwordGripPoint
        tool.Grip = CFrame.new(gripPoint * handle.Size.Y) * SwordGripRotation
    else
        local model = self._oreModels[itemId]:Clone()
        local size = model:GetExtentsSize()
        model:ScaleTo(model:GetScale() * 1.6 / math.max(size.X, size.Y, size.Z))
        model:PivotTo(CFrame.identity)
        handle = model.PrimaryPart
        handle.Transparency = 1
        handle.Parent = tool
        for index, node in ipairs(model:GetDescendants()) do
            if node:IsA("BaseScript") or node:IsA("ModuleScript") then
                node:Destroy()
            elseif node:IsA("BasePart") then
                node.Anchored = false
                node.CanCollide = false
                node.CanTouch = false
                node.CanQuery = false
                node.Massless = true
                local weld = Instance.new("WeldConstraint")
                weld.Part0 = handle
                weld.Part1 = node
                weld.Parent = node
            end
        end
        model.Name = "OreVisual"
        model.Parent = tool
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

--- 武器品质或变异改变时重建 Tool；剑胚按当前幸运等级刷新图标。
function Comp:SyncTools()
    if not self._active or self:GetTotalCapacity() == 0 then
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
            or (Items.Data[entry.itemId].HeldHandler == "Sword"
                and (tool:GetAttribute("Quality") ~= (entry.itemId == SwordRules.ItemId and entry.extraData.Quality or 1)
                    or tool:GetAttribute("MutationId") ~= (entry.extraData and entry.extraData.MutationId)))
            or (tool.Parent ~= backpack and tool.Parent ~= player.Character)) then
            tool:Destroy()
            self._tools[grid] = nil
            tool = nil
        end
        if entry then
            if not tool then
                tool = self:CreateTool(entry.itemId, entry.extraData)
                self._tools[grid] = tool
                local quality = entry.itemId == SwordRules.ItemId and entry.extraData.Quality
                local name = quality and _G.GameConfig.WeaponData[quality].Name or Items.Display[entry.itemId].Name
                tool.Name = name
                tool:SetAttribute("DisplayNameSource", name)
            end
            tool:SetAttribute("FrameworkGrid", grid)
            tool:SetAttribute("WeaponLevel", entry.extraData and entry.extraData.Level)
            tool:SetAttribute("StoredMoney", entry.extraData and entry.extraData.StoredMoney)
            local blankLuckLevel = entry.extraData and entry.extraData.blankLuckLevel
            tool:SetAttribute("blankLuckLevel", blankLuckLevel)
            if entry.itemId == SwordRules.BlankItemId then
                -- 幸运等级可超过图标档数；只限制展示，不改变剑胚属性。
                local iconLevel = if type(blankLuckLevel) == "number" and blankLuckLevel % 1 == 0
                    then math.clamp(blankLuckLevel, 1, 40) else 1
                local blankIcon = _G.GameConfig.WeaponData[iconLevel].BlankIconId
                if blankIcon then
                    tool.TextureId = blankIcon
                end
            end
            tool:SetAttribute("FrameworkStackCount", entry.stackCount)
            if not tool.Parent then
                tool.Parent = backpack
            end
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

--- 只装备当前快捷格里的本人道具；再次选择同一格则卸下。
function Comp:SelectGrid(grid, expectedTool)
    if not self._active or not self:_CheckGridIndexValid(grid) or grid > self:GetShortcutCapacity() then
        return
    end
    local tool = self._tools[grid]
    if not tool or tool ~= expectedTool then
        return
    end
    local player = self:GetPlayerNode()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return
    end
    if tool.Parent == character then
        humanoid:UnequipTools()
    elseif tool.Parent and tool.Parent == player:FindFirstChildOfClass("Backpack") then
        humanoid:EquipTool(tool)
    end
end

--- 使用两端格子的当前 Tool 防止复制延迟导致交换错误物品。
--- @param sourceGrid number 来源格号。
--- @param targetGrid number 目标格号。
--- @param sourceTool Tool 客户端看到的来源道具。
--- @param targetTool Tool? 客户端看到的目标道具。
--- @return boolean 是否已提交换格。
function Comp:RequestSwapGrid(sourceGrid, targetGrid, sourceTool, targetTool)
    if not self._active or not self:_CheckGridIndexValid(sourceGrid) or not self:_CheckGridIndexValid(targetGrid)
        or sourceGrid == targetGrid or not sourceTool then
        return false
    end
    if self._tools[sourceGrid] ~= sourceTool or self._tools[targetGrid] ~= targetTool then
        return false
    end
    local equippedGrid = self:GetEquippedGrid()
    if not self:SwapGridData(sourceGrid, targetGrid) then
        return false
    end
    if equippedGrid == sourceGrid or equippedGrid == targetGrid then
        local character = self:GetPlayerNode().Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid:UnequipTools()
        end
    end
    self:SyncTools()
    return true
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
