-- 升级工坊入口：复用导出 View 的展示、关闭按钮与弹窗动画。
local FX = _G.FX
local FXLoader = FX.Loader
local Fields = _G.PlayerDataConfig
local Rules = FXLoader:RequireShared("Scripts.Game.Shared.UpgradeWorkshopRules")
local GameUtility = FXLoader:RequireShared("Scripts.Game.Shared.GameUtility")
FXLoader:RequireFromParent(script, "Generated.CUpgradeWorkshopView")
local TranslationTexts = FX.Text.Define("UpgradeWorkshopFeedback", {
    Success = "Workshop upgrade complete!",
    Failed = "Upgrade failed. Please try again.",
    MaxLevel = "This workshop upgrade is already at its maximum level.",
    InsufficientCash = "Not enough cash to upgrade.",
})
local Component = FX.Class("CUpgradeWorkshopUICompClass", "CUpgradeWorkshopView")

--- 请求防重只保留在当前 UI 会话，等级与余额来自同步存档。
--- @param owner table 所属客户端玩家对象。
function Component:Ctor(owner)
    Component.Super.Ctor(self, owner)
    self.State = { entries = {} }
    self._pending = {}
end

--- 绑定导出按钮并刷新一次，界面保持关闭，等待侧栏入口打开。
function Component:OnReady()
    Component.Super.OnReady(self)
    self:BindUIData()
    self:Hide()
end

--- 订阅等级和金币，用服务端回执显示结果并解除请求中状态。
function Component:BindUIData()
    FX.Network:RegServerMsgCallback("S2C_UpgradeWorkshopResult", function(upgradeId, success)
        if not self._pending[upgradeId] then
            return
        end
        -- 成败均释放防重；显示数据始终读取服务端同步快照，不预测扣费或加级。
        self._pending[upgradeId] = nil
        self:UpdateState()
        local commonUI = self:GetOwner():RequireComponent("CCommonUICompClass")
        commonUI:ShowLocalizedTips(success and TranslationTexts.Success or TranslationTexts.Failed)
    end)
    self:WatchDataChanged(Fields.UpgradeWorkshop, function()
        self:UpdateState()
    end)
    self:WatchDataChanged(Fields.Money, function()
        self:UpdateState()
    end)
    local player = self:GetPlayerNode()
    self:TrackConnection(player:GetAttributeChangedSignal("GMFreeUpgrades"):Connect(function()
        self:UpdateState()
    end))
end

--- 将权威等级与余额转换为 View 规定的完整三行快照。
function Component:UpdateState()
    local levels = self:GetTable(Fields.UpgradeWorkshop)
    local money = self:GetNumber(Fields.Money)
    local free = self:GetPlayerNode():GetAttribute("GMFreeUpgrades") == true
    local entries = {}
    for upgradeId in pairs(Rules.BasePrices) do
        local level = levels[upgradeId]
        local maxed = level >= Rules.MaxLevel
        local price = free and 0 or Rules.GetPrice(upgradeId, level)
        entries[upgradeId] = {
            level = Rules.GetLevel(level),
            currentValue = upgradeId == "income" and "×" .. GameUtility.NumberToText(Rules.GetMultiplier(level))
                or tostring(Rules.GetLevel(level)),
            nextValue = maxed and "" or (upgradeId == "income" and "×" .. GameUtility.NumberToText(Rules.GetMultiplier(level + 1))
                or tostring(Rules.GetLevel(level + 1))),
            price = price,
            canUpgrade = not maxed and money >= price,
            maxed = maxed,
            pending = self._pending[upgradeId] == true,
        }
    end
    self.State = {entries = entries}
    self:RefreshUI()
end

--- 金币价格沿用项目统一数量格式化，不覆盖 View 的展示逻辑。
--- @param amount number 未格式化的金币数量。
--- @return string 格式化后的数量。
function Component:FormatAmount(amount)
    return GameUtility.NumberToText(amount)
end

--- 满级或余额不足时显示提示；符合资格才提交当前等级，费用与结果由服务端裁定。
--- @param action string View 发出的动作名称。
--- @param payload table View 提供的稳定升级 ID。
function Component:OnUIAction(action, payload)
    local upgradeId = payload.upgradeId
    local entry = self.State.entries[upgradeId]
    if action ~= "Upgrade" or not entry or entry.pending then
        return
    end
    if entry.maxed then
        self:GetOwner():RequireComponent("CCommonUICompClass"):ShowLocalizedTips(TranslationTexts.MaxLevel)
        return
    end
    if not entry.canUpgrade then
        self:GetOwner():RequireComponent("CCommonUICompClass"):ShowLocalizedTips(TranslationTexts.InsufficientCash)
        return
    end
    self._pending[upgradeId] = true
    self:UpdateState()
    FX.Network:SendMsgToServer("C2S_UpgradeWorkshop", upgradeId, entry.level - 1)
end

--- 移除本组件持有的结果回调，其余订阅由父类释放。
function Component:Dtor()
    FX.Network:UnRegServerMsgCallback("S2C_UpgradeWorkshopResult")
    Component.Super.Dtor(self)
end

return Component
