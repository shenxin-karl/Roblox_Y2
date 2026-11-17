-- 工坊升级沿用零级存档；采样模拟器时转换为从1开始的等级。
local FX = _G.FX
local Numerical = FX.Loader:RequireShared("Scripts.Game.Configs.NumericalConfig")
local Rules = {
    MaxLevel = Numerical.forgingUpgradeCurves.input.max - 1,
    BasePrices = {smelt = Numerical.smeltingUpgradeCurves, forge = Numerical.forgingUpgradeCurves,
        income = Numerical.incomeUpgradeCurves},
}

--- 以升级前等级采样下一次费用，两端共用模拟器导出的曲线。
--- @param upgradeId string 固定升级 ID。
--- @param level number 当前整数等级。
--- @return number 升到下一级的金币消耗。
function Rules.GetPrice(upgradeId, level)
    return FX.CurveSampler:SampleCurveGroupColumn(Rules.BasePrices[upgradeId], "upgradeCost", level + 1)
end

--- 零级保持原效果，每级增加基础效果的百分之十。
--- @param level number 当前整数等级。
--- @return number 玩家收益倍率，不用于熔炉或锻造等级。
function Rules.GetMultiplier(level)
    return FX.CurveSampler:SampleCurveGroupColumn(Numerical.incomeUpgradeCurves, "effect", level + 1)
end

--- 熔炉与锻造分别从1级起步，存档各自记录已升级次数；不修改已有剑胚。
--- @param level number 存档中的零起点升级等级。
--- @return number 实际熔炉等级或锻造等级。
function Rules.GetLevel(level)
    return level + 1
end

--- 五档按模拟器权重抽取，低于1的结果夹到1，变异由矿石原样继承。
--- @param furnaceLevel number 本次制作使用的实际熔炉等级 L。
--- @param random Random 服务端持有的随机数发生器。
--- @return number 本次剑胚幸运等级 W，与矿石变异无关。
function Rules.RollBlankLuckLevel(furnaceLevel, random)
    local total, weights = 0, {}
    for offset = -2, 2 do
        local weight = FX.CurveSampler:SampleCurve(Numerical.smeltingLuckWeightCurve, offset + 2)
        weights[offset] = weight
        total += weight
    end
    local roll = random:NextNumber() * total
    for offset = -2, 2 do
        roll -= weights[offset]
        if roll < 0 then
            return math.max(1, furnaceLevel + offset)
        end
    end
    return furnaceLevel + 2
end

return Rules
