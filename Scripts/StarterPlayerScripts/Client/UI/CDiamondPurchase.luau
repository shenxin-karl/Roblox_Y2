-- 客户端统一钻石购买入口；钻石礼包在货币商店的 Robux 页。
local FC = _G.FC
local DiamondPurchase = {}

--- 打开购买钻石的商品页，可从任何钻石消费界面调用。
--- @return boolean 商店组件已就绪并接受打开请求。
function DiamondPurchase.Open()
    local player = FC.PlayerObject
    local shop = player and player:GetComponent("CCurrencyShopUICompClass")
    if not shop then
        return false
    end
    return shop:OpenTab("Robux")
end

--- 花费钻石前打开共用确认页；这里只展示报价，不扣钻。
--- @param config table 商品信息与钻石价格。
--- @param submit function 确认后的提交动作。
--- @return boolean 是否已打开确认页。
function DiamondPurchase.Confirm(config, submit)
    local confirmation = FC.PlayerObject:GetComponent("CMoneyMultiplierUICompClass")
    return confirmation ~= nil and confirmation:OpenDiamondPurchase(config, submit)
end

--- 来源界面失效时，仅关闭仍在展示的对应商品报价。
--- @param itemId string 要关闭的商品标识。
function DiamondPurchase.CloseConfirmation(itemId)
    local player = FC.PlayerObject
    local confirmation = player and player:GetComponent("CMoneyMultiplierUICompClass")
    if confirmation then
        confirmation:CloseDiamondPurchase(itemId)
    end
end

return DiamondPurchase
