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

return DiamondPurchase
