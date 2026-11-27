-- 存档档位 1 对应原有的 2 倍收益，后续各档沿用 Y2 收益曲线。
local FX = _G.FX
local Numerical = FX.Loader:RequireShared("Scripts.Game.Configs.NumericalConfig")
local Rules = {MaxTier = 8}

--- 沿用 Y1：同服好友每人增加 0.25 倍，最多计 4 人；好友状态未就绪时不加成。
function Rules.GetFriendBonus(friendCount)
    return math.min(friendCount or 0, 4) * 0.25
end

--- 取当前槽位收益倍率，最高 256 倍。
--- @param tier number 玩家持久化档位。
--- @return number 当前倍率。
function Rules.GetMultiplier(tier)
    local curveTier = math.clamp(tier, 1, Rules.MaxTier)
    return FX.CurveSampler:SampleCurveGroupColumn(Numerical.paidMultiplierCurves, "multiplier", curveTier)
end

--- 按目标档位取价格，保留各倍率原定的价格。
--- @param tier number 玩家当前档位。
--- @return number? 达到上限时无下一档价格。
function Rules.GetNextPrice(tier)
    if tier >= Rules.MaxTier then
        return nil
    end
    return FX.CurveSampler:SampleCurveGroupColumn(Numerical.paidMultiplierCurves, "diamondCost", tier + 1)
end

return Rules
