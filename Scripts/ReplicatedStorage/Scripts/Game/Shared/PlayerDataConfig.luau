-- 模板玩家字段；玩法字段由新项目显式添加，默认值集中维护。
_G.PlayerKVEnum = {
    ePlayerData = "PlayerData",
    eDynamicData = "DynamicData",
    eStaticData = "StaticData",
    eActivityData = "ActivityData",
}
local PlayerKVEnum = _G.PlayerKVEnum
local initialUnlockedSlots = {}
for slotId = 1, _G.GameConfig.CommonConfig.BaseInitialSlots do
    initialUnlockedSlots[tostring(slotId)] = true
end

return {
    Money = {
        Type = "number", Key = "Money", DefVal = 0,
        KVTable = PlayerKVEnum.ePlayerData, Sync = true,
    },
    Diamonds = {
        Type = "number", Key = "Diamonds", DefVal = 0,
        KVTable = PlayerKVEnum.ePlayerData, Sync = true,
    },
    -- 进度随玩家保存；SlotData 以字符串槽位编号保存各槽的业务数据，不保存场景实例。
    BaseData = {
        Type = "table", Key = "BaseData",
        DefVal = {
            UnlockedSlotCount = _G.GameConfig.CommonConfig.BaseInitialSlots,
            UnlockedSlots = initialUnlockedSlots, SlotData = {},
        },
        KVTable = PlayerKVEnum.ePlayerData, Sync = true,
    },
    -- 场景基地每次登录重新分配，不随档案保存；0 表示正在等待空基地。
    BaseId = {
        Type = "number", Key = "BaseId", DefVal = 0, Sync = true,
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
