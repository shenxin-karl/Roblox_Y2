local FX = _G.FX
local FXTask = FX.Task
local NEXT_FRAME_DELAY = 1 / 30

-----------------------------------------------------------
-- 商店页签基类
-----------------------------------------------------------
local ShopPageBaseClass = FX.Class("ShopPageBaseClass")

--- 初始化商店页签，页签只持有列表节点，不关心列表节点的真实路径。
---@param ownerComp table 商店 UI 容器组件，用于转发统一购买入口。
---@param tabConfig table 页签配置，包含页面名与商品配置源。
---@return nil
function ShopPageBaseClass:Ctor(ownerComp, tabConfig)
    self._ownerComp = ownerComp
    self._tabConfig = tabConfig
    self._listNode = self:CreateListNode()
    self._itemList = {}
    self._refreshTask = nil
end

-----------------------------------------------------------
-- 子类覆盖接口
-----------------------------------------------------------

--- 创建或返回当前页签的商品列表节点，子类按项目 UI 结构实现。
---@param self ShopPageBaseClass
---@return table listNode 商品条目挂载节点。
function ShopPageBaseClass:CreateListNode()
    FX.ErrorWithTraceback("ShopPageBaseClass:CreateListNode not implemented")
end

--- 返回当前页签商品配置列表，子类负责决定配置来源和过滤规则。
---@param self ShopPageBaseClass
---@return table shopItemConfigList 当前页签商品配置数组。
function ShopPageBaseClass:GetItemConfigList()
    FX.ErrorWithTraceback("ShopPageBaseClass:GetItemConfigList not implemented")
end

-----------------------------------------------------------
-- 框架流程
-----------------------------------------------------------

--- 按页签配置里的商品条目类名创建单个商品条目实例。
---@param self ShopPageBaseClass
---@param shopItemConfig table 商品配置。
---@param itemIndex number 商品在当前页签中的顺序索引。
---@return table item 商品条目实例。
function ShopPageBaseClass:CreateItem(shopItemConfig, itemIndex)
    local itemClass = FX.GetClass(self._tabConfig.PageItemClassName)
    return itemClass.New(self, shopItemConfig, itemIndex)
end

--- 返回页签逻辑名，供商店容器切页使用。
---@param self ShopPageBaseClass
---@return string pageName 页签逻辑名。
function ShopPageBaseClass:GetPageName()
    return self._tabConfig.PageName
end

--- 返回页签标题，供页签按钮显示使用。
---@param self ShopPageBaseClass
---@return string tabTitle 页签显示标题。
function ShopPageBaseClass:GetTabTitle()
    return self._tabConfig.Name
end

--- 刷新当前已有商品条目，不创建或销毁节点，适用于只更新展示状态。
---@param self ShopPageBaseClass
---@return nil
function ShopPageBaseClass:Refresh()
    for _, item in ipairs(self._itemList) do
        item:Refresh()
    end
end

--- 下一帧清理并重建商品列表，避免当前帧 UI 事件链中立即销毁节点。
---@param self ShopPageBaseClass
---@return nil
function ShopPageBaseClass:RefreshNextFrame()
    if self._refreshTask ~= nil then
        return
    end

    self._refreshTask = FXTask:Delay(NEXT_FRAME_DELAY, function()
        self._refreshTask = nil
        self:RebuildItems()
    end)
end

--- 清理并按配置重建当前页签商品列表。
---@param self ShopPageBaseClass
---@return nil
function ShopPageBaseClass:RebuildItems()
    self:ClearItems()
    for itemIndex, shopItemConfig in ipairs(self:GetItemConfigList()) do
        local item = self:CreateItem(shopItemConfig, itemIndex)
        self:AddItem(item)
        item:Refresh()
    end
end

--- 把商品条目挂到页签列表节点下，并记录实例用于清理。
---@param self ShopPageBaseClass
---@param item table 商品条目实例。
---@return nil
function ShopPageBaseClass:AddItem(item)
    item:GetRootNode().Parent = self._listNode
    table.insert(self._itemList, item)
end

--- 清理当前页签的商品条目实例和节点。
---@param self ShopPageBaseClass
---@return nil
function ShopPageBaseClass:ClearItems()
    for _, item in ipairs(self._itemList) do
        item:Destroy()
    end
    self._itemList = {}
end

--- 显示页签列表节点，不主动创建或清理商品节点。
---@param self ShopPageBaseClass
---@return nil
function ShopPageBaseClass:Show()
    self._listNode.Visible = true
    self:RebuildItems()
end

--- 隐藏页签并释放动态商品节点。
---@param self ShopPageBaseClass
---@return nil
function ShopPageBaseClass:Hide()
    if self._refreshTask ~= nil then
        FXTask:Cancel(self._refreshTask)
        self._refreshTask = nil
    end

    self:ClearItems()
    self._listNode.Visible = false
end

--- 销毁页签，释放列表中的商品条目。
---@param self ShopPageBaseClass
---@return nil
function ShopPageBaseClass:Dtor()
    if self._refreshTask ~= nil then
        FXTask:Cancel(self._refreshTask)
        self._refreshTask = nil
    end

    self:ClearItems()
    self._listNode = nil
    self._ownerComp = nil
    self._tabConfig = nil
end

return ShopPageBaseClass
