-- 剑的临时成长规则；数值来自源 XLSX 导出的通用配置，不改变槽位解锁等级。
local Config = _G.GameConfig.CommonConfig
local Rules = {ItemId = 1003, RawItemId = Config.FurnaceSwordItemId}

--- 从合并矿石配置查找武器词条对应的变异。
--- @param mutationId string 武器词条中的变异 ID。
--- @return table? 对应矿石配置；未知 ID 返回 nil。
function Rules.GetMutation(mutationId)
    for grade, rockType in pairs(_G.GameConfig.MiningRockData) do
        if rockType.MutationId == mutationId then
            return rockType
        end
    end
    return nil
end

--- 校验武器词条；变异和幸运值必须完整，缺失时不补默认属性。
--- @param extra table? 背包或槽位中保存的武器属性。
--- @return table? 有效的变异和幸运值，损坏属性返回 nil。
function Rules.GetTraits(extra)
    if type(extra) ~= "table" then
        return nil
    end
    local mutationId = extra.MutationId
    local mutation = Rules.GetMutation(mutationId)
    local luck = extra.Luck
    if not mutation or type(luck) ~= "number" or luck < 0 or luck >= math.huge then
        return nil
    end
    return {MutationId = mutationId, Luck = luck}
end

--- 校验背包与槽位之间转移的武器成长，拒绝损坏存档参与交易。
--- @param sword table? 武器成长数据。
--- @return boolean 等级和累计金币是否有效。
function Rules.IsValid(sword)
    return type(sword) == "table" and type(sword.Level) == "number"
        and sword.Level >= 1 and sword.Level % 1 == 0 and sword.Level < math.huge
        and type(sword.StoredMoney) == "number" and sword.StoredMoney >= 0
        and sword.StoredMoney < math.huge and Rules.GetIncome(sword.Level) < math.huge
        and Rules.GetUpgradePrice(sword.Level) < math.huge
end

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
