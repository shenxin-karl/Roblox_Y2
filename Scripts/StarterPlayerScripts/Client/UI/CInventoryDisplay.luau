-- SvnHotbar 的展示与输入适配；只消费格子快照和真实格号映射。
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local FX, FC = _G.FX, _G.FC
local FXLoader = FX.Loader
local Text = FX.Text
local Drag = FXLoader:RequireFromParent(script, "CInventoryDrag")
local Display = {}
Display.__index = Display

local TranslationTexts = Text.Define("Y2Inventory", {
    Empty = "No items in the backpack.",
    EmptyCategory = "No items in this category.",
    All = "All",
})

local AllTab = {id = "All", label = TranslationTexts.All}
local DesignHeight = 720
local HorizontalMargin = 24
local SlotSize = 64
local SlotGap = 4
local PanelColor = Color3.fromRGB(17, 19, 22)
local ControlColor = Color3.fromRGB(42, 46, 52)
local OutlineColor = Color3.fromRGB(8, 9, 11)
local TextColor = Color3.fromRGB(246, 247, 248)
local TopbarButtonSize = 40
local TopbarPadding = 8
local TopbarCenterOffsetY = 5
local TopbarDark = Color3.fromRGB(27, 29, 32)
local TopbarLight = Color3.fromRGB(240, 243, 246)

local keyCodes = {Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five,
    Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine, Enum.KeyCode.Zero}

--- 按布局倍率缩放像素偏移，保留屏幕锚点使用的比例分量。
--- @param value UDim2 设计态的位置或尺寸。
--- @param scale number 响应式布局倍率。
--- @return UDim2 缩放后的布局值。
local function scaleOffsets(value, scale)
    return UDim2.new(value.X.Scale, value.X.Offset * scale, value.Y.Scale, value.Y.Offset * scale)
end

--- 给浅色文字加深色描边，让文字在明亮场景上仍清晰。
--- @param label GuiObject 要描边的文本节点。
--- @param thickness number 描边的设计像素宽度。
local function outlineText(label, thickness)
    local stroke = label:FindFirstChild("TextOutline") or Instance.new("UIStroke")
    stroke.Name = "TextOutline"
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
    stroke.Thickness = thickness
    stroke.Color = OutlineColor
    stroke.Parent = label
end

--- 沿用原面板和格子列表，替换它们在玩家界面里的外观与布局。
--- @param bar Frame 快捷栏容器。
--- @param panel Frame 背包面板。
--- @param list ScrollingFrame 背包格子列表。
local function styleInventory(bar, panel, list)
    bar.BackgroundTransparency = 1
    bar.Size = UDim2.fromOffset(0, SlotSize)
    bar.Position = UDim2.new(0.5, 0, 1, -8)
    FXLoader:Here(bar, "UIStroke").Enabled = false
    FXLoader:Here(bar, "UIListLayout").Padding = UDim.new(0, SlotGap)
    local barPadding = FXLoader:Here(bar, "UIPadding")
    barPadding.PaddingTop = UDim.new(0, 0)
    barPadding.PaddingBottom = UDim.new(0, 0)
    barPadding.PaddingLeft = UDim.new(0, 0)
    barPadding.PaddingRight = UDim.new(0, 0)

    panel.Size = UDim2.fromOffset(724, 304)
    panel.Position = UDim2.new(0.5, 0, 1, -(SlotSize + 20))
    panel.BackgroundColor3 = PanelColor
    panel.BackgroundTransparency = 0.24
    FXLoader:Here(panel, "UIGradient").Enabled = false
    FXLoader:Here(panel, "UICorner").CornerRadius = UDim.new(0, 18)
    local panelStroke = FXLoader:Here(panel, "UIStroke")
    panelStroke.Color = OutlineColor
    panelStroke.Transparency = 0.28
    FXLoader:Here(panelStroke, "UIGradient").Enabled = false
    local panelPadding = FXLoader:Here(panel, "UIPadding")
    panelPadding.PaddingTop = UDim.new(0, 12)
    panelPadding.PaddingBottom = UDim.new(0, 12)
    panelPadding.PaddingLeft = UDim.new(0, 18)
    panelPadding.PaddingRight = UDim.new(0, 18)

    FXLoader:Here(panel, "TitleIcon").Visible = false
    FXLoader:Here(panel, "Divider").Visible = false
    local title = FXLoader:Here(panel, "Title")
    title.Position = UDim2.fromOffset(3, 0)
    title.Size = UDim2.new(1, -160, 0, 36)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 22
    title.TextColor3 = TextColor
    title.TextTruncate = Enum.TextTruncate.AtEnd
    outlineText(title, 2)

    local empty = FXLoader:Here(panel, "Empty")
    empty.AnchorPoint = Vector2.new(0.5, 0.5)
    empty.Position = UDim2.fromScale(0.5, 0.55)
    empty.Size = UDim2.new(1, -20, 0, 42)
    empty.Font = Enum.Font.GothamBold
    empty.TextColor3 = Color3.fromRGB(205, 208, 215)
    empty.TextSize = 22
    empty.TextWrapped = true
    empty.ZIndex = 2
    outlineText(empty, 2)

    list.Position = UDim2.fromOffset(0, 46)
    list.Size = UDim2.new(1, 0, 1, -46)
    list.CanvasSize = UDim2.fromOffset(0, 0)
    list.AutomaticCanvasSize = Enum.AutomaticSize.None
    local grid = FXLoader:Here(list, "UIGridLayout")
    grid.CellSize = UDim2.fromOffset(SlotSize, SlotSize)
    grid.CellPadding = UDim2.fromOffset(SlotGap, SlotGap)
