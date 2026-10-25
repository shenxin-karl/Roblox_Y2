--[[
    服务端玩家背包组件:
    提供玩家背包和快捷栏的物品管理功能。
    数据格式: { {itemId = 1001, count = 1}, ... }，1-N个为快捷栏，N+1 以后是背包
    配置: shortcutCapacity(默认8), inventoryCapacity(默认50), kvType, storeKey
    priority参数: 0优先快捷栏, 1优先背包
]]

local FX, FS = _G.FX, _G.FS
local FXTable = FX.Table
local FXLog = FX.Log

local FSInventoryCompClass = FX.Class("FSInventoryCompClass", "FSPlayerCompClass")

function FSInventoryCompClass:GetConfig()
    --[[
        return {
            storeTableVarEnum = ...,    -- 存储在什么kv表中, 比如 "InventoryData"
            shortcutCapacity = 8,       -- 快捷栏容量, 比如8
            inventoryCapacity = 50,     -- 背包容量, 比如50
        }
    ]]
    error("GetConfig not implemented")
end

-- 数据变化时由项目组件同步原生 Tool。
function FSInventoryCompClass:OnAllChanged() end

-- 获取组件名称
function FSInventoryCompClass:GetCompName()
    return "FSInventoryComp"
end

--[[
格子数据
gridData = {
    itemId = 道具Id,
    stackCount = 数量
    extraData = 额外数据   -- 当前道具的额外数据, 比如 buff 等
}
]]

-- 获取数据, 格式为 { { itemId = xxx, stackCount = xx, extraData = xxx } ... }
-- 前 N 个是快捷栏的数据, 后 M 个是背包的数据
-- N + M = 总容量
--- 存档使用字符串格号，算法入口还原为数字索引。
--- @return table 独立的背包数据副本。
function FSInventoryCompClass:_GetData()
    local result = {}
    for key, value in pairs(self:GetTable(self:GetConfig().storeTableVarEnum)) do
        result[tonumber(key)] = value
    end
    return result
end
-- 设置数据, 格式为 { { itemId = xxx, stackCount = xx, extraData = xxx } ... }
--- 避免 DataStore 与 RemoteEvent 截断稀疏数组。
--- @param data table 数字格号索引的数据。
--- @return boolean 是否完成写入。
function FSInventoryCompClass:_SetData(data)
    local serialized = {}
    for key, value in pairs(data) do
        serialized[tostring(key)] = value
    end
    local ret = self:SetTable(self:GetConfig().storeTableVarEnum, serialized)
    return ret
end

--- 排除外部输入的非整数、NaN 和越界格号。
--- @param gridIndex number 格号。
--- @return boolean 是否有效。
function FSInventoryCompClass:_CheckGridIndexValid(gridIndex)
    if not gridIndex then
        return false
    end
    return type(gridIndex) == "number"
        and gridIndex == gridIndex
        and gridIndex % 1 == 0
        and gridIndex >= 1
        and gridIndex <= self:GetTotalCapacity()
end

-- 获取快捷栏容量
function FSInventoryCompClass:GetShortcutCapacity()
    return self:GetConfig().shortcutCapacity
end
-- 获取背包容量
function FSInventoryCompClass:GetInventoryCapacity()
    return self:GetConfig().inventoryCapacity
end
-- 获取总容量
function FSInventoryCompClass:GetTotalCapacity()
    return self:GetShortcutCapacity() + self:GetInventoryCapacity()
end

-- 获得迭代器遍历信息
-- 返回两个表 分别遍历 快捷栏 和 背包的开始和结束索引
function FSInventoryCompClass:_GetGridIteratorInfoList(type)
    local shortcutCap = self:GetShortcutCapacity()
    local totalCap = self:GetTotalCapacity()
    local shortcutIteratorInfo = { first = 1, last = shortcutCap }
    local inventoryIteratorInfo = { first = shortcutCap + 1, last = totalCap }
    if type == 0 then
        return { shortcutIteratorInfo, inventoryIteratorInfo }
    else
        return { inventoryIteratorInfo, shortcutIteratorInfo }
    end
end

