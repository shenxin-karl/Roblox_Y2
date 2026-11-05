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
        -- 只请求升级当前第一槽的剑，等级、费用与所属玩家均由服务端确定。
        "C2S_UpgradeSlotSword",
        -- 仅提交公共石头节点；次数、矿石奖励和兑换配方由服务端确定。
        "C2S_MineRock",
        "C2S_SmeltSword",
    },
    ServerMsgID = {},
}
