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
local CARRIED_ROCK_SIZE = 8
local CARRY_WALK_SPEED_PENALTY = 15
local TranslationTexts = FX.Text.Define("FurnaceSmelt", {
    Success = "Smelting successful: you received a sword blank.",
    NeedOre = "You need one ore in your backpack to smelt a sword blank.",
    BackpackFull = "Your backpack is full. Make room for the sword blank and try again.",
    TooFar = "Move closer to your furnace to smelt the ore.",
    Failed = "Smelting failed. Please try again.",
    OreDeposited = "Ore added to your backpack.",
    CarryHome = "Carry the ore back to your base to put it in your backpack.",
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
    self._carried = {}
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
                self:UpdateCarried(now)
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
                or humanoid.Sit or humanoid.PlatformStand or character:GetAttribute(Settings.CarryAttribute)
                or (root.Position - anchor.WorldPosition).Magnitude > prompt.MaxActivationDistance then
                return
            end
            seat:Sit(humanoid)
        end)
    end
end

--- 创建钩爪，并为客户端绳索提供固定在座椅和机头上的两个端点。
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

    -- 三角截面沿厚度挤出成实心刃片，连续截面共用边线，保证爪背弧线没有缺口。
    --- @param jaw Model 当前钳口。
    --- @param hinge CFrame 钳口枢轴坐标。
    --- @param a Vector3 钳口局部平面上的第一个顶点。
    --- @param b Vector3 第二个顶点。
    --- @param c Vector3 第三个顶点。
    --- @param thickness number 刃片厚度。
    --- @param color Color3 刃片颜色。
    local function addBladeTriangle(jaw, hinge, a, b, c, thickness, color)
        local ab, ac, bc = (b - a).Magnitude, (c - a).Magnitude, (c - b).Magnitude
        if ab > bc and ab >= ac then
            a, b, c = c, a, b
        elseif ac > bc then
            a, b, c = b, c, a
        end
        local back = (c - b).Unit
        local foot = b + back * (a - b):Dot(back)
        local up = (a - foot).Unit
        local right = up:Cross(back)
        for index, endpoint in ipairs({b, c}) do
            local length = (foot - endpoint).Magnitude
            if length > 0.001 then
                local sign = if index == 1 then 1 else -1
                local pose = CFrame.fromMatrix((a + endpoint) / 2, right * sign, up, back * sign)
                local face = addPart("Blade", Vector3.new(thickness, (a - foot).Magnitude, length),
                    hinge * pose, color, jaw)
                face.Shape = Enum.PartType.Wedge
            end
        end
    end

    local gunmetal = Color3.fromRGB(47, 62, 73)
    local cuttingSteel = Color3.fromRGB(176, 203, 211)
    local enamel = Color3.fromRGB(230, 143, 51)
    local upright = CFrame.Angles(0, 0, math.pi / 2)
    model.PrimaryPart = addPart("Hub", Vector3.new(1.6, 0.46, 0.86), pivot, gunmetal, model)
    addPart("WinchDrum", Vector3.new(0.74, 1.23, 1.23), pivot * upright, gunmetal, model).Shape = Enum.PartType.Cylinder
    addPart("DrumCap", Vector3.new(0.12, 1.07, 1.07), pivot * CFrame.new(0, 0.39, 0) * upright,
        enamel, model).Shape = Enum.PartType.Cylinder
    addPart("Spindle", Vector3.new(0.13, 0.48, 0.48), pivot * CFrame.new(0, 0.49, 0) * upright,
        cuttingSteel, model).Shape = Enum.PartType.Cylinder
    addPart("CableSocket", Vector3.new(0.78, 0.56, 0.56),
        pivot * CFrame.new(0, 0, 0.67) * CFrame.Angles(0, math.pi / 2, 0), cuttingSteel, model).Shape = Enum.PartType.Cylinder

    -- 每行给出叉臂内外两条轮廓与前伸距离，最后收成一个向内的尖端。
    local sections = {
        {-0.22, 0.23, 0}, {0.38, 0.91, 0.55}, {0.75, 1.38, 1.18},
        {0.94, 1.46, 1.75}, {0.91, 1.29, 2.24}, {0.85, 1.05, 2.56},
    }
    for side = -1, 1, 2 do
        local jaw = Instance.new("Model")
        jaw.Name = if side == -1 then "LeftJaw" else "RightJaw"
        local hinge = pivot * CFrame.new(side * Settings.ClawJawHinge, 0, 0)
        jaw.WorldPivot = hinge
        local inner, outer
        for index, section in ipairs(sections) do
            local nextInner = Vector3.new(side * section[1], 0, -section[3])
            local nextOuter = Vector3.new(side * section[2], 0, -section[3])
            if inner then
                local color = if index <= 3 then enamel else cuttingSteel
                local thickness = if index <= 3 then 0.48 else 0.33
                addBladeTriangle(jaw, hinge, inner, outer, nextOuter, thickness, color)
                addBladeTriangle(jaw, hinge, inner, nextOuter, nextInner, thickness, color)
            end
            inner, outer = nextInner, nextOuter
        end
        addBladeTriangle(jaw, hinge, inner, outer, Vector3.new(side * 0.72, 0, -2.85), 0.27, cuttingSteel)
        addPart("PivotCollar", Vector3.new(0.58, 0.68, 0.68), hinge * upright, gunmetal, jaw).Shape = Enum.PartType.Cylinder
        addPart("PivotPin", Vector3.new(0.66, 0.36, 0.36), hinge * upright, cuttingSteel, jaw).Shape = Enum.PartType.Cylinder
        jaw.Parent = model
    end
    local cableStart = Instance.new("Attachment")
    cableStart.Name = "ClawCableStart"
    cableStart.Position = seat.CFrame:PointToObjectSpace(home)
    cableStart.Parent = seat
    local cableEnd = Instance.new("Attachment")
    cableEnd.Name = "ClawCableEnd"
    cableEnd.Position = Vector3.new(0, 0, 1.08)
    cableEnd.Parent = model.PrimaryPart
    local carried = Instance.new("ObjectValue")
    carried.Name = "CarriedRock"
    carried.Parent = model
    model:AddTag(Settings.ClawTag)
    model.Parent = seat
    return {Humanoid = humanoid, Home = home, Model = model, CableStart = cableStart, Carried = carried}
end

--- 只接受占用座椅的当前角色提交的盘内终点，从服务端的爪座沿直线发射。
--- @param mining table 当前玩家的矿场组件。
--- @param humanoid Humanoid 服务端当前活着的角色。
--- @param target any 客户端提交的 Vector2(X, Z)。
function Manager:CastClaw(mining, humanoid, target)
    local seat = humanoid.SeatPart
    local claw = seat and self._claws[seat]
    if not claw or claw.Humanoid ~= humanoid or seat.Occupant ~= humanoid or claw.Shot or self._carried[mining]
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
        Mining = mining, Started = started, Direction = offset.Unit, Distance = distance, Traveled = 0,
    }
    claw.Model:SetAttribute("ShotReturnSpeed", nil)
    claw.Model:SetAttribute("ShotReturnAt", nil)
    claw.Model:SetAttribute("ShotTarget", position)
    claw.Model:SetAttribute("ShotStarted", started)
