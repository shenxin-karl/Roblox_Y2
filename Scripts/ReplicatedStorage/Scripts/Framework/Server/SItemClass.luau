local FX, FS = _G.FX, _G.FS
local FXTable = FX.Table

local FSItemClass = FX.Class("FSItemClass")
FS.ItemClass = FSItemClass

--- 按字段是否声明校验额外数据，允许 Schema 使用 false 作为默认值。
--- @param itemId number 用于查找物品类型及其 Schema 的物品 ID。
--- @param extraData table? 待校验的物品额外数据。
local function ValidateExtraData(itemId, extraData)
    if not FX.IsDebugMode() then
        return
    end

    if extraData == nil then
        return
    end
    local itemDataConfig = _G.Provider:GetItemDataConfig(itemId)
    local itemType = itemDataConfig.Type
    local itemExtraDataSchema = _G.Provider:GetItemExtraDataSchema(itemType)

    FX.DebugAssert(itemExtraDataSchema ~= nil, "Item extra data schema not found for item type: " .. itemType)
    for key, value in pairs(extraData) do
        FX.DebugAssert(
            itemExtraDataSchema[key] ~= nil,
            "Item extra data schema not found for item type: " .. itemType .. " key: " .. tostring(key)
        )
    end
end

function FSItemClass:Ctor(itemId, stackCount, extraData)
    self._itemId = itemId
    self._stackCount = stackCount
    self._extraData = extraData
    ValidateExtraData(itemId, extraData)
end

function FSItemClass:GetItemId()
    return self._itemId
end

function FSItemClass:GetStackCount()
    return self._stackCount
end

function FSItemClass:SetStackCount(stackCount)
    self._stackCount = stackCount
end

function FSItemClass:AddStackCount(stackCount)
    self._stackCount = self._stackCount + stackCount
end

function FSItemClass:GetExtraData()
    local itemDataConfig = _G.Provider:GetItemDataConfig(self._itemId)
    local itemType = itemDataConfig.Type
    local itemExtraDataSchema = _G.Provider:GetItemExtraDataSchema(itemType)
    return FXTable:MergeMultiple(itemExtraDataSchema, self._extraData)
end

function FSItemClass:RemoveStackCount(stackCount)
    self._stackCount = self._stackCount - stackCount
end

--- 独立词条物品不堆叠，普通物品服从项目配置。
--- @return number 单格上限。
function FSItemClass:GetMaxStackCount()
    return self._extraData and 1 or _G.Provider:GetItemDataConfig(self._itemId).MaxStack
end

function FSItemClass:GetSerializeData()
    return {
        itemId = self._itemId,
        stackCount = self._stackCount,
        extraData = self._extraData,
    }
end

function FSItemClass:FromSerializeData(serializeData)
    self._itemId = serializeData.itemId
    self._stackCount = serializeData.stackCount
    self._extraData = serializeData.extraData
end

_G.FItemFactor = {}
local FItemFactor = _G.FItemFactor
function FItemFactor:_MakeStackList(itemId, count, extraData)
    local list = {}
    local itemConfig = _G.Provider:GetItemDataConfig(itemId)
    local maxStack = itemConfig.MaxStack
    -- 有额外数据时（例如宠物/装备词条等），通常不允许堆叠，按单个道具发放
    if extraData ~= nil then
        maxStack = 1
    end
    for i = 1, count do
        local curCount = math.min(maxStack, count)
        table.insert(list, FS.ItemClass.New(itemId, curCount, extraData))
        count = count - curCount
        if count <= 0 then
            break
        end
    end
    return list
end

-- 追加奖励到列表中
function FItemFactor:AppendItem(itemList, itemId, count, extraData)
    local list = self:_MakeStackList(itemId, count, extraData)
    for _, item in ipairs(list) do
        table.insert(itemList, item)
    end
    return list
end

return true
