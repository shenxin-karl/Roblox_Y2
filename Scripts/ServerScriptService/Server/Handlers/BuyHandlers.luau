-- 平台商品由 Roblox 收据结算，钻石商品由玩家档案事务结算。
local FX = _G.FX
local Fields = _G.PlayerDataConfig
local Welfare = FX.Loader:RequireShared("Scripts.Game.Shared.WelfareRules")
local DiamondPack = {}
local WeeklyDiamondPass = {}
local CollectAllIncome = {}

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

--- 首次扣费并永久解锁；后续只领取待领在线收益，由同一个奖励计划入账并清零。
--- @param player table 服务端按认证身份取得的玩家对象。
--- @param purchase boolean 是否明确请求购买；领取请求不扣费。
--- @param price number 钻石商品配置中的价格。
--- @return string, number? 购买或领取结果，成功时附带实际到账金币。
function CollectAllIncome:Collect(player, purchase, price)
    local unlocked = player:GetFlag(Fields.CollectAllIncomeUnlocked)
    if purchase then
        if unlocked then
            return "AlreadyOwned"
        end
        if player:GetNumber(Fields.Diamonds) < price then
            return "InsufficientDiamonds"
        end
    elseif not unlocked then
        return "Locked"
    end

    local slots = player:RequireComponent("SSlotSwordComp")
    slots:Accrue()
    local rewards, total = slots:BuildCollectAllRewards()
    if not purchase and total == 0 then
        return "Empty"
    end
    local reward = player:RequireComponent("FSRewardComp")
    local success = player:RunDataTransaction(function()
        if purchase then
            return reward:ExchangeRewards({{Type = "Money", Currency = "Diamonds", Count = price}}, rewards)
                and player:SetFlag(Fields.CollectAllIncomeUnlocked, true)
        end
        return reward:AddRewards(rewards)
    end)
    if not success then
        return "Failed"
    end
    return purchase and "Purchased" or "Claimed", total
end

return {DiamondPack = DiamondPack, WeeklyDiamondPass = WeeklyDiamondPass, CollectAllIncome = CollectAllIncome}