end

--- 扫描本帧走过的水平线段，取最先进入的矿石判定圈，避免高速出爪跳过矿石。
--- @param origin Vector3 本段起点。
--- @param direction Vector3 出爪的水平方向单位向量。
--- @param length number 本段长度。
--- @return table? 本段锁定的矿石。
--- @return number 命中点距本段起点的距离，无命中时为正无穷。
function Manager:CaptureRock(origin, direction, length)
    local nearest, best = nil, math.huge
    for id, rock in pairs(self._rocks) do
        if rock.Model and not rock.Captured then
            local part = rock.Model.PrimaryPart
            local offset = part.Position - origin
            local along = offset:Dot(direction)
            local lateral = offset.X * direction.Z - offset.Z * direction.X
            local reach = (math.max(part.Size.X, part.Size.Z) / 2 + 1.3) * Settings.ClawRockHitScale
            local chord = reach * reach - lateral * lateral
            if chord >= 0 then
                local half = math.sqrt(chord)
                local contact = math.max(0, along - half)
                if along + half >= 0 and contact <= length and contact < best then
                    nearest, best = rock, contact
                end
            end
        end
    end
    if nearest then
        nearest.Captured = true
    end
    return nearest, best
end

--- 被放弃的矿沿用原时隙，或按接手的时隙重新生成，避免在旧位置被抓取。
--- @param rock table? 被放弃的矿石；空爪时为 nil。
function Manager:ReturnRock(rock)
    if not rock then
        return
    end
    if self._rocks[rock.Id] == rock then
        rock.Captured = nil
        return
    end
    if rock.Model then
        rock.Model:Destroy()
        rock.Model = nil
    end
    rock.Captured = nil
    for id, other in pairs(self._rocks) do
        if not other.Captured then
            rock.SpawnAt = other.SpawnAt
            self._rocks[id] = nil
            if other.Model then
                other.Model:Destroy()
                other.Model = nil
            end
            table.insert(self._beltReserve, other)
            self._rocks[rock.Id] = rock
            return
        end
    end
    -- 时隙全被占用时，等下一个空位，不复用上一批的出矿时间。
    rock.SpawnAt = nil
    table.insert(self._beltReserve, 1, rock)
