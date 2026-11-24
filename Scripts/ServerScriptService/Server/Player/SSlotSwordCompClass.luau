-- 基地武器：放置、卸下、在线积累和升级由服务端裁定，持久化沿用 BaseData。
local CollectionService = game:GetService("CollectionService")
local FX = _G.FX
local FXLoader = FX.Loader
local Fields = _G.PlayerDataConfig
local Rules = FXLoader:RequireShared("Scripts.Game.Shared.SwordRules")
local WorkshopRules = FXLoader:RequireShared("Scripts.Game.Shared.UpgradeWorkshopRules")
local GameUtility = FXLoader:RequireShared("Scripts.Game.Shared.GameUtility")
local TranslationTexts = FX.Text.Define("BaseWeapon", {
    FinishedRequired = "Equip a finished sword before placing it in an empty slot.",
    BackpackFull = "Not enough backpack space to remove this weapon.",
    Placed = "Weapon placed.",
    Removed = "Weapon returned to your backpack.",
    UpgradeSuccess = "Weapon upgraded to level {level:int}!",
    UpgradeFailed = "Weapon upgrade failed. Please try again.",
    MaxLevel = "This weapon is already at its maximum level.",
    NotEnoughCash = "Not enough cash to upgrade this weapon. You need ${value}.",
})
local WeaponVisual = FXLoader:RequireShared("Scripts.Game.Shared.WeaponVisual")
local MoneyMultiplier = FXLoader:RequireShared("Scripts.Game.Shared.MoneyMultiplierRules")
local Comp = FX.Class("SSlotSwordCompClass", "FSPlayerCompClass")

--- 持有本次会话的显示与节流；离线收益快照通过独立玩家字段保存。
--- @param owner table 当前服务端玩家对象。
function Comp:Ctor(owner)
    Comp.Super.Ctor(self, owner)
    self._lastUpgrade = -math.huge
    self._lastTransfer = -math.huge
    self._displays, self._prompts = {}, {}
end

--- 返回玩家组件协作名称。
--- @return string 槽位剑组件名。
function Comp:GetCompName()
    return "SSlotSwordComp"
end

--- 首次赠剑由奖励框架提交；角色重生不走赠送入口。
function Comp:OnPlayerLogin()
    self._active = true
    local offline = self:GetTable(Fields.OfflineIncome)
    local now = os.time()
    if offline.Timestamp > 0 then
        offline.Pending += offline.Rate * math.clamp(now - offline.Timestamp, 0, _G.GameConfig.CommonConfig.OfflineMaxSeconds)
    end
    offline.Timestamp = now
    self:SetTable(Fields.OfflineIncome, offline)
    self:RequireComponent("FSRewardComp"):AddRewards({{Type = "StarterSlotSword"}})
    self:WatchDataChanged(Fields.BaseId, function()
        self:RefreshSlots()
    end)
    self:WatchDataChanged(Fields.BaseData, function()
        self:RefreshSlots()
    end)
    self:WatchDataChanged(Fields.UpgradeWorkshop, function()
        self:Publish()
    end)
    self:WatchDataChanged(Fields.PaidMultiplierTier, function()
        self:Publish()
    end)
    self:SnapshotIncome()
end

--- 为现有牌子和绿区创建透明展示锚点，不修改地图编辑器管理的实例。
--- @param source BasePart 已核对的地图显示面。
--- @param name string 运行时锚点名称。
--- @param display Model 本槽位的运行时容器。
--- @return Part 本组件拥有的透明锚点。
function Comp:CreateAnchor(source, name, display)
    local part = Instance.new("Part")
    part.Name, part.Size, part.CFrame = name, source.Size, source.CFrame
    part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
    part.Transparency = 1
    if name == "CollectArea" then
        local target = Instance.new("ObjectValue")
        target.Name, target.Value = "AnimationTarget", source
        target.Parent = part
    end
    part.Parent = display
    return part
end

