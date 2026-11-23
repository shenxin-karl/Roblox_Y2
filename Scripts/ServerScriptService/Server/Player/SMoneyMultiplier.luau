-- 金钱倍率只接受已认证玩家和预期档位，扣款与升级同档事务提交。
local FX = _G.FX
local Fields = _G.PlayerDataConfig
local Rules = FX.Loader:RequireShared("Scripts.Game.Shared.MoneyMultiplierRules")
local MoneyMultiplier = {}

--- 重查存档档位与余额；重复请求不能自动购买下一档。
--- @param player table 服务端按认证 UserId 取得的玩家对象。
--- @param expectedTier any 客户端确认购买时显示的当前档位。
--- @return string 购买结果：Purchased、InsufficientDiamonds、Maxed、Stale 或 Failed。
function MoneyMultiplier.Buy(player, expectedTier)
    local tier = player:GetNumber(Fields.PaidMultiplierTier)
    if expectedTier ~= tier then
        return "Stale"
    end
    local price = Rules.GetNextPrice(tier)
    if not price then
        return "Maxed"
    end
    if player:GetNumber(Fields.Diamonds) < price then
        return "InsufficientDiamonds"
    end

    local slots = player:RequireComponent("SSlotSwordComp")
    slots:Accrue()
    local success = player:RunDataTransaction(function()
        return player:RequireComponent("FSRewardComp"):ExchangeRewards({
            {Type = "Money", Currency = "Diamonds", Count = price},
        }, {}) and player:SetNumber(Fields.PaidMultiplierTier, tier + 1)
    end)
    if not success then
        return "Failed"
    end
    slots:SnapshotIncome()
    return "Purchased"
end

return MoneyMultiplier
