-- SvnHotbar 的展示与输入适配；只消费格子快照和真实格号映射。
local UserInputService = game:GetService("UserInputService")
local FX, FC = _G.FX, _G.FC
local FXLoader = FX.Loader
local Text = FX.Text
local Drag = FXLoader:RequireFromParent(script, "CInventoryDrag")
local VirtualGrid = FXLoader:RequireShared("Scripts.Framework.Client.FCVirtualGrid")
local Display = {}
Display.__index = Display

local TranslationTexts = Text.Define("Y2Inventory", {
    Empty = "No items in the backpack.",
})

local keyCodes = {Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five,
    Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine, Enum.KeyCode.Zero}

--- 初始化按钮的通用显示字段。
--- @param button GuiButton 快捷格或可回收的背包格。
--- @return table 按钮及其显示节点。
local function bindSlot(button)
    local count = FXLoader:Here(button, "Key"):Clone()
    count.Name = "Count"
    count.AnchorPoint = Vector2.new(1, 1)
    count.Position = UDim2.new(1, -4, 1, -5)
    count.Size = UDim2.new(1, -8, 0, 14)
    count.TextXAlignment = Enum.TextXAlignment.Right
    count.Text = ""
    count.Visible = true
    count.Parent = button

    local indicator = FXLoader:Here(button, "Indicator")
    indicator.Size = UDim2.new(.6, 0, indicator.Size.Y.Scale, indicator.Size.Y.Offset)
    local name = FXLoader:Here(button, "ToolName")
    name.AutoLocalize = false
    return {
        button = button,
        icon = FXLoader:Here(button, "Icon"),
        name = name,
        count = count,
        indicator = indicator,
    }
end

--- 刷新一个显示节点，空格同样可作为拖拽目标。
--- @param cell table 格子的显示节点。
--- @param slot table? 该格当前展示的道具快照。
local function renderSlot(cell, slot)
    cell.icon.Image = slot and slot.icon or ""
    cell.name.Text = slot and slot.icon == "" and Text.TrSource(slot.name) or ""
    cell.count.Text = slot and slot.count and slot.count > 1 and tostring(slot.count) or ""
    cell.indicator.Visible = slot ~= nil and slot.equipped
end

