-- 水晶采矿表现：服务端矿石只负责碰撞与次数，本地副本负责弹缩、同色碎片和命中特效。
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local FX = _G.FX
-- 矿石模型自带彩虹标签，加载后由客户端更新材质颜色。
FX.Loader:RequireShared("Scripts.Game.Shared.MutationVisual")
local Settings = FX.Loader:RequireShared("Scripts.Game.Shared.MiningSettings")
local Effects = {}
Effects.__index = Effects
local BeltTreadCount = 48
local BeltTreadAngle = math.pi * 2 / BeltTreadCount
local ClawCableSegmentCount = 10
local ClawCableDiameter = 0.16
local ClawCableAxis = CFrame.Angles(0, math.pi / 2, 0)
-- 原光环按 R6 身体分组；以身体包围盒为基准映射到矿石表面。
local AuraReferenceSize = Vector3.new(4, 5, 2)
local AuraOffsets = {
    Head = Vector3.new(0, 2, 0),
    Torso = Vector3.new(0, 0.5, 0),
    ["Left Arm"] = Vector3.new(-1.5, 0.5, 0),
    ["Right Arm"] = Vector3.new(1.5, 0.5, 0),
    ["Left Leg"] = Vector3.new(-0.5, -1.5, 0),
    ["Right Leg"] = Vector3.new(0.5, -1.5, 0),
}

--- 由矿场组件持有，沿用服务器复制的次数而不预测发奖。
--- @param owner table 矿场客户端组件。
--- @return table 本地采矿表现对象。
function Effects.New(owner)
    local self = setmetatable({}, Effects)
    self._owner = owner
    self._templates = FX.Loader:Shared("Assets.Decorations.MiningEffects")
    self._crystals = {}
    for id, rockType in pairs(_G.GameConfig.MiningRockData) do
        local template = FX.Loader:Shared(rockType.ModelPath)
        local crystals = assert(template:FindFirstChild("Crystals", true), "Mining rock requires crystals")
        self._crystals[id] = assert(crystals:FindFirstChildWhichIsA("BasePart"), "Mining rock requires a crystal part")
    end
    self._mutationTemplates = {}
    for grade, mutation in pairs(_G.GameConfig.MiningRockData) do
        if mutation.EffectPath then
            self._mutationTemplates[mutation.MutationId] = FX.Loader:Shared(mutation.EffectPath)
        end
    end
    self._rocks = {}
    self._claws = {}
    self._clawCables = {}
    self._clawAdded = CollectionService:GetInstanceAddedSignal(Settings.ClawTag):Connect(function(claw)
        self._claws[claw] = false
    end)
    self._clawRemoved = CollectionService:GetInstanceRemovedSignal(Settings.ClawTag):Connect(function(claw)
        self._claws[claw] = nil
        self:RemoveClawCable(claw)
    end)
    for index, claw in ipairs(CollectionService:GetTagged(Settings.ClawTag)) do
        self._claws[claw] = false
    end
    self._pending = {}
    self._fragments = {}
    self._fragmentPool = {}
    self._folder = Instance.new("Folder")
    self._folder.Name = "MiningVisuals"
    self._folder.Parent = FX.Loader:Workspace("Decorations")
    self._added = CollectionService:GetInstanceAddedSignal(Settings.RockTag):Connect(function(rock)
        self:AddRock(rock)
    end)
    self._removed = CollectionService:GetInstanceRemovedSignal(Settings.RockTag):Connect(function(rock)
        self:RemoveRock(rock)
    end)
    for index, rock in ipairs(CollectionService:GetTagged(Settings.RockTag)) do
        self:AddRock(rock)
    end
    return self
end