end

--- 为快捷格和背包格绑定图标、变异角标和绿色堆叠数量。
--- @param button GuiButton 快捷格或可回收的背包格。
--- @return table 按钮及其显示节点。
local function bindSlot(button)
    button.BackgroundColor3 = PanelColor
    FXLoader:Here(button, "UIGradient").Enabled = false
    FXLoader:Here(button, "UICorner").CornerRadius = UDim.new(0, 11)
    FXLoader:Here(button, "Hover").BackgroundColor3 = ControlColor
    local border = FXLoader:Here(button, "UIStroke")
    border.Thickness = 1.5
    border.Color = OutlineColor
    FXLoader:Here(border, "UIGradient").Enabled = false

    local key = FXLoader:Here(button, "Key")
    key.AnchorPoint = Vector2.new(0, 1)
    key.Position = UDim2.new(0, 5, 1, -4)
    key.Font = Enum.Font.GothamBold
    key.TextSize = 14
    key.TextColor3 = TextColor
    key.TextTransparency = 0
    local count = key:Clone()
    count.Name = "Count"
    count.AnchorPoint = Vector2.new(1, 1)
    count.Position = UDim2.new(1, -4, 1, -5)
    count.Size = UDim2.new(1, -8, 0, 14)
    count.TextXAlignment = Enum.TextXAlignment.Right
    count.TextColor3 = Color3.fromRGB(117, 255, 82)
    count.Text = ""
    count.Visible = true
    count.Parent = button
    outlineText(key, 2)
    outlineText(count, 2)

    local indicator = FXLoader:Here(button, "Indicator")
    indicator.Size = UDim2.new(.6, 0, indicator.Size.Y.Scale, indicator.Size.Y.Offset)
    indicator.BackgroundColor3 = Color3.fromRGB(159, 234, 255)
    local name = FXLoader:Here(button, "ToolName")
    name.AutoLocalize = false
    name.Size = UDim2.new(1, -8, 1, -20)
    name.Position = UDim2.fromScale(0.5, 0.44)
    local icon = FXLoader:Here(button, "Icon")
    icon.ScaleType = Enum.ScaleType.Fit
    icon.Size = UDim2.fromScale(0.72, 0.72)
    icon.Position = UDim2.fromScale(0.5, 0.46)
    local badge = Instance.new("Frame")
    badge.Name = "MutationBadge"
    badge.AnchorPoint = Vector2.new(1, 0)
    badge.Position = UDim2.new(1, -3, 0, 3)
    badge.Size = UDim2.fromOffset(26, 26)
    badge.BackgroundColor3 = OutlineColor
    badge.BackgroundTransparency = 1
    badge.BorderSizePixel = 0
    badge.ZIndex = icon.ZIndex + 1
    badge.Interactable = false
    badge.Visible = false
    badge.Parent = button
    local badgeCorner = Instance.new("UICorner")
    badgeCorner.CornerRadius = UDim.new(0, 6)
    badgeCorner.Parent = badge
    local badgeImage = Instance.new("ImageLabel")
    badgeImage.Name = "Icon"
    badgeImage.BackgroundTransparency = 1
    badgeImage.Position = UDim2.fromOffset(2, 2)
    badgeImage.Size = UDim2.new(1, -4, 1, -4)
    badgeImage.ScaleType = Enum.ScaleType.Fit
    badgeImage.ZIndex = badge.ZIndex + 1
    badgeImage.Interactable = false
    badgeImage.Parent = badge
    --- 专用图片加载前保持透明，避免角标先露出空底框。
    local function refreshBadgeImage()
        badge.BackgroundTransparency = if badgeImage.IsLoaded then 0 else 1
    end
    badgeImage:GetPropertyChangedSignal("IsLoaded"):Connect(refreshBadgeImage)
    return {
        button = button,
        border = border,
        icon = icon,
        badge = badge,
        badgeImage = badgeImage,
        refreshBadgeImage = refreshBadgeImage,
        name = name,
        count = count,
        indicator = indicator,
    }
