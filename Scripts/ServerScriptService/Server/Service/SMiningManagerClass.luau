-- 服务端公共矿场：同服共用一批矿石，拾取、受击与熔炼由服务端决定。
local FX, FS = _G.FX, _G.FS
local FXLoader = FX.Loader
local Numerical = FXLoader:RequireShared("Scripts.Game.Configs.NumericalConfig")
local Settings = FXLoader:RequireShared("Scripts.Game.Shared.MiningSettings")
local ForgeSettings = FXLoader:RequireShared("Scripts.Game.Shared.ForgeSettings")
local WorkshopRules = FXLoader:RequireShared("Scripts.Game.Shared.UpgradeWorkshopRules")
local Config = _G.GameConfig.CommonConfig
local Fields = _G.PlayerDataConfig
local Tutorial = FXLoader:RequireShared("Scripts.Game.Shared.TutorialGuideConfig")
local HttpService = game:GetService("HttpService")
local TranslationTexts = FX.Text.Define("FurnaceSmelt", {
    Success = "Smelting successful: you received a sword blank.",
    NeedOre = "You need one ore in your backpack to smelt a sword blank.",
    BackpackFull = "Your backpack is full. Make room for the sword blank and try again.",
    OreBackpackFull = "Make room in your backpack to put away the ore you are carrying.",
    OreDeposited = "Ore added to your backpack.",
    TooFar = "Move closer to your furnace to smelt the ore.",
    Failed = "Smelting failed. Please try again.",
})
local Manager = FX.Class("SMiningManagerClass", "FXObjectBaseClass")

--- 矿面是横放的圆柱，局部 X 为厚度；落点保持角色竖直。
--- @return CFrame 矿区中央的传送落点。
function Manager:GetArrival()
    return CFrame.new(self._ground.Position + Vector3.new(0, self._ground.Size.X / 2 + 4, 0))
end

--- 公共矿场启动即出第一批，之后按服务器时间换批，与玩家进出无关。
function Manager:Ctor()
    Manager.Super.Ctor(self)
    assert(Numerical.miningRefreshInterval > 0, "miningRefreshInterval must be positive")
    assert(Numerical.miningSpawnCount > 0 and Numerical.miningSpawnCount % 1 == 0, "Invalid miningSpawnCount")
    local decorations = FXLoader:Workspace("Decorations")
    self._ground = FXLoader:Workspace(Settings.GroundPath)
    self._folder = Instance.new("Folder")
    self._folder.Name = "PublicMiningRocks"
    self._folder.Parent = decorations
    self._rocks = {}
    self._batchId = 0
    self._carried = {}
    self._rockTemplates = {}
    self._oreTypes = {}
    local rockTypes = _G.GameConfig.MiningRockData
    local weights = Numerical.miningMutationProbabilityCurve.weights
    for id in ipairs(weights) do
        assert(rockTypes[id], "Missing spawnable mining rock ID: " .. id)
    end
    -- 保留不再刷新的变异，旧矿石仍可熔炼成原变异的剑胚。
    for id, rockType in pairs(rockTypes) do
        assert(id == rockType.Id, "Invalid mining rock ID: " .. id)
        local template = FXLoader:Shared(rockType.ModelPath)
        assert(template:IsA("Model") and template.PrimaryPart, "Mining rock requires a model with bounds")
        assert(_G.ItemConfig.Data[rockType.OreItemId].Type == "Ore" and not self._oreTypes[rockType.OreItemId],
            "Mining rock requires a distinct ore item: " .. id)
        self._rockTemplates[id] = template
        self._oreTypes[rockType.OreItemId] = rockType
    end
    self._random = Random.new()
    self:Refresh()
end

--- 按实际圆柱矿面判断安全边界，离开矿面后不再承受木棍命中。
--- @param position Vector3 服务端角色位置。
--- @return boolean 角色是否处于矿区。
function Manager:IsInQuarry(position)
    return Settings.IsInQuarry(self._ground, position)
end