--- 克隆对应矿石模型，让受击抖动只作用于本地外观，避免影响玩家行走。
--- @param rock Instance 流式加载到客户端的公共矿石。
function Effects:AddRock(rock)
    if self._rocks[rock] or not rock:IsA("Model") then
        return
    end
    local hits = rock:GetAttribute("RemainingHits")
    local maxHits = rock:GetAttribute("MaxHits")
    local mutationId = rock:GetAttribute("MutationId")
    local grade = rock:GetAttribute("RockGrade")
    if hits and hits <= 0 then
        self:RemoveRock(rock)
        return
    end
    if not hits or not maxHits or not mutationId or not grade or not rock.PrimaryPart then
        -- 标签与属性可能分批复制；不等待或漏掉稍后才完整到达的矿石。
        if not self._pending[rock] then
            --- 属性或主部件到达后重新检查完整模型，不创建重复外观。
            local function retry()
                self:AddRock(rock)
            end
            self._pending[rock] = {
                rock.AttributeChanged:Connect(retry),
                rock:GetPropertyChangedSignal("PrimaryPart"):Connect(retry),
            }
        end
        return
    end
    if self._pending[rock] then
        for index, connection in ipairs(self._pending[rock]) do
            connection:Disconnect()
        end
        self._pending[rock] = nil
    end
    local model = rock:Clone()
    CollectionService:RemoveTag(model, Settings.RockTag)
    local visual = model.PrimaryPart
    for index, node in ipairs(model:GetDescendants()) do
        if node:IsA("BasePart") then
            node.CanCollide = false
            node.CanTouch = false
            node.CanQuery = false
            node.LocalTransparencyModifier = 0
        end
    end
    model.Parent = self._folder
    local entry = {
        Model = model, ModelScale = model:GetScale(),
        Visual = visual, Size = visual.Size,
        Hits = hits, MaxHits = maxHits,
        Crystal = self._crystals[grade],
        Transparencies = {}, Lights = {},
    }
    self._rocks[rock] = entry
    for index, node in ipairs(rock:GetDescendants()) do
        if node:IsA("BasePart") then
            entry.Transparencies[node] = node.LocalTransparencyModifier
            node.LocalTransparencyModifier = 1
        elseif node:IsA("Light") then
            entry.Lights[node] = node.Enabled
            node.Enabled = false
        end
    end
    self:AddMutationEffect(entry, mutationId)
    entry.Connection = rock:GetAttributeChangedSignal("RemainingHits"):Connect(function()
        local remaining = rock:GetAttribute("RemainingHits")
        if remaining and remaining < entry.Hits then
            entry.Hits = remaining
            entry.Started = os.clock()
            self:PlayHitEffect(entry, remaining == 0)
            self:UpdateHealthBar(entry)
            if remaining == 0 then
                self:ClearMutationEffect(entry)
                model:Destroy()
            end
        end
    end)
    self:UpdateHealthBar(entry)
end

--- 将角色光环的粒子组挂到矿石附着点，保留嵌套节点和素材自身旋转。
--- @param entry table 本地矿石表现及原始尺寸。
--- @param mutationId string 服务器复制的固定变异 ID。
function Effects:AddMutationEffect(entry, mutationId)
    local template = self._mutationTemplates[mutationId]
    if not template then
        return
    end
    entry.AuraRoots = {}
    entry.AuraAttachments = {}
    entry.AuraEmitters = {}
    local dimensions = entry.Size / AuraReferenceSize
    entry.AuraSizeScale = math.min(dimensions.X, dimensions.Y, dimensions.Z)
    for index, group in ipairs(template:GetChildren()) do
        local anchor = Instance.new("Attachment")
        anchor.Name = "MiningAura_" .. group.Name
        local offset = assert(AuraOffsets[group.Name], "Unknown aura group: " .. group.Name)
        table.insert(entry.AuraRoots, anchor)
        table.insert(entry.AuraAttachments, {Node = anchor, Offset = offset / AuraReferenceSize})
        for childIndex, child in ipairs(group:GetChildren()) do
            child:Clone().Parent = anchor
        end
        for descendantIndex, node in ipairs(anchor:GetDescendants()) do
            if node:IsA("Attachment") then
                table.insert(entry.AuraAttachments, {Node = node, Offset = node.Position / AuraReferenceSize})
            elseif node:IsA("ParticleEmitter") then
                node.Enabled = true
                node.LockedToPart = true
                -- 沿用 Money 的加色混合，避免光效纹理露出黑色底框。
                node.LightEmission = 1
                node.Speed = NumberRange.new(node.Speed.Min * entry.AuraSizeScale, node.Speed.Max * entry.AuraSizeScale)
                node.Acceleration *= entry.AuraSizeScale
                table.insert(entry.AuraEmitters, {Node = node, Size = node.Size})
            end
        end
        anchor.Parent = entry.Visual
    end
    self:UpdateMutationEffect(entry, 1)