end

--- 刷新格子的名称、角标和堆叠数量，单件不显示数量。
--- @param cell table 格子的显示节点。
--- @param slot table? 该格当前展示的道具快照。
local function renderSlot(cell, slot)
    cell.icon.Image = slot and slot.icon or ""
    cell.badgeImage.Image = slot and slot.badgeIcon or ""
    cell.badge.Visible = cell.badgeImage.Image ~= ""
    cell.refreshBadgeImage()
    cell.name.Text = if slot and slot.icon == "" then
        (if slot.label then Text.Tr(slot.label) else Text.TrSource(slot.name)) else ""
    cell.count.Text = slot and slot.count and slot.count > 1 and ("X" .. tostring(slot.count)) or ""
    local equipped = slot ~= nil and slot.equipped
    local selected = equipped and cell.isShortcut == true
    cell.indicator.Visible = equipped and not selected
    cell.button.BackgroundTransparency = if slot then 0.3 else 0.48
    cell.border.Color = if selected then Color3.new(1, 1, 1) else OutlineColor
    cell.border.Thickness = if selected then 3.5 else 1.5
    cell.border.Transparency = if selected then 0 else 0.38
    cell.button.ZIndex = if selected then 2 else 1
end

--- 背包入口单独占用顶栏安全区，空快捷栏不会带走入口。
--- @param root ScreenGui 快捷栏所属的界面。
--- @param bagButton ImageButton 提供现有背包图标的模板。
--- @return ScreenGui 顶栏按钮所属界面。
--- @return ImageButton 背包切换按钮。
--- @return ImageLabel 随面板开关反色的背包图标。
local function createTopbarButton(root, bagButton)
    local topbar = Instance.new("ScreenGui")
    topbar.Name = "InventoryTopbar"
    topbar.ResetOnSpawn = false
    topbar.DisplayOrder = root.DisplayOrder + 1
    topbar.Enabled = root.Enabled

    local button = Instance.new("ImageButton")
    button.Name = "BackpackToggle"
    button.AnchorPoint = Vector2.new(0, 0.5)
    button.Size = UDim2.fromOffset(TopbarButtonSize, TopbarButtonSize)
    button.BackgroundColor3 = TopbarDark
    button.BackgroundTransparency = 0.08
    button.BorderSizePixel = 0
    button.Parent = topbar

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.5, 0)
    corner.Parent = button

    local icon = Instance.new("ImageLabel")
    icon.Name = "BackpackIcon"
    icon.Image = bagButton.Image
    icon.ImageColor3 = TopbarLight
    icon.ScaleType = Enum.ScaleType.Fit
    icon.BackgroundTransparency = 1
    icon.AnchorPoint = Vector2.new(0.5, 0.5)
    icon.Position = UDim2.fromScale(0.5, 0.5)
    icon.Size = UDim2.fromScale(0.55, 0.55)
    icon.Parent = button
    topbar.Parent = root.Parent
    return topbar, button, icon
