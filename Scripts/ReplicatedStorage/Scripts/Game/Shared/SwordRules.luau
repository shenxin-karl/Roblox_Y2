-- 剑的临时成长规则；数值来自源 XLSX 导出的通用配置，不改变槽位解锁等级。
local Config = _G.GameConfig.CommonConfig
local Rules = {}

--- 按剑本身等级计算每秒收益，槽位编号不参与成长。
--- @param level number 剑的当前等级。
--- @return number 未格式化的每秒金币数。
function Rules.GetIncome(level)
    return Config.SwordInitialIncome + (level - 1) * Config.SwordIncomePerLevel
end

--- 临时采用线性费用，客户端只展示服务端发布的结果。
--- @param level number 升级前剑的等级。
--- @return number 升到下一级需要的金币数。
function Rules.GetUpgradePrice(level)
    return level * Config.SwordUpgradePricePerLevel
end

return Rules
