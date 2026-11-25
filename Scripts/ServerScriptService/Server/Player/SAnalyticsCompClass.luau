-- 服务端根据已提交的玩法结果计算教程和有序漏斗。
local HttpService = game:GetService("HttpService")
local AnalyticsService = game:GetService("AnalyticsService")
local FX, FS = _G.FX, _G.FS
local Fields = _G.PlayerDataConfig
local Tutorial = FX.Loader:RequireShared("Scripts.Game.Shared.TutorialGuideConfig")
local Sword = FX.Loader:RequireShared("Scripts.Game.Shared.SwordRules")
local Workshop = FX.Loader:RequireShared("Scripts.Game.Shared.UpgradeWorkshopRules")
local Mining = FX.Loader:RequireShared("Scripts.Game.Shared.MiningSettings")
local Paid = FX.Loader:RequireShared("Scripts.Game.Shared.MoneyMultiplierRules")
local GameUtility = FX.Loader:RequireShared("Scripts.Game.Shared.GameUtility")
local Texts = FX.Text.Define("TutorialResult", {
    UpgradeIncome = "Weapon income increased from ${before}/s to ${after}/s.",
})
local Comp = FX.Class("SAnalyticsCompClass", "FSPlayerCompClass")
local Version = tostring(game.PlaceVersion)
local MilestoneNotices = {"6", "7", "18"}

--- 返回业务组件协作名。
--- @return string 组件名。
function Comp:GetCompName()
    return "SAnalyticsComp"
end

--- 开始本次统计会话；为已满级熔炉的既有玩家恢复引导，不计入新玩家漏斗。
function Comp:StartSession()
    self._session = HttpService:GenerateGUID(false)
    local player = self:GetPlayerObject()
    local progress = self:GetTable(Fields.TutorialProgress)
    if not progress.FirstAt then
        progress.FirstAt = os.time()
        progress.FirstSession = self._session
        progress.IsNew = not player:HasStoredData(Fields.BaseData)
        progress.Reached["1"] = progress.FirstAt
        local slots = self:GetTableView(Fields.BaseData).UnlockedSlots
        for key, unlocked in slots do
            local slot = tonumber(key)
            if unlocked and slot > Tutorial.InitialSlots and (not progress.FirstSlot or slot < progress.FirstSlot) then
                progress.FirstSlot, progress.FirstUnlockAt = slot, progress.FirstAt
            end
        end
        self:SetTable(Fields.TutorialProgress, progress)
        if progress.IsNew then
            self:Event("FirstJoin", progress.FirstAt)
            self:SendFunnel(progress, 1)
        end
    end
    if not progress.IsNew and not progress.Reached["10"]
        and self:GetTableView(Fields.UpgradeWorkshop).smelt >= Workshop.GetMaxLevel("smelt") then
        progress.Reached["10"] = os.time()
        self:SetTable(Fields.TutorialProgress, progress)
    end
    --- 只从已提交的进度差异读取槽位事件和首次达成的里程碑。
    --- @param current table 新进度。
    --- @param previous table 原进度。
    self:WatchDataChanged(Fields.TutorialProgress, function(current, previous)
        if previous then
            task.defer(function()
                if self._session then
                    if not current.Hidden then
                        for index, step in ipairs(MilestoneNotices) do
                            if current.Reached[step] and not previous.Reached[step] then
                                FX.Network:SendMsgToClient(self:GetPlayerId(), "S2C_TutorialMilestone", step)
                            end
                        end
                    end
                    self:ObserveSlotResults(current, previous)
                    if current.Placements ~= previous.Placements or current.Unlocks ~= previous.Unlocks then
                        self:OnUpdate(os.time())
                    end
                end
            end)
        end
    end)
end

--- 原始事件携带本次会话与版本；数值默认是发生时间。
--- @param name string 稳定的事件名。
--- @param value number? 发生时间或事件值。
--- @param detail string? 具体结果或业务关联标识。
function Comp:Event(name, value, detail)
    local player = self:GetPlayerNode()
    if self._session and player and player.Parent then
        FS.AnalyticsManager:Custom(player, "Y2_" .. name, value or os.time(),
            {Tutorial.Version .. "/" .. Version, self._session, detail or "Success"})
    end
