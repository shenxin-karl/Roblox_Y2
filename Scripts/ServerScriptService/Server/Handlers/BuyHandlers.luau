-- Roblox 收据事务负责去重和保存；处理器只写当前玩家档案。
local FX = _G.FX
local Fields = _G.PlayerDataConfig
local Welfare = FX.Loader:RequireShared("Scripts.Game.Shared.WelfareRules")
local DiamondPack = {}
local WeeklyDiamondPass = {}

--- 校验商品中必填的正整数发货参数。
--- @param value any 配置中的奖励数量或天数。
--- @return boolean 是否是有效的发货参数。
local function IsPositiveInteger(value)
    return type(value) == "number" and value > 0 and value % 1 == 0
end

--- @param context table 框架提供的购买上下文。
--- @return boolean 配置是否允许结算一个钻石礼包。
function DiamondPack:CanBuy(context)
    local values = context.goodsConfig.NumberArray
    return context.num == 1 and values ~= nil and IsPositiveInteger(values[1])
end

--- @param context table 框架已预检的购买上下文。
--- @return boolean 钻石是否写入档案。
function DiamondPack:Buy(context)
    return context.playerObject:RequireComponent("FSRewardComp"):AddRewards({
        {Type = "Money", Currency = "Diamonds", Count = context.goodsConfig.NumberArray[1]},
    })
end

--- @param context table 框架提供的购买上下文。
--- @return boolean 配置是否指定了有效周卡及奖励。
function WeeklyDiamondPass:CanBuy(context)
    local config = context.goodsConfig
    local values = config.NumberArray
    return context.num == 1 and table.find(Welfare.PassIds, config.DevGoodsId) ~= nil and values ~= nil
        and IsPositiveInteger(values[1]) and IsPositiveInteger(values[2]) and values[3] == 6
end

--- 即时发放首日钻石，余次从次日开始；同日续购只增加未来次数。
--- @param context table 框架已预检的购买上下文。
--- @return boolean 即时钻石与周卡存档是否一起提交。
function WeeklyDiamondPass:Buy(context)
    local config = context.goodsConfig
    local values = config.NumberArray
    local player = context.playerObject
    local data = player:GetTable(Fields.WelfareData)
    local key = tostring(config.DevGoodsId)
    local pass = data.Passes[key]
    if not pass or pass.Remaining == 0 then
        pass = {LastClaimDay = Welfare.GetDay(os.time()), Remaining = 0}
    end
    pass.DailyAmount = values[2]
    pass.Remaining += values[3]
    data.Passes[key] = pass
    return player:RequireComponent("FSRewardComp"):AddRewards({
        {Type = "Money", Currency = "Diamonds", Count = values[1]},
    }) and player:SetTable(Fields.WelfareData, data)
end

return {DiamondPack = DiamondPack, WeeklyDiamondPass = WeeklyDiamondPass}
