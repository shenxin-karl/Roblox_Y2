-- 固定格尺寸的纵向虚拟网格，只保留视口和上下各一行所需的节点。
local Grid = {}
Grid.__index = Grid

--- 接管普通滚动容器的布局；节点创建和内容绑定由调用方负责。
--- @param list ScrollingFrame 纵向滚动容器。
--- @param layout UIGridLayout 提供固定像素格尺寸及间距的布局模板。
--- @param padding UIPadding 提供固定像素内边距。
--- @param scale UIScale 滚动容器所在面板的缩放。
--- @param count number 展示格数。
--- @param createCell function 返回包含 button 的可复用格子。
--- @param bindCell function 接收格子和当前显示索引。
--- @return table 虚拟网格。
function Grid.new(list, layout, padding, scale, count, createCell, bindCell)
    local self = setmetatable({
        _list = list,
        _layout = layout,
        _padding = padding,
        _scale = scale,
        _count = count,
        _createCell = createCell,
        _bindCell = bindCell,
        _cells = {},
        _originalCanvasSize = list.CanvasSize,
        _originalAutomaticCanvasSize = list.AutomaticCanvasSize,
    }, Grid)
    layout.Parent = nil
    padding.Parent = nil
    list.AutomaticCanvasSize = Enum.AutomaticSize.None
    local function refresh()
        self:Refresh()
    end
    self._connections = {
        list:GetPropertyChangedSignal("CanvasPosition"):Connect(refresh),
        list:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(refresh),
        scale:GetPropertyChangedSignal("Scale"):Connect(refresh),
    }
    return self
end

--- 按可视行计算画布与格子池；滚动只更新显示索引，不改实际库存位置。
function Grid:Refresh()
    local list = self._list
    local window = list.AbsoluteWindowSize
    if window.X <= 0 or window.Y <= 0 then
        return
    end

    local scale = self._scale.Scale
    local cellSize, gap = self._layout.CellSize, self._layout.CellPadding
    local width, height = cellSize.X.Offset, cellSize.Y.Offset
    local stepX, stepY = width + gap.X.Offset, height + gap.Y.Offset
    local padding = self._padding
    local left, right = padding.PaddingLeft.Offset, padding.PaddingRight.Offset
    local top, bottom = padding.PaddingTop.Offset, padding.PaddingBottom.Offset
    local columns = math.max(1, math.floor((window.X / scale - left - right + gap.X.Offset) / stepX))
    local rows = math.ceil(self._count / columns)
    local canvasHeight = top + bottom + math.max(0, rows * stepY - gap.Y.Offset)
    local canvasSize = UDim2.fromOffset(0, canvasHeight)
    if list.CanvasSize ~= canvasSize then
        list.CanvasSize = canvasSize
    end

    local windowHeight = window.Y / scale
    local scrollTop = math.clamp(list.CanvasPosition.Y / scale, 0, math.max(0, canvasHeight - windowHeight))
    local firstRow = math.max(0, math.floor((scrollTop - top) / stepY) - 1)
    local lastRow = math.min(rows - 1, math.ceil((scrollTop + windowHeight - top) / stepY))
    local firstIndex = firstRow * columns + 1
    local lastIndex = math.min(self._count, (lastRow + 1) * columns)
    local visibleCount = math.max(0, lastIndex - firstIndex + 1)

    for poolIndex = 1, visibleCount do
        local cell = self._cells[poolIndex]
        if not cell then
            cell = self._createCell()
            cell.button.Parent = list
            self._cells[poolIndex] = cell
        end
        local index = firstIndex + poolIndex - 1
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        cell.button.Position = UDim2.fromOffset(left + column * stepX, top + row * stepY)
        cell.button.Size = UDim2.fromOffset(width, height)
        self._bindCell(cell, index)
        cell.button.Visible = true
    end
    for poolIndex = visibleCount + 1, #self._cells do
        local cell = self._cells[poolIndex]
        self._bindCell(cell, nil)
        cell.button.Visible = false
    end
end

--- 释放格子池和滚动监听，恢复调用方的原布局。
function Grid:Destroy()
    for _, connection in ipairs(self._connections) do
        connection:Disconnect()
    end
    for _, cell in ipairs(self._cells) do
        cell.button:Destroy()
    end
    self._layout.Parent = self._list
    self._padding.Parent = self._list
    self._list.CanvasSize = self._originalCanvasSize
    self._list.AutomaticCanvasSize = self._originalAutomaticCanvasSize
end

return Grid