--- 接管现有 SvnHotbar 的展示，不依赖库存存档或网络协议。
--- @param root ScreenGui 当前玩家的 SvnHotbar。
--- @param config table 快捷栏格数、展示格数与显示索引到真实格号的映射。
--- @param onSelect function 快捷格点击或按键回调。
--- @param onSwap function 拖拽交换回调。
--- @return table 背包展示对象。
function Display.new(root, config, onSelect, onSwap)
    local self = setmetatable({
        _slots = {},
        _shortcutCells = {},
        _createdShortcuts = {},
        _backpackCapacity = config.backpackCapacity,
        _usedBackpackSlots = 0,
    }, Display)
    local bar = FXLoader:Here(root, "Bar")
    local bagBox = FXLoader:Here(bar, "BagBox")
    local bagButton = FXLoader:Here(bagBox, "BagButton")
    local handle = FXLoader:Here(root, "Handle")
    local panel = FXLoader:Here(root, "Inventory")
    local list = FXLoader:Here(panel, "List")
    self._panel = panel
    self._countLabel = FXLoader:Here(panel, "Count")
    self._emptyLabel = FXLoader:Here(panel, "Empty")
    self._emptyLabel.AutoLocalize = false
    panel.Visible = false
    bagBox.Visible = config.backpackCapacity > 0
    handle.Visible = bagBox.Visible

    local dragLayer = Instance.new("Frame")
    dragLayer.Name = "DragLayer"
    dragLayer.BackgroundTransparency = 1
    dragLayer.Size = UDim2.fromScale(1, 1)
    dragLayer.ZIndex = 20
    dragLayer.Parent = root
    self._dragLayer = dragLayer
    local ghost = Instance.new("ImageLabel")
    ghost.BackgroundTransparency = 1
    ghost.AnchorPoint = Vector2.new(.5, .5)
    ghost.ZIndex = 20
    ghost.Visible = false
    ghost.Parent = dragLayer
    local templateButton = FXLoader:Here(bar, "Slot1"):Clone()
    self._templateButton = templateButton
    local ghostName = FXLoader:Here(templateButton, "ToolName"):Clone()
    ghostName.AutoLocalize = false
    ghostName.ZIndex = ghost.ZIndex + 1
    ghostName.Parent = ghost
    self._drag = Drag.new(root.Parent, ghost, ghostName, function(grid)
        return self._slots[grid]
    end, onSelect, onSwap)

    for _, button in ipairs(bar:GetChildren()) do
        local grid = tonumber(string.match(button.Name, "^Slot(%d+)$"))
        if grid then
            button.Visible = grid <= config.shortcutCapacity
        end
    end
    for grid = 1, config.shortcutCapacity do
        local button = bar:FindFirstChild("Slot" .. grid)
        if not button then
            button = templateButton:Clone()
            button.Name = "Slot" .. grid
            button.LayoutOrder = grid
            button.Parent = bar
            table.insert(self._createdShortcuts, button)
        end
        local key = FXLoader:Here(button, "Key")
        key.Visible = keyCodes[grid] ~= nil
        if key.Visible then
            key.Text = tostring(grid % 10)
        end
        self._shortcutCells[grid] = bindSlot(button)
        self._drag:RegisterSlot(button, function()
            return grid
        end)
    end

    local panelScale = FXLoader:Here(panel, "Scale")
    if config.backpackCapacity > 0 then
        self._grid = VirtualGrid.new(list, FXLoader:Here(list, "UIGridLayout"), FXLoader:Here(list, "UIPadding"),
            panelScale, config.backpackCapacity, function()
                local button = templateButton:Clone()
                FXLoader:Here(button, "Key").Visible = false
                local cell = bindSlot(button)
                self._drag:RegisterSlot(button, function()
                    return cell.grid
                end, list)
                return cell
            end, function(cell, displayIndex)
                cell.grid = displayIndex and config.getBackpackGrid(displayIndex)
                if cell.grid then
                    renderSlot(cell, self._slots[cell.grid])
                end
            end)
    end

    local barScale = FXLoader:Here(bar, "Scale")
    local handleScale = FXLoader:Here(handle, "Scale")
    local layout = FXLoader:Here(bar, "UIListLayout")
    local padding = FXLoader:Here(bar, "UIPadding")
    local barCount = config.shortcutCapacity + (bagBox.Visible and 1 or 0)
    local barWidth = templateButton.Size.X.Offset * barCount + layout.Padding.Offset * (barCount - 1)
        + padding.PaddingLeft.Offset + padding.PaddingRight.Offset
    local function resize()
        local width = math.max(1, root.AbsoluteSize.X - 24)
        barScale.Scale = math.min(1, width / barWidth)
        panelScale.Scale = math.min(1, width / panel.Size.X.Offset)
        handleScale.Scale = panelScale.Scale
    end
    local function toggleBackpack()
        self:ToggleBackpack()
    end
    self._connections = {
        root:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize),
        bagButton.Activated:Connect(toggleBackpack),
        handle.Activated:Connect(toggleBackpack),
        UserInputService.InputBegan:Connect(function(input, processed)
            if processed or not root.Enabled or input.UserInputType ~= Enum.UserInputType.Keyboard then
                return
            end
            if input.KeyCode == Enum.KeyCode.Backquote then
                self:ToggleBackpack()
                return
            end
            local grid = table.find(keyCodes, input.KeyCode)
            local slot = grid and self._shortcutCells[grid] and self._slots[grid]
            if slot then
                onSelect(grid, slot)
            end
        end),
        FC.Localization.Changed:Connect(function()
            self:Render(self._slots, self._usedBackpackSlots)
        end),
    }
    resize()
    return self
end

--- 打开时刷新视口；关闭时回收当前输入状态。
function Display:ToggleBackpack()
    if not self._grid then
        return
    end
    self._panel.Visible = not self._panel.Visible
    if self._panel.Visible then
        self._grid:Refresh()
    else
        self._drag:Cancel()
    end
end

--- 每次只绘制快捷栏和当前虚拟格子。
--- @param slots table 以真实格号为键的显示快照。
--- @param usedBackpackSlots number 背包区域的已用格数。
function Display:Render(slots, usedBackpackSlots)
    self._slots = slots
    self._usedBackpackSlots = usedBackpackSlots
    for grid, cell in ipairs(self._shortcutCells) do
        renderSlot(cell, slots[grid])
    end
    self._countLabel.Text = string.format("%d / %d", usedBackpackSlots, self._backpackCapacity)
    self._emptyLabel.Visible = usedBackpackSlots == 0
    if self._emptyLabel.Visible then
        self._emptyLabel.Text = Text.Tr(TranslationTexts.Empty)
    end
    if self._grid and self._panel.Visible then
        self._grid:Refresh()
    end
end

--- 清理展示对象拥有的节点与监听。
function Display:Destroy()
    for _, connection in ipairs(self._connections) do
        connection:Disconnect()
    end
    self._drag:Destroy()
    if self._grid then
        self._grid:Destroy()
    end
    for _, cell in ipairs(self._shortcutCells) do
        cell.count:Destroy()
    end
    for _, button in ipairs(self._createdShortcuts) do
        button:Destroy()
    end
    self._templateButton:Destroy()
    self._dragLayer:Destroy()
end

return Display
