-- 项目背包适配：配置、真实格号和操作协议在此接入。
local StarterGui = game:GetService("StarterGui")
local FX = _G.FX
local FXLoader = FX.Loader
FXLoader:RequireShared("Scripts.Framework.Client.Player.FCInventoryCompClass")
local Display = FXLoader:RequireFromParent(script, "CInventoryDisplay")
local Inventory = FX.Class("CInventoryCompClass", "FCInventoryCompClass")

--- 两端使用相同的快捷栏和背包容量。
--- @param owner table 本地玩家对象。
function Inventory:Ctor(owner)
    local config = _G.Provider:GetInventoryConfig()
    Inventory.Super.Ctor(self, owner, config.ShortcutCapacity, config.BackpackCapacity)
end

--- @return string 项目的背包组件协作名称。
function Inventory:GetCompName()
    return "CInventoryComp"
end

--- 从真实库存生成显示数据，展示布局不修改存档格号。
--- @param slots table 以真实格号为键的库存快照。
function Inventory:OnSlotsChanged(slots)
    local displaySlots = {}
    local usedBackpackSlots = 0
    for grid, slot in pairs(slots) do
        displaySlots[grid] = {
            token = slot.tool,
            name = slot.name,
            icon = slot.icon,
            count = slot.count,
            equipped = slot.equipped,
        }
        if grid > self._shortcutCapacity then
            usedBackpackSlots += 1
        end
    end
    self._display:Render(displaySlots, usedBackpackSlots)
end

--- 初始化视图后接管原生界面；背包可以独立于快捷栏启用。
function Inventory:OnReady()
    if self._totalCapacity == 0 then
        return
    end
    local playerGui = FXLoader:Player("PlayerGui")
    local root = playerGui:WaitForChild("SvnHotbar", 5)
    if not root then
        warn("[Inventory] StarterGui.SvnHotbar is unavailable")
        return
    end
    self._rootNode = root
    self._display = Display.new(root, {
        shortcutCapacity = self._shortcutCapacity,
        backpackCapacity = self._backpackCapacity,
        getBackpackGrid = function(displayIndex)
            return self._shortcutCapacity + displayIndex
        end,
    }, function(grid, expectedSlot)
        self:_SelectGrid(grid, expectedSlot.token)
    end, function(sourceGrid, targetGrid, expectedSlot)
        self:_SwapGrid(sourceGrid, targetGrid, expectedSlot.token)
    end)
    self:OnSlotsChanged({})
    self:StartInventorySync()
    self._nativeBackpackEnabled = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack)
    StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
    self:Show()
end

--- 仅选择当前快捷格持有的道具，最终由服务端装备。
--- @param grid number 真实格号。
--- @param expectedTool Tool 按下时看到的道具。
function Inventory:_SelectGrid(grid, expectedTool)
    local slot = self:GetSlot(grid)
    if grid <= self._shortcutCapacity and slot and slot.tool == expectedTool then
        FX.Network:SendMsgToServer("C2S_SelectInventoryGrid", grid, slot.tool)
    end
end

--- 拖拽从显示索引还原为真实格号，发送两端道具供服务端核对。
--- @param sourceGrid number 来源格。
--- @param targetGrid number 目标格。
--- @param expectedTool Tool 按下时看到的源道具。
function Inventory:_SwapGrid(sourceGrid, targetGrid, expectedTool)
    local source = self:GetSlot(sourceGrid)
    if not source or source.tool ~= expectedTool then
        return
    end
    local target = self:GetSlot(targetGrid)
    FX.Network:SendMsgToServer("C2S_SwapInventoryGrid", sourceGrid, targetGrid, source.tool, target and target.tool)
end

--- 先停止展示和输入，再由基类解除数据监听。
function Inventory:Dtor()
    if self._display then
        self:Hide()
        self._display:Destroy()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, self._nativeBackpackEnabled)
    end
    Inventory.Super.Dtor(self)
end

return Inventory