-- 判断是否可以添加物品列表
-- 返回值: 可以添加返回 true, 否则返回 false
-- items: 物品对象列表
--- 用独立模拟数据累计所有待添加堆叠量，保证批量预检不超卖空位。
--- @param items table 道具对象列表。
--- @param removedItems table? 兑换时先按默认快捷栏优先顺序消耗的道具，不修改实际背包。
--- @return boolean 全批道具是否均可容纳。
function FSInventoryCompClass:CanAddItems(items, removedItems)
    for _, itemObject in pairs(items) do
        if not self:CheckItemObjectValid(itemObject) then
            FXLog:ErrorFmt("CanAddItemObjectList failed, itemObject: %s", FXTable:ToString(itemObject))
            return false
        end
    end

    local data = self:_GetData()
    if removedItems then
        for itemIndex, itemObject in ipairs(removedItems) do
            if not self:CheckItemObjectValid(itemObject) then
                return false
            end
            local remaining = itemObject:GetStackCount()
            for gridIndex = 1, self:GetTotalCapacity() do
                local gridData = data[gridIndex]
                if gridData and gridData.itemId == itemObject:GetItemId() then
                    local count = math.min(remaining, gridData.stackCount)
                    gridData.stackCount -= count
                    remaining -= count
                    if gridData.stackCount == 0 then
                        data[gridIndex] = nil
                    end
                    if remaining == 0 then
                        break
                    end
                end
            end
            if remaining > 0 then
                return false
            end
        end
    end
    local dataCopy = {}
    local function canAddItemObject(itemObject)
        local serializedData = itemObject:GetSerializeData()
        local itemConfig = self:GetItemDataConfig(serializedData.itemId)
        local maxStack = serializedData.extraData and 1 or (itemConfig and (itemConfig.MaxStack or 1) or 1)
        local addCount = itemObject:GetStackCount()
        for i = 1, self:GetTotalCapacity() do
            local gridData = dataCopy[i] or data[i]
            if not gridData then
                local canPlace = math.min(addCount, maxStack)
                addCount = addCount - canPlace
                dataCopy[i] = {
                    itemId = serializedData.itemId,
                    stackCount = canPlace,
                    extraData = serializedData.extraData,
                }
                if addCount <= 0 then
                    return true
                end
            else
                gridData = FXTable:Copy(gridData)
                local maxStackableCount = math.min(addCount, self:_GetMaxStackableCount(gridData, serializedData))
                addCount = addCount - maxStackableCount
                gridData.stackCount += maxStackableCount
                dataCopy[i] = gridData
                if addCount <= 0 then
                    return true
                end
            end
        end
        return false
    end
    for _, itemObject in pairs(items) do
        if not canAddItemObject(itemObject) then
            return false
        end
    end
    return true
end

-- 判断是否可以添加物品
-- 返回值: 可以添加返回 true, 否则返回 false
-- item: 物品对象
function FSInventoryCompClass:CanAddItem(item)
    return self:CanAddItems({ item })
end

-- 判断是否可以移除物品
-- 返回值: 可以移除返回 true, 否则返回 false
-- itemId: 物品ID
-- count: 物品数量
function FSInventoryCompClass:CanRemoveItemById(itemId, count)
    local itemObject = FS.ItemClass.New(itemId, count)
    if not self:CheckItemObjectValid(itemObject) then
        FXLog:ErrorFmt("CanRemoveItemById failed, itemId: %d", itemId)
        return false
    end
    return self:GetItemCountById(itemId) >= count
end

-- 判断是否可以移除物品列表
-- 返回值: 可以移除返回 true, 否则返回 false
-- items: 物品对象列表
function FSInventoryCompClass:CanRemoveItems(items)
    local removeCountByItemId = {}
    for _, itemObject in pairs(items) do
        if not self:CheckItemObjectValid(itemObject) then
            FXLog:ErrorFmt("CanRemoveItems failed, itemObject: %s", FXTable:ToString(itemObject))
            return false
        end
        local itemId = itemObject:GetItemId()
        local removeCount = itemObject:GetStackCount()
        removeCountByItemId[itemId] = (removeCountByItemId[itemId] or 0) + removeCount
    end
    if next(removeCountByItemId) == nil then
        return true
    end

    local data = self:_GetData()
    for i = 1, self:GetTotalCapacity() do
        local gridData = data[i]
        if gridData then
            local removeCount = removeCountByItemId[gridData.itemId]
            if removeCount then
                removeCount = removeCount - gridData.stackCount
                if removeCount <= 0 then
                    removeCountByItemId[gridData.itemId] = nil
                    if next(removeCountByItemId) == nil then
                        return true
                    end
                else
                    removeCountByItemId[gridData.itemId] = removeCount
                end
            end
        end
    end
    return false
