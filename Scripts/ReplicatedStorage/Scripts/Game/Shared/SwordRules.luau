-- 武器品质、逐锤概率与收益规则；静态武器映射来自 XLSX，成长曲线来自模拟器。
local FX = _G.FX
local Config = _G.GameConfig.CommonConfig
local Numerical = FX.Loader:RequireShared("Scripts.Game.Configs.NumericalConfig")
local Rules = {ItemId = 1003, BlankItemId = Config.SwordBlankItemId}

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

--- 从道具配置解析变异石的目标词条，其他道具不参与变异。
--- @param itemId number 背包道具配置 ID。
--- @return table? 目标变异配置。
function Rules.GetStoneMutation(itemId)
    local item = _G.ItemConfig.Data[itemId]
    if item and item.Type == "MutationStone" and item.KVTable then
        return Rules.GetMutation(item.KVTable.MutationId)
    end
    return nil
end

--- 校验剑胚或成品词条；变异与剑胚幸运等级独立保存，缺失时不补默认属性。
--- @param extra table? 背包或槽位中保存的武器属性。
--- @return table? 有效的变异和剑胚幸运等级，损坏属性返回 nil。
function Rules.GetTraits(extra)
    if type(extra) ~= "table" then
        return nil
    end
    local mutationId = extra.MutationId
    local mutation = Rules.GetMutation(mutationId)
    local blankLuckLevel = extra.blankLuckLevel
    if not mutation or type(blankLuckLevel) ~= "number" or blankLuckLevel < 1
        or blankLuckLevel >= math.huge or blankLuckLevel % 1 ~= 0 then
        return nil
    end
    return {MutationId = mutationId, blankLuckLevel = blankLuckLevel, Quality = extra.Quality,
        MakerUserId = extra.MakerUserId, ForgeRoundId = extra.ForgeRoundId, AfterTutorial = extra.AfterTutorial}
end

--- 校验背包与槽位之间转移的武器成长，拒绝损坏存档参与交易。
--- @param sword table? 武器成长数据。
--- @return boolean 等级和累计金币是否有效。
function Rules.IsValid(sword)
    return type(sword) == "table" and type(sword.Level) == "number"
        and sword.Level >= 1 and sword.Level % 1 == 0 and sword.Level < math.huge
        and type(sword.StoredMoney) == "number" and sword.StoredMoney >= 0
        and sword.StoredMoney < math.huge and Rules.GetTraits(sword) ~= nil
        and type(sword.Quality) == "number" and _G.GameConfig.WeaponData[sword.Quality] ~= nil
        and Rules.GetIncome(sword) < math.huge
        and Rules.GetUpgradePrice(sword.Level) < math.huge
end

--- 基础秒收益按系数的品质次方计算，再乘武器等级与变异；玩家倍率由调用方加入。
--- @param sword table 含 Quality、Level、MutationId 的成品属性。
--- @return number 未格式化的单把秒收益。
function Rules.GetIncome(sword)
    local mutationMultiplier = Rules.GetMutation(sword.MutationId).mutationMultiplier
    return Config.SwordIncomeCoefficient ^ sword.Quality
        * FX.CurveSampler:SampleCurveGroupColumn(Numerical.swordUpgradeCurves, "levelMultiplier", sword.Level)
        * mutationMultiplier
end

--- 从模拟器导出的武器升级曲线读取当前等级对应费用。
--- @param level number 升级前剑的等级。
--- @return number 升到下一级需要的金币数。
function Rules.GetUpgradePrice(level)
    return FX.CurveSampler:SampleCurveGroupColumn(Numerical.swordUpgradeCurves, "upgradeCost", level)
end

--- 按锻造设计返回单锤百分比；剑胚幸运等级只在成功与破损之间转移概率，变异不参与。
--- @param blankLuckLevel number 剑胚幸运等级 W。
--- @param forgeLevel number 开始打造时的锻造等级 P。
--- @param quality number 当前品质 Q，范围 max(1, P-4) 到 P+3。
--- @return table success、unchanged、broken、destroy 四项百分比。
function Rules.GetForgeProbabilities(blankLuckLevel, forgeLevel, quality)
    local index = quality - forgeLevel + 5
    local success = ({94, 93, 91, 88, 70, 50, 30, 10})[index]
    local unchanged = ({5, 5, 5, 5, 5, 15, 25, 40})[index]
    local destroy = ({0, 0, 0, 0, 3, 5, 10, 15})[index]
    if quality >= forgeLevel then
        local luckDifference = math.clamp(blankLuckLevel - forgeLevel, -10, 10)
        success = luckDifference > 0 and math.min(success * (1 + 0.2 * luckDifference), 100 - unchanged - destroy)
            or success * (1 + 0.05 * luckDifference)
    end
    return {success = success, unchanged = unchanged, broken = 100 - unchanged - destroy - success, destroy = destroy}
end

--- 出售仅回收武器自身一分钟收益和未领金币，不受玩家及付费倍率影响。
--- @param sword table 已校验的成品属性。
--- @return number 本次回收金币。
function Rules.GetSellPrice(sword)
    return Rules.GetIncome(sword) * Config.SwordSellIncomeSeconds + sword.StoredMoney
end

return Rules
