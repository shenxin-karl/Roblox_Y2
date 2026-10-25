local FX = _G.FX

FX.BuyHandlerClass = FX.Class("FXBuyHandlerClass")
local FXBuyHandlerClass = FX.BuyHandlerClass
function FXBuyHandlerClass:CanBuy(context)
    return true
end

function FXBuyHandlerClass:Buy(context)
    error("DefaultHandler:Buy not implemented")
end

FX.BuyContextClass = FX.Class("FXBuyContextClass")
local FXBuyContextClass = FX.BuyContextClass
function FXBuyContextClass:Ctor(playerObject, devGoodsId, num)
    self.playerObject = playerObject
    self.devGoodsId = devGoodsId
    self.num = num
    self.goodsConfig = _G.Provider:GetGoodsConfig(self.devGoodsId)
    self.extraData = nil -- 额外数据, 用于传递给处理器
end

function FXBuyContextClass:CanBuy()
    if not self.goodsConfig then
        return false
    end

    local buyHandler = _G.Provider:GetBuyHandler(self.goodsConfig.BuyHandler)
    if not buyHandler then
        return false
    end

    local ok, ret = FX.PCall(function()
        return buyHandler:CanBuy(self)
    end)
    return ok and ret
end

function FXBuyContextClass:Buy()
    local buyHandler = _G.Provider:GetBuyHandler(self.goodsConfig.BuyHandler)
    if not buyHandler then
        return false
    end
    local ok, ret = FX.PCall(function()
        return buyHandler:Buy(self)
    end)
    return ok and ret
end
return true