end

--- 带走时释放轮盘时隙；库存奖励仍要等玩家搬回自己基地。
function Manager:VacateSlot(rock)
    if self._rocks[rock.Id] ~= rock then
        return
    end
    self._rocks[rock.Id] = nil
    local nextRock = table.remove(self._beltReserve, 1)
    if nextRock then
        local laps = math.floor((workspace:GetServerTimeNow() - rock.SpawnAt) / BELT_LAP_TIME) + 1
        nextRock.SpawnAt = rock.SpawnAt + laps * BELT_LAP_TIME
        self._rocks[nextRock.Id] = nextRock
    end
end

--- 仅接受本座位这一抓的选择。保留时把放大的矿举过头顶，并降低搬运者的移速。
--- @param mining table 当前玩家的矿场组件。
--- @param humanoid Humanoid 当前操作座椅的角色。
--- @param catchId string 当前抓取编号。
--- @param keep boolean 玩家是否保留矿石。
function Manager:ChooseOre(mining, humanoid, catchId, keep)
    local seat = humanoid.SeatPart
    local claw = seat and self._claws[seat]
    local shot = claw and claw.Shot
    if not shot or not shot.Pending or shot.Mining ~= mining or claw.Humanoid ~= humanoid
        or seat.Occupant ~= humanoid or claw.Model:GetAttribute("PendingCatch") ~= catchId then
        return
    end
    local character = humanoid.Parent
    local head = character:FindFirstChild("Head")
    if keep and (not head or self._carried[mining]) then
        return
    end
    local rock = shot.Rock
    claw.Shot = nil
    claw.Carried.Value = nil
    claw.Model:SetAttribute("PendingCatch", nil)
    claw.Model:SetAttribute("ShotStarted", nil)
    if not keep then
        self:ReturnRock(rock)
        return
    end
    self:VacateSlot(rock)
    local model = rock.Model
    rock.Model = nil
    model:RemoveTag(Settings.RockTag)
    local size = model:GetExtentsSize()
    model:ScaleTo(model:GetScale() * CARRIED_ROCK_SIZE / math.max(size.X, size.Y, size.Z))
    local bounds, scaled = model:GetBoundingBox()
    local goal = head.CFrame * CFrame.new(0, head.Size.Y / 2 + scaled.Y / 2 + 0.12, -0.18)
    model:PivotTo(goal * bounds:ToObjectSpace(model:GetPivot()))
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Massless = true
            local weld = Instance.new("WeldConstraint")
            weld.Part0, weld.Part1, weld.Parent = head, part, part
            part.Anchored = false
        end
    end
    local shoulders = {}
    model.Parent = character
    local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
    for _, joint in ipairs(character:GetDescendants()) do
        if joint:IsA("Motor6D") and joint.Part0 == torso and joint.Name:match("Shoulder$") then
            shoulders[joint] = joint.C0
            joint.C0 = CFrame.new(joint.C0.Position) * CFrame.Angles(math.rad(155), 0, 0) * joint.C0.Rotation
        end
    end
    local walkSpeed = humanoid.WalkSpeed
    local carryWalkSpeed = math.max(0, walkSpeed - CARRY_WALK_SPEED_PENALTY)
    self._carried[mining] = {Rock = rock, Model = model, Humanoid = humanoid, Shoulders = shoulders,
        WalkSpeed = walkSpeed, CarryWalkSpeed = carryWalkSpeed}
    humanoid.WalkSpeed = carryWalkSpeed
    character:SetAttribute(Settings.CarryAttribute, true)
    humanoid.Sit = false
    mining:GetPlayerObject():ShowLocalizedTips(TranslationTexts.CarryHome)
end

