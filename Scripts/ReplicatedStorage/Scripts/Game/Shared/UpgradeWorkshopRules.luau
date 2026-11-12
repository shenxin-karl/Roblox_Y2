-- 工坊临时成长规则：先打通真实升级，正式平衡配置接入前使用线性费用和效果。
local Rules = {
    MaxLevel = 20,
    BasePrices = {smelt = 10, forge = 20, income = 30},
}

--- 费用按升级前等级线性增长，两端共用同一展示规则。
--- @param upgradeId string 固定升级 ID。
--- @param level number 当前整数等级。
--- @return number 升到下一级的金币消耗。
function Rules.GetPrice(upgradeId, level)
    return Rules.BasePrices[upgradeId] * (level + 1)
end

--- 零级保持原效果，每级增加基础效果的百分之十。
--- @param level number 当前整数等级。
--- @return number 幸运值或收益的倍率。
function Rules.GetMultiplier(level)
    return 1 + level * 0.1
end

return Rules