end

--- 按实际发生时刻记录事件，并保存首次满足的里程碑。
--- @param name string 稳定的事件名。
--- @param step number? 主漏斗节点。
--- @param detail string? 具体结果。
function Comp:Record(name, step, detail)
    self:Event(name, nil, detail)
    if step then
        local progress = self:GetTable(Fields.TutorialProgress)
        local key = tostring(step)
        if not progress.Reached[key] then
            progress.Reached[key] = os.time()
            self:SetTable(Fields.TutorialProgress, progress)
        end
    end
end

--- 判断当前是否已经完成六槽目标，供新开轮次记录归属。
--- @return boolean 全部目标是否完成。
function Comp:IsComplete()
    return self:GetTableView(Fields.TutorialProgress).Reached["18"] ~= nil
end

--- 剑胚被锻造台成功接收才算开锻。
--- @param data table 已提交的锻造状态。
function Comp:ForgeStarted(data)
    local step = data.MakerUserId == self:GetPlayerId() and 5 or nil
    self:Record("ForgeStarted", step, (data.BlankId or "GiftOrLegacy") .. "/" .. data.RoundId)
    if data.AfterTutorial then
        self:Event("PostTutorialForgeStarted", nil, data.RoundId)
        self:AdvancePostTutorial(2, "开始新一轮锻造", data.RoundId)
    end
    self:AdvanceOffline("再次开始锻造", 4)
end

--- 一轮只在成品实际进包后计数；旧存档及赠胚保留原有玩法但不计自制。
--- @param data table 刚刚交付的锻造状态。
function Comp:ForgeDelivered(data)
    self:Event("WeaponDelivered", nil, (data.RoundId or "Legacy") .. "/" .. data.FinishMode)
    if data.AfterTutorial then
        self:Event("PostTutorialWeaponDelivered", nil, data.RoundId)
        self:AdvancePostTutorial(3, "获得新武器", data.RoundId)
    end
    if not data.RoundId or data.MakerUserId ~= self:GetPlayerId() then
        return
    end
    local progress = self:GetTable(Fields.TutorialProgress)
    if progress.LastCraftRound == data.RoundId then
        return
    end
    progress.LastCraftRound = data.RoundId
    progress.Crafted += 1
    local index = progress.Crafted
    if index == 1 then
        progress.FirstRound = data.RoundId
        progress.Reached["6"] = os.time()
    elseif index == 2 then
        progress.SecondRound = data.RoundId
        progress.Reached["12"] = os.time()
    elseif index <= 6 then
        progress.Reached[tostring(index + 11)] = os.time()
    end
    self:SetTable(Fields.TutorialProgress, progress)
end

--- 分开记录熔炉、锻造和收益倍率的金币升级。
--- @param id string 工坊项目 ID。
--- @param level number 扣费前等级。
function Comp:WorkshopUpgraded(id, level)
    self:Record("WorkshopUpgrade", id == "smelt" and 10 or nil, id .. "/" .. level .. "/" .. (level + 1))
    if self:IsComplete() then
        self:FirstPostUpgrade(id)
    end
end

--- 分类型只记录达标后的第一笔金币升级。
--- @param kind string 升级类别。
function Comp:FirstPostUpgrade(kind)
    local progress = self:GetTable(Fields.TutorialProgress)
    progress.PostUpgrades = progress.PostUpgrades or {}
    if not progress.PostUpgrades[kind] then
        progress.PostUpgrades[kind] = true
        self:SetTable(Fields.TutorialProgress, progress)
        self:Event("PostTutorialUpgrade", nil, kind)
    end
end

