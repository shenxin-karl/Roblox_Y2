-- 项目背包适配：配置、真实格号和操作协议在此接入。
local StarterGui = game:GetService("StarterGui")
local FX = _G.FX
local FXLoader = FX.Loader
FXLoader:RequireShared("Scripts.Framework.Client.Player.FCInventoryCompClass")
local Display = FXLoader:RequireFromParent(script, "CInventoryDisplay")
local ItemData = FXLoader:RequireShared("Scripts.Game.Configs.ItemConfig").Data
local Inventory = FX.Class("CInventoryCompClass", "FCInventoryCompClass")

local TranslationTexts = FX.Text.Define("Y2InventoryCategories", {
    Ore = "Ore",
    SwordBlank = "Sword Blanks",
    ForgedSword = "Forged Swords",
})

--- 将本项目的道具类型适配为通用页签规则。
--- @param itemType string ItemConfig 的道具类型，同时用作页签 ID。
--- @return table 对应的筛选页签配置。
local function createTypeTab(itemType)
    return {
        id = itemType,
        label = TranslationTexts[itemType],
        matches = function(slot)
            return slot.itemType == itemType
        end,
    }
end

local BackpackTabs = {
    createTypeTab("Ore"),
    createTypeTab("SwordBlank"),
    createTypeTab("ForgedSword"),
}

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
        local itemId = slot.tool:GetAttribute("FrameworkItemId")
        local item = itemId and ItemData[itemId]
        displaySlots[grid] = {
            token = slot.tool,
            name = slot.name,
            icon = slot.icon,
            count = slot.count,
            equipped = slot.equipped,
            itemType = item and item.Type,
        }
        if grid > self._shortcutCapacity then
            usedBackpackSlots += 1
        end
    end
    self._display:Render(displaySlots, usedBackpackSlots)
    self:_TryRevealBackpackDrop()
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
        backpackTabs = BackpackTabs,
    }, function(grid, expectedSlot)
        self:_SelectGrid(grid, expectedSlot.token)
    end, function(sourceGrid, targetGrid, expectedSlot, reveal)
        self:_SwapGrid(sourceGrid, targetGrid, expectedSlot.token, reveal)
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
--- @param reveal function? 确认目标道具已复制到本地后显示该道具。
function Inventory:_SwapGrid(sourceGrid, targetGrid, expectedTool, reveal)
    local source = self:GetSlot(sourceGrid)
    if not source or source.tool ~= expectedTool then
        return
    end
    local target = self:GetSlot(targetGrid)
    self._pendingBackpackDrop = nil
    if not reveal or target then
        FX.Network:SendMsgToServer("C2S_SwapInventoryGrid", sourceGrid, targetGrid, source.tool, target and target.tool)
        return
    end

    local pending = {
        sourceGrid = sourceGrid,
        targetGrid = targetGrid,
        itemId = source.tool:GetAttribute("FrameworkItemId"),
        reveal = reveal,
    }
    self._pendingBackpackDrop = pending
    -- RPC 与 Tool 复制可能先后到达，两端都确认后才切页。
    local ok, committed = pcall(FX.Network.InvokeServer, FX.Network, "C2S_SwapInventoryGrid",
        sourceGrid, targetGrid, source.tool, nil)
    if self._pendingBackpackDrop ~= pending then
        return
    end
    if not ok or not committed then
        self._pendingBackpackDrop = nil
        return
    end
    pending.committed = true
    self:_TryRevealBackpackDrop()
    if self._pendingBackpackDrop == pending then
        task.delay(5, function()
            if self._pendingBackpackDrop == pending then
                self._pendingBackpackDrop = nil
            end
        end)
    end
end

--- 目标 Tool 可能是服务端重建的；用已确认的换格和复制后的格子内容判断。
function Inventory:_TryRevealBackpackDrop()
    local pending = self._pendingBackpackDrop
    if not pending or not pending.committed or self:GetSlot(pending.sourceGrid) then
        return
    end
    local target = self:GetSlot(pending.targetGrid)
    if target and target.tool:GetAttribute("FrameworkItemId") == pending.itemId then
        self._pendingBackpackDrop = nil
        pending.reveal()
    end
end

--- 先停止展示和输入，再由基类解除数据监听。
function Inventory:Dtor()
    self._pendingBackpackDrop = nil
    if self._display then
        self:Hide()
        self._display:Destroy()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, self._nativeBackpackEnabled)
    end
    Inventory.Super.Dtor(self)
end

return Inventory
