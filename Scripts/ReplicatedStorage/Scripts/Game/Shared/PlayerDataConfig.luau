-- 模板玩家字段；玩法字段由新项目显式添加，默认值集中维护。
_G.PlayerKVEnum = {
    ePlayerData = "PlayerData",
    eDynamicData = "DynamicData",
    eStaticData = "StaticData",
    eActivityData = "ActivityData",
}
local PlayerKVEnum = _G.PlayerKVEnum

return {
    Money = {
        Type = "number", Key = "Money", DefVal = 0,
        KVTable = PlayerKVEnum.ePlayerData, Sync = true,
    },
    Diamonds = {
        Type = "number", Key = "Diamonds", DefVal = 0,
        KVTable = PlayerKVEnum.ePlayerData, Sync = true,
    },
    Settings = {
        Type = "table", Key = "Settings",
        DefVal = {musicVolume = 100, soundEffectsVolume = 100},
        KVTable = PlayerKVEnum.eStaticData, Sync = true,
    },
    DataVersion = {
        Type = "number", Key = "DataVersion", DefVal = 0,
        KVTable = PlayerKVEnum.ePlayerData, Sync = false,
    },
    Inventory = {
        Type = "table", Key = "Inventory", DefVal = {},
        KVTable = PlayerKVEnum.ePlayerData, Sync = false,
    },
    Guide = {
        Type = "table", Key = "Guide",
        DefVal = {activeGuideId = "", guideMap = {}, target = {type = "None"}},
        KVTable = PlayerKVEnum.ePlayerData, Sync = true,
    },
    GoodsBuyInfo = {
        Type = "table", Key = "GoodsBuyInfo", DefVal = {},
        KVTable = PlayerKVEnum.eStaticData, Sync = false,
    },
    HandItemGridIndex = {
        Type = "number", Key = "HandItemGridIndex", DefVal = -1, Sync = true,
    },
    FirstLogin = {
        Type = "boolean", Key = "FirstLogin", DefVal = true,
        KVTable = PlayerKVEnum.eStaticData, Sync = true,
    },
}