--- 从已提交奖励读出放置、领取、升级、解锁的事实。
--- @param current table 新进度。
--- @param previous table 原进度。
function Comp:ObserveSlotResults(current, previous)
    if current.Placements ~= previous.Placements then
        local result = current.LastPlacement
        self:Event(result.AfterTutorial and "PostTutorialWeaponPlaced" or "WeaponPlaced", result.At,
            result.Round .. "/" .. result.Slot)
        if result.AfterTutorial then
            self:AdvancePostTutorial(4, "放置新武器", result.Round)
        end
    end
    if current.FirstCollection and not previous.FirstCollection then
        local result = current.FirstCollection
        self:Event("FirstHomemadeCollection", current.Reached["8"],
            result.Round .. "/" .. result.Slot .. "/" .. result.Amount)
    end
    if current.WeaponUpgrades ~= previous.WeaponUpgrades then
        local result = current.LastUpgrade
        self:Event("WeaponUpgrade", result.At, (result.Round or "LegacyOrStarter") .. "/" .. result.From .. "/" .. result.To)
        if previous.Reached["18"] then
            self:FirstPostUpgrade("weapon")
        end
        local sword = self:GetTableView(Fields.BaseData).SlotData[tostring(result.Slot)]
        if result.SelfMade and previous.Upgrades == 0 and sword
            and sword.ForgeRoundId == result.Round and sword.Level == result.To then
            local after = self:GetTable(Fields.BaseData).SlotData[tostring(result.Slot)]
            local before = table.clone(after)
            before.Level = result.From
            local multiplier = Workshop.GetMultiplier(self:GetTableView(Fields.UpgradeWorkshop).income)
                * Paid.GetMultiplier(self:GetNumber(Fields.PaidMultiplierTier))
            self:GetPlayerObject():ShowLocalizedTips(Texts.UpgradeIncome, {
                before = GameUtility.NumberToText(Sword.GetIncome(before) * multiplier),
                after = GameUtility.NumberToText(Sword.GetIncome(after) * multiplier),
            })
        end
    end
    if current.Unlocks ~= previous.Unlocks then
        self:Event("SlotUnlocked", current.LastUnlock.At, tostring(current.LastUnlock.Slot))
    end
end

--- 达标后只跟踪新开的轮次；入槽必须匹配一次已交付的成品。
--- @param step number 漏斗节点。
--- @param label string 节点名称。
--- @param round string 锻造轮次标识。
function Comp:AdvancePostTutorial(step, label, round)
    local progress = self:GetTable(Fields.TutorialProgress)
    if not progress.PostStep or progress.PostStep + 1 ~= step
        or (step == 4 and progress.PostRound ~= round) then
        return
    end
    progress.PostStep = step
    if step == 3 then
        progress.PostRound = round
    end
    self:SetTable(Fields.TutorialProgress, progress)
    self:NamedFunnel("Y2_AfterTutorial", progress.FirstSession, step, label, progress.PostVariant)
end

--- 发送已连续满足的步骤，避免平台把跳过的条件自动算成完成。
--- @param progress table 本次可编辑的进度。
--- @param last number 当前连续达到的最高节点。
function Comp:SendFunnel(progress, last)
    local player = self:GetPlayerNode()
    local fields = {Tutorial.Version, Version, "Carry"}
    local latest = progress.FirstAt
    for step = 1, last do
        local previous = latest
        latest = math.max(latest, progress.Reached[tostring(step)])
        if latest - progress.FirstAt <= 86400 and step > progress.Reported
            and FS.AnalyticsManager:Onboarding(player, step, Tutorial.Funnel[step], fields) then
            progress.Reported = step
            if step > 1 then
                FS.AnalyticsManager:Custom(player, "Y2_OnboardingStepSeconds", latest - previous,
                    {Tutorial.Version .. "/" .. Version, tostring(step), "First24Hours"})
            end
        end
        if self._session == progress.FirstSession and step > progress.SessionReported
            and self:NamedFunnel("Y2_FirstSession", progress.FirstSession, step, Tutorial.Funnel[step], "Carry") then
            progress.SessionReported = step
            if step > 1 then
                FS.AnalyticsManager:Custom(player, "Y2_OnboardingStepSeconds", latest - previous,
                    {Tutorial.Version .. "/" .. Version, tostring(step), "FirstSession"})
            end
        end
    end
    self:SetTable(Fields.TutorialProgress, progress)
end

