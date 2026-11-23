-- 商店与福利协议共用框架认证身份；共享白名单合入后启用对应动作。
local FX, FS = _G.FX, _G.FS
local MoneyMultiplier = FX.Loader:Require(script.Parent.Parent, "Player.SMoneyMultiplier")
local Service = {}

--- 只注册项目白名单中已声明的 RPC，避免与并行修改的共享路由重复注册。
--- @param name string 项目 C2S 协议名。
--- @param handler function 接收已认证 UserId 的回调。
local function Register(name, handler)
    if table.find(_G.NetworkProtocol.ClientMsgID, name) then
        FX.Network:RegClientMsgCallback(name, handler)
    end
end

--- 服务端管理器创建后注册倍率购买、福利领取和矿区导航。
function Service.Init()
    Register("C2S_BuyMoneyMultiplier", function(userId, expectedTier)
        local player = FS.PlayerManager:GetPlayerObject(userId)
        return player and MoneyMultiplier.Buy(player, expectedTier) or "Failed"
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
