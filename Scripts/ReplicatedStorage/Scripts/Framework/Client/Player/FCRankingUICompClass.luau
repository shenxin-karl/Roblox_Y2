local FX = _G.FX
local FXNetwork = FX.Network

local FCRankingUICompClass = FX.Class("FCRankingUICompClass", "FCUICompClass")

--- 初始化排行榜 UI 基类状态，并绑定榜单类型切换按钮。
---@param owner table 组件归属对象。
---@return nil
function FCRankingUICompClass:Ctor(owner)
    FCRankingUICompClass.Super.Ctor(self, owner)
    self._tabIndex = self:GetDefaultRankingTabIndex()
    self._rankRows = {}
    self._myNo = nil
    self._myScore = 0
    self._tabBtnList = {}
    self:BindRankingTypeButtons()
end

--- 返回排行榜组件默认协作名。
---@param self table 当前排行榜 UI 组件。
---@return string
function FCRankingUICompClass:GetCompName()
    return "RankingUI"
end

--- 返回默认榜单页签，默认取配置列表中的第一个榜。
---@param self table 当前排行榜 UI 组件。
---@return number
function FCRankingUICompClass:GetDefaultRankingTabIndex()
    return self:GetRankingTabConfigList()[1].tabType
end

--- 返回排行榜请求协议名，派生类可在协议不同的项目中重写。
---@param self table 当前排行榜 UI 组件。
---@return string
function FCRankingUICompClass:GetRankingRequestName()
    return "C2S_RankingData"
end

--- 返回本次请求的排行榜起止名次。
---@param self table 当前排行榜 UI 组件。
---@return number, number
function FCRankingUICompClass:GetRankingRange()
    return 1, 100
end

--- 返回排行榜基础节点映射，基类只依赖榜单列表和榜单类型列表。
---@param self table 当前排行榜 UI 组件。
---@return table
function FCRankingUICompClass:GetRankingNodeMap()
    FX.ErrorWithTraceback("FCRankingUICompClass:GetRankingNodeMap() is not implemented")
end

--- 返回项目启用的榜单配置列表，由基类据此绑定按钮和切榜。
---@param self table 当前排行榜 UI 组件。
---@return table
function FCRankingUICompClass:GetRankingTabConfigList()
    FX.ErrorWithTraceback("FCRankingUICompClass:GetRankingTabConfigList() is not implemented")
end

--- 返回指定榜单类型的配置。
---@param tabType number 榜单类型索引。
---@return table
function FCRankingUICompClass:GetRankingTabConfig(tabType)
    local configList = self:GetRankingTabConfigList()
    for _, tabConfig in ipairs(configList) do
        if tabConfig.tabType == tabType then
            return tabConfig
        end
    end
    FX.ErrorWithTraceback(
        string.format("FCRankingUICompClass:GetRankingTabConfig() failed, tabType=%s", tostring(tabType))
    )
end

--- 返回指定名次使用的行模板节点。
---@param rankNo number 排行榜名次。
---@return UIComponent
function FCRankingUICompClass:GetRankRowTemplate(rankNo)
    FX.ErrorWithTraceback("FCRankingUICompClass:GetRankRowTemplate() is not implemented")
end

--- 初始化榜单类型按钮，统一处理按钮显隐、标题和点击切换。
---@param self table 当前排行榜 UI 组件。
---@return nil
function FCRankingUICompClass:BindRankingTypeButtons()
    self._tabBtnList = {}
    local nodeMap = self:GetRankingNodeMap()
    local rankingTypeListNode = nodeMap.rankingTypeListNode
    for _, childNode in ipairs(rankingTypeListNode:GetChildren()) do
        if childNode:IsA("GuiButton") then
            childNode.Visible = false
        end
    end

    for _, tabConfig in ipairs(self:GetRankingTabConfigList()) do
        local tabBtn = rankingTypeListNode:FindFirstChild(tabConfig.buttonName)
        if tabBtn == nil or not tabBtn:IsA("GuiButton") then
            FX.ErrorWithTraceback(
                string.format(
                    "FCRankingUICompClass:BindRankingTypeButtons() failed, buttonName=%s",
                    tostring(tabConfig.buttonName)
                )
            )
        end
        tabBtn.Visible = true
        self:SetRankingTypeButtonTitle(tabBtn, tabConfig.tabTitle)
        table.insert(self._tabBtnList, {
            tabBtn = tabBtn,
            tabType = tabConfig.tabType,
        })
        self:TrackConnection(tabBtn.Activated:Connect(function()
            self:OnRankingTypeButtonClick(tabConfig.tabType)
        end))
    end
    self:RefreshRankingTypeButtonDisplay()
end

--- 写入榜单类型按钮标题，兼容按钮自身标题和 BtnTxt 子节点。
---@param tabBtn UIButton 榜单类型按钮节点。
---@param title string 榜单类型标题。
---@return nil
function FCRankingUICompClass:SetRankingTypeButtonTitle(tabBtn, title)
    if tabBtn:FindFirstChild("BtnTxt") then
        tabBtn.BtnTxt.Text = title
        return
    end
    tabBtn.Text = title
end

--- 刷新所有榜单类型按钮的选中状态。
---@param self table 当前排行榜 UI 组件。
---@return nil
function FCRankingUICompClass:RefreshRankingTypeButtonDisplay()
    for _, tabInfo in ipairs(self._tabBtnList) do
        tabInfo.tabBtn:SetAttribute("Selected", self._tabIndex == tabInfo.tabType)
    end
end