--- 克隆成品剑外观和变异光环，并为每个占用槽位发布独立的收益与升级属性。
--- @param slotId number 已解锁且放有成品剑的槽位编号。
--- @param slot table 管理器持有的场景槽位。
--- @param base table 本次会话的基地。
function Comp:CreateDisplay(slotId, slot, base)
    local standard = FXLoader:Here(slot.Model, "StandardDisplay")
    local top = FXLoader:Here(standard, "DisplayTop")
    local display = Instance.new("Model")
    display.Name = "SlotSword" .. slotId
    display.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
    display:SetAttribute("OwnerUserId", self:GetPlayerId())
    display:SetAttribute("SlotId", slotId)
    local swordData = self:GetSword(slotId)
    local sword = WeaponVisual.Create(swordData.Quality, 4, swordData.MutationId)
    sword.Name = "Sword"
    sword.Anchored, sword.CanCollide, sword.CanTouch, sword.CanQuery = true, false, false, false
    WeaponVisual.SetCFrame(sword, top.CFrame * CFrame.new(0, top.Size.Y / 2 + sword.Size.Y / 2 + 0.1, 0))
    sword.Parent = display
    local sign = self:CreateAnchor(FXLoader:Here(standard, "InformationSign.WritingFace"), "UpgradeSign", display)
    -- SurfaceGui 按钮依赖可查询面；略微前移，避免原牌子挡住点击射线。
    sign.CanQuery = true
    sign.CFrame *= CFrame.new(0, 0, -0.03)
    local collect = self:CreateAnchor(FXLoader:Here(standard, "GreenButton"), "CollectArea", display)
    self._displays[slotId] = {Model = display, Sign = sign, Collect = collect, LastIncome = os.clock()}
    display.Parent = base.Runtime
    self:Publish()
    CollectionService:AddTag(display, "SlotSwordDisplay")
end

--- 只处理已配置的成品武器，剑胚不能产生基地收益。
--- @param slotId number 服务端槽位编号。
--- @return table? 当前槽位的成品剑存档副本。
function Comp:GetSword(slotId)
    local sword = self:GetTable(Fields.BaseData).SlotData[tostring(slotId)]
    if sword and sword.ItemId == Rules.ItemId then
        return sword
    end
    return nil
end

--- 为解锁槽位创建放置或卸下交互，实际触发仍核对引擎提供的玩家身份。
--- @param slotId number 场景槽位编号。
--- @param slot table 已解锁的场景槽位。
--- @param base table 本人的基地会话。
function Comp:CreatePrompt(slotId, slot, base)
    local standard = FXLoader:Here(slot.Model, "StandardDisplay")
    local anchor = Instance.new("Part")
    anchor.Name = "WeaponPoint" .. slotId
    anchor.Anchored, anchor.CanCollide, anchor.CanTouch, anchor.CanQuery = true, false, false, false
    anchor.Size, anchor.Transparency = Vector3.one, 1
    anchor.CFrame = FXLoader:Here(standard, "DisplayTop").CFrame
    anchor.Parent = base.Runtime
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "SlotWeapon"
    prompt.ActionText, prompt.ObjectText, prompt.AutoLocalize = "", "", false
    prompt.HoldDuration, prompt.MaxActivationDistance, prompt.RequiresLineOfSight = 0.35, 10, false
    prompt:SetAttribute("OwnerUserId", self:GetPlayerId())
    prompt:SetAttribute("SlotId", slotId)
    prompt.Parent = anchor
    local connection = prompt.Triggered:Connect(function(player)
        if player == self:GetPlayerNode() then
            self:Transfer(slotId)
        end
    end)
    self._prompts[slotId] = {Prompt = prompt, Anchor = anchor, Connection = connection}
    CollectionService:AddTag(prompt, "BaseWeaponPrompt")
end