end

--- 从原始偏移和粒子尺寸缩放，不累计误差；静止矿石不重复构造序列。
--- @param entry table 持有本块矿石光环节点的表现记录。
--- @param scale number 当前受击和残血共同决定的缩放倍率。
function Effects:UpdateMutationEffect(entry, scale)
    if not entry.AuraRoots or entry.AuraScale == scale then
        return
    end
    entry.AuraScale = scale
    for index, attachment in ipairs(entry.AuraAttachments) do
        attachment.Node.Position = attachment.Offset * entry.Visual.Size
    end
    local sizeScale = entry.AuraSizeScale * scale
    for index, emitter in ipairs(entry.AuraEmitters) do
        local points = {}
        for pointIndex, point in ipairs(emitter.Size.Keypoints) do
            points[pointIndex] = NumberSequenceKeypoint.new(point.Time, point.Value * sizeScale, point.Envelope * sizeScale)
        end
        emitter.Node.Size = NumberSequence.new(points)
    end
end

--- 挖完立即清掉存活粒子；其余移除路径随本地外观一起销毁。
--- @param entry table 当前矿石表现记录。
function Effects:ClearMutationEffect(entry)
    if not entry.AuraRoots then
        return
    end
    for index, root in ipairs(entry.AuraRoots) do
        root:Destroy()
    end
    entry.AuraRoots = nil
    entry.AuraAttachments = nil
    entry.AuraEmitters = nil
end

--- 沿用 Money 的世界血条，仅受损时出现，击碎后隐藏。
--- @param entry table 当前石头外观与服务端剩余次数。
function Effects:UpdateHealthBar(entry)
    if not entry.HealthBar and entry.Hits > 0 and entry.Hits < entry.MaxHits then
        local bar = Instance.new("BillboardGui")
        bar.Name = "RockHealthBar"
        bar.Adornee = entry.Visual
        bar.Size = UDim2.fromScale(5, 0.6)
        bar.AlwaysOnTop = true
        bar.LightInfluence = 0
        bar.MaxDistance = 80
        local background = Instance.new("Frame")
        background.Name = "Background"
        background.Size = UDim2.fromScale(1, 1)
        background.BackgroundColor3 = Color3.fromRGB(25, 29, 35)
        background.BorderSizePixel = 0
        background.Parent = bar
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = background
        local fill = Instance.new("Frame")
        fill.Name = "Fill"
        fill.BackgroundColor3 = Color3.fromRGB(80, 220, 105)
        fill.BorderSizePixel = 0
        fill.Parent = background
        corner:Clone().Parent = fill
        bar.Parent = entry.Visual
        entry.HealthBar = bar
    end
    if entry.HealthBar then
        entry.HealthBar.Enabled = entry.Hits > 0 and entry.Hits < entry.MaxHits
        entry.HealthBar.Background.Fill.Size = UDim2.fromScale(entry.Hits / entry.MaxHits, 1)
    end
end

--- 移除刷新或流式卸载的石头，不把普通移除当作击碎。
--- @param rock Instance 已离开矿场标签集合的石头。
function Effects:RemoveRock(rock)
    if self._pending[rock] then
        for index, connection in ipairs(self._pending[rock]) do
            connection:Disconnect()
        end
        self._pending[rock] = nil
    end
    local entry = self._rocks[rock]
    if entry then
        entry.Connection:Disconnect()
        entry.Model:Destroy()
        if rock.Parent then
            for part, transparency in pairs(entry.Transparencies) do
                if part.Parent then
                    part.LocalTransparencyModifier = transparency
                end
            end
            for light, enabled in pairs(entry.Lights) do
                if light.Parent then
                    light.Enabled = enabled
                end
            end
        end
        self._rocks[rock] = nil
    end
end

