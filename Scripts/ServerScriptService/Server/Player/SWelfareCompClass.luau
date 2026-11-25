-- 服务端记录真实在服时间和领取标记；周卡余次跨日保留。
local FX, FS = _G.FX, _G.FS
local Fields = _G.PlayerDataConfig
local PlaytimeRanking = _G.Provider:GetRankingEnum()[2]
local Rules = FX.Loader:RequireShared("Scripts.Game.Shared.WelfareRules")
local SwordRules = FX.Loader:RequireShared("Scripts.Game.Shared.SwordRules")
local Workshop = FX.Loader:RequireShared("Scripts.Game.Shared.UpgradeWorkshopRules")
local Component = FX.Class("SWelfareCompClass", "FSPlayerCompClass")
local Randomizer = Random.new()

--- @return string 玩家福利组件协作名。
function Component:GetCompName()
    return "SWelfareComp"
end

--- 由成功的服务端玩法累计今日任务。
--- @param id string 服务器内部的任务 ID。
function Component:AdvanceTask(id)
    local day = Rules.GetDay(os.time())
    local data = Rules.AdvanceTask(self:GetTable(Fields.WelfareTasks), day, id)
    if data then
        self:SetTable(Fields.WelfareTasks, data)
    end
end

--- 直接从当前展示台重新计算，避免使用上一秒的离线快照。
--- @return number 当前基地每秒金币产出。
function Component:GetBaseIncome()
    local rate = 0
    local base = self:GetTableView(Fields.BaseData)
    for slot, sword in base.SlotData do
        if base.UnlockedSlots[slot] and SwordRules.IsValid(sword) then
            rate += SwordRules.GetIncome(sword)
        end
    end
    return rate * Workshop.GetMultiplier(self:GetTableView(Fields.UpgradeWorkshop).income)
        * self:RequireComponent("SSlotSwordComp"):GetPaidMultiplier()
end

--- 在领取时确定剑胚幸运等级，配置道具（如收益卡、变异石）直接按道具 ID 发放。
--- @param reward table 福利配置中的奖励条目。
--- @return table 奖励组件可发放的单条奖励。
function Component:ResolveReward(reward)
    if reward.type == "Blank" then
        local furnace = Workshop.GetLevel(self:GetTableView(Fields.UpgradeWorkshop).smelt)
        local offset = reward.id == "Lucky Sword Blank" and 2 or Randomizer:NextInteger(-1, 1)
        return {Type = "Item", ItemId = SwordRules.BlankItemId, Count = reward.amount,
            ExtraData = {MutationId = "Normal", blankLuckLevel = math.max(1, furnace + offset)}}
    elseif reward.type == "Item" then
        return {Type = "Item", ItemId = reward.id, Count = reward.amount}
    end
    return {Type = "Money", Currency = reward.id, Count = reward.amount}
end

--- 登录日起算在服时间，离线不累计。
function Component:OnPlayerLogin()
    self._lastUpdate = os.time()
    self:UpdateClock(self._lastUpdate)
end

--- 日福利和月榜共用实际在服时钟；跨月的一次计时按 UTC 月初拆分。
--- @param now number 当前服务端 Unix 秒。
function Component:UpdateClock(now)
    local data = self:GetTable(Fields.WelfareData)
    local day = Rules.GetDay(now)
    if now > self._lastUpdate then
        local ranking = FS.RankingManager:GetRanking(PlaytimeRanking)
        local date = os.date("!*t", now)
        local monthStart = day * 86400 - (date.day - 1) * 86400
        if self._lastUpdate < monthStart then
            ranking:AddOnlineSeconds(self:GetPlayerId(), monthStart - self._lastUpdate, monthStart - 1)
        end
        local currentSeconds = now - math.max(self._lastUpdate, monthStart)
        if currentSeconds > 0 then
            ranking:AddOnlineSeconds(self:GetPlayerId(), currentSeconds, now)
        end
    end
    local elapsed = now - math.max(self._lastUpdate, day * 86400)
    local newDay = day > data.Day
    if not newDay and elapsed <= 0 then
        return
    end
    if newDay then
        data.Day = day
        data.SignInDay = math.min(data.SignInDay + 1, 7)
        data.OnlineSeconds = 0
        data.OnlineClaims = {}
    end
    data.OnlineSeconds += math.max(0, elapsed)
    self._lastUpdate = now
    self:SetTable(Fields.WelfareData, data)
end

--- 在线计时每五秒同步一次，领取前会补齐尾数。
--- @param serverTime number 框架更新时戳；日切使用 Unix 时间。
function Component:OnUpdate(serverTime)
    local now = os.time()
    if self._lastUpdate and now - self._lastUpdate >= 5 then
        self:UpdateClock(now)
    end
end

--- 离服前保存不足一个更新周期的在线时间。
function Component:OnPlayerLogout()
    if self._lastUpdate then
        self:UpdateClock(os.time())
        self._lastUpdate = nil
    end
end

--- 客户端只提交稳定奖励 ID；资格、金额与发放均由服务端决定。
--- @param kind any diamonds、signin、online 或 task。
--- @param id any 配置内的奖励 ID。
--- @return boolean 本次是否实际领取。
function Component:Claim(kind, id)
    if not self._lastUpdate or type(id) ~= "string" then
        return false
    end
    local player = self:GetPlayerObject()
    self:UpdateClock(os.time())
    local data = self:GetTable(Fields.WelfareData)
    local tasks = self:GetTable(Fields.WelfareTasks)
    local reward
    if kind == "diamonds" and id == "daily_diamonds" then
        local amount = Rules.GetDailyAmount(data)
        if amount <= 0 then
            return false
        end
        reward = {Type = "Money", Currency = "Diamonds", Count = amount}
        data.DailyClaimDay = data.Day
        for key, pass in pairs(data.Passes) do
            if pass.Remaining > 0 and pass.LastClaimDay < data.Day then
                pass.Remaining -= 1
                pass.LastClaimDay = data.Day
            end
        end
    elseif kind == "online" or kind == "signin" or kind == "task" then
        local claims = kind == "online" and data.OnlineClaims or (kind == "signin" and data.SignInClaims or tasks.Claims)
        if claims[id] and (kind ~= "task" or tasks.Day == data.Day) then
            return false
        end
        for index, group in ipairs(Rules.Groups) do
            if group.kind ~= kind then
                continue
            end
            for itemIndex, item in ipairs(group.items) do
                if item.id == id then
                    if (kind == "online" and data.OnlineSeconds >= item.minutes * 60)
                        or (kind == "signin" and data.SignInDay >= item.day)
                        or (kind == "task" and Rules.GetTaskProgress(tasks, data.Day, id) >= item.target) then
                        reward = self:ResolveReward(item.reward)
                        claims[id] = true
                    end
                    break
                end
            end
            break
        end
    end
    if not reward then
        return false
    end
    local field, snapshot = Fields.WelfareData, data
    if kind == "task" then
        field, snapshot = Fields.WelfareTasks, tasks
    end
    return player:RunDataTransaction(function()
        return self:RequireComponent("FSRewardComp"):AddRewards({reward}) and self:SetTable(field, snapshot)
    end)
end

return Component
