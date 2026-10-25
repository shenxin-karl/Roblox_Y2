local FX = _G.FX

-----------------------------------------------------------
-- 商店 UI 容器基类
-----------------------------------------------------------
local FCShopUICompClass = FX.Class("FCShopUICompClass", "FCUICompClass")

--- 初始化商店容器状态；具体 UI 节点由项目子类准备后再调用创建流程。
---@param owner table 玩家对象，供组件调用公共 UI 与玩家数据接口。
---@return nil
function FCShopUICompClass:Ctor(owner)
    FCShopUICompClass.Super.Ctor(self, owner)
    self._pageMap = {}
    self._tabBtnMap = {}
    self._currentPage = nil
    self._currentPageName = nil
end

-----------------------------------------------------------
-- 子类覆盖接口
-----------------------------------------------------------

--- 返回框架商店组件名；项目商店子类通常需要覆盖为业务组件名。
---@param self FCShopUICompClass
---@return string compName 组件逻辑名。
function FCShopUICompClass:GetCompName()
    return "FCShopUIComp"
end

--- 返回页签配置列表，配置需包含 `PageName` 与 `ClassName`。
---@param self FCShopUICompClass
---@return table tabConfigList 页签配置数组。
function FCShopUICompClass:GetTabConfigList()
    FX.ErrorWithTraceback("FCShopUICompClass:GetTabConfigList not implemented")
end

--- 创建页签按钮；子类负责克隆模板、挂载父节点和写入标题。
---@param self FCShopUICompClass
---@param tabConfig table 当前页签配置。
---@param page table 当前页签实例。
---@return table tabBtn 页签按钮节点。
function FCShopUICompClass:CreateTabButton(tabConfig, page)
    FX.ErrorWithTraceback("FCShopUICompClass:CreateTabButton not implemented")
end

--- 刷新页签按钮选中态；子类负责适配不同项目的按钮节点结构。
---@param self FCShopUICompClass
---@param tabBtn table 页签按钮节点。
---@param isSelected boolean 是否为当前选中页签。
---@return nil
function FCShopUICompClass:RefreshTabButton(tabBtn, isSelected)
    FX.ErrorWithTraceback("FCShopUICompClass:RefreshTabButton not implemented")
end

-----------------------------------------------------------
-- 框架流程
-----------------------------------------------------------

--- 按页签配置创建全部页面实例，页面类必须继承 `ShopPageBaseClass`。
---@param self FCShopUICompClass
---@return nil
function FCShopUICompClass:CreatePages()
    for _, tabConfig in ipairs(self:GetTabConfigList()) do
        local pageClass = FX.GetClass(tabConfig.ClassName)
        local page = pageClass.New(self, tabConfig)
        page:Hide()
        self._pageMap[tabConfig.PageName] = page
    end
end

--- 按页签配置创建并绑定全部页签按钮。
---@param self FCShopUICompClass
---@return nil
function FCShopUICompClass:CreateTabs()
    for _, tabConfig in ipairs(self:GetTabConfigList()) do
        local pageName = tabConfig.PageName
        local page = self._pageMap[pageName]
        local tabBtn = self:CreateTabButton(tabConfig, page)
        self:BindTabButton(tabBtn, pageName)
        self._tabBtnMap[pageName] = tabBtn
    end
end

--- 绑定页签按钮点击切页事件；按钮生命周期由项目 UI 节点管理。
---@param self FCShopUICompClass
---@param tabBtn table 页签按钮节点。
---@param pageName string 页签逻辑名。
---@return nil
function FCShopUICompClass:BindTabButton(tabBtn, pageName)
    self:TrackConnection(tabBtn.Activated:Connect(function()
        self:SwitchPage(pageName)
    end))
end

--- 切到配置中的第一个页签，保证商店初始化后有有效页面。
---@param self FCShopUICompClass
---@return nil
function FCShopUICompClass:SwitchDefaultPage()
    local firstTabConfig = self:GetTabConfigList()[1]
    if firstTabConfig == nil then
        return
    end
    self:SwitchPage(firstTabConfig.PageName)
end

--- 切换当前页签，并同步页签按钮组选中态。
---@param self FCShopUICompClass
---@param pageName string 页签逻辑名。
---@return nil
function FCShopUICompClass:SwitchPage(pageName)
    if self._currentPageName == pageName then
        return
    end

    local nextPage = self._pageMap[pageName]
    if self._currentPage ~= nil then
        self._currentPage:Hide()
    end

    self._currentPageName = pageName
    self._currentPage = nextPage
    self._currentPage:Show()
    self:RefreshTabButtons()
end

--- 刷新全部页签按钮状态，选中表现由项目子类实现。
---@param self FCShopUICompClass
---@return nil
function FCShopUICompClass:RefreshTabButtons()
    for pageName, tabBtn in pairs(self._tabBtnMap) do
        self:RefreshTabButton(tabBtn, pageName == self._currentPageName)
    end
end

--- 销毁商店页面实例，释放动态商品节点。
---@param self FCShopUICompClass
---@return nil
function FCShopUICompClass:Dtor()
    for _, page in pairs(self._pageMap) do
        page:Dtor()
    end

    self._pageMap = nil
    self._tabBtnMap = nil
    self._currentPage = nil
    self._currentPageName = nil
    FCShopUICompClass.Super.Dtor(self)
end

return FCShopUICompClass
