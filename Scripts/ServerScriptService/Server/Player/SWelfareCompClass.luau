-- 服务端记录真实在服时间和领取标记；周卡余次跨日保留。
local FX = _G.FX
local Fields = _G.PlayerDataConfig
local Rules = FX.Loader:RequireShared("Scripts.Game.Shared.WelfareRules")
local Component = FX.Class("SWelfareCompClass", "FSPlayerCompClass")

--- @return string 玩家福利组件协作名。
function Component:GetCompName()
    return "SWelfareComp"
end

--- 登录日起算在服时间，离线不累计。
function Component:OnPlayerLogin()
    self._lastUpdate = os.time()
    self:UpdateClock(self._lastUpdate)
end

--- UTC 换日只重置在线状态，签到以实际登录过的天数累计。
--- @param now number 当前服务端 Unix 秒。
function Component:UpdateClock(now)
    local data = self:GetTable(Fields.WelfareData)
    local day = Rules.GetDay(now)
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
--- @param kind any diamonds、signin 或 online。
--- @param id any 配置内的奖励 ID。
--- @return boolean 本次是否实际领取。
function Component:Claim(kind, id)
    if not self._lastUpdate or type(id) ~= "string" then
        return false
    end
    local player = self:GetPlayerObject()
    self:UpdateClock(os.time())
    local data = self:GetTable(Fields.WelfareData)
    local amount
    if kind == "diamonds" and id == "daily_diamonds" then
        amount = Rules.GetDailyAmount(data)
        data.DailyClaimDay = data.Day
        for key, pass in pairs(data.Passes) do
            if pass.Remaining > 0 and pass.LastClaimDay < data.Day then
                pass.Remaining -= 1
                pass.LastClaimDay = data.Day
            end
        end
    elseif kind == "online" or kind == "signin" then
        local isOnline = kind == "online"
        local claims = isOnline and data.OnlineClaims or data.SignInClaims
        if claims[id] then
            return false
        end
        for index, group in ipairs(Rules.Groups) do
            if group.kind ~= kind then
                continue
            end
            for itemIndex, item in ipairs(group.items) do
                if item.id == id then
                    if (isOnline and data.OnlineSeconds >= item.minutes * 60)
                        or (not isOnline and data.SignInDay >= item.day) then
                        amount = item.reward.amount
                        claims[id] = true
                    end
                    break
                end
            end
            break
        end
    end
    if not amount or amount <= 0 then
        return false
    end
    return player:RunDataTransaction(function()
        return self:RequireComponent("FSRewardComp"):AddRewards({
            {Type = "Money", Currency = "Diamonds", Count = amount},
        }) and self:SetTable(Fields.WelfareData, data)
    end)
end

return Component