--- 进度变化时同步所有已解锁槽位的交互与武器，清除已失效楼层的显示。
function Comp:RefreshSlots()
    local base = self:RequireComponent("SBaseComp"):GetBase()
    if not self._active or not base then
        return
    end
    if not self._collectAllDisplay then
        local display = Instance.new("Model")
        display.Name = "BaseCollectAll"
        display.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
        display:SetAttribute("OwnerUserId", self:GetPlayerId())
        display:SetAttribute("CollectAll", true)
        self:CreateAnchor(base.CollectAll, "CollectArea", display)
        display.Parent = base.Runtime
        self._collectAllDisplay = display
        self:Publish()
        CollectionService:AddTag(display, "SlotSwordDisplay")
    end
    local data = self:GetTable(Fields.BaseData)
    for slotId, entry in pairs(self._prompts) do
        if not data.UnlockedSlots[tostring(slotId)] then
            entry.Connection:Disconnect()
            entry.Anchor:Destroy()
            self._prompts[slotId] = nil
        end
    end
    for slotId, view in pairs(self._displays) do
        if not data.UnlockedSlots[tostring(slotId)] or not self:GetSword(slotId) then
            view.Model:Destroy()
            self._displays[slotId] = nil
        end
    end
    for floorIndex, floor in pairs(base.Floors) do
        for slotId, slot in pairs(floor.Slots) do
            if data.UnlockedSlots[tostring(slotId)] then
                if not self._prompts[slotId] then
                    self:CreatePrompt(slotId, slot, base)
                end
                if self:GetSword(slotId) and not self._displays[slotId] then
                    self:CreateDisplay(slotId, slot, base)
                end
            end
        end
    end
    self:Publish()
end

--- 服务端按本人槽位和距离裁定转移，完成后提示武器去向。
--- @param slotId number 固定在服务端交互回调中的槽位编号。
function Comp:Transfer(slotId)
    local entry = self._prompts[slotId]
    if not entry or not self:IsNear(entry.Anchor, 6)
        or os.clock() - self._lastTransfer < 0.5 then
        return
    end
    self._lastTransfer = os.clock()
    self:Accrue()
    local reward = self:RequireComponent("FSRewardComp")
    local sword = self:GetSword(slotId)
    if sword then
        local traits = Rules.GetTraits(sword)
        if not traits then
            return
        end
        traits.Level, traits.StoredMoney = sword.Level, sword.StoredMoney
        local success = reward:AddRewards({
            {Type = "SlotSwordRemove", SlotId = slotId, Level = sword.Level, StoredMoney = sword.StoredMoney},
            {Type = "Item", ItemId = sword.ItemId, Count = 1,
                ExtraData = traits},
        })
        self:GetPlayerObject():ShowLocalizedTips(success and TranslationTexts.Removed or TranslationTexts.BackpackFull)
    else
        local grid = self:RequireComponent("FSInventoryComp"):GetEquippedGrid()
        local success = grid and reward:AddRewards({{Type = "SlotSwordPlace", SlotId = slotId, Grid = grid}})
        self:GetPlayerObject():ShowLocalizedTips(success and TranslationTexts.Placed or TranslationTexts.FinishedRequired)
    end
end

--- 每次按完整在线秒结算；离服时 View 已失效，使用公开副本接口完成最后结算。
function Comp:Accrue()
    if not self._active then
        return
    end
    local now = os.clock()
    local data = self:GetTable(Fields.BaseData)
    local incomeMultiplier = WorkshopRules.GetMultiplier(self:GetTable(Fields.UpgradeWorkshop).income)
    local changed = false
    for slotId, view in pairs(self._displays) do
        local seconds = math.floor(now - view.LastIncome)
        local sword = data.SlotData[tostring(slotId)]
        if seconds > 0 and sword and sword.ItemId == Rules.ItemId then
            view.LastIncome += seconds
            sword.StoredMoney += Rules.GetIncome(sword) * incomeMultiplier * self:GetPaidMultiplier() * seconds
            changed = true
        end
    end
    if changed then
        self:SetTable(Fields.BaseData, data)
    end
end

--- 按实际根节点距离判定，不能靠客户端提交位置或替其他玩家触发。
--- @param part BasePart 服务端持有的交互锚点。
--- @param horizontalMargin number 交互面的水平扩展距离。
--- @return boolean 本人存活角色是否靠近该面。
function Comp:IsNear(part, horizontalMargin)
    local player = self:GetPlayerNode()
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = humanoid and humanoid.RootPart
    if not self._active or not part or not root or humanoid.Health <= 0 then
        return false
    end
    local offset = part.CFrame:PointToObjectSpace(root.Position)
    return math.abs(offset.X) <= part.Size.X / 2 + horizontalMargin
        and math.abs(offset.Z) <= part.Size.Z / 2 + horizontalMargin
        and math.abs(offset.Y) <= 5
