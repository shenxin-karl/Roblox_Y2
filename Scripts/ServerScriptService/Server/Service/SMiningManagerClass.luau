-- 服务端公共矿场：输送同服矿石、结算钩爪抓取和熔炼。
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
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local BELT_LAP_TIME = Settings.BeltLapTime
local BELT_SPAWN_INTERVAL = 3.5
local PORTAL_EXIT_TIME = 1.6
local BELT_UPDATE_INTERVAL = 1 / 20
local TranslationTexts = FX.Text.Define("FurnaceSmelt", {
    Success = "Smelting successful: you received a sword blank.",
    NeedOre = "You need one ore in your backpack to smelt a sword blank.",
    BackpackFull = "Your backpack is full. Make room for the sword blank and try again.",
    TooFar = "Move closer to your furnace to smelt the ore.",
    Failed = "Smelting failed. Please try again.",
    OreDeposited = "Ore added to your backpack.",
    OreBackpackFull = "Make room in your backpack to collect the ore.",
    ClawDepositFailed = "The ore could not be collected. Please try again.",
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
    self._belt = FXLoader:FindFromWorkspace(Settings.BeltPath)
    self._miningSeats = {}
    self._claws = {}
    if self._belt then
        self._beltEntry = FXLoader:Here(self._belt, "BeltEntry").Position
        self._portalExit = FXLoader:Here(self._belt, "PortalExit").Position
        -- 相邻底板保留搭接以免出现碰撞缝，但错开相同高度的可见表面。
        local decks = FXLoader:Here(self._belt, "Decks")
        for index, deck in ipairs(decks:GetChildren()) do
            local number = tonumber(deck.Name:match("^Deck(%d+)$"))
            if deck:IsA("Model") and number and number % 2 == 0 then
                deck:PivotTo(deck:GetPivot() - Vector3.new(0, 0.05, 0))
            end
        end
        local ramp = FXLoader:Here(self._belt, "FeedRamp")
        ramp.CFrame += Vector3.new(0, 0.06, 0)
        local center = self._ground.Position
        self._beltRadius = (self._beltEntry - Vector3.new(center.X, self._beltEntry.Y, center.Z)).Magnitude
        self._clawCenter = Vector3.new(center.X, self._beltEntry.Y + Settings.ClawHeight, center.Z)
        local elapsed = 0
        RunService.Heartbeat:Connect(function(deltaTime)
            elapsed += deltaTime
            if elapsed >= BELT_UPDATE_INTERVAL then
                elapsed %= BELT_UPDATE_INTERVAL
                local now = workspace:GetServerTimeNow()
                self:UpdateBeltRocks(now)
                self:UpdateClaws(now)
            end
        end)
    end
    self._folder = Instance.new("Folder")
    self._folder.Name = "PublicMiningRocks"
    self._folder.Parent = decorations
    self._rocks = {}
    self._beltReserve = {}
    self._batchId = 0
    self._rockTemplates = {}
    self._oreTypes = {}
    local rockTypes = _G.GameConfig.MiningRockData
    -- 按列名读取变异抽奖权重，曲线组调整列顺序时不会影响刷矿。
    for index, column in ipairs(Numerical.mutationCurves.columns) do
        if column.key == "probability" then
            self._mutationLottery = column.formula
            break
        end
    end
    assert(self._mutationLottery and self._mutationLottery.weights, "Missing mining mutation lottery weights")
    for id in ipairs(self._mutationLottery.weights) do
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
    local seats = FXLoader:FindFromWorkspace(Settings.SeatsPath)
    if seats then
        self:BindSeatPrompts(seats)
    end
    self:Refresh()
end

--- 登记可操作的座椅并绑定原生入座提示。
--- @param seats Model 矿区中摆好的操作椅集合。
function Manager:BindSeatPrompts(seats)
    for index, chair in ipairs(seats:GetChildren()) do
        local seat = FXLoader:Find(chair, "Seat")
        if not seat or not seat:IsA("Seat") then
            continue
        end
        local anchor = FXLoader:Find(seat, "SitPromptAnchor")
        local prompt = anchor and FXLoader:Find(anchor, "SitPrompt")
        if self._belt then
            self._miningSeats[seat] = true
            seat:SetAttribute(Settings.SeatAttribute, true)
        end
        --- Occupant 不复制，给客户端箭头单独同步座椅空闲状态。
        local function refreshSeat()
            local vacant = seat.Occupant == nil
            if self._belt then
                seat:SetAttribute(Settings.SeatVacantAttribute, vacant)
            end
            if prompt then
                prompt.Enabled = vacant
            end
        end
        seat:GetPropertyChangedSignal("Occupant"):Connect(refreshSeat)
        refreshSeat()
        if not prompt then
            continue
        end
        prompt.Triggered:Connect(function(player)
            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local root = humanoid and humanoid.RootPart
            if not prompt.Enabled or seat.Occupant or not root or humanoid.Health <= 0
                or humanoid.Sit or humanoid.PlatformStand
                or (root.Position - anchor.WorldPosition).Magnitude > prompt.MaxActivationDistance then
                return
            end
            seat:Sit(humanoid)
        end)
    end
end

--- 为入座玩家创建钩爪，用粗缆和金属接头让俯视时也能看清牵引动作。
--- @param seat Seat 当前玩家占用的操作椅。
--- @param humanoid Humanoid 当前坐在该椅上的角色。
--- @return table 操作椅的钩爪状态。
function Manager:CreateClaw(seat, humanoid)
    local position = Vector3.new(seat.Position.X, self._clawCenter.Y, seat.Position.Z)
    local forward = (self._clawCenter - position).Unit
    local home = position + forward * 3.2
    local pivot = CFrame.lookAt(home, home + forward)
    local model = Instance.new("Model")
    model.Name = "MiningClaw"
    model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
    model:SetAttribute("RestPose", pivot)

    --- 生成无碰撞的机械零件。
    --- @param name string 零件名。
    --- @param size Vector3 零件尺寸。
    --- @param cf CFrame 零件世界坐标。
    --- @param color Color3 零件颜色。
    --- @param parent Instance 零件父节点。
    --- @return Part 创建的零件。
    local function addPart(name, size, cf, color, parent)
        local part = Instance.new("Part")
        part.Name, part.Size, part.CFrame, part.Color = name, size, cf, color
        part.Material = Enum.Material.Metal
        part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
        part.CastShadow = false
        part.Parent = parent
        return part
    end

    local steel = Color3.fromRGB(53, 63, 78)
    local gold = Color3.fromRGB(255, 182, 51)
    model.PrimaryPart = addPart("Hub", Vector3.new(1.7, 0.7, 1), pivot, steel, model)
    addPart("CableCoupler", Vector3.new(0.86, 0.6, 0.64),
        pivot * CFrame.new(0, 0, 0.62), Color3.fromRGB(160, 172, 188), model)
    for side = -1, 1, 2 do
        local jaw = Instance.new("Model")
        jaw.Name = if side == -1 then "LeftJaw" else "RightJaw"
        local hinge = pivot * CFrame.new(side * Settings.ClawJawHinge, 0, 0)
        jaw.WorldPivot = hinge
        addPart("Arm", Vector3.new(0.6, 0.72, 1.9),
            hinge * CFrame.new(side * 0.39, 0, -0.82) * CFrame.Angles(0, -side * 0.42, 0), gold, jaw)
        addPart("Tip", Vector3.new(0.95, 0.72, 0.55),
            hinge * CFrame.new(side * 0.67, 0, -1.73) * CFrame.Angles(0, side * 0.48, 0), gold, jaw)
        jaw.Parent = model
    end
    local cableStart = Instance.new("Attachment")
    cableStart.Position = seat.CFrame:PointToObjectSpace(home)
    cableStart.Parent = seat
    local cableEnd = Instance.new("Attachment")
    cableEnd.Position = Vector3.new(0, 0, 0.82)
    cableEnd.Parent = model.PrimaryPart
    local cable = Instance.new("Beam")
    cable.Name = "Cable"
    cable.Attachment0, cable.Attachment1 = cableStart, cableEnd
    cable.Width0, cable.Width1 = 0.64, 0.56
    cable.Color = ColorSequence.new(Color3.fromRGB(34, 42, 55))
    cable.Segments, cable.FaceCamera, cable.Enabled = 1, true, false
    cable.Parent = model
    local carried = Instance.new("ObjectValue")
    carried.Name = "CarriedRock"
    carried.Parent = model
    model:AddTag(Settings.ClawTag)
    model.Parent = seat
    return {Humanoid = humanoid, Home = home, Model = model, CableStart = cableStart, Carried = carried}
end

--- 发射只接受占用操作椅的当前角色和盘面内的有限坐标。
--- @param mining table 当前玩家的矿场组件。
--- @param humanoid Humanoid 服务端当前活着的角色。
--- @param target any 客户端提交的 Vector2(X, Z)。
function Manager:CastClaw(mining, humanoid, target)
    local seat = humanoid.SeatPart
    local claw = seat and self._claws[seat]
    if not claw or claw.Humanoid ~= humanoid or seat.Occupant ~= humanoid or claw.Shot
        or typeof(target) ~= "Vector2" then
        return
    end
    local position = Vector3.new(target.X, self._clawCenter.Y, target.Y)
    if not ((position - self._clawCenter).Magnitude <= self._beltRadius + Settings.ClawEdgeMargin) then
        return
    end
    local offset = position - claw.Home
    local distance = offset.Magnitude
    if distance < 0.05 then
        return
    end
    local started = workspace:GetServerTimeNow()
    claw.Shot = {
        Mining = mining, Target = position, Distance = distance,
        HitAt = started + distance / Settings.ClawOutSpeed,
    }
    claw.Model:SetAttribute("ShotReturnSpeed", nil)
    claw.Model:SetAttribute("ShotReturnAt", nil)
    claw.Model:SetAttribute("ShotTarget", position)
    claw.Model:SetAttribute("ShotStarted", started)
end

--- 到达点击点才检测矿石；同帧的另一把钩爪不能重复锁定它。
--- @param target Vector3 钩爪出击终点。
--- @return table? 锁定的矿石。
function Manager:CaptureRock(target)
    local nearest, best = nil, math.huge
    for id, rock in pairs(self._rocks) do
        if rock.Model and not rock.Captured then
            local part = rock.Model.PrimaryPart
            local offset = part.Position - target
            local distance = Vector2.new(offset.X, offset.Z).Magnitude
            local reach = math.max(part.Size.X, part.Size.Z) / 2 + 1.3
            if distance <= reach and distance < best then
                nearest, best = rock, distance
            end
        end
    end
    if nearest then
        nearest.Captured = true
    end
    return nearest
end

--- 收回座位后才发矿；中途离座或发奖失败时把矿还给当前批次。
--- @param shot table 当前发射及它锁定的矿石。
--- @param completed boolean 是否完整收回。
function Manager:FinishClaw(shot, completed)
    local rock = shot.Rock
    if not rock then
        return
    end
    if completed then
        local player = shot.Mining:GetPlayerObject()
        local ore = _G.GameConfig.MiningRockData[rock.Grade]
        local rewards = {{Type = "Item", ItemId = ore.OreItemId, Count = 1}}
        local reward = player:RequireComponent("FSRewardComp")
        if reward:AddRewards(rewards) then
            if self._rocks[rock.Id] == rock then
                self._rocks[rock.Id] = nil
                local nextRock = table.remove(self._beltReserve, 1)
                if nextRock then
                    -- 补矿沿用被抓走的时隙，下一次经过传送门时才出矿。
                    local now = workspace:GetServerTimeNow()
                    local laps = math.floor((now - rock.SpawnAt) / BELT_LAP_TIME) + 1
                    nextRock.SpawnAt = rock.SpawnAt + laps * BELT_LAP_TIME
                    self._rocks[nextRock.Id] = nextRock
                end
            end
            rock.Model:Destroy()
            player:RequireComponent("SAnalyticsComp"):Record("OrePicked", 3, "Claw")
            player:ShowLocalizedTips(TranslationTexts.OreDeposited)
            return
        end
        player:ShowLocalizedTips(reward:CanAddRewards(rewards)
            and TranslationTexts.ClawDepositFailed or TranslationTexts.OreBackpackFull)
    end
    if self._rocks[rock.Id] == rock then
        rock.Captured = nil
    else
        rock.Model:Destroy()
    end
end

--- 命中后按矿石品级决定回程速度；离座、换角色和离服均清理未完成的抓取。
--- @param now number 当前服务器时间。
function Manager:UpdateClaws(now)
    for seat in pairs(self._miningSeats) do
        local humanoid = seat.Occupant
        local character = humanoid and humanoid.Parent
        local player = character and Players:GetPlayerFromCharacter(character)
        if not player or player.Character ~= character or humanoid.Health <= 0 or humanoid.PlatformStand then
            humanoid = nil
        end
        local claw = self._claws[seat]
        if claw and claw.Humanoid ~= humanoid then
            if claw.Shot then
                self:FinishClaw(claw.Shot, false)
            end
            claw.Model:Destroy()
            claw.CableStart:Destroy()
            self._claws[seat], claw = nil, nil
        end
        if not claw and humanoid then
            self._claws[seat] = self:CreateClaw(seat, humanoid)
            continue
        end
        local shot = claw and claw.Shot
        if not shot then
            continue
        end
        if not shot.Mining:IsMiningActive() then
            self:FinishClaw(shot, false)
            claw.Shot = nil
            claw.Carried.Value = nil
            claw.Model:SetAttribute("ShotStarted", nil)
            continue
        end
        if not shot.FinishAt then
            if now < shot.HitAt then
                continue
            end
            shot.Rock = self:CaptureRock(shot.Target)
            local returnSpeed = Settings.ClawReturnSpeed
            if shot.Rock then
                local rarity = (shot.Rock.Grade - 1) / math.max(1, #self._mutationLottery.weights - 1)
                returnSpeed *= 1 - 0.55 * rarity
            end
            local returnAt = if shot.Rock then now + Settings.ClawGripTime else shot.HitAt
            shot.FinishAt = returnAt + shot.Distance / returnSpeed
            claw.Carried.Value = shot.Rock and shot.Rock.Model
            claw.Model:SetAttribute("ShotReturnSpeed", returnSpeed)
            claw.Model:SetAttribute("ShotReturnAt", returnAt)
        end
        if now >= shot.FinishAt then
            claw.Shot = nil
            self:FinishClaw(shot, true)
            claw.Carried.Value = nil
            claw.Model:SetAttribute("ShotStarted", nil)
        end
    end
end

--- 生成仅用于展示的场景矿石，不阻挡玩家或其他矿石。
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
            part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
        end
    end
    model:SetAttribute("RockGrade", rock.Grade)
    model:SetAttribute("MutationId", config.MutationId)
    model:SetAttribute("MaxHits", 1)
    model:SetAttribute("RemainingHits", 1)
    model:AddTag(Settings.RockTag)
    rock.Model = model
    model.Parent = self._folder
end

--- 传送门逐块出矿，矿石从门口进入带面，再沿固定半径循环。
--- @param now number 当前服务器时间。
function Manager:UpdateBeltRocks(now)
    local center = self._ground.Position
    local entry = self._beltEntry
    local entryAngle = math.atan2(entry.Z - center.Z, entry.X - center.X)
    for id, rock in pairs(self._rocks) do
        if not rock.Captured and rock.SpawnAt and now >= rock.SpawnAt then
            local age = now - rock.SpawnAt
            local position
            if age < PORTAL_EXIT_TIME then
                position = self._portalExit:Lerp(entry, age / PORTAL_EXIT_TIME)
            else
                local angle = entryAngle + (age - PORTAL_EXIT_TIME) % BELT_LAP_TIME * math.pi * 2 / BELT_LAP_TIME
                position = Vector3.new(center.X + math.cos(angle) * self._beltRadius, entry.Y,
                    center.Z + math.sin(angle) * self._beltRadius)
            end
            rock.Origin = CFrame.new(position + Vector3.new(0, rock.Height, 0)) * rock.Rotation
            if rock.Model then
                rock.Model:PivotTo(rock.Origin)
            else
                self:PlaceRock(rock)
            end
        end
    end
end

--- 替换上一批展示矿石。
--- @param includeAllGrades boolean 是否给当前刷新池的每个品类保留一个位置。
function Manager:ReplaceGroundRocks(includeAllGrades)
    for id, rock in pairs(self._rocks) do
        if rock.Model and not rock.Captured then
            rock.Model:Destroy()
        end
    end
    table.clear(self._rocks)
    table.clear(self._beltReserve)
    self._batchId += 1
    local radius = math.min(self._ground.Size.Y, self._ground.Size.Z) / 2 - 4
    local center = self._ground.Position + Vector3.new(0, self._ground.Size.X / 2, 0)
    local phase = self._random:NextNumber(0, math.pi * 2)
    local curve = self._mutationLottery
    local guaranteedCount = includeAllGrades and #curve.weights or 0
    local spawnCount = math.max(Numerical.miningSpawnCount, guaranteedCount)
    -- 每圈只用一组独立时隙，余下矿石留到有空位时再补上。
    local beltSlots = math.floor(BELT_LAP_TIME / BELT_SPAWN_INTERVAL)
    local now = workspace:GetServerTimeNow()
    for slot = 1, spawnCount do
        local angle = phase + (slot - 1) * math.pi * 2 / spawnCount
        local distance = self._random:NextNumber(radius * 0.35, radius)
        local grade = if slot <= guaranteedCount then slot else FX.CurveSampler:SampleLotteryPrize(curve)
        local config = _G.GameConfig.MiningRockData[grade]
        local id = tostring(self._batchId) .. "_" .. slot
        local height = self._rockTemplates[grade].PrimaryPart.Size.Y * config.ModelScale / 2
        local rotation = CFrame.Angles(0, self._random:NextNumber(0, math.pi * 2), 0)
        local rock = {Id = id, Grade = grade}
        if self._belt then
            rock.Height = height
            rock.Rotation = rotation
            if slot <= beltSlots then
                rock.SpawnAt = now + (slot - 1) * BELT_SPAWN_INTERVAL
                self._rocks[id] = rock
            else
                table.insert(self._beltReserve, rock)
            end
        else
            local position = center + Vector3.new(math.cos(angle) * distance, height, math.sin(angle) * distance)
            rock.Origin = CFrame.new(position) * rotation
            self._rocks[id] = rock
            self:PlaceRock(rock)
        end
    end
    if self._belt then
        self:UpdateBeltRocks(now)
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
    player:RequireComponent("SBaseComp"):PlaySmeltEffect()
    player:RequireComponent("SWelfareComp"):AdvanceTask("smelt")
    player:RequireComponent("SAnalyticsComp"):Record("BlankSmelted", 4, blankId)
    player:ShowLocalizedTips(TranslationTexts.Success)
end

return Manager