end

--- 按实际可见格数计算快捷栏宽度；空格只在打开背包时显示。
function Display:_RefreshShortcutVisibility()
    local hasShortcutItem = false
    local visibleCount = 0
    for grid, cell in ipairs(self._shortcutCells) do
        local occupied = self._slots[grid] ~= nil
        hasShortcutItem = hasShortcutItem or occupied
        cell.button.Visible = occupied or self._panel.Visible
        if cell.button.Visible then
            visibleCount += 1
        end
    end
    local canDragFromBackpack = self._panel.Visible and self._usedBackpackSlots > 0 and self._shortcutCapacity > 0
    self._bar.Visible = hasShortcutItem or canDragFromBackpack
    self._visibleShortcutCount = visibleCount
    self._resize()
end

--- 分类放到标题下方，让空提示和物品区域都对齐面板中心。
--- @param list ScrollingFrame 背包格子列表。
function Display:_CreateBackpackTabs(list)
    local tabs = Instance.new("ScrollingFrame")
    tabs.Name = "FilterTabs"
    tabs.BackgroundTransparency = 1
    tabs.BorderSizePixel = 0
    tabs.ScrollingDirection = Enum.ScrollingDirection.X
    tabs.ScrollBarThickness = 2
    tabs.CanvasSize = UDim2.fromOffset(0, 0)
    tabs.AutomaticCanvasSize = Enum.AutomaticSize.X
    tabs.Position = list.Position
    tabs.Size = UDim2.new(1, 0, 0, 34)
    tabs.Parent = self._panel
    self._tabs = tabs
    list.Position += UDim2.fromOffset(0, 42)
    list.Size -= UDim2.fromOffset(0, 42)

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.Padding = UDim.new(0, 6)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = tabs
    for index, tab in ipairs(self._backpackTabs) do
        local button = Instance.new("TextButton")
        button.Name = tab.id .. "Tab"
        button.AutoLocalize = false
        button.AutoButtonColor = false
        button.BorderSizePixel = 0
        button.Font = Enum.Font.GothamMedium
        button.TextSize = 14
        button.TextTruncate = Enum.TextTruncate.AtEnd
        button.Size = UDim2.fromOffset(124, 30)
        button.LayoutOrder = index
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = button
        button.Activated:Connect(function()
            if self._activeTab == tab then
                return
            end
            self:_SelectBackpackTab(tab)
        end)
        button.Parent = tabs
        self._tabButtons[index] = button
    end
end

--- 切换实际筛选时，使旧页签上发起的拖入反馈失效。
--- @param tab table 要显示的背包页签。
function Display:_SelectBackpackTab(tab)
    self._drag:Cancel()
    self._activeTab = tab
    self._backpackViewRevision += 1
    self._backpackList.CanvasPosition = Vector2.zero
    self:_RefreshBackpack()
end

--- 只把有道具的真实格号交给虚拟列表，首个空格号只用于拖拽落点。
function Display:_RefreshBackpack()
    local activeTab = self._activeTab
    local showAll = activeTab == AllTab
    local grids = self._backpackGrids
    self._firstEmptyBackpackGrid = nil
    table.clear(grids)
    for index = 1, self._backpackCapacity do
        local grid = self._shortcutCapacity + index
        local slot = self._slots[grid]
        if slot and (showAll or activeTab.matches(slot)) then
            table.insert(grids, grid)
        elseif not slot and not self._firstEmptyBackpackGrid then
            self._firstEmptyBackpackGrid = grid
        end
    end

    for index, button in ipairs(self._tabButtons) do
        local tab = self._backpackTabs[index]
        local selected = tab == activeTab
        button.Text = Text.Tr(tab.label)
        button.BackgroundColor3 = if selected then Color3.fromRGB(60, 66, 74) else ControlColor
        button.TextColor3 = TextColor
    end
    local empty = #grids == 0
    self._emptyLabel.Visible = empty
    if empty then
        self._emptyLabel.Text = Text.Tr(if showAll then TranslationTexts.Empty else TranslationTexts.EmptyCategory)
    end
    if self._panel.Visible then
        self:_RefreshBackpackGrid()
    end