--- 同批次只在原坐标生成地面矿石；搬运模型另挂在角色上。
--- @param rock table 当前批次的一块矿石。
function Manager:PlaceRock(rock)
    local model = self._rockTemplates[rock.Grade]:Clone()
    local config = _G.GameConfig.MiningRockData[rock.Grade]
    model.Name = "Rock_" .. rock.Id
    model:ScaleTo(model:GetScale() * config.ModelScale)
    model:PivotTo(rock.Origin)
    for index, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = true
            part.CanTouch = false
        end
    end
    model:SetAttribute("MiningRockId", rock.Id)
    model:SetAttribute("RockGrade", rock.Grade)
    model:SetAttribute("MutationId", config.MutationId)
    model:SetAttribute("MaxHits", 1)
    model:SetAttribute("RemainingHits", 1)
    model:AddTag(Settings.RockTag)
    rock.Model = model
    model.Parent = self._folder
end

--- 替换地上的旧矿；已经扛起的矿仍可搬回基地。
--- @param includeAllGrades boolean 是否给当前刷新池的每个品类保留一个位置。
function Manager:ReplaceGroundRocks(includeAllGrades)
    self._folder:ClearAllChildren()
    table.clear(self._rocks)
    self._batchId += 1
    local radius = math.min(self._ground.Size.Y, self._ground.Size.Z) / 2 - 4
    local center = self._ground.Position + Vector3.new(0, self._ground.Size.X / 2, 0)
    local phase = self._random:NextNumber(0, math.pi * 2)
    local curve = Numerical.miningMutationProbabilityCurve
    local guaranteedCount = includeAllGrades and #curve.weights or 0
    local spawnCount = math.max(Numerical.miningSpawnCount, guaranteedCount)
    for slot = 1, spawnCount do
        local angle = phase + (slot - 1) * math.pi * 2 / spawnCount
        local distance = self._random:NextNumber(radius * 0.35, radius)
        local grade = if slot <= guaranteedCount then slot else FX.CurveSampler:SampleLotteryPrize(curve)
        local config = _G.GameConfig.MiningRockData[grade]
        local position = center + Vector3.new(math.cos(angle) * distance,
            self._rockTemplates[grade].PrimaryPart.Size.Y * config.ModelScale / 2, math.sin(angle) * distance)
        local id = tostring(self._batchId) .. "_" .. slot
        local rock = {Id = id, Grade = grade,
            Origin = CFrame.new(position) * CFrame.Angles(0, self._random:NextNumber(0, math.pi * 2), 0)}
        self._rocks[id] = rock
        self:PlaceRock(rock)
    end
end

--- 自动换批负责更新时间和安排下一次；GM 强刷只替换矿石。
function Manager:Refresh()
    self._nextRefresh = workspace:GetServerTimeNow() + Numerical.miningRefreshInterval
    self:ReplaceGroundRocks(false)
    workspace:SetAttribute(Settings.RefreshAttribute, self._nextRefresh)
    task.delay(Numerical.miningRefreshInterval, function()
        self:Refresh()
    end)
end

--- 阻止通过地图快捷传送跳过搬运。
--- @param player table 当前服务端玩家对象。
--- @return boolean 当前是否扛着一块矿。
function Manager:IsCarrying(player)
    return self._carried[player] ~= nil
end

