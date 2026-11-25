-- Y2 福利档位及每日任务；需变异矿石或邀请回执的条目暂不开放。
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
            {id = "3", minutes = 3, reward = {type = "Blank", id = "Sword Blank", amount = 1}},
            {id = "card_6", minutes = 6, reward = {type = "Item", id = 1201, amount = 1}},
            {id = "lucky_10", minutes = 10, reward = {type = "Blank", id = "Lucky Sword Blank", amount = 1}},
            {id = "card_15", minutes = 15, reward = {type = "Item", id = 1202, amount = 1}},
            {id = "diamonds_20", minutes = 20, reward = {type = "Money", id = "Diamonds", amount = 8}},
            {id = "gold_stone_30", minutes = 30, reward = {type = "Item", id = 1302, amount = 1}},
        }},
        {kind = "task", page = "TasksBox", columns = 1, gapX = 0, gapY = 9, items = {
            {id = "gift", title = "Gift Sword Blanks", target = 2,
                reward = {type = "Item", id = 1201, amount = 1}},
            {id = "smelt", title = "Smelt Sword Blanks", target = 10,
                reward = {type = "Item", id = 1202, amount = 1}},
            {id = "hammer", title = "Hammer at the Forge", target = 50,
                reward = {type = "Money", id = "Diamonds", amount = 5}},
        }},
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

--- 旧档案和昨天的任务进度按未开始展示。
--- @param data table 玩家每日任务存档。
--- @param day number 当前福利 UTC 日。
--- @param id string 任务 ID。
--- @return number 当前进度。
function Rules.GetTaskProgress(data, day, id)
    return data.Day == day and (data.Progress[id] or 0) or 0
end

--- 按已配置的目标封顶，避免完成后继续反复写档。
--- @param data table 玩家每日任务存档副本。
--- @param day number 当前 UTC 日。
--- @param id string 可信玩法事件对应的任务 ID。
--- @return table? 有新进度时返回更新后的快照。
function Rules.AdvanceTask(data, day, id)
    for index, item in ipairs(Rules.Groups[3].items) do
        if item.id ~= id then
            continue
        end
        local current = Rules.GetTaskProgress(data, day, id)
        if current >= item.target then
            return nil
        end
        if data.Day ~= day then
            data = {Day = day, Progress = {}, Claims = {}}
        end
        data.Progress[id] = current + 1
        return data
    end
    return nil
end

return Rules