--- 命中闪光与飞散粒子跟随水晶原色，击碎时仅保留少量浅色烟尘。
--- @param entry table 石头原始姿态及本地外观。
--- @param broken boolean 是否已经耗尽服务端次数。
function Effects:PlayHitEffect(entry, broken)
    local center = entry.Visual.Position
    local character = self._owner:GetPlayerCharacter()
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local away = root and center - root.Position or Vector3.zAxis
    away = Vector3.new(away.X, 0, away.Z)
    entry.Direction = away.Magnitude > 0.01 and away.Unit or Vector3.zAxis
    local camera = workspace.CurrentCamera
    local direction = camera and camera.CFrame.Position - center or Vector3.zAxis
    local normal = direction.Magnitude > 0.01 and direction.Unit or Vector3.zAxis
    local localDirection = entry.Visual.CFrame:VectorToObjectSpace(normal)
    local half = entry.Visual.Size / 2
    local distance = 1 / math.max(math.abs(localDirection.X) / half.X,
        math.abs(localDirection.Y) / half.Y, math.abs(localDirection.Z) / half.Z)
    local effect = Instance.new("Part")
    effect.Name = "RockHitEffect"
    effect.Size = Vector3.one * 0.1
    effect.Transparency = 1
    effect.Anchored = true
    effect.CanCollide = false
    effect.CanTouch = false
    effect.CanQuery = false
    local position = center + normal * (distance + 0.55)
    effect.CFrame = CFrame.lookAt(position, position + normal)
    effect.Parent = self._folder
    local radius = math.clamp(math.max(entry.Size.X, entry.Size.Y, entry.Size.Z) * 0.55, 1.5, 4)
    local origin = self._templates.ImpactOrigin:Clone()
    local color = entry.Crystal.Color
    origin.ImpactFlash.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.35))
    origin.ImpactShockwave.Color = ColorSequence.new(color)
    origin.ImpactSparks.Color = ColorSequence.new(color)
    local burst = math.min(radius * (broken and 0.8 or 0.55), 2.4)
    origin.ImpactFlash.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, burst * 0.45),
        NumberSequenceKeypoint.new(0.15, burst),
        NumberSequenceKeypoint.new(1, burst * 0.65),
    })
    origin.ImpactShockwave.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, radius * 0.5),
        NumberSequenceKeypoint.new(0.35, radius * 2),
        NumberSequenceKeypoint.new(1, radius * 3),
    })
    origin.ImpactSparks.Speed = NumberRange.new(radius * 3, radius * 6)
    origin.Parent = effect
    origin.ImpactFlash:Emit(1)
    origin.ImpactShockwave:Emit(1)
    origin.ImpactSparks:Emit(broken and 28 or 18)
    if broken then
        local dustOrigin = Instance.new("Attachment")
        dustOrigin.Position = effect.CFrame:PointToObjectSpace(center)
        dustOrigin.Parent = effect
        local dust = self._templates.Smoke:Clone()
        dust.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.6))
        dust.Lifetime = NumberRange.new(0.2, 0.3)
        dust.Size = NumberSequence.new(1, 3)
        dust.Transparency = NumberSequence.new(0.75, 1)
        dust.Parent = dustOrigin
        dust:Emit(1)
    end
    local sound = self._templates.RockBreak:Clone()
    local settings = self._owner:GetTable(_G.PlayerDataConfig.Settings)
    sound.Volume *= settings.soundEffectsVolume / 100
    sound.Parent = effect
    sound:Play()
    Debris:AddItem(effect, 3)
    local fragmentOrigin = broken and CFrame.lookAt(center, center + normal) or effect.CFrame
    self:SpawnFragments(fragmentOrigin, entry.Size, entry.Crystal, broken)
end