--- 同一个公共矿石只接受最先到达的有效拾取请求，搬运时只在角色背上显示水晶。
--- @param player table 当前服务端玩家对象。
--- @param humanoid Humanoid 已校验存活的当前角色。
--- @param rockId any 客户端提交的公共矿石编号。
function Manager:PickUp(player, humanoid, rockId)
    if type(rockId) ~= "string" or self._carried[player] or humanoid.PlatformStand
        or workspace:GetServerTimeNow() >= self._nextRefresh then
        return
    end
    local rock = self._rocks[rockId]
    local character = humanoid.Parent
    local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
    local position = humanoid.RootPart.Position
    if not torso or not torso:IsA("BasePart") or not rock or not rock.Model or not self:IsInQuarry(position)
        or (position - rock.Origin.Position).Magnitude > Settings.InteractDistance then
        return
    end
    local model = Instance.new("Model")
    model.Name = "CarriedMiningOre"
    model.WorldPivot = rock.Model:GetPivot()
    for index, group in ipairs(rock.Model:GetDescendants()) do
        if group:IsA("Model") and group.Name == "Crystals" then
            group:Clone().Parent = model
        end
    end
    if #model:GetChildren() == 0 then
        model:Destroy()
        warn("Mining rock has no Crystals model: " .. rock.Grade)
        return
    end
    for name, value in pairs(rock.Model:GetAttributes()) do
        model:SetAttribute(name, value)
    end
    local bounds, size = model:GetBoundingBox()
    local carryScale = math.min(1, torso.Size.Y * 1.5 / math.max(size.X, size.Y, size.Z))
    model.WorldPivot = bounds
    model:ScaleTo(carryScale)
    -- 以水晶包围盒为中心，沿躯干局部 +Z 留出贴背空间。
    model:PivotTo(torso.CFrame * CFrame.new(0, 0, (torso.Size.Z + size.Z * carryScale) / 2 + 0.1))
    for index, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = false, false, false, false
            part.Massless = true
            local weld = Instance.new("WeldConstraint")
            weld.Part0, weld.Part1 = torso, part
            weld.Parent = part
        end
    end
    local carry = {Rock = rock, Model = model, Humanoid = humanoid, Speed = humanoid.WalkSpeed, Hits = 0}
    self._carried[player] = carry
    rock.Model:Destroy()
    rock.Model = nil
    carry.Death = humanoid.Died:Connect(function()
        self:ReleaseOre(player, true)
    end)
    humanoid.WalkSpeed = carry.Speed * Settings.CarrySpeedMultiplier
    model.Parent = character
    character:SetAttribute(Settings.CarryAttribute, true)
    player:RequireComponent("SAnalyticsComp"):Record("OrePicked", 3, "Carry")
end

--- 清除背上的水晶和减速；还矿时保留原刷新点，即使搬运跨过了一次换批。
--- @param player table 当前服务端玩家对象。
--- @param returnToQuarry boolean 是否还矿，入包成功时为 false。
function Manager:ReleaseOre(player, returnToQuarry)
    local carry = self._carried[player]
    if not carry then
        return
    end
    self._carried[player] = nil
    carry.Death:Disconnect()
    carry.Model:Destroy()
    local humanoid = carry.Humanoid
    if humanoid.Parent then
        humanoid.Parent:SetAttribute(Settings.CarryAttribute, nil)
        if humanoid.WalkSpeed == carry.Speed * Settings.CarrySpeedMultiplier then
            humanoid.WalkSpeed = carry.Speed
        end
    end
    local rock = carry.Rock
    if returnToQuarry then
        self._rocks[rock.Id] = rock
        self:PlaceRock(rock)
        if humanoid.Health > 0 then
            player:RequireComponent("SAnalyticsComp"):Record("OreDropped")
        end
    else
        self._rocks[rock.Id] = nil
    end
end

--- 木棍只命中矿区里正前方最近的搬运者；两次命中击倒并归还矿石，不扣血。
--- @param attacker table 来自已认证会话的攻击者。
--- @param humanoid Humanoid 已校验存活且装备木棍的攻击者角色。
function Manager:Strike(attacker, humanoid)
    local source = humanoid.RootPart
    if humanoid.PlatformStand or not self:IsInQuarry(source.Position) then
        return
    end
    local victim, targetRoot
    local nearest = Settings.StickRange
    for player, carry in pairs(self._carried) do
        local target = carry.Humanoid
        local root = target.RootPart
        if player ~= attacker and target.Health > 0 and root and self:IsInQuarry(root.Position) then
            local offset = root.Position - source.Position
            local distance = offset.Magnitude
            if distance <= nearest and (distance < 0.01 or source.CFrame.LookVector:Dot(offset.Unit) >= 0.35) then
                victim, targetRoot, nearest = player, root, distance
            end
        end
    end
    if not victim then
        return
    end
    local carry = self._carried[victim]
    carry.Hits += 1
    if carry.Hits == 2 then
        local target = carry.Humanoid
        self:ReleaseOre(victim, true)
        target.PlatformStand = true
        targetRoot:ApplyAngularImpulse(source.CFrame.RightVector * targetRoot.AssemblyMass * 5)
        task.delay(Settings.KnockdownDuration, function()
            if target.Parent and target.Health > 0 then
                target.PlatformStand = false
            end
        end)
    end
end

