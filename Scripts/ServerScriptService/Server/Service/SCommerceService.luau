-- 商店与福利协议共用框架认证身份；共享白名单合入后启用对应动作。
local FX, FS = _G.FX, _G.FS
local MoneyMultiplier = FX.Loader:Require(script.Parent.Parent, "Player.SMoneyMultiplier")
local PurchaseReceiptService = FX.Loader:RequireFromParent(script, "SPurchaseReceiptService")
local CollectAllGoodsId = 201
local Service = {}

--- 只注册项目白名单中已声明的 RPC，避免与并行修改的共享路由重复注册。
--- @param name string 项目 C2S 协议名。
--- @param handler function 接收已认证 UserId 的回调。
local function Register(name, handler)
    if table.find(_G.NetworkProtocol.ClientMsgID, name) then
        FX.Network:RegClientMsgCallback(name, handler)
    end
end

--- 服务端管理器创建后注册钻石购买、福利领取和矿区导航。
function Service.Init()
    Register("C2S_CollectAllIncome", function(userId, purchase)
        local player = FS.PlayerManager:GetPlayerObject(userId)
        if not player or type(purchase) ~= "boolean" then
            return "Failed"
        end
        local config = _G.GoodsConfig.GemGoodsData[CollectAllGoodsId]
        local handler = _G.Provider:GetBuyHandler(config.BuyHandler)
        return handler:Collect(player, purchase, config.Price)
    end)
    Register("C2S_BuyMoneyMultiplier", function(userId, expectedTier)
        local player = FS.PlayerManager:GetPlayerObject(userId)
        if not player or type(expectedTier) ~= "number" or expectedTier % 1 ~= 0 then
            return "Failed"
        end
        local attempt = PurchaseReceiptService.GetMultiplierAttempt(player, expectedTier)
        local result = MoneyMultiplier.Buy(player, expectedTier)
        PurchaseReceiptService.ReportMultiplier(player, expectedTier, result, attempt)
        return result
    end)
    Register("C2S_ClaimWelfare", function(userId, kind, rewardId)
        local player = FS.PlayerManager:GetPlayerObject(userId)
        local component = player and player:GetComponent("SWelfareComp")
        return component ~= nil and component:Claim(kind, rewardId) or false
    end)
    Register("C2S_TeleportToMine", function(userId)
        local player = FS.PlayerManager:GetPlayerObject(userId)
        local mining = player and player:GetComponent("SMiningComp")
        if mining then
            mining:TeleportToMine()
        end
    end)
end

return Service
