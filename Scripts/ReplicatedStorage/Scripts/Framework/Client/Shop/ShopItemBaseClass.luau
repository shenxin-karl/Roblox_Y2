local FX = _G.FX

-----------------------------------------------------------
-- 商店商品条目基类
-----------------------------------------------------------
local ShopItemBaseClass = FX.Class("ShopItemBaseClass")

--- 初始化商品条目，根节点由子类按具体 UI 模板创建。
---@param ownerPage table 所属商店页签，用于转发统一购买入口。
---@param itemConfig table 商品配置。
---@param itemIndex number 商品在当前页签中的顺序索引。
---@return nil
function ShopItemBaseClass:Ctor(ownerPage, itemConfig, itemIndex)
    self._ownerPage = ownerPage
    self._itemConfig = itemConfig
    self._itemIndex = itemIndex
    self._rootNode = self:CreateRootNode()
    self:BindEvent()
end

-----------------------------------------------------------
-- 子类覆盖接口
-----------------------------------------------------------

--- 创建商品条目根节点，子类负责克隆模板并返回根节点。
---@param self ShopItemBaseClass
---@return table rootNode 商品条目根节点。
function ShopItemBaseClass:CreateRootNode()
    FX.ErrorWithTraceback("ShopItemBaseClass:CreateRootNode not implemented")
end

--- 绑定商品条目事件，构造期只调用一次，避免刷新时重复注册点击事件。
---@param self ShopItemBaseClass
---@return nil
function ShopItemBaseClass:BindEvent() end

--- 刷新商品显示内容，子类按具体商品节点结构实现。
---@param self ShopItemBaseClass
---@return nil
function ShopItemBaseClass:Refresh()
    FX.ErrorWithTraceback("ShopItemBaseClass:Refresh not implemented")
end

-----------------------------------------------------------
-- 框架流程
-----------------------------------------------------------

--- 返回商品条目根节点，供页签基类挂载到列表节点。
---@param self ShopItemBaseClass
---@return table rootNode 商品条目根节点。
function ShopItemBaseClass:GetRootNode()
    return self._rootNode
end

--- 销毁商品条目节点并释放引用。
---@param self ShopItemBaseClass
---@return nil
function ShopItemBaseClass:Destroy()
    self._rootNode:Destroy()
    self._rootNode = nil
    self._ownerPage = nil
    self._itemConfig = nil
    self._itemIndex = nil
end

return ShopItemBaseClass