--- 角色在本人基地的任一楼层都能交付矿石；没放下前保留减速。
--- @param player table 当前服务端玩家对象。
function Manager:TryDeposit(player)
    local carry = self._carried[player]
    if not carry then
        return
    end
    local humanoid = carry.Humanoid
    local root = humanoid.RootPart
    local base = player:RequireComponent("SBaseComp"):GetBase()
    if not root or humanoid.Health <= 0 or not base or base.OwnerUserId ~= player:GetPlayerId() then
        return
    end
    local inBase = false
    for floorIndex = 1, base.FloorCount do
        local floor = base.Floors[floorIndex].Part
        local offset = floor.CFrame:PointToObjectSpace(root.Position)
        local half = floor.Size / 2
        if math.abs(offset.X) <= half.X and math.abs(offset.Z) <= half.Z
            and offset.Y >= -half.Y and offset.Y <= half.Y + Settings.BaseDepositHeight then
            inBase = true
            break
        end
    end
    if not inBase then
        carry.DepositWarned = nil
        return
    end
    local rockType = _G.GameConfig.MiningRockData[carry.Rock.Grade]
    local rewards = {{Type = "Item", ItemId = rockType.OreItemId, Count = 1}}
    local reward = player:RequireComponent("FSRewardComp")
    if not reward:AddRewards(rewards) then
        if not carry.DepositWarned then
            carry.DepositWarned = true
            player:ShowLocalizedTips(reward:CanAddRewards(rewards)
                and TranslationTexts.Failed or TranslationTexts.OreBackpackFull)
        end
        return
    end
    self:ReleaseOre(player, false)
    player:ShowLocalizedTips(TranslationTexts.OreDeposited)
end

--- 本人到自家炉台时，用背包里一块矿石换剑胚，优先选手持矿石。
--- @param player table 当前服务端玩家对象。
--- @param humanoid Humanoid 已校验存活的当前角色。
function Manager:Smelt(player, humanoid)
    local base = player:RequireComponent("SBaseComp"):GetBase()
    local workshop = base and base.OwnerUserId == player:GetPlayerId() and ForgeSettings.FindPersonalWorkshop(base.Id)
    local hearth = workshop and FXLoader:Find(workshop, ForgeSettings.PersonalFurnacePart)
    if not hearth or (hearth.Position - humanoid.RootPart.Position).Magnitude > ForgeSettings.PersonalInteractDistance then
        player:ShowLocalizedTips(TranslationTexts.TooFar)
        return
    end
    local inventory = player:RequireComponent("FSInventoryComp")
    local items = inventory:GetData()
    local held = items[inventory:GetEquippedGrid()]
    local ore = held and self._oreTypes[held.itemId]
    if not ore then
        for grid, item in pairs(items) do
            local candidate = self._oreTypes[item.itemId]
            if candidate and (not ore or candidate.Id < ore.Id) then
                ore = candidate
            end
        end
    end
    if not ore then
        player:RequireComponent("SAnalyticsComp"):Record("MissingOre")
        player:ShowLocalizedTips(TranslationTexts.NeedOre)
        return
    end
    local furnaceLevel = WorkshopRules.GetLevel(player:GetTableView(Fields.UpgradeWorkshop).smelt)
    local costs = {{Type = "Item", ItemId = ore.OreItemId, Count = Tutorial.RequiredOre}}
    local blankId = HttpService:GenerateGUID(false)
    local rewards = {{Type = "Item", ItemId = Config.SwordBlankItemId, Count = 1,
        ExtraData = {MutationId = ore.MutationId, BlankMakerUserId = player:GetPlayerId(), BlankId = blankId,
            blankLuckLevel = WorkshopRules.RollBlankLuckLevel(furnaceLevel, self._random)}}}
    local reward = player:RequireComponent("FSRewardComp")
    if not reward:ExchangeRewards(costs, rewards) then
        -- 完整消耗一叠矿石可能腾出剑胚的位置。
        local removed = {FS.ItemClass.New(ore.OreItemId, Tutorial.RequiredOre)}
        local blank = rewards[1]
        local canFit = inventory:CanAddItems({FS.ItemClass.New(blank.ItemId, 1, blank.ExtraData)}, removed)
        player:ShowLocalizedTips(canFit and TranslationTexts.Failed or TranslationTexts.BackpackFull)
        return
    end
    player:RequireComponent("SWelfareComp"):AdvanceTask("smelt")
    player:RequireComponent("SAnalyticsComp"):Record("BlankSmelted", 4, blankId)
    player:ShowLocalizedTips(TranslationTexts.Success)
end

return Manager
