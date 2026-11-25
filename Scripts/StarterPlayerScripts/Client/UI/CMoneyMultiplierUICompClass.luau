-- 倍率确认页复用导出 View；钻石不足时统一转到钻石礼包。
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
    self._expectedTier = tier
    self._purchaseEntry = entry or "HUD"
    self.Config = {
        itemId = tostring(tier),
        name = "",
        nameText = Text.Tr(TranslationTexts.Title, {rate = Utility.NumberToText(Rules.GetMultiplier(tier + 1))}),
        category = TranslationTexts.Category.Source,
        description = "",
        descriptionText = Text.Tr(TranslationTexts.Description),
        price = price,
        icon = "rbxassetid://106875000830237",
    }
    self.State = {status = "Ready"}
    self:Show()
    FX.Network:SendMsgToServer("C2S_CommerceAnalytics", "Seen", -tier, self._purchaseEntry)
end

--- 复用统一数值格式显示价格。
--- @param amount number 购买费用。
--- @return string 格式化后的价格。
function Component:FormatNumber(amount)
    return Utility.NumberToText(amount)
end

--- 客户端只提交已确认档位；服务端余额变化同样可触发缺钻跳转。
--- @param action string Buy 或 Close。
--- @param payload table View 提供的档位商品 ID。
function Component:OnUIAction(action, payload)
    if action == "Close" then
        self:Hide()
        return
    end
    if action ~= "Buy" or self.State.pending or payload.itemId ~= self.Config.itemId then
        return
    end
    self.State.pending = true
    self.State.error = nil
    self:RefreshUI()
    self._purchaseTask = task.defer(function()
        local ok, result = pcall(function()
            return FX.Network:InvokeServer("C2S_BuyMoneyMultiplier", self._expectedTier)
        end)
        self._purchaseTask = nil
        self.State.pending = false
        if ok and result == "InsufficientDiamonds" then
            self:Hide()
            DiamondPurchase.Open()
        elseif ok and result == "Purchased" then
            self.State.status = "Purchased"
            self:RefreshUI()
        elseif ok and (result == "Stale" or result == "Maxed") then
            local wasOpen = self:GetRootNode().Enabled
            if wasOpen then
                self:Hide()
                self:OpenPurchase(self._purchaseEntry)
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