end

--- 钱包入账与累计额清零在同一奖励计划中预检提交，失败保留原累计额。
--- @param slotId number 当前检查的收益槽位。
function Comp:Collect(slotId)
    local sword = self:GetSword(slotId)
    local view = self._displays[slotId]
    if not sword or not view or sword.StoredMoney <= 0 or not self:IsNear(view.Collect, 2) then
        return
    end
    local success = self:RequireComponent("FSRewardComp"):AddRewards({
        {Type = "SlotSwordCollect", SlotId = slotId, Amount = sword.StoredMoney},
        {Type = "Money", Currency = "Money", Count = sword.StoredMoney},
    })
    if success then
        view.Model:SetAttribute("CollectSequence", (view.Model:GetAttribute("CollectSequence") or 0) + 1)
    end
end

--- 本人走到基地前的绿块后，将所有楼层的累计收益作为同一奖励计划领取。
function Comp:CollectAll()
    local base = self:RequireComponent("SBaseComp"):GetBase()
    if not base or not self:IsNear(base.CollectAll, 0) then
        return
    end
    local rewards, total = {}, 0
    local data = self:GetTable(Fields.BaseData)
    for slotId, sword in pairs(data.SlotData) do
        if sword.ItemId == Rules.ItemId and sword.StoredMoney > 0 then
            table.insert(rewards, {Type = "SlotSwordCollect", SlotId = slotId, Amount = sword.StoredMoney})
            total += sword.StoredMoney
        end
    end
    if total > 0 then
        table.insert(rewards, {Type = "Money", Currency = "Money", Count = total})
        local success = self:RequireComponent("FSRewardComp"):AddRewards(rewards)
        if success then
            local display = self._collectAllDisplay
            display:SetAttribute("CollectSequence", (display:GetAttribute("CollectSequence") or 0) + 1)
        end
    end
end

--- 取得附近最近一把已放置剑的正常价格，供 GM 补齐这次升级所需金币。
--- @return number? 可升级剑的原价。
function Comp:GetNearbyUpgradePrice()
    local closestDistance = math.huge
    local price
    for slotId, display in pairs(self._displays) do
        if self:IsNear(display.Sign, 6) then
            local sword = self:GetSword(slotId)
            if Rules.IsValid(sword) and Rules.GetUpgradePrice(sword.Level + 1) < math.huge then
                local position = self:GetPlayerNode().Character:GetPivot().Position
                local distance = (display.Sign.Position - position).Magnitude
                if distance < closestDistance then
                    closestDistance = distance
                    price = Rules.GetUpgradePrice(sword.Level)
                end
            end
        end
    end
    return price
end

--- 只升级本人当前槽位的武器；显示未完成的原因，成功后立即更新牌子和结果提示。
--- @param slotId any 客户端请求的槽位编号。
function Comp:Upgrade(slotId)
    if type(slotId) ~= "number" or slotId % 1 ~= 0 then
        return
    end
    local view = self._displays[slotId]
    if not view or not self:IsNear(view.Sign, 6) or os.clock() - self._lastUpgrade < 0.4 then
        return
    end
    self._lastUpgrade = os.clock()
    self:Accrue()
    local sword = self:GetSword(slotId)
    local player = self:GetPlayerObject()
    if not Rules.IsValid(sword) then
        player:ShowLocalizedTips(TranslationTexts.UpgradeFailed)
        return
    end
    local nextLevel = sword.Level + 1
    if Rules.GetUpgradePrice(nextLevel) >= math.huge then
        player:ShowLocalizedTips(TranslationTexts.MaxLevel)
        return
    end
    local costs = {}
    if self:GetPlayerNode():GetAttribute("GMFreeUpgrades") ~= true then
        local price = Rules.GetUpgradePrice(sword.Level)
        if self:GetNumber(Fields.Money) < price then
            player:ShowLocalizedTips(TranslationTexts.NotEnoughCash, {value = GameUtility.NumberToText(price)})
            return
        end
        costs = {{Type = "Money", Currency = "Money", Count = price}}
    end
    local success = self:RequireComponent("FSRewardComp"):ExchangeRewards(costs,
        {{Type = "SlotSwordUpgrade", SlotId = slotId, ExpectedLevel = sword.Level}})
    if success then
        self:Publish()
        player:ShowLocalizedTips(TranslationTexts.UpgradeSuccess, {level = nextLevel})
    else
        player:ShowLocalizedTips(TranslationTexts.UpgradeFailed)
    end
