-- 项目协议在框架初始化前加载；Ready、同步、好友与购买预检由框架声明。
return {
    ClientMsgID = {
        -- settings: {musicVolume: integer 0..100, soundEffectsVolume: integer 0..100}。
        "C2S_SaveSettings",
        -- 无客户端目标参数，只能回到服务端为本人分配的基地。
        "C2S_ReturnHome",
        -- 仅请求前往锻造庭院入口，落点由服务端决定。
        "C2S_TeleportToForge",
        -- 仅请求进入或离开，不接受客户端指定的台位或传送坐标。
        "C2S_EnterForge",
        "C2S_LeaveForge",
        -- 提交本人槽位编号，等级、费用与所属玩家均由服务端确定。
        "C2S_UpgradeSlotSword",
        -- 在本人已占用的锻造台消耗一个剑胚，配方由服务端确定。
        "C2S_ForgeSword",
        "C2S_FinishSword",
        "C2S_SellSword",
        -- requestId: 递增整数；boosted: 是否用钻石双倍领取；价格和倍率不由客户端提交。
        "C2S_ClaimOfflineIncome",
        "C2S_OfferRawSword",
        "C2S_ReplyRawSword",
        -- 仅提交公共石头节点；次数、矿石奖励和兑换配方由服务端确定。
        "C2S_MineRock",
        "C2S_SmeltSword",
        -- upgradeId: smelt/forge/income；expectedLevel: 整数 0..19；服务端决定价格与新等级。
        "C2S_UpgradeWorkshop",
        -- failureId: 当前损毁进度的服务端标识；费用及恢复内容均由服务端决定。
        "C2S_RecoverForgeSword",
        -- RPC(expectedTier: number)：只购买服务端档位的下一档，返回购买结果字符串。
        "C2S_BuyMoneyMultiplier",
        -- RPC(kind: string, rewardId: string)：服务端校验福利资格，返回是否领取成功。
        "C2S_ClaimWelfare",
        -- 无客户端参数；矿区落点由服务端决定。
        "C2S_TeleportToMine",
    },
    -- S2C_UpgradeWorkshopResult(upgradeId: string, success: boolean)，真实等级沿用玩家字段同步。
    -- S2C_OfflineIncomeResult(requestId: number, success: boolean, insufficientDiamonds: boolean)。
    ServerMsgID = {"S2C_ForgeSwordResult", "S2C_MiningReward", "S2C_UpgradeWorkshopResult", "S2C_RawSwordOffer",
        "S2C_OfflineIncomeResult", "S2C_ForgeRecoveryInsufficientDiamonds"},
}