--- 缩小原水晶部件作为碎片；复用时重设外观，避免不同矿石之间串色。
--- @param origin CFrame 碎片生成位置与飞散朝向。
--- @param rockSize Vector3 原始石头尺寸。
--- @param source BasePart 当前品质模板中的水晶部件，提供形状、颜色与材质。
--- @param broken boolean 击碎时扩大碎片及飞散范围。
function Effects:SpawnFragments(origin, rockSize, source, broken)
    local count = broken and 7 or 3
    local phase = math.random() * math.pi * 2
    for index = 1, count do
        local part = table.remove(self._fragmentPool)
        if not part then
            part = source:Clone()
            part:ClearAllChildren()
            part.Name = "CrystalFragment"
            part.Anchored = true
            part.CanCollide = false
            part.CanTouch = false
            part.CanQuery = false
            part.CastShadow = false
        end
        local size = (0.6 + math.random() * 0.4) * (broken and 1.25 or 0.8)
        part.Size = source.Size * (size / math.max(source.Size.X, source.Size.Y, source.Size.Z))
        part.Color = source.Color
        part.Material = source.Material
        part.MaterialVariant = source.MaterialVariant
        part.Reflectance = source.Reflectance
        part.LocalTransparencyModifier = 0
        part.Transparency = 0
        local rotation = CFrame.Angles(math.random() * math.pi, math.random() * math.pi, math.random() * math.pi)
        local offset = broken and Vector3.new((math.random() - 0.5) * rockSize.X * 0.7,
            (math.random() - 0.5) * rockSize.Y * 0.5, (math.random() - 0.5) * rockSize.Z * 0.7) or Vector3.zero
        part.CFrame = CFrame.new(origin.Position + offset) * rotation
        part.Parent = self._folder
        local angle = phase + (index - 1 + math.random() * 0.4) / count * math.pi * 2
        local spread = broken and (7 + math.random() * 5) or 2
        table.insert(self._fragments, {
            Part = part, Size = part.Size, Position = part.Position, Rotation = rotation,
            Started = os.clock(), Lifetime = 0.55 + math.random() * 0.15,
            Velocity = Vector3.new(math.cos(angle) * spread, broken and (8 + math.random() * 3) or 5,
                math.sin(angle) * spread) + (broken and Vector3.zero or origin.LookVector * 6),
            Spin = Vector3.new(math.random() * 10 - 5, math.random() * 10 - 5, math.random() * 10 - 5),
        })
    end
end

--- 深色履带板和矿石同向同速移动，带板底部与固定底板留出间隙。
function Effects:UpdateBelt()
    local belt = self._beltTreads
    if not belt then
        local entry = FX.Loader:FindFromWorkspace(Settings.BeltPath .. ".BeltEntry")
        local ground = FX.Loader:FindFromWorkspace(Settings.GroundPath)
        if not entry or not ground then
            return
        end
        local center = Vector3.new(ground.Position.X, entry.Position.Y + 0.10, ground.Position.Z)
        local radius = Vector2.new(entry.Position.X - center.X, entry.Position.Z - center.Z).Magnitude
        belt = {Center = center, Radius = radius, Parts = {}, Frames = {}}
        self._beltTreads = belt
    end
    local character = self._owner:GetPlayerCharacter()
    local root = character and character.PrimaryPart
    if not root or (root.Position - belt.Center).Magnitude > 170 then
        return
    end
    local phase = workspace:GetServerTimeNow() % Settings.BeltLapTime * math.pi * 2 / Settings.BeltLapTime
    for index = 1, BeltTreadCount do
        local angle = phase + (index - 1) * BeltTreadAngle
        local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
        local position = belt.Center + outward * belt.Radius
        belt.Frames[index] = CFrame.lookAt(position, position + outward)
        if not belt.Parts[index] then
            local tread = Instance.new("Part")
            tread.Name = "OreBeltTread"
            tread.Size = Vector3.new(2 * (belt.Radius - 3.2) * math.tan(BeltTreadAngle / 2) - 0.36, 0.10, 6.2)
            tread.CFrame = belt.Frames[index]
            tread.Material = Enum.Material.Metal
            tread.Color = if index % 2 == 0 then Color3.fromRGB(105, 119, 142) else Color3.fromRGB(71, 86, 109)
            tread.Anchored, tread.CanCollide, tread.CanTouch, tread.CanQuery = true, false, false, false
            tread.CastShadow = false
            tread.Parent = self._folder
            belt.Parts[index] = tread
        end
    end
    workspace:BulkMoveTo(belt.Parts, belt.Frames, Enum.BulkMoveMode.FireCFrameChanged)
end

--- 让左右爪齿围绕各自的转轴转动，保留钩头机身的位置。
--- @param claw Model 钩头模型。
--- @param pose CFrame 钩头当前姿态。
--- @param grip number 爪齿闭合比例，零代表张开。
local function SetClawGrip(claw, pose, grip)
    local left = claw:FindFirstChild("LeftJaw")
    local right = claw:FindFirstChild("RightJaw")
    if left and right then
        local angle = 0.48 * grip
        left:PivotTo(pose * CFrame.new(-Settings.ClawJawHinge, 0, 0) * CFrame.Angles(0, -angle, 0))
        right:PivotTo(pose * CFrame.new(Settings.ClawJawHinge, 0, 0) * CFrame.Angles(0, angle, 0))
    end
