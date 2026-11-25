-- 离线收益业务接入：复用UIEditor展示，真实金额、钻石与领取结果由服务端决定。
local FX = _G.FX
local FXLoader = FX.Loader
local Fields = _G.PlayerDataConfig
local Utility = FXLoader:RequireShared("Scripts.Game.Shared.GameUtility")
local DiamondPurchase = FXLoader:RequireFromParent(script, "CDiamondPurchase")
local MoneyRain = FXLoader:RequireFromParent(script, "CMoneyRain")
FXLoader:RequireFromParent(script, "Generated.COfflineIncomeView")
local Component = FX.Class("COfflineIncomeUICompClass", "COfflineIncomeView")

--- 父构造后准备静态价格与本次登录的请求状态，不伪造待领取金额。
--- @param owner table 当前客户端玩家对象。
function Component:Ctor(owner)
    Component.Super.Ctor(self, owner)
    self.Config = {diamondCost = _G.GameConfig.CommonConfig.OfflineDoubleClaimDiamondCost}
    self._requestId = 0
    self._pending, self._failed, self._autoOpened = false, false, false
end

--- 先绑定生成节点，再订阅真实数据；只有登录后存在待领收益才自动弹出。
function Component:OnReady()
    Component.Super.OnReady(self)
    self:Hide()
    self:BindUIData()
end

--- 数据订阅仅建立一次，回执与权威字段更新共同恢复领取状态。
function Component:BindUIData()
    FX.Network:RegServerMsgCallback("S2C_OfflineIncomeResult", function(requestId, success, insufficientDiamonds)
        if self._destroyed or not self._pending or requestId ~= self._requestId then
            return
        end
        self._pending = false
        self._failed = not success and not insufficientDiamonds
        self:UpdateState()
        if success then
            self:Hide()
            MoneyRain.Play()
        elseif insufficientDiamonds == true then
            DiamondPurchase.Open()
        end
    end)
    self:WatchDataChanged(Fields.OfflineIncome, function()
        self:UpdateState()
    end)
    self:WatchDataChanged(Fields.Diamonds, function()
        self:UpdateState()
    end)
end

--- 提供完整快照，不把在线刷新时间变化当成再次弹窗的原因。
function Component:UpdateState()
    local amount = self:GetTable(Fields.OfflineIncome).Pending
    self.State = {
        amount = amount,
        diamonds = self:GetNumber(Fields.Diamonds),
        pending = self._pending,
        failed = self._failed,
    }
    self:RefreshUI()
    if amount > 0 and not self._autoOpened then
        self._autoOpened = true
        self:Show()
        FX.Network:SendMsgToServer("C2S_TutorialHint", "OfflineShown")
    end
end

--- 仅覆写契约允许的金额格式化，文案和按钮仍由生成View负责。
--- @param amount number 未格式化金币数。
--- @return string 项目统一的数量缩写。
function Component:FormatAmount(amount)
    return Utility.NumberToText(amount)
end

--- 领取只发送请求编号与单双倍选项；关闭保留未领取奖励。
--- @param action string 生成View发出的Claim或Close。
--- @param payload table Claim含boosted:boolean，Close为空。
function Component:OnUIAction(action, payload)
    if action == "Close" then
        self:Hide()
        return
    end
    if action ~= "Claim" or self._pending or not self.State or self.State.amount <= 0 then
        return
    end
    if payload.boosted and self.State.diamonds < self.Config.diamondCost then
        DiamondPurchase.Open()
        return
    end
    self._requestId += 1
    self._pending, self._failed = true, false
    self:UpdateState()
    FX.Network:SendMsgToServer("C2S_ClaimOfflineIncome", self._requestId, payload.boosted)
end

--- 解除结果回调，订阅与展示资源由父类清理。
function Component:Dtor()
    self._destroyed = true
    FX.Network:UnRegServerMsgCallback("S2C_OfflineIncomeResult")
    Component.Super.Dtor(self)
end

return Component
