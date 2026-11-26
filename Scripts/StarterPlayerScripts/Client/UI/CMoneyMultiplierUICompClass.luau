-- 钻石付款共用一个确认页，金币倍率在此提供档位报价和提交动作。
local FX = _G.FX
local Loader = FX.Loader
local Text = FX.Text
local Fields = _G.PlayerDataConfig
local Rules = Loader:RequireShared("Scripts.Game.Shared.MoneyMultiplierRules")
local Utility = Loader:RequireShared("Scripts.Game.Shared.GameUtility")
local DiamondPurchase = Loader:RequireFromParent(script, "CDiamondPurchase")
Loader:RequireFromParent(script, "Generated.CShopPurchaseView")
local Component = FX.Class("CMoneyMultiplierUICompClass", "CShopPurchaseView")
local TranslationTexts = Text.Define("Y2MoneyMultiplier", {
    Title = "Money Multiplier ×{rate}",
    Category = "MONEY MULTIPLIER",
    Description = "Permanently increase cash from displayed swords, including offline income.",
    Maxed = "Your money multiplier has reached ×256.",
    Unavailable = "This purchase is currently unavailable.",
    OfferChanged = "This offer has changed. Open it again to continue.",
})

--- 只绑定导出按钮，首次打开时才传入当前档位。
function Component:OnReady()
    Component.Super.OnReady(self)
    self:Hide()
end

--- 用当前存档档位打开购买确认页，已达上限只提示。
--- @param entry string? 商店入口，未传时来自主界面。
function Component:OpenPurchase(entry)
    local commonUI = self:GetOwner():RequireComponent("CCommonUICompClass")
    if not table.find(_G.NetworkProtocol.ClientMsgID, "C2S_BuyMoneyMultiplier") then
        commonUI:ShowLocalizedTips(TranslationTexts.Unavailable)
        return
    end
    if self.State and self.State.pending then
        return
    end
    local tier = self:GetNumber(Fields.PaidMultiplierTier)
    local price = Rules.GetNextPrice(tier)
    if not price then
        commonUI:ShowLocalizedTips(TranslationTexts.Maxed)
        return
    end
    local opened = self:OpenDiamondPurchase({
        itemId = tostring(tier),
        name = "",
        nameText = Text.Tr(TranslationTexts.Title, {rate = Utility.NumberToText(Rules.GetMultiplier(tier + 1))}),
        category = TranslationTexts.Category.Source,
        description = "",
        descriptionText = Text.Tr(TranslationTexts.Description),
        price = price,
        icon = "rbxassetid://88523199655864",
    }, function()
        return FX.Network:InvokeServer("C2S_BuyMoneyMultiplier", tier)
    end, function()
        self:OpenPurchase(entry)
    end)
    if opened then
        FX.Network:SendMsgToServer("C2S_CommerceAnalytics", "Seen", -tier, entry or "HUD")
    end
end

--- 同一时间显示一笔报价，等待服务端时保留已确认目标。
--- @param config table 购买 View 所需的商品信息和钻石价格。
--- @param submit function 仅在确认后调用，返回业务结果字符串。
--- @param refreshQuote function? 报价失效时重新打开当前商品。
--- @return boolean 是否已打开确认页。
function Component:OpenDiamondPurchase(config, submit, refreshQuote)
    if self.State and self.State.pending then
        return false
    end
    self.Config = config
    self._submit = submit
    self._refreshQuote = refreshQuote
    self.State = {status = "Ready"}
    self:Show()
    return true
end

--- 失效报价按商品标识关闭；关闭按钮省略标识以关闭当前报价。
--- @param itemId string? 来源界面持有的商品标识。
function Component:CloseDiamondPurchase(itemId)
    if itemId and (not self._submit or self.Config.itemId ~= itemId) then
        return
    end
    self._submit = nil
    self:Hide()
end

--- 复用统一数值格式显示价格。
--- @param amount number 购买费用。
--- @return string 格式化后的价格。
function Component:FormatNumber(amount)
    return Utility.NumberToText(amount)
end

--- 确认后才提交固定商品；服务器回执不足时打开充值页。
--- @param action string Buy 或 Close。
--- @param payload table View 提供的商品 ID。
function Component:OnUIAction(action, payload)
    if action == "Close" then
        self:CloseDiamondPurchase()
        return
    end
    if action ~= "Buy" or not self._submit or self.State.pending or self.State.status ~= "Ready"
        or payload.itemId ~= self.Config.itemId then
        return
    end
    local submit = self._submit
    self.State.pending = true
    self.State.error = nil
    self:RefreshUI()
    self._purchaseTask = task.defer(function()
        local ok, result = pcall(submit)
        self._purchaseTask = nil
        self.State.pending = false
        if ok and result == "InsufficientDiamonds" then
            self._submit = nil
            self:Hide()
            DiamondPurchase.Open()
        elseif ok and (result == "Purchased" or result == "AlreadyOwned") then
            self.State.status = "Purchased"
            self:RefreshUI()
        elseif ok and result == "Submitted" then
            self._submit = nil
            self.State.busy = true
            self:RefreshUI()
            self:Hide()
        elseif ok and (result == "Stale" or result == "Maxed") then
            local refreshQuote = self._submit and self._refreshQuote
            self._submit = nil
            self:Hide()
            if refreshQuote then
                refreshQuote()
            else
                self:GetOwner():RequireComponent("CCommonUICompClass"):ShowLocalizedTips(TranslationTexts.OfferChanged)
            end
        else
            self.State.error = "PurchaseFailed"
            self:RefreshUI()
        end
    end)
end

--- 玩家对象销毁时取消未完成的客户端等待。
function Component:Dtor()
    if self._purchaseTask then
        task.cancel(self._purchaseTask)
    end
    Component.Super.Dtor(self)
end

return Component