end

--- 收回或卸载钩爪时移除本地绳索，避免残留在盘面。
--- @param claw Model 钩头模型。
function Effects:RemoveClawCable(claw)
    local cable = self._clawCables[claw]
    if cable then
        cable.Folder:Destroy()
        self._clawCables[claw] = nil
    end
end

--- 用细圆柱绘制黄棕色麻绳，以轻微下垂表现重量，不参与物理和命中。
--- @param claw Model 钩头模型。
--- @param startPosition Vector3 座椅端的世界坐标。
--- @param endPosition Vector3 钩头接头的世界坐标。
function Effects:DrawClawCable(claw, startPosition, endPosition)
    local cable = self._clawCables[claw]
    if not cable then
        local folder = Instance.new("Folder")
        folder.Name = "ClawCable"
        cable = {Folder = folder, Parts = {}}
        self._clawCables[claw] = cable
        for index = 1, ClawCableSegmentCount do
            local part = Instance.new("Part")
            part.Shape = Enum.PartType.Cylinder
            part.Material = Enum.Material.Fabric
            part.Color = Color3.fromRGB(195, 148, 72)
            part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
            part.CastShadow = false
            part.Parent = folder
            cable.Parts[index] = part
        end
    end

    local sag = math.min((endPosition - startPosition).Magnitude * 0.016, 0.65)
    local previous = startPosition
    for index, part in ipairs(cable.Parts) do
        local t = index / ClawCableSegmentCount
        local point = startPosition:Lerp(endPosition, t) - Vector3.yAxis * (4 * sag * t * (1 - t))
        local length = (point - previous).Magnitude
        -- 轻微重叠，避免弧线转折处露出接缝。
        part.Size = Vector3.new(length + 0.025, ClawCableDiameter, ClawCableDiameter)
        part.CFrame = CFrame.lookAt((previous + point) / 2, point) * ClawCableAxis
        previous = point
    end
    if not cable.Folder.Parent then
        cable.Folder.Parent = self._folder
    end
end

--- 按服务端时间播放钩爪和绳索；抓到矿时先合爪，再保持夹紧回收。
function Effects:UpdateClaws()
    local now = workspace:GetServerTimeNow()
    for claw, moving in pairs(self._claws) do
        local started = claw:GetAttribute("ShotStarted")
        if not started and not moving then
            continue
        end
        local rest = claw:GetAttribute("RestPose")
        local carried = claw:FindFirstChild("CarriedRock")
        if not rest or not claw.PrimaryPart or not carried then
            self:RemoveClawCable(claw)
            continue
        end
        if not started then
            claw:PivotTo(rest)
            SetClawGrip(claw, rest, 0)
            self:RemoveClawCable(claw)
            self._claws[claw] = false
            continue
        end
        local target = claw:GetAttribute("ShotTarget")
        if not target then
            continue
        end
        local offset = target - rest.Position
        local distance = offset.Magnitude
        local elapsed = math.max(0, now - started)
        local outTime = math.max(distance, 0.001) / Settings.ClawOutSpeed
        local returnSpeed = claw:GetAttribute("ShotReturnSpeed")
        local returnAt = claw:GetAttribute("ShotReturnAt")
        local fraction = math.min(1, elapsed / outTime)
        if returnAt and returnSpeed and now >= returnAt then
            fraction = math.max(0, 1 - (now - returnAt) * returnSpeed / math.max(distance, 0.001))
        end
        local position = rest.Position:Lerp(target, fraction)
        local direction = if distance > 0.001 then offset.Unit else rest.LookVector
        local pose = CFrame.lookAt(position, position + direction)
        local rock = carried.Value
        local grip = if rock and returnAt then math.clamp(1 - (returnAt - now) / Settings.ClawGripTime, 0, 1) else 0
        claw:PivotTo(pose)
        SetClawGrip(claw, pose, grip)
        local cableStart = claw.Parent and claw.Parent:FindFirstChild("ClawCableStart")
        local cableEnd = claw.PrimaryPart:FindFirstChild("ClawCableEnd")
        if cableStart and cableEnd and fraction * distance > cableEnd.Position.Z + 0.25 then
            self:DrawClawCable(claw, cableStart.WorldPosition, cableEnd.WorldPosition)
        else
            self:RemoveClawCable(claw)
        end
        self._claws[claw] = true
        local entry = rock and self._rocks[rock]
        if entry and entry.Hits > 0 then
            local rockPose = rock:GetPivot()
            local heldPosition = position + direction * 1.45
            entry.Model:PivotTo(CFrame.new(rockPose.Position:Lerp(heldPosition, grip)) * rockPose.Rotation)
            entry.LastPose = rockPose
        end
    end