end

--- 发布公开展示值；离服结算触发数据通知时仍从公开副本读取倍率，不依赖已失效的 View。
function Comp:Publish()
    if self._collectAllDisplay then
        local total = 0
        for slotId, sword in pairs(self:GetTable(Fields.BaseData).SlotData) do
            if sword.ItemId == Rules.ItemId then
                total += sword.StoredMoney
            end
        end
        self._collectAllDisplay:SetAttribute("StoredMoney", total)
    end
    for slotId, view in pairs(self._displays) do
        local sword = self:GetSword(slotId)
        local display = view.Model
        display:SetAttribute("HasSword", sword ~= nil)
        if sword then
            display:SetAttribute("Level", sword.Level)
            display:SetAttribute("Income", Rules.GetIncome(sword)
                * WorkshopRules.GetMultiplier(self:GetTable(Fields.UpgradeWorkshop).income) * self:GetPaidMultiplier())
            display:SetAttribute("UpgradePrice", Rules.GetUpgradePrice(sword.Level))
            display:SetAttribute("StoredMoney", sword.StoredMoney)
            display:SetAttribute("Quality", sword.Quality)
        end
    end
end

--- 付费档位表示最终倍率，历史档位不重复连乘。
--- @return number 当前有效付费金币倍率。
function Comp:GetPaidMultiplier()
    return MoneyMultiplier.GetMultiplier(self:GetNumber(Fields.PaidMultiplierTier))
end

--- 保存当前基地总秒收益和服务端时间；背包武器不参与离线计算。
function Comp:SnapshotIncome()
    local rate = 0
    local data = self:GetTable(Fields.BaseData)
    for slotId, sword in pairs(data.SlotData) do
        if data.UnlockedSlots[slotId] and Rules.IsValid(sword) then
            rate += Rules.GetIncome(sword)
        end
    end
    rate *= WorkshopRules.GetMultiplier(self:GetTable(Fields.UpgradeWorkshop).income) * self:GetPaidMultiplier()
    local offline = self:GetTable(Fields.OfflineIncome)
    offline.Timestamp, offline.Rate = os.time(), rate
    self:SetTable(Fields.OfflineIncome, offline)
end

--- 复用框架每秒更新，积累后自动领取；不用客户端领钱协议或独立保存循环。
--- @param serverTime number 框架秒更新时戳，在线间隔使用单调时钟计算。
function Comp:OnUpdate(serverTime)
    if self._active then
        self:RefreshSlots()
        self:Accrue()
        self:CollectAll()
        for slotId in pairs(self._displays) do
            self:Collect(slotId)
        end
        self:SnapshotIncome()
    end
end

--- 离服结算最后完整在线秒并清理本组件的展示，未领金额仍由框架保存。
function Comp:OnPlayerLogout()
    if not self._active then
        return
    end
    self:Accrue()
    self:SnapshotIncome()
    self._active = false
    if self._collectAllDisplay then
        self._collectAllDisplay:Destroy()
        self._collectAllDisplay = nil
    end
    for slotId, view in pairs(self._displays) do
        view.Model:Destroy()
    end
    for slotId, entry in pairs(self._prompts) do
        entry.Connection:Disconnect()
        entry.Anchor:Destroy()
    end
    table.clear(self._displays)
    table.clear(self._prompts)
end

--- 覆盖非正常销毁路径，基类负责释放数据订阅。
function Comp:Dtor()
    self:OnPlayerLogout()
    Comp.Super.Dtor(self)
end

return Comp