end

--- 按实际道具数调整画布，滚动或筛选时复用同一批格子及输入监听。
function Display:_RefreshBackpackGrid()
    if not self._panel.Visible then
        return
    end
    local list = self._backpackList
    local grids = self._backpackGrids
    local cells = self._backpackCells
    local visibleCount = 0
    if #grids == 0 then
        list.CanvasSize = UDim2.fromOffset(0, 0)
        list.CanvasPosition = Vector2.zero
    else
        local window = list.AbsoluteWindowSize
        if window.X <= 0 or window.Y <= 0 then
            return
        end
        local scale = self._panelScale.Scale
        local padding = self._backpackPadding
        local left, right = padding.PaddingLeft.Offset, padding.PaddingRight.Offset
        local top, bottom = padding.PaddingTop.Offset, padding.PaddingBottom.Offset
        local step = SlotSize + SlotGap
        local columns = math.max(1, math.floor((window.X / scale - left - right + SlotGap) / step))
        local rows = math.ceil(#grids / columns)
        local canvasHeight = top + bottom + rows * step - SlotGap
        list.CanvasSize = UDim2.fromOffset(0, canvasHeight)
        local windowHeight = window.Y / scale
        local scrollTop = math.min(list.CanvasPosition.Y / scale, math.max(0, canvasHeight - windowHeight))
        local firstRow = math.max(0, math.floor((scrollTop - top) / step) - 1)
        local lastRow = math.min(rows - 1, math.ceil((scrollTop + windowHeight - top) / step))
        local lastIndex = math.min(#grids, (lastRow + 1) * columns)
        for index = firstRow * columns + 1, lastIndex do
            visibleCount += 1
            local cell = cells[visibleCount]
            if not cell then
                cell = self:_CreateBackpackCell()
                cells[visibleCount] = cell
            end
            local column = (index - 1) % columns
            local row = math.floor((index - 1) / columns)
            cell.grid = grids[index]
            cell.button.Position = UDim2.fromOffset(left + column * step, top + row * step)
            renderSlot(cell, self._slots[cell.grid])
            cell.button.Visible = true
        end
    end
    for index = visibleCount + 1, #cells do
        local cell = cells[index]
        cell.grid = nil
        cell.button.Visible = false
    end
end

--- 格子首次进入池时绑定输入，滚动和换页只更换它对应的真实格号。
--- @return table 可复用的背包格子。
function Display:_CreateBackpackCell()
    local list = self._backpackList
    local button = self._templateButton:Clone()
    button.Visible = false
    button.Size = UDim2.fromOffset(SlotSize, SlotSize)
    FXLoader:Here(button, "Key").Visible = false
    local cell = bindSlot(button)
    self._drag:RegisterSlot(button, function()
        return cell.grid
    end, list)
    button.Parent = list
    return cell
end

--- 接管现有 SvnHotbar 的展示，不依赖库存存档或网络协议。
--- @param root ScreenGui 当前玩家的 SvnHotbar。
--- @param config table 槽位容量、背包分类及独立木棍格的选择回调。
--- 页签按数组顺序创建，每项包含唯一 id、Text.Define 文案 label 和筛选函数 matches(slot)。
--- All 由展示层创建；不提供分类时保留原背包布局。
--- @param onSelect function 库存格点击或快捷格按键回调。
--- @param onSwap function 拖拽交换回调。
--- @return table 背包展示对象。
function Display.new(root, config, onSelect, onSwap)
    local self = setmetatable({
        _slots = {},
        _shortcutCells = {},
        _createdShortcuts = {},
        _shortcutCapacity = config.shortcutCapacity,
        _backpackCapacity = config.backpackCapacity,
        _usedBackpackSlots = 0,
        _activeTab = AllTab,
        _tabButtons = {},
        _backpackGrids = {},
        _backpackCells = {},
        _backpackViewRevision = 0,
    }, Display)
    local bar = FXLoader:Here(root, "Bar")
    local bagBox = FXLoader:Here(bar, "BagBox")
    local bagButton = FXLoader:Here(bagBox, "BagButton")
    local handle = FXLoader:Here(root, "Handle")
    local panel = FXLoader:Here(root, "Inventory")
    local list = FXLoader:Here(panel, "List")
    self._bar = bar
    self._panel = panel
    self._backpackList = list
    self._countLabel = FXLoader:Here(panel, "Count")
    self._emptyLabel = FXLoader:Here(panel, "Empty")
    self._emptyLabel.AutoLocalize = false
    styleInventory(bar, panel, list)
    panel.Visible = false
    bar.Visible = false
    bagBox.Visible = false
    handle.Visible = false

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
    end, onSelect, function(sourceGrid, targetGrid, slot)
        local tab = self._activeTab
        local reveal
        if self._panel.Visible and targetGrid == self._firstEmptyBackpackGrid
            and tab ~= AllTab and not tab.matches(slot) then
            local revision = self._backpackViewRevision
            reveal = function()
                if self._backpackViewRevision == revision then
                    self:_SelectBackpackTab(AllTab)
                end
            end
        end
        onSwap(sourceGrid, targetGrid, slot, reveal)
    end)

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
        button.Size = UDim2.fromOffset(SlotSize, SlotSize)
        local key = FXLoader:Here(button, "Key")
        key.Visible = keyCodes[grid] ~= nil
        if key.Visible then
            key.Text = tostring(grid % 10)
        end
        local cell = bindSlot(button)
        cell.isShortcut = true
        self._shortcutCells[grid] = cell
        self._drag:RegisterSlot(button, function()
            return grid
        end)
    end

    local panelScale = FXLoader:Here(panel, "Scale")
    self._panelScale = panelScale
    if config.backpackCapacity > 0 then
        self._backpackLayout = FXLoader:Here(list, "UIGridLayout")
        self._backpackPadding = FXLoader:Here(list, "UIPadding")
        self._backpackLayout.Parent = nil
        self._backpackPadding.Parent = nil
        if config.backpackTabs and #config.backpackTabs > 0 then
            self._backpackTabs = table.clone(config.backpackTabs)
            table.insert(self._backpackTabs, 1, AllTab)
            self:_CreateBackpackTabs(list)
        end
        self._drag:RegisterDropArea(list, function()
            return self._firstEmptyBackpackGrid
        end)
    end

    local barScale = FXLoader:Here(bar, "Scale")
    local barCount = config.shortcutCapacity
    local barWidth = SlotSize * barCount + SlotGap * math.max(0, barCount - 1)
    local contentWidth = math.max(barWidth, panel.Size.X.Offset)
    local originalInsets = root.ScreenInsets
    local scales = {
        {node = bar, scale = barScale, position = bar.Position, baseScale = barScale.Scale},
        {node = panel, scale = panelScale, position = panel.Position, baseScale = panelScale.Scale},
    }
    root.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
    --- 桌面沿用原缩放；触屏快捷栏独立按可见格数适配宽度，并给底边留出触控空间。
    local function resize()
        local size = root.AbsoluteSize
        if size.X <= 0 or size.Y <= 0 then
            return
        end
        local scale = math.min(1.4, size.X / (contentWidth + HorizontalMargin), size.Y / DesignHeight)
        local barEntry, panelEntry = scales[1], scales[2]
        local touchEnabled = UserInputService.TouchEnabled
        local shortcutScale = scale
        local bottomGap = -barEntry.position.Y.Offset * scale
        if touchEnabled then
            local count = math.max(1, self._visibleShortcutCount or barCount)
            local visibleWidth = SlotSize * count + SlotGap * (count - 1)
            shortcutScale = math.min(1.2, math.max(1, size.Y / DesignHeight),
                math.max(1, size.X - HorizontalMargin) / (visibleWidth * barEntry.baseScale))
            bottomGap = 16
        end
        bar.Position = UDim2.new(0.5, 0, 1, -bottomGap)
        barScale.Scale = barEntry.baseScale * shortcutScale
        local panelPosition = scaleOffsets(panelEntry.position, scale)
        if touchEnabled then
            panelPosition = UDim2.new(0.5, 0, 1, -(bottomGap + SlotSize * barScale.Scale + 12))
        end
        panel.Position = panelPosition
        panelScale.Scale = panelEntry.baseScale * scale
    end
    self._resize = resize
    self._restoreLayout = function()
        root.ScreenInsets = originalInsets
        for _, entry in ipairs(scales) do
            entry.node.Position = entry.position
            entry.scale.Scale = entry.baseScale
        end
    end
    self._connections = {
        root:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize),
        UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(resize),
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
    if self._backpackCapacity > 0 then
        local function refreshGrid()
            self:_RefreshBackpackGrid()
        end
        table.insert(self._connections, list:GetPropertyChangedSignal("CanvasPosition"):Connect(refreshGrid))
        table.insert(self._connections, list:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(refreshGrid))
        table.insert(self._connections, panelScale:GetPropertyChangedSignal("Scale"):Connect(refreshGrid))
        local close = Instance.new("TextButton")
        close.Name = "CloseBackpack"
        close.AutoLocalize = false
        close.AnchorPoint = Vector2.new(1, 0)
        close.Position = UDim2.fromScale(1, 0)
        close.Size = UDim2.fromOffset(36, 36)
        close.BackgroundColor3 = Color3.fromRGB(224, 23, 30)
        close.BorderSizePixel = 0
        close.Font = Enum.Font.GothamBold
        close.Text = "×"
        close.TextSize = 28
        close.TextColor3 = TextColor
        close.Parent = panel
        outlineText(close, 2)
        local closeCorner = Instance.new("UICorner")
        closeCorner.CornerRadius = UDim.new(0, 10)
        closeCorner.Parent = close
        local border = Instance.new("UIStroke")
        border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        border.Thickness = 3
        border.Color = OutlineColor
        border.Parent = close
        self._closeButton = close

        local count = self._countLabel
        count.Position = UDim2.new(1, -46, 0, 0)
        count.Size = UDim2.fromOffset(94, 36)
        count.BackgroundColor3 = ControlColor
        count.BackgroundTransparency = 0.12
        count.BorderSizePixel = 0
        count.Font = Enum.Font.GothamBold
        count.TextColor3 = TextColor
        count.TextSize = 15
        count.TextXAlignment = Enum.TextXAlignment.Center
        local countCorner = count:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
        countCorner.CornerRadius = UDim.new(0, 10)
        countCorner.Parent = count
        table.insert(self._connections, close.Activated:Connect(function()
            self:ToggleBackpack()
        end))

        local topbar, button, icon = createTopbarButton(root, bagButton)
        self._topbar = topbar
        self._topbarButton = button
        self._topbarIcon = icon
        local topNav = FXLoader:Here(root.Parent, "Main.HUD.TopNav")

        --- 对齐 Roblox 顶栏按钮的中心并避开主导航；顶栏放不下时移到左下方。
        local function positionTopbarButton()
            local area = GuiService:GetInsetArea(Enum.ScreenInsets.TopbarSafeInsets)
            local navMin = topNav.AbsolutePosition
            local navMax = navMin + topNav.AbsoluteSize
            local halfButton = TopbarButtonSize / 2

            --- 使用与顶栏安全区相同的坐标比较按钮和主导航，并留出间距。
            --- @param left number 按钮左边界。
            --- @param top number 按钮上边界。
            --- @return boolean 按钮是否碰到主导航。
            local function overlapsNavigation(left, top)
                return left < navMax.X + TopbarPadding
                    and left + TopbarButtonSize + TopbarPadding > navMin.X
                    and top < navMax.Y + TopbarPadding
                    and top + TopbarButtonSize + TopbarPadding > navMin.Y
            end

            local topbarLeft = area.Min.X + TopbarPadding
            -- 原生按钮的中心比安全区中线略低，空间不足时仍把按钮留在安全区内。
            local centerY = math.min(area.Height / 2 + TopbarCenterOffsetY, area.Height - halfButton)
            local topbarTop = area.Min.Y + centerY - halfButton
            if area.Width >= TopbarButtonSize + TopbarPadding and area.Height >= TopbarButtonSize
                and not overlapsNavigation(topbarLeft, topbarTop) then
                topbar.ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets
                button.Position = UDim2.fromOffset(TopbarPadding, centerY)
            else
                local fallbackTop = TopbarPadding
                if overlapsNavigation(TopbarPadding, fallbackTop) then
                    fallbackTop = navMax.Y + TopbarPadding
                end
                topbar.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
                button.Position = UDim2.fromOffset(TopbarPadding, fallbackTop + halfButton)
            end
        end

        table.insert(self._connections, GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(positionTopbarButton))
        table.insert(self._connections, topNav:GetPropertyChangedSignal("AbsolutePosition"):Connect(positionTopbarButton))
        table.insert(self._connections, topNav:GetPropertyChangedSignal("AbsoluteSize"):Connect(positionTopbarButton))
        table.insert(self._connections, root:GetPropertyChangedSignal("Enabled"):Connect(function()
            topbar.Enabled = root.Enabled
        end))
        table.insert(self._connections, button.Activated:Connect(function()
            self:ToggleBackpack()
        end))
        positionTopbarButton()
    end
    resize()
    return self
end

--- 打开时刷新视口；关闭时回收当前输入状态。
--- @param visible boolean? 显式指定显隐；省略时切换。
function Display:ToggleBackpack(visible)
    if self._backpackCapacity == 0 or visible == self._panel.Visible then
        return
    end
    self._panel.Visible = if visible == nil then not self._panel.Visible else visible
    self._backpackViewRevision += 1
    self:_RefreshShortcutVisibility()
    self._topbarButton.BackgroundColor3 = if self._panel.Visible then TopbarLight else TopbarDark
    self._topbarIcon.ImageColor3 = if self._panel.Visible then TopbarDark else TopbarLight
    if self._panel.Visible then
        self:_RefreshBackpackGrid()
    else
        self._drag:Cancel()
    end
end

--- 每次只绘制快捷栏和当前虚拟格子。
--- @param slots table 按真实格号索引的道具显示快照。
--- @param usedBackpackSlots number 背包区域的已用格数。
function Display:Render(slots, usedBackpackSlots)
    self._slots = slots
    self._usedBackpackSlots = usedBackpackSlots
    for grid, cell in ipairs(self._shortcutCells) do
        renderSlot(cell, slots[grid])
    end
    self:_RefreshShortcutVisibility()
    self._countLabel.Text = string.format("%d / %d", usedBackpackSlots, self._backpackCapacity)
    if self._backpackCapacity > 0 then
        self:_RefreshBackpack()
    end
end

--- 清理展示对象拥有的节点与监听。
function Display:Destroy()
    for _, connection in ipairs(self._connections) do
        connection:Disconnect()
    end
    self._drag:Destroy()
    if self._topbar then
        self._topbar:Destroy()
        self._closeButton:Destroy()
    end
    if self._tabs then
        self._tabs:Destroy()
    end
    if self._backpackLayout then
        for _, cell in ipairs(self._backpackCells) do
            cell.button:Destroy()
        end
        self._backpackList.CanvasSize = UDim2.fromOffset(0, 0)
        self._backpackLayout.Parent = self._backpackList
        self._backpackPadding.Parent = self._backpackList
    end
    self._restoreLayout()
    for _, cell in ipairs(self._shortcutCells) do
        cell.count:Destroy()
        cell.badge:Destroy()
    end
    for _, button in ipairs(self._createdShortcuts) do
        button:Destroy()
    end
    self._templateButton:Destroy()
    self._dragLayer:Destroy()
end

return Display
