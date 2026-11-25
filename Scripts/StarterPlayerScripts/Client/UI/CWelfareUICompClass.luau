-- 福利中心只展示同步档案；每日、签到和在线奖励由服务端领取。
local FX, FC = _G.FX, _G.FC
local Loader = FX.Loader
local Fields = _G.PlayerDataConfig
local Welfare = Loader:RequireShared("Scripts.Game.Shared.WelfareRules")
local Utility = Loader:RequireShared("Scripts.Game.Shared.GameUtility")
local SwordRules = Loader:RequireShared("Scripts.Game.Shared.SwordRules")
Loader:RequireFromParent(script, "Generated.CWelfareView")
local Component = FX.Class("CWelfareUICompClass", "CWelfareView")
local TranslationTexts = FX.Text.Define("Y2Welfare", {ClaimFailed = "A reward could not be claimed. Please try again."})

--- 绑定生成按钮与档案订阅，初次加入时保持隐藏。
function Component:OnReady()
    Component.Super.OnReady(self)
    self:Hide()
    for index, field in ipairs({Fields.WelfareData, Fields.WelfareTasks}) do
        self:WatchDataChanged(field, function()
            self:UpdateWelfare()
        end)
    end
    self:TrackConnection(FC.Localization.Changed:Connect(function()
        self:UpdateWelfare()
    end))
end

--- 由同步档案生成 View 需要的分组、资格和剩余领取次数。
function Component:UpdateWelfare()
    local data = self:GetTable(Fields.WelfareData)
    local tasks = self:GetTable(Fields.WelfareTasks)
    local passes = {}
    for index, goodsId in ipairs(Welfare.PassIds) do
        local product = _G.GoodsConfig.GoodsData[goodsId]
        local pass = data.Passes[tostring(goodsId)]
        passes[index] = {name = product.Name, amount = product.NumberArray[2],
            remaining = pass and pass.Remaining or 0, claimedToday = pass ~= nil and pass.LastClaimDay >= data.Day}
    end
    self.Config = {
        diamonds = {rewardId = "daily_diamonds", loginAmount = Welfare.DailyAmount, passes = passes},
        groups = Welfare.Groups,
    }
    local amount = data.Day >= 0 and Welfare.GetDailyAmount(data) or 0
    local diamondStatus = data.Day < 0 and "Locked" or (amount > 0 and "Claimable" or "Claimed")
    local onlineMinutes = data.OnlineSeconds / 60
    local entries = {}
    for index, group in ipairs(Welfare.Groups) do
        local groupEntries = {}
        entries[group.kind] = groupEntries
        local kind = group.kind
        local claims = if kind == "online" then data.OnlineClaims elseif kind == "signin" then data.SignInClaims
            elseif tasks.Day == data.Day then tasks.Claims else {}
        for itemIndex, item in ipairs(group.items) do
            local current = kind == "task" and Welfare.GetTaskProgress(tasks, data.Day, item.id) or nil
            local ready = (kind == "online" and onlineMinutes >= item.minutes)
                or (kind == "signin" and data.SignInDay >= item.day)
                or (kind == "task" and current >= item.target)
            groupEntries[item.id] = {
                status = claims[item.id] and "Claimed" or (ready and "Claimable" or "Locked"),
                pending = self._claimKind == group.kind and self._claimId == item.id,
                current = current,
            }
        end
    end
    self.State = {diamonds = {amount = amount, status = diamondStatus, pending = self._claimKind == "diamonds"},
        onlineMinutes = onlineMinutes, signInDay = data.SignInDay, entries = entries, busy = self._claiming == true}
    self:RefreshUI()
end

--- 使用 View 的金币、钻石和道具原型；配置道具共用名称和图标字段。
--- @param reward table 福利规则中定义的奖励。
--- @return table View 所需的名称、图标类别和可选道具图。
function Component:GetRewardDisplay(reward)
    if reward.type == "Blank" then
        local icon = _G.GameConfig.WeaponData[1].BlankIconId or _G.ItemConfig.Display[SwordRules.BlankItemId].IconId
        return {name = reward.id, icon = "Egg", image = icon}
    elseif reward.type == "Item" then
        local item = _G.ItemConfig.Display[reward.id]
        return {name = item.Name, icon = "Egg", image = item.IconId}
    end
    return {name = reward.id, icon = reward.id == "Money" and "Coin" or "Gem"}
end

--- @param amount number 原始奖励数量。
--- @return string 统一缩写后的展示值。
function Component:FormatNumber(amount)
    return Utility.NumberToText(amount)
end

--- 生成页一次发出多条 Claim 时保留全部条目，依序请求各奖励。
--- @param action string Claim 或 ClaimDiamonds。
--- @param payload table View 提供的奖励 ID 与可选分类。
function Component:OnUIAction(action, payload)
    if self._claiming or (action ~= "Claim" and action ~= "ClaimDiamonds") then
        return
    end
    local kind = action == "ClaimDiamonds" and "diamonds" or payload.kind
    local id = payload.rewardId
    local entry = kind == "diamonds" and self.State.diamonds or self.State.entries[kind][id]
    if entry.status ~= "Claimable" then
        return
    end
    if self._claimQueue then
        table.insert(self._claimQueue, {kind = kind, id = id})
        return
    end
    local queue = {{kind = kind, id = id}}
    self._claimQueue = queue
    self._claimTask = task.defer(function()
        self._claiming = true
        local failed = false
        for index, claim in ipairs(queue) do
            self._claimKind, self._claimId = claim.kind, claim.id
            self:UpdateWelfare()
            local ok, claimed = pcall(function()
                return FX.Network:InvokeServer("C2S_ClaimWelfare", claim.kind, claim.id)
            end)
            failed = failed or not ok or not claimed
        end
        self._claimTask = nil
        self._claimQueue = nil
        self._claiming = false
        self._claimKind, self._claimId = nil, nil
        self:UpdateWelfare()
        if failed then
            self:GetOwner():RequireComponent("CCommonUICompClass"):ShowLocalizedTips(TranslationTexts.ClaimFailed)
        end
    end)
end

--- 关闭玩家对象时取消未完成请求，父类释放模板与订阅。
function Component:Dtor()
    if self._claimTask then
        task.cancel(self._claimTask)
    end
    Component.Super.Dtor(self)
end

return Component