end

-- 移除物品列表
-- 返回值: 可以移除返回 true, 否则返回 false
-- items: 物品对象列表
-- priority: 0优先快捷栏, 1优先背包
function FSInventoryCompClass:RemoveItems(items, priority)
    if not self:CanRemoveItems(items) then
        return false
    end

    local removeCountByItemId = {}
    for _, itemObject in pairs(items) do
        local itemId = itemObject:GetItemId()
        local removeCount = itemObject:GetStackCount()
        removeCountByItemId[itemId] = (removeCountByItemId[itemId] or 0) + removeCount
    end
    if next(removeCountByItemId) == nil then
        return true
    end

    priority = priority or 0
    local data = self:_GetData()
    local iterInfoList = self:_GetGridIteratorInfoList(priority)

    local function removeItem(context)
        local gridIndex = context.gridIndex
        local gridData = context.gridData
        local removeCount = context.removeCount
        if not gridData or not removeCount then
            return
        end

        local realRemoveCount = math.min(removeCount, gridData.stackCount)
        gridData.stackCount = gridData.stackCount - realRemoveCount
        removeCountByItemId[gridData.itemId] = removeCount - realRemoveCount
        if gridData.stackCount <= 0 then
            data[gridIndex] = nil
        end
        if removeCountByItemId[gridData.itemId] <= 0 then
            removeCountByItemId[gridData.itemId] = nil
        end
    end

    for _, iterInfo in ipairs(iterInfoList) do
        for i = iterInfo.first, iterInfo.last do
            if next(removeCountByItemId) == nil then
                break
            end
            local gridData = data[i]
            local context = {
                gridIndex = i,
                gridData = gridData,
                removeCount = gridData and removeCountByItemId[gridData.itemId],
            }
            removeItem(context)
        end
    end

    if next(removeCountByItemId) ~= nil then
        FXLog:ErrorFmt("RemoveItems failed, items: %s", FXTable:ToString(items))
        return false
    end

    self:_SetData(data)
    return true
end

-- 添加物品
-- 返回值: 添加成功返回 true, 否则返回 false
-- items: 物品对象列表
-- priority: 0优先快捷栏, 1优先背包
--- 预检通过后批量添加，并同步每个发生部分或完整堆叠的格子。
--- @param items table 道具对象列表。
--- @param priority number 0 优先快捷栏，1 优先背包。
--- @return boolean 是否完成整批添加。
function FSInventoryCompClass:AddItems(items, priority)
    if not self:CanAddItems(items) then
        return false
    end
    priority = priority or 0
    local data = self:_GetData()
    local iterInfoList = self:_GetGridIteratorInfoList(priority)

    local function addItem(item)
        -- 第一步先找相同的位置叠加
        local serializedData = item:GetSerializeData()
        local function tryStackItem()
            for _, iterInfo in ipairs(iterInfoList) do
                for i = iterInfo.first, iterInfo.last do
                    local gridData = data[i]
                    if gridData then
                        local complete = self:_StackItem(gridData, serializedData)
                        if complete then
                            return true
                        end
                    end
                end
            end
            return false
        end

        if serializedData.extraData == nil and tryStackItem() then
            return true
        end

        -- 第二步找空位
        local function tryAddItem()
            local itemConfig = self:GetItemDataConfig(serializedData.itemId)
            -- 如果物品有 extraData，最大堆叠数为 1，否则使用配置中的 MaxStack
            local maxStack = serializedData.extraData and 1 or (itemConfig and (itemConfig.MaxStack or 1) or 1)
            local function addToGrid(grid)
                local gridData = data[grid]
                if gridData then
                    return false
                end
                local addCount = math.min(serializedData.stackCount, maxStack)
                data[grid] = {
                    itemId = serializedData.itemId,
                    stackCount = addCount,
                    extraData = serializedData.extraData,
                }
                serializedData.stackCount = serializedData.stackCount - addCount
                return serializedData.stackCount <= 0
            end

            for _, iterInfo in ipairs(iterInfoList) do
                for i = iterInfo.first, iterInfo.last do
                    if addToGrid(i) then
                        return true
                    end
                end
            end
            return false
        end

        if tryAddItem() then
            return true
        end
        assert(false, "AddItem failed, itemObject: %s", tostring(serializedData))
    end

    for _, item in pairs(items) do
        addItem(item)
    end
    local ret = self:_SetData(data)
    return ret