--- 一个命名漏斗在同一会话或尝试内顺序上报。
--- @param name string 漏斗名称。
--- @param id string 漏斗会话标识。
--- @param step number 顺序节点。
--- @param label string 节点名称。
--- @param variant string 入口维度。
--- @return boolean 平台调用是否成功返回。
function Comp:NamedFunnel(name, id, step, label, variant)
    local player = self:GetPlayerNode()
    return FS.AnalyticsManager:Call(player, function()
        AnalyticsService:LogFunnelStepEvent(player, name, id, step, label, {
            [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = Tutorial.Version,
            [Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = Version,
            [Enum.AnalyticsCustomFieldKeys.CustomField03.Name] = variant,
        })
    end)
end

--- 有可领取离线收益的回归只开一次；实际显示由客户端回执。
function Comp:OnPlayerLogin()
    if self:GetTableView(Fields.OfflineIncome).Pending > 0 then
        self:StartOffline()
    end
end

--- 停止离服后的展示和延期分析回调。
function Comp:OnPlayerLogout()
    self._session = nil
end

--- 分别为免费及钻石双倍领取保留相同的回归入口分母。
function Comp:StartOffline()
    if self._offlineStep then
        return
    end
    self._offlineStep = 1
    for index, variant in ipairs({"Free", "Boosted"}) do
        self:NamedFunnel("Y2_Offline" .. variant, self._session, 1, "回归时有离线收益", variant)
    end
end

--- 依序记录界面显示、已到账和本次回归再次开锻。
--- @param action string 节点名。
--- @param step number 节点编号。
--- @param variant string? 成功领取方式。
function Comp:AdvanceOffline(action, step, variant)
    if not self._offlineStep or self._offlineStep + 1 ~= step then
        return
    end
    self._offlineStep = step
    if step == 3 then
        self._offlineVariant = variant
    end
    if step == 2 then
        for index, branch in ipairs({"Free", "Boosted"}) do
            self:NamedFunnel("Y2_Offline" .. branch, self._session, step, action, branch)
        end
    else
        self:NamedFunnel("Y2_Offline" .. self._offlineVariant, self._session, step, action, self._offlineVariant)
    end
end

--- 后续开关只改变展示；回执只记录服务端当前允许显示的步骤。
--- @param action any 客户端动作。
--- @param step any 客户端实际显示的步骤。
function Comp:HandleHint(action, step)
    if action == "OfflineShown" then
        if self:GetTableView(Fields.OfflineIncome).Pending > 0 then
            self:StartOffline()
            self:AdvanceOffline("看到离线收益领取界面", 2)
        end
        return
    end
    local current = self._target
    if not current or current.step ~= step then
        return
    end
    if action == "Shown" and self._shownStep ~= step and current.type ~= "Hidden" then
        self._shownStep = step
        self:Event("HintShown", nil, tostring(step))
    elseif (action == "Hide" or action == "Show") and step >= 9 and step <= 12 then
        local hidden = action == "Hide"
        local progress = self:GetTable(Fields.TutorialProgress)
        if hidden ~= (progress.Hidden == true) then
            progress.Hidden = hidden
            self:SetTable(Fields.TutorialProgress, progress)
            self:Event(hidden and "HintDisabled" or "HintEnabled", nil, tostring(step))
            self:OnUpdate(os.time())
        end
    end
end

--- 计算当前六个目标槽位中的不同自制武器。
--- @param progress table 已保存的引导状态。
--- @param base table 当前基地快照。
--- @return number 六槽内自制成品数。
function Comp:CountStarterWeapons(progress, base)
    local seen, count = {}, 0
    for key, sword in base.SlotData do
        if (tonumber(key) <= Tutorial.InitialSlots or tonumber(key) == progress.FirstSlot)
            and Tutorial.IsSelfMade(sword, self:GetPlayerId()) and not seen[sword.ForgeRoundId] then
            seen[sword.ForgeRoundId] = true
            count += 1
        end
    end
    return count
end

--- 计算下一处玩法目标与实际价格；恢复时重新读取背包、锻造台和基地。
--- @param progress table 已提交的进度。
--- @param base table 当前基地数据。
--- @param count number 六个目标槽内的当前自制武器数。
--- @return table 客户端展示目标。
function Comp:SelectTarget(progress, base, count)
    local hit = progress.Reached
    if not hit["2"] or self:GetNumber(Fields.BaseId) == 0 then
        return {type = "None"}
    end
    if hit["18"] then
        return {type = self._justCompleted and not progress.Hidden and "Complete" or "None", step = 13}
    end
    local step = (not hit["3"] or not hit["4"]) and 1 or not hit["6"] and 3 or not hit["7"] and 4 or not hit["8"] and 5
        or not hit["9"] and 6 or not hit["10"] and 7 or not hit["11"] and 8 or not progress.SecondPlaced and 9
        or not hit["13"] and 10 or count < Tutorial.InitialSlots and 11 or 12
    if step >= 9 and progress.Hidden then
        return {type = "Hidden", step = step}
    end
    local items = self:GetTableView(Fields.Inventory)
    local blank, ore, weapon, second
    for grid, item in items do
        local extra = item.extraData
        if item.itemId == Sword.BlankItemId and extra and extra.BlankMakerUserId == self:GetPlayerId() then
            blank = true
        elseif _G.ItemConfig.Data[item.itemId].Type == "Ore" then
            ore = true
        elseif item.itemId == Sword.ItemId and Tutorial.IsSelfMade(extra, self:GetPlayerId()) then
            weapon = true
            second = second or extra.ForgeRoundId ~= progress.FirstRound
        end
    end
    local forge = self:GetTableView(Fields.ForgeData)
    local player = self:GetPlayerNode()
    local character = player and player.Character
    local target = {step = step, count = count, goal = Tutorial.InitialSlots + 1}
    local slot, replace, upgrade
    local readyMoney, totalMoney, rate, hasSelfMade = 0, 0, 0, false
    local balance = self:GetNumber(Fields.Money)
    local multiplier = Workshop.GetMultiplier(self:GetTableView(Fields.UpgradeWorkshop).income)
        * Paid.GetMultiplier(self:GetNumber(Fields.PaidMultiplierTier))
    for key, unlocked in base.UnlockedSlots do
        local id, sword = tonumber(key), base.SlotData[key]
        if unlocked and (id <= Tutorial.InitialSlots or id == progress.FirstSlot) then
            if not sword and (not slot or id < slot or (step == 9 and id == progress.FirstSlot)) then
                if step ~= 9 or slot ~= progress.FirstSlot then
                    slot = id
                end
            elseif sword and not Tutorial.IsSelfMade(sword, self:GetPlayerId()) and (not replace or id < replace) then
                replace = id
            end
        end
        if sword then
            totalMoney += sword.StoredMoney
        end
        if Tutorial.IsSelfMade(sword, self:GetPlayerId()) then
            hasSelfMade = true
            readyMoney += sword.StoredMoney
            rate += Sword.GetIncome(sword) * multiplier
            local preferred = step == 6 and sword.ForgeRoundId == progress.FirstRound
            local oldSword = upgrade and base.SlotData[tostring(upgrade)]
            if Sword.GetUpgradePrice(sword.Level + 1) < math.huge
                and (not upgrade or preferred
                    or (step ~= 6 or oldSword.ForgeRoundId ~= progress.FirstRound) and id < upgrade) then
                upgrade = id
            end
        end
    end
    local function SetPrice(price)
        target.price = price
        target.short = math.max(0, price - balance)
        target.pending = totalMoney
    end
    if step == 5 and hasSelfMade then
        target.type = "Collect"
        target.waiting = readyMoney <= 0
        target.rate = rate
    elseif (step == 6 or step == 10) and upgrade then
        target.type, target.slot = "Upgrade", upgrade
        SetPrice(Sword.GetUpgradePrice(base.SlotData[tostring(upgrade)].Level))
    elseif step == 7 then
        local level = self:GetTableView(Fields.UpgradeWorkshop).smelt
        if level < Workshop.GetMaxLevel("smelt") then
            target.type = "Luck"
            SetPrice(Workshop.GetPrice("smelt", level))
            if target.short > 0 then
                target.type = "LuckCollect"
            end
        end
    elseif step == 8 then
        local ownBase = self:RequireComponent("SBaseComp"):GetBase()
        for floorIndex = 1, ownBase.FloorCount do
            for id in pairs(ownBase.Floors[floorIndex].Slots) do
                if not base.UnlockedSlots[tostring(id)] and (not target.slot or id < target.slot) then
                    target.slot = id
                end
            end
        end
        target.type = "Unlock"
        if target.slot then
            SetPrice(_G.GameConfig.BaseSlotData[target.slot].UnlockPrice)
        end
    elseif weapon and step ~= 1 and step ~= 3 and (step ~= 9 or second) then
        target.slot = slot or replace
        target.type = slot and "Place" or replace and "Replace" or "NoSlot"
    elseif forge.Active then
        target.type = forge.Finished and "Pending" or "Forge"
        target.inForge = self:GetNumber(Fields.ForgeStation) > 0
    elseif blank then
        target.type = "Forge"
    elseif ore and (step ~= 1 or hit["3"]) then
        target.type = "Smelt"
        if step == 1 then
            target.step = 2
        end
    elseif character and character:GetAttribute(Mining.CarryAttribute) then
        target.type = "Carry"
    else
        target.type = (hit["3"] or step > 1) and "NeedOre" or "Mine"
    end
    return target
end

--- 每秒用当前条件刷新；时间戳保留真实顺序，漏斗只提交连续前缀。
--- @param now number 当前服务器 Unix 秒。
function Comp:OnUpdate(now)
    if not self._session then
        return
    end
    if not self._offlineStep and self:GetTableView(Fields.OfflineIncome).Pending > 0 then
        self:StartOffline()
    end
    local progress = self:GetTable(Fields.TutorialProgress)
    local base = self:GetTableView(Fields.BaseData)
    local hit = progress.Reached
    local changed = false
    local player = self:GetPlayerNode()
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not hit["2"] and self:GetNumber(Fields.BaseId) > 0 and humanoid and humanoid.RootPart
        and humanoid.Health > 0 and not humanoid.PlatformStand then
        hit["2"], changed = now, true
        self:Event("ReadyToPlay", now)
    end
    local firstComplete = progress.FirstSlot ~= nil
    for index = 2, 10 do
        firstComplete = firstComplete and hit[tostring(index)] ~= nil
    end
    if firstComplete and not hit["11"] then
        hit["11"], changed = now, true
        self:Event("FirstRoundComplete", now, tostring(progress.FirstSlot))
    end
    local count = self:CountStarterWeapons(progress, base)
    if hit["11"] and hit["13"] and hit["17"] and not hit["18"] and count == Tutorial.InitialSlots + 1 then
        hit["18"], changed = now, true
        self._justCompleted = true
        progress.PostStep, progress.PostVariant = 1, progress.Hidden and "Hidden" or "Visible"
        self:Event("TutorialComplete", now, progress.PostVariant)
        self:NamedFunnel("Y2_AfterTutorial", progress.FirstSession, 1, "完成新手引导", progress.PostVariant)
    end
    if changed then
        self:SetTable(Fields.TutorialProgress, progress)
    end
    local last = 0
    while hit[tostring(last + 1)] do
        last += 1
    end
    if progress.IsNew and last > (self._attempted or 1) then
        self._attempted = last
        self:SendFunnel(progress, last)
    end
    local target = self:SelectTarget(progress, base, count)
    local previous = self._target
    if previous and target.type == previous.type and target.step == previous.step and target.slot == previous.slot
        and target.count == previous.count and target.price == previous.price and target.short == previous.short
        and target.waiting == previous.waiting and target.pending == previous.pending and target.inForge == previous.inForge
        and target.rate == previous.rate then
        return
    end
    self._target = target
    self:SetTable(Fields.Guide, {target = target})
    if target.type == "NoSlot" and not self._noSlot then
        self._noSlot = true
        self:Event("NoStarterSlot")
    end
end

return Comp
