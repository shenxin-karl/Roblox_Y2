-- 引导目标与主漏斗的稳定编号。
local Tutorial = {
    Version = "Y2_V1",
    RequiredOre = 1,
    InitialSlots = _G.GameConfig.CommonConfig.BaseInitialSlots,
    Funnel = {
        "首次进入游戏", "准备就绪", "拾取矿石", "熔炼出剑胚", "开始锻造",
        "获得第一把武器", "放置自制武器", "领取自制武器收益",
        "升级自制武器", "升级熔炉幸运", "完成首轮",
        "获得第二把武器", "第二次升级武器", "获得第三把武器",
        "获得第四把武器", "获得第五把武器", "获得第六把武器", "填满六个初始槽位",
    },
}

--- 赠送剑胚和初始赠剑没有当前玩家的完整打造来源。
--- @param sword table? 槽位或背包内保存的成品属性。
--- @param userId number 当前玩家。
--- @return boolean 是否由本人制胚并锻造。
function Tutorial.IsSelfMade(sword, userId)
    return sword ~= nil and sword.MakerUserId == userId and type(sword.ForgeRoundId) == "string"
end

return Tutorial