end

-- 添加物品
-- 返回值: 添加成功返回 true, 否则返回 false
-- itemObject: 物品对象列表
-- priority: 0优先快捷栏, 1优先背包
function FSInventoryCompClass:AddItem(item, priority)
    return self:AddItems({ item }, priority)
end

-- 移除物品
-- 返回值: 移除成功返回 true, 否则返回 false
-- itemId: 物品ID
-- count: 物品数量
-- priority: 0优先快捷栏, 1优先背包
function FSInventoryCompClass:RemoveItemById(itemId, count, priority)
    if not self:CanRemoveItemById(itemId, count) then
        return false
    end

    priority = priority or 0
    local data = self:_GetData()
    local remainingCount = count
    local iterInfoList = self:_GetGridIteratorInfoList(priority)

    for _, iterInfo in ipairs(iterInfoList) do
        for i = iterInfo.first, iterInfo.last do
            local gridData = data[i]
            if gridData and gridData.itemId == itemId then
                local removeCount = math.min(remainingCount, gridData.stackCount)
                gridData.stackCount = gridData.stackCount - removeCount
                remainingCount = remainingCount - removeCount
                if gridData.stackCount <= 0 then
                    data[i] = nil
                end
                if remainingCount <= 0 then
                    local ret = self:_SetData(data)
                    return ret
                end
            end
        end
    end
    error(string.format("RemoveItemById failed, itemId: %d, count: %d", itemId, count))
end

-- 获取道具数量
-- 返回值: 道具数量
-- itemId: 物品ID
function FSInventoryCompClass:GetItemCountById(itemId)
    local data = self:_GetData()
    local totalCount = 0
    for i = 1, self:GetTotalCapacity() do
        local gridData = data[i]
        if gridData and gridData.itemId == itemId then
            totalCount = totalCount + gridData.stackCount
        end
    end
    return totalCount
end

-- 查找物品
-- 返回值: 找到返回 grid(从1开始), count, 否则返回 nil, 0
-- itemId: 物品ID
-- priority: 0优先快捷栏, 1优先背包
function FSInventoryCompClass:FindItemById(itemId, priority)
    local data = self:_GetData()
    local iterInfoList = self:_GetGridIteratorInfoList(priority)
    for _, iterInfo in ipairs(iterInfoList) do
        for i = iterInfo.first, iterInfo.last do
            local gridData = data[i]
            if gridData and gridData.itemId == itemId then
                return i, gridData.stackCount
            end
        end
    end
    return nil, 0
end

-- 获取格子数据
-- 返回值:      ItemObject 对象
-- grid:       格子编号(从1开始), 前 N 是快捷栏数据, 剩下是背包数据
function FSInventoryCompClass:GetGridData(grid)
    if grid < 1 or grid > self:GetTotalCapacity() then
        FXLog:ErrorFmt("GetGridData failed, grid: %d, totalCap: %d", grid, self:GetTotalCapacity())
        return
    end
    local data = self:_GetData()
    local gridData = data[grid]
    return gridData
end

-- 获取格子物品对象
-- 返回值: 物品对象
-- grid: 格子编号(从1开始)
function FSInventoryCompClass:GetGridItemObject(grid)
    if grid < 1 or grid > self:GetTotalCapacity() then
        FXLog:ErrorFmt("GetGridItemObject failed, grid: %d, totalCap: %d", grid, self:GetTotalCapacity())
        return
    end
    local data = self:_GetData()
    local gridData = data[grid]
    if not gridData then
        return nil
    end
    return FS.ItemClass.New(gridData.itemId, gridData.stackCount, gridData.extraData)
end

-- 判断是否可以删除格子中的道具
-- 返回值: 可以删除返回 true, 否则返回 false
-- grid: 格子编号(从1开始)
-- count: 要删除的数量，如果不传或为nil则删除全部
function FSInventoryCompClass:CanRemoveItemFromGridId(grid, count)
    if not self:_CheckGridIndexValid(grid) then
        FXLog:ErrorFmt("CanRemoveItemFromGridId failed, grid: %d, totalCap: %d", grid, self:GetTotalCapacity())
        return false
    end
    local data = self:_GetData()
    local gridData = data[grid]
    if not gridData then
        return false
    end
    local currentCount = gridData.stackCount
    if not count then
        return true
    end
    return currentCount >= count
end