--- 玩家进自家基地才交付；搬运结束时恢复移速，死亡、离服或换角色时归还轮盘。
--- @param now number 当前服务器时间。
function Manager:UpdateCarried(now)
    for mining, carry in pairs(self._carried) do
        if carry.Depositing then
            continue
        end
        local humanoid = carry.Humanoid
        local character = humanoid.Parent
        local root = humanoid.RootPart
        local deliver = false
        if mining:IsMiningActive() and character and root and humanoid.Health > 0
            and mining:GetPlayerNode().Character == character then
            if now < (carry.NextCheck or 0) then
                continue
            end
            carry.NextCheck = now + 0.25
            local player = mining:GetPlayerObject()
            local base = player:RequireComponent("SBaseComp"):GetBase()
            if base and base.OwnerUserId == player:GetPlayerId() then
                for index = 1, base.FloorCount do
                    local floor = base.Floors[index].Part
                    local p, half = floor.CFrame:PointToObjectSpace(root.Position), floor.Size / 2
                    if math.abs(p.X) <= half.X and math.abs(p.Z) <= half.Z and p.Y >= -half.Y and p.Y <= half.Y + 9 then
                        deliver = true
                        break
                    end
                end
            end
            if not deliver then
                carry.Warned = nil
                continue
            end
            local ore = _G.GameConfig.MiningRockData[carry.Rock.Grade]
            local rewards = {{Type = "Item", ItemId = ore.OreItemId, Count = 1}}
            local reward = player:RequireComponent("FSRewardComp")
            carry.Depositing = true
            if not reward:AddRewards(rewards) then
                carry.Depositing = false
                if not carry.Warned then
                    carry.Warned = true
                    player:ShowLocalizedTips(reward:CanAddRewards(rewards)
                        and TranslationTexts.ClawDepositFailed or TranslationTexts.OreBackpackFull)
                end
                continue
            end
            player:RequireComponent("SAnalyticsComp"):Record("OrePicked", 3, "Carry")
            player:ShowLocalizedTips(TranslationTexts.OreDeposited)
        end
        self._carried[mining] = nil
        if humanoid.WalkSpeed == carry.CarryWalkSpeed then
            humanoid.WalkSpeed = carry.WalkSpeed
        end
        carry.Model:Destroy()
        for joint, original in pairs(carry.Shoulders) do
            if joint.Parent then
                joint.C0 = original
            end
        end
        if character then
            character:SetAttribute(Settings.CarryAttribute, nil)
        end
        if not deliver then
            self:ReturnRock(carry.Rock)
        end
    end
end

--- 双向扫过本帧路径，首次命中后锁矿；带矿返回后等座位上的玩家选择。
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
                self:ReturnRock(claw.Shot.Rock)
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
            self:ReturnRock(shot.Rock)
            claw.Shot = nil
            claw.Carried.Value = nil
            claw.Model:SetAttribute("PendingCatch", nil)
            claw.Model:SetAttribute("ShotStarted", nil)
            continue
        end
        if shot.Pending then
            continue
        end
        if not shot.FinishAt then
            local traveled = math.min((now - shot.Started) * Settings.ClawOutSpeed, shot.Distance)
            local start = claw.Home + shot.Direction * shot.Traveled
            local rock, contact = self:CaptureRock(start, shot.Direction, traveled - shot.Traveled)
            local returnSpeed = Settings.ClawReturnSpeed
            if rock then
                shot.Rock = rock
                shot.Distance = shot.Traveled + contact
                claw.Model:SetAttribute("ShotTarget", start + shot.Direction * contact)
                local rarity = (rock.Grade - 1) / math.max(1, #self._mutationLottery.weights - 1)
                returnSpeed *= 1 - 0.55 * rarity
            elseif traveled < shot.Distance then
                shot.Traveled = traveled
                continue
            end
            local returnAt = if rock then now + Settings.ClawGripTime
                else shot.Started + shot.Distance / Settings.ClawOutSpeed
            shot.FinishAt = returnAt + shot.Distance / returnSpeed
            shot.ReturnRemaining = shot.Distance
            claw.Carried.Value = shot.Rock and shot.Rock.Model
            claw.Model:SetAttribute("ShotReturnSpeed", returnSpeed)
            claw.Model:SetAttribute("ShotReturnAt", returnAt)
        end
        if not shot.Rock then
            local remaining = math.clamp((shot.FinishAt - now) * Settings.ClawReturnSpeed, 0, shot.ReturnRemaining)
            local start = claw.Home + shot.Direction * shot.ReturnRemaining
            local rock, contact = self:CaptureRock(start, -shot.Direction, shot.ReturnRemaining - remaining)
            if rock then
                remaining = shot.ReturnRemaining - contact
                local rarity = (rock.Grade - 1) / math.max(1, #self._mutationLottery.weights - 1)
                local speed = Settings.ClawReturnSpeed * (1 - 0.55 * rarity)
                shot.Rock = rock
                shot.FinishAt = now + remaining / speed
                claw.Carried.Value = rock.Model
                claw.Model:SetAttribute("ShotReturnSpeed", speed)
                claw.Model:SetAttribute("ShotReturnAt", now - (shot.Distance - remaining) / speed)
            end
            shot.ReturnRemaining = remaining
        end
        if now >= shot.FinishAt then
            if shot.Rock then
                shot.Pending = true
                claw.Model:SetAttribute("PendingCatch", HttpService:GenerateGUID(false))
            else
                claw.Shot = nil
                claw.Model:SetAttribute("ShotStarted", nil)
            end
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
