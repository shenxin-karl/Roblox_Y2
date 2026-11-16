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
--- @return number 玩家收益倍率，不用于两项幸运升级。
function Rules.GetMultiplier(level)
    return FX.CurveSampler:SampleCurveGroupColumn(Numerical.incomeUpgradeCurves, "effect", level + 1)
end

--- 两项幸运升级每级加一，初始幸运为1；不修改已经制作的原料。
--- @param level number 存档中的零起点升级等级。
--- @return number 实际人物或熔炼幸运。
function Rules.GetLuck(level)
    return level + 1
end

--- 五档按模拟器权重抽取，低于1的结果夹到1，变异由矿石原样继承。
--- @param level number 熔炼升级的零起点等级。
--- @param random Random 服务端持有的随机数发生器。
--- @return number 本次原料幸运。
function Rules.RollMaterialLuck(level, random)
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
            return math.max(1, Rules.GetLuck(level) + offset)
        end
    end
    return Rules.GetLuck(level) + 2
end

return Rules