--- 点击榜单类型按钮后切换榜单并刷新 UI。
---@param tabType number 目标榜单类型索引。
---@return nil
function FCRankingUICompClass:OnRankingTypeButtonClick(tabType)
    if self._tabIndex == tabType then
        return
    end
    self._tabIndex = tabType
    self:UpdateRankingUI()
end

--- 统一刷新排行榜 UI，切换榜单和打开界面时都走这里。
---@param self table 当前排行榜 UI 组件。
---@return nil
function FCRankingUICompClass:UpdateRankingUI()
    self:RefreshRankingTypeButtonDisplay()
    self:RefreshHeaderText(self._tabIndex)
    self:RefreshRankingData()
end

--- 打开排行榜时重置到默认榜单并刷新显示。
---@param self table 当前排行榜 UI 组件。
---@return nil
function FCRankingUICompClass:OnShow()
    self._tabIndex = self:GetDefaultRankingTabIndex()
    self:UpdateRankingUI()
end

--- 请求服务端排行榜数据；默认沿用框架排行榜协议。
---@param self table 当前排行榜 UI 组件。
---@return table
function FCRankingUICompClass:RequestRankingData()
    local beginIndex, endIndex = self:GetRankingRange()
    return FXNetwork:InvokeServer(self:GetRankingRequestName(), 2, self._tabIndex, beginIndex, endIndex) or {}
end

--- 规整服务端返回的排行榜数据，补齐展示层需要的字段。
---@param itemData table 服务端返回的排行榜条目映射。
---@return table
function FCRankingUICompClass:NormalizeRankingRows(itemData)
    local rows = {}
    if type(itemData) ~= "table" then
        return rows
    end

    local beginIndex, endIndex = self:GetRankingRange()
    for index, rankData in ipairs(itemData) do
        local rankNo = rankData.rankNo or (beginIndex + index - 1)
        if rankData then
            table.insert(rows, {
                rankNo = tonumber(rankData.rankNo) or rankNo,
                playerName = rankData.playerName or "",
                playerId = tonumber(rankData.playerId) or 0,
                rankScore = tonumber(rankData.rankScore) or 0,
            })
        end
    end
    return rows
end

--- 刷新排行榜数据，并统一驱动列表与自己的排名区域。
---@param self table 当前排行榜 UI 组件。
---@return nil
function FCRankingUICompClass:RefreshRankingData()
    local rankingData = self:RequestRankingData()
    self._rankRows = self:NormalizeRankingRows(rankingData.itemData)
    self._myNo = tonumber(rankingData.myNo)
    if self._myNo and self._myNo <= 0 then
        self._myNo = nil
    end
    self._myScore = tonumber(rankingData.myScore) or 0

    self:RefreshRankList()
    self:RefreshMyRankData()
end

--- 按指定榜单类型刷新表头文本，由派生类按项目 UI 结构实现。
---@param tabType number 当前榜单类型索引。
---@return nil
function FCRankingUICompClass:RefreshHeaderText(tabType)
    FX.ErrorWithTraceback("FCRankingUICompClass:RefreshHeaderText() is not implemented")
end

--- 刷新排行榜列表；具体行样式由 RefreshRankRowNode 承接。
---@param self table 当前排行榜 UI 组件。
---@return nil
function FCRankingUICompClass:RefreshRankList()
    local nodeMap = self:GetRankingNodeMap()
    local rankListNode = nodeMap.rankListNode
    for _, node in ipairs(self._rowNodes or {}) do
        node:Destroy()
    end
    self._rowNodes = {}
    for _, rankData in ipairs(self._rankRows) do
        local rowTemplate = self:GetRankRowTemplate(rankData.rankNo)
        local rowNode = rowTemplate:Clone()
        rowNode.Name = string.format("RankRow_%d", rankData.rankNo)
        rowNode.Visible = true
        rowNode.Position = UDim2.fromOffset(0, 0)
        rowNode.AnchorPoint = Vector2.zero
        rowNode.LayoutOrder = rankData.rankNo
        table.insert(self._rowNodes, rowNode)
        self:RefreshRankRowNode(rowNode, rankData)
        rowNode.Parent = rankListNode
    end
end

--- 刷新单行排行榜展示，由派生类按项目行节点结构实现。
---@param rowNode UIComponent 排行榜行节点。
---@param rankData table 已规整的排行榜行数据。
---@return nil
function FCRankingUICompClass:RefreshRankRowNode(rowNode, rankData)
    FX.ErrorWithTraceback("FCRankingUICompClass:RefreshRankRowNode() is not implemented")
end

--- 刷新自己的排名和分数展示，由派生类按项目 UI 结构实现。
---@param self table 当前排行榜 UI 组件。
---@return nil
function FCRankingUICompClass:RefreshMyRankData()
    FX.ErrorWithTraceback("FCRankingUICompClass:RefreshMyRankData() is not implemented")
end

--- 格式化排行榜玩家名，默认不追加项目内调试信息。
---@param playerName string 玩家名。
---@param playerId number 玩家 ID。
---@return string
function FCRankingUICompClass:FormatPlayerName(playerName, playerId)
    return playerName
end

--- 格式化排行榜分数，默认直接转字符串。
---@param score number 排行榜分数。
---@return string
function FCRankingUICompClass:FormatScore(score)
    return tostring(score or 0)
end

--- 清理本组件创建的排行榜行。
function FCRankingUICompClass:Dtor()
    for _, node in ipairs(self._rowNodes or {}) do
        node:Destroy()
    end
    FCRankingUICompClass.Super.Dtor(self)
end
return FCRankingUICompClass
