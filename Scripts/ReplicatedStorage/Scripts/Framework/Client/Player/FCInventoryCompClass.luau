-- 客户端背包基类：从原生 Tool 投影库存快照，展示和操作由项目子类接入。
local FX = _G.FX
local Inventory = FX.Class("FCInventoryCompClass", "FCUICompClass")

--- 容量由项目传入，框架不依赖具体项目的 Provider 或协议。
--- @param owner table 本地玩家对象。
--- @param shortcutCapacity number 快捷栏格数。
--- @param backpackCapacity number 背包格数。
function Inventory:Ctor(owner, shortcutCapacity, backpackCapacity)
    Inventory.Super.Ctor(self, owner)
    self._shortcutCapacity = shortcutCapacity
    self._backpackCapacity = backpackCapacity
    self._totalCapacity = shortcutCapacity + backpackCapacity
    self._slots = {}
    self._containerConnections = {}
    self._toolConnections = {}
end

--- @param grid number 真实格号。
--- @return table? 最近一次收到的格子快照。
function Inventory:GetSlot(grid)
    return self._slots[grid]
end

--- 监听本人角色与 Backpack，沿用已复制的 Tool 作为展示数据。
function Inventory:StartInventorySync()
    local player = self:GetPlayerNode()
    self:TrackConnection(player.CharacterAdded:Connect(function(character)
        self:_BindContainer("Character", character)
    end))
    self:TrackConnection(player.CharacterRemoving:Connect(function(character)
        if self._character == character then
            self:_BindContainer("Character", nil)
        end
    end))
    self:TrackConnection(player.ChildAdded:Connect(function(child)
        if child:IsA("Backpack") then
            self:_BindContainer("Backpack", child)
        end
    end))
    self:TrackConnection(player.ChildRemoved:Connect(function(child)
        if child == self._backpack then
            self:_BindContainer("Backpack", nil)
        end
    end))
    self:_BindContainer("Character", player.Character)
    self:_BindContainer("Backpack", player:FindFirstChildOfClass("Backpack"))
end

--- 角色或背包替换时停止监听旧容器。
--- @param kind string 容器类别。
--- @param container Instance? 当前容器。
function Inventory:_BindContainer(kind, container)
    local oldConnections = self._containerConnections[kind]
    if oldConnections then
        for _, connection in ipairs(oldConnections) do
            connection:Disconnect()
        end
    end
    if kind == "Character" then
        self._character = container
    else
        self._backpack = container
    end
    if container then
        self._containerConnections[kind] = {
            container.ChildAdded:Connect(function(child)
                if child:IsA("Tool") then
                    self:_QueueRefresh()
                end
            end),
            container.ChildRemoved:Connect(function(child)
                if child:IsA("Tool") then
                    self:_QueueRefresh()
                end
            end),
        }
    else
        self._containerConnections[kind] = nil
    end
    self:_QueueRefresh()
end

--- 合并同一批 Tool 复制与装备变化。
function Inventory:_QueueRefresh()
    if self._refreshQueued or self._destroyed then
        return
    end
    self._refreshQueued = true
    task.defer(function()
        self._refreshQueued = false
        if not self._destroyed then
            self:_RefreshInventory()
        end
    end)
end

--- 先重建真实格号快照，再交给子类生成显示数据。
function Inventory:_RefreshInventory()
    local slots, seen = {}, {}
    local function readContainer(container, equipped)
        if not container then
            return
        end
        for _, tool in ipairs(container:GetChildren()) do
            if not tool:IsA("Tool") then
                continue
            end
            seen[tool] = true
            if not self._toolConnections[tool] then
                local function refresh()
                    self:_QueueRefresh()
                end
                self._toolConnections[tool] = {
                    tool:GetAttributeChangedSignal("FrameworkGrid"):Connect(refresh),
                    tool:GetAttributeChangedSignal("FrameworkStackCount"):Connect(refresh),
                    tool:GetPropertyChangedSignal("TextureId"):Connect(refresh),
                    tool:GetPropertyChangedSignal("Name"):Connect(refresh),
                }
            end
            local grid = tool:GetAttribute("FrameworkGrid")
            if type(grid) == "number" and grid % 1 == 0 and grid >= 1 and grid <= self._totalCapacity then
                slots[grid] = {
                    tool = tool,
                    name = tool.Name,
                    icon = tool.TextureId,
                    count = tool:GetAttribute("FrameworkStackCount"),
                    equipped = equipped,
                }
            end
        end
    end
    readContainer(self._backpack, false)
    readContainer(self._character, true)
    for tool, connections in pairs(self._toolConnections) do
        if not seen[tool] then
            for _, connection in ipairs(connections) do
                connection:Disconnect()
            end
            self._toolConnections[tool] = nil
        end
    end
    self._slots = slots
    self:OnSlotsChanged(slots)
end

--- 项目子类在这里更新界面或其他本地消费者。
--- @param slots table 以真实格号为键的快照。
function Inventory:OnSlotsChanged(slots)
end

--- 清理容器连接，防止延后的刷新访问已销毁组件。
function Inventory:Dtor()
    self._destroyed = true
    for _, groups in ipairs({self._containerConnections, self._toolConnections}) do
        for _, connections in pairs(groups) do
            for _, connection in ipairs(connections) do
                connection:Disconnect()
            end
        end
    end
    Inventory.Super.Dtor(self)
end

return Inventory