-- 删除格子的特定道具的数量
-- 返回值: 成功返回 true, 失败返回 false
-- grid: 格子编号(从1开始)
-- count: 要删除的数量，如果不传或为nil则删除全部
function FSInventoryCompClass:RemoveItemFromGridId(grid, count)
    -- 检查格子编号是否有效
    if not self:_CheckGridIndexValid(grid) then
        FXLog:ErrorFmt(
            "RemoveItemFromGrid失败: 格子编号无效 grid=%d, 有效范围 1-%d",
            grid,
            self:GetTotalCapacity()
        )
        return false
    end

    local data = self:_GetData()
    local gridData = data[grid]
    if not gridData then
        return false
    end

    local currentCount = gridData.stackCount
    if not count then
        data[grid] = nil
        return self:_SetData(data)
    end

    -- 检查数量是否有效
    if count <= 0 then
        FXLog:ErrorFmt(
            "RemoveItemFromGrid失败: 数量无效 count=%d, grid=%d, itemId=%d",
            count,
            grid,
            gridData.itemId or 0
        )
        return false
    end

    -- 检查数量是否足够
    if currentCount < count then
        FXLog:ErrorFmt(
            "RemoveItemFromGrid失败: 数量不足 grid=%d, itemId=%d, 当前数量=%d, 需要删除=%d",
            grid,
            gridData.itemId or 0,
            currentCount,
            count
        )
        return false
    end

    -- 减少数量
    local newCount = currentCount - count
    if newCount > 0 then
        gridData.stackCount = newCount
    else
        data[grid] = nil
    end
    local ret = self:_SetData(data)
    return ret
end

-- 判断是否可以添加物品到格子
-- 返回值: 可以添加返回 true, 否则返回 false
-- grid: 格子编号(从1开始)
-- itemObject: 物品对象
function FSInventoryCompClass:CanAddItemToGridId(grid, itemObject)
    if not self:_CheckGridIndexValid(grid) then
        FXLog:ErrorFmt("CanAddItemToGridId failed, grid: %d, totalCap: %d", grid, self:GetTotalCapacity())
        return false
    end
    if not itemObject then
        return false
    end
    if not self:CheckItemObjectValid(itemObject) then
        return false
    end

    local gridData = self:GetGridData(grid)
    if not gridData then
        return true
    end
    if gridData.itemId ~= itemObject:GetItemId() then
        return false
    end

    local curStackCount = gridData.stackCount
    local addStackCount = itemObject:GetStackCount()
    local itemDataConfig = self:GetItemDataConfig(itemObject:GetItemId())
    return (curStackCount + addStackCount) <= itemDataConfig.MaxStack
end

-- 添加物品到格子
-- 返回值: 成功返回 true, 否则返回 false
-- grid: 格子编号(从1开始)
-- itemObject: 物品对象
function FSInventoryCompClass:AddItemToGridId(grid, itemObject)
    if not self:CanAddItemToGridId(grid, itemObject) then
        return false
    end

    local data = self:_GetData()
    if not data[grid] then
        data[grid] = {
            itemId = itemObject:GetItemId(),
            stackCount = itemObject:GetStackCount(),
            extraData = itemObject:GetExtraData(),
        }
    else
        data[grid].stackCount = data[grid].stackCount + itemObject:GetStackCount()
    end

    self:_SetData(data)
    return true
end

-- 交换两个格子的数据
-- 返回值: 成功返回 true, 否则返回 false
-- grid1: 第一个格子编号(从1开始)
-- grid2: 第二个格子编号(从1开始)
function FSInventoryCompClass:SwapGridData(grid1, grid2)
    if not self:_CheckGridIndexValid(grid1) or not self:_CheckGridIndexValid(grid2) then
        FXLog:ErrorFmt("SwapGridData failed, grid1: %s, grid2: %s", tostring(grid1), tostring(grid2))
        return false
    end
    if grid1 == grid2 then
        return true
    end

    local data = self:_GetData()
    local grid1Data = data[grid1]
    local grid2Data = data[grid2]
    if not grid1Data and not grid2Data then
        return true
    end

    data[grid1] = grid2Data
    data[grid2] = grid1Data
    local ret = self:_SetData(data)
    return ret
end

