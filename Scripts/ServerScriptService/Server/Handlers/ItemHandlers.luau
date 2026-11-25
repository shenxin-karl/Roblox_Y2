-- 收益卡在使用时计算真实基地收益，零收益时保留道具。
return {
    WelfareIncomeCard = {
        --- 缓存本次使用计算出的金额，后续扣卡和发奖共用此值。
        --- @param handler table 由框架调用的处理器。
        --- @param context table 当前玩家与道具使用上下文。
        --- @return boolean 是否有可兑换的金币。
        CanUse = function(handler, context)
            local welfare = context.playerObject:RequireComponent("SWelfareComp")
            context.extraData = welfare:GetBaseIncome() * context.itemDataConfig.NumberArray[1]
            return context.extraData > 0 and context.extraData < math.huge
        end,
        --- 发放预检时计算的金币，调用方负责在失败时回滚扣卡。
        --- @param handler table 由框架调用的处理器。
        --- @param context table 当前玩家与已验证收益。
        --- @return boolean 金币是否到账。
        Use = function(handler, context)
            return context.playerObject:RequireComponent("FSRewardComp"):AddRewards({
                {Type = "Money", Currency = "Money", Count = context.extraData},
            })
        end,
    },
}
