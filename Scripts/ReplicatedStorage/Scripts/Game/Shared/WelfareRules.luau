-- 迁移 Y1 福利中的钻石档位；Y1 专属道具与任务不进入 Y2。
local FX = _G.FX
local Numerical = FX.Loader:RequireShared("Scripts.Game.Configs.NumericalConfig")
local Rules = {
    DailyAmount = Numerical.dailyDiamondReward,
    PassIds = {111, 112},
    Groups = {
        {kind = "signin", page = "SignInBox", columns = 3, gapX = 9, gapY = 12, items = {
            {id = "2", day = 2, reward = {type = "Money", id = "Diamonds", amount = 15}},
            {id = "5", day = 5, reward = {type = "Money", id = "Diamonds", amount = 15}},
            {id = "7", day = 7, reward = {type = "Money", id = "Diamonds", amount = 20}},
        }},
        {kind = "online", page = "OnlineBox", columns = 3, gapX = 16, gapY = 12, items = {
            {id = "10", minutes = 10, reward = {type = "Money", id = "Diamonds", amount = 2}},
            {id = "20", minutes = 20, reward = {type = "Money", id = "Diamonds", amount = 3}},
            {id = "30", minutes = 30, reward = {type = "Money", id = "Diamonds", amount = 5}},
        }},
        {kind = "task", page = "TasksBox", columns = 1, gapX = 0, gapY = 9, items = {}},
    },
}

--- 按 UTC 日切换签到、在线进度和钻石领取。
--- @param timestamp number Unix 秒。
--- @return number UTC 日序号。
function Rules.GetDay(timestamp)
    return math.floor(timestamp / 86400)
end

--- 计算今日可领取的登录钻石及已激活的两张周卡。
--- @param data table 玩家福利存档。
--- @return number 今日可领取数量。
function Rules.GetDailyAmount(data)
    local amount = data.DailyClaimDay == data.Day and 0 or Rules.DailyAmount
    for key, pass in pairs(data.Passes) do
        if pass.Remaining > 0 and pass.LastClaimDay < data.Day then
            amount += pass.DailyAmount
        end
    end
    return amount
end

return Rules
