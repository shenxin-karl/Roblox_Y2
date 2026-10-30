-- 项目协议在框架初始化前加载；Ready、同步、好友与购买预检由框架声明。
return {
    ClientMsgID = {
        -- settings: {musicVolume: integer 0..100, soundEffectsVolume: integer 0..100}。
        "C2S_SaveSettings",
        -- 无客户端目标参数，只能回到服务端为本人分配的基地。
        "C2S_ReturnHome",
    },
    ServerMsgID = {},
}