-- 整理物品: 按物品ID从小到大整理, 相同物品ID会堆叠在一起
-- 整理规则: 0 仅整理快捷栏, 1 仅整理背包. 注意快捷栏的道具不会和背包混在一起整理
function FSInventoryCompClass:SortByItemId(sortRule)
    local data = self:_GetData()
    local function sortRange(startIdx, endIdx)
        local stackItemMap = {}
        local unstackItemMap = {}
        local itemIdMap = {}
        for i = startIdx, endIdx do
            local gridData = data[i]
            if gridData then
                local extraData = gridData.extraData
                itemIdMap[gridData.itemId] = true
                if extraData then
                    unstackItemMap[gridData.itemId] = {}
                    table.insert(unstackItemMap[gridData.itemId], gridData)
                else
                    stackItemMap[gridData.itemId] = stackItemMap[gridData.itemId] or 0
                    stackItemMap[gridData.itemId] = stackItemMap[gridData.itemId] + gridData.stackCount
                end
            end
        end

        local itemIdList = {}
        for itemId in pairs(itemIdMap) do
            table.insert(itemIdList, itemId)
        end
        table.sort(itemIdList, function(lhs, rhs)
            return lhs < rhs
        end)

        local gridIdx = 1
        local newRangeData = {}
        for _, itemId in ipairs(itemIdList) do
            local stackCount = stackItemMap[itemId]
            if stackCount then
                local itemConfig = self:GetItemDataConfig(itemId)
                local maxStack = itemConfig and (itemConfig.MaxStack or 1) or 1
                local itemCount = math.ceil(stackCount / maxStack)
                local remainCount = stackCount
                for i = 1, itemCount do
                    local addCount = math.min(remainCount, maxStack)
                    newRangeData[gridIdx] = {
                        itemId = itemId,
                        stackCount = addCount,
                    }
                    remainCount = remainCount - addCount
                    gridIdx = gridIdx + 1
                end
            else
                for _, gridData in ipairs(unstackItemMap[itemId]) do
                    newRangeData[gridIdx] = gridData
                    gridIdx = gridIdx + 1
                end
            end
        end
        -- 清空范围内的数据
        for i = startIdx, endIdx do
            data[i] = nil
        end
        -- 将新数据映射到正确的索引位置
        for i = 1, gridIdx - 1 do
            if newRangeData[i] then
                data[startIdx + i - 1] = newRangeData[i]
            end
        end
        return true
    end

    local iterInfoList = self:_GetGridIteratorInfoList(0)
    local shortcutIterInfo = iterInfoList[1]
    local inventoryIterInfo = iterInfoList[2]
    if sortRule == 0 or sortRule == 3 then
        sortRange(shortcutIterInfo.first, shortcutIterInfo.last)
    end
    if sortRule == 1 or sortRule == 3 then
        sortRange(inventoryIterInfo.first, inventoryIterInfo.last)
    end
    local ret = self:_SetData(data)
    self:OnAllChanged()
    return ret
end

-- 清空背包
-- 返回值: 成功返回 true, 否则返回 false
-- 清空所有格子（包括快捷栏和背包）
function FSInventoryCompClass:ClearAll()
    local data = self:_GetData()
    local totalCap = self:GetTotalCapacity()
    for i = 1, totalCap do
        data[i] = nil
    end
    local ret = self:_SetData(data)
    self:OnAllChanged()
    return ret
end

-- 清除快捷栏
-- 返回值: 成功返回 true, 否则返回 false
-- 只清除快捷栏的格子（索引 1 到 shortcutCapacity）
function FSInventoryCompClass:ClearShortcut()
    local data = self:_GetData()
    local shortcutCap = self:GetShortcutCapacity()
    for i = 1, shortcutCap do
        data[i] = nil
    end
    local ret = self:_SetData(data)
    return ret
end

-- 清除背包
-- 返回值: 成功返回 true, 否则返回 false
-- 只清除背包的格子（索引 shortcutCapacity + 1 到 totalCapacity）
function FSInventoryCompClass:ClearInventory()
    local data = self:_GetData()
    local shortcutCap = self:GetShortcutCapacity()
    local totalCap = self:GetTotalCapacity()
    for i = shortcutCap + 1, totalCap do
        data[i] = nil
    end
    local ret = self:_SetData(data)
    self:OnAllChanged()

    return ret
end

-- 返回背包的数据
-- 数据格式为： { [格子ID] = { itemId = 道具ID, count = 数量 }， ... }
function FSInventoryCompClass:GetData()
    return self:_GetData()
end