end

--- 跟随矿石移动，只在位置或受击缩放变化时更新本地模型和粒子。
function Effects:Update()
    local now = os.clock()
    for rock, entry in pairs(self._rocks) do
        if entry.Hits > 0 and rock.PrimaryPart then
            local pose = rock:GetPivot()
            if not entry.Started then
                if pose ~= entry.LastPose then
                    entry.Model:PivotTo(pose)
                    entry.LastPose = pose
                end
                continue
            end
            local ratio = entry.Hits / entry.MaxHits
            local scale = ratio > 0.66 and 1 or (ratio > 0.33 and 0.92 or 0.84)
            local progress = math.clamp((now - entry.Started) / 0.35, 0, 1)
            scale *= 1 + math.sin(progress * math.pi * 2) * (1 - progress) * 0.18
            local position = pose.Position + Vector3.new(0, entry.Size.Y * (scale - 1) / 2, 0)
            local kickProgress = math.clamp((now - entry.Started) / 0.16, 0, 1)
            local kick = math.sin(kickProgress * math.pi * 2) * (1 - kickProgress)
            local direction = entry.Direction or Vector3.zAxis
            local tiltAxis = pose:VectorToObjectSpace(Vector3.yAxis:Cross(direction))
            entry.Model:ScaleTo(entry.ModelScale * scale)
            self:UpdateMutationEffect(entry, scale)
            entry.Model:PivotTo(CFrame.new(position + direction * (0.18 * kick)) * pose.Rotation
                * CFrame.fromAxisAngle(tiltAxis, math.rad(4) * kick))
            if entry.HealthBar then
                entry.HealthBar.StudsOffsetWorldSpace = Vector3.new(0, entry.Visual.Size.Y / 2 + 1.2, 0)
            end
            if progress == 1 then
                entry.Started = nil
                entry.LastPose = pose
            end
        end
    end
    for index = #self._fragments, 1, -1 do
        local fragment = self._fragments[index]
        local elapsed = now - fragment.Started
        if elapsed >= fragment.Lifetime then
            fragment.Part.Parent = nil
            table.insert(self._fragmentPool, fragment.Part)
            table.remove(self._fragments, index)
        else
            local fade = math.clamp((elapsed / fragment.Lifetime - 0.7) / 0.3, 0, 1)
            local position = fragment.Position + fragment.Velocity * elapsed + Vector3.new(0, -14 * elapsed * elapsed, 0)
            local spin = fragment.Spin * elapsed
            fragment.Part.CFrame = CFrame.new(position) * fragment.Rotation * CFrame.Angles(spin.X, spin.Y, spin.Z)
            fragment.Part.Size = fragment.Size * math.max(0.05, 1 - fade)
            fragment.Part.Transparency = fade
        end
    end
end

--- 断开监听，复位钩爪并随特效目录清除绳索，最后销毁碎片池。
function Effects:Destroy()
    self._clawAdded:Disconnect()
    self._clawRemoved:Disconnect()
    for claw, moving in pairs(self._claws) do
        local rest = claw:GetAttribute("RestPose")
        if moving and rest then
            claw:PivotTo(rest)
            SetClawGrip(claw, rest, 0)
        end
    end
    self._added:Disconnect()
    self._removed:Disconnect()
    for rock in pairs(self._pending) do
        self:RemoveRock(rock)
    end
    for rock in pairs(self._rocks) do
        self:RemoveRock(rock)
    end
    self._folder:Destroy()
    for index, fragment in ipairs(self._fragmentPool) do
        fragment:Destroy()
    end
end

return Effects