--- 服务端校验道具使用请求，禁止客户端用零、负数或小数绕过实际消耗。
---@param grid number 格子编号。
---@param useCount number 使用数量。
---@return boolean canUse 是否可以使用。
---@return table|nil context 道具上下文。
function FSInventoryCompClass:CanUseItem(grid, useCount)
    if type(grid) ~= "number" or grid % 1 ~= 0 then
        return false
    end
    if type(useCount) ~= "number" or useCount <= 0 or useCount % 1 ~= 0 then
        return false
    end

    local totalCap = self:GetTotalCapacity()
    if grid < 1 or grid > totalCap then
        FXLog:ErrorFmt("CanUseItem failed, grid: %d, totalCap: %d", grid, totalCap)
        return false
    end
    local gridData = self:GetGridData(grid)
    if not gridData then
        return false
    end

    if gridData.stackCount < useCount then
        return false
    end

    local itemObject = FS.ItemClass.New(gridData.itemId, useCount, gridData.extraData)
    local context = FX.ItemContextClass.New(self:GetPlayerObject(), itemObject)
    local ret = context:CanUse()
    return ret, context
end

-- 使用道具
function FSInventoryCompClass:UseItem(grid, useCount)
    local ok, context = self:CanUseItem(grid, useCount)
    if not ok then
        return false
    end

    local gridData = self:GetGridData(grid)
    if context.consumeCount > 0 then
        if not self:RemoveItemFromGridId(grid, context.consumeCount) then
            return false
        end
    end

    local ok = context:Use()
    if not ok then
        FXLog:ErrorFmt("UseItem failed, itemId: %d, useCount: %d", gridData.itemId, useCount)
        return false
    end
    return true
end

-- 检查物品对象是否有效
-- 返回值: 有效返回 true, 否则返回 false
-- itemObject: 物品对象
function FSInventoryCompClass:CheckItemObjectValid(itemObject)
    if not itemObject then
        return false
    end
    if type(itemObject._stackCount) ~= "number" or itemObject._stackCount <= 0 then
        return false
    end
    local typeExtraData = type(itemObject._extraData)
    if typeExtraData ~= "table" and typeExtraData ~= "nil" then
        return false
    end
    if itemObject._extraData ~= nil and itemObject._stackCount > 1 then
        return false
    end
    local itemConfig = self:GetItemDataConfig(itemObject._itemId or -1)
    if not itemConfig then
        return false
    end

    local result = itemObject._stackCount <= (itemConfig.MaxStack or 1)
    if not result and FX.IsDebugMode() then
        local serializeData = itemObject:GetSerializeData()
        error("CheckItemObjectValid failed, itemObject: " .. FXTable:ToString(serializeData))
    end
    return result
end

--- 计算普通道具可以合并的数量；任意一方携带独立额外数据时禁止堆叠，避免属性丢失或串用。
---@param itemData1 table 目标格子数据。
---@param itemData2 table 待合并的道具数据。
---@return number maxStackableCount 本次最多可合并数量，不可堆叠时返回 0。
function FSInventoryCompClass:_GetMaxStackableCount(itemData1, itemData2)
    if not itemData1 or not itemData2 then
        return 0
    end
    if itemData1.itemId ~= itemData2.itemId then
        return 0
    end
    if itemData1.extraData ~= nil or itemData2.extraData ~= nil then
        return 0
    end
    local itemConfig = self:GetItemDataConfig(itemData1.itemId)
    if not itemConfig then
        return 0
    end
    local maxStack = ((itemConfig.MaxStack or 1) - itemData1.stackCount)
    return math.max(0, math.min(maxStack, itemData2.stackCount))
end

-- 返回 true 表示堆叠完成
function FSInventoryCompClass:_StackItem(itemData1, itemData2)
    local maxStackableCount = self:_GetMaxStackableCount(itemData1, itemData2)
    if maxStackableCount <= 0 then
        return false
    end
    itemData1.stackCount = itemData1.stackCount + maxStackableCount
    itemData2.stackCount = itemData2.stackCount - maxStackableCount
    return itemData2.stackCount <= 0
end

-- 返回道具的配置
--[[
    {
        Id = 1,
        Type = "Consumes",
        MaxStack = 10,
        CanDelete = false,
    }
]]
function FSInventoryCompClass:GetItemDataConfig(itemId)
    return _G.Provider:GetItemDataConfig(itemId)
end

return FSInventoryCompClass
