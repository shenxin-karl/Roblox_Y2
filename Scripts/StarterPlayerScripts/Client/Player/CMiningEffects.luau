-- Money 采矿表现：服务端石头只负责碰撞与次数，本地副本负责弹缩、碎屑和命中特效。
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local FX = _G.FX
local Settings = FX.Loader:RequireShared("Scripts.Game.Shared.MiningSettings")
local Effects = {}
Effects.__index = Effects

--- 由矿场组件持有，沿用服务器复制的次数而不预测发奖。
--- @param owner table 矿场客户端组件。
--- @return table 本地采矿表现对象。
function Effects.New(owner)
    local self = setmetatable({}, Effects)
    self._owner = owner
    self._templates = FX.Loader:Shared("Assets.Decorations.MiningEffects")
    self._rocks = {}
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

--- 克隆单块石头的外观，固定碰撞体不跟随受击抖动，避免影响玩家行走。
--- @param rock Instance 流式加载到客户端的公共矿石。
function Effects:AddRock(rock)
    local hits = rock:GetAttribute("RemainingHits")
    if self._rocks[rock] or not rock:IsA("BasePart") or not hits or hits <= 0 then
        return
    end
    local visual = rock:Clone()
    CollectionService:RemoveTag(visual, Settings.RockTag)
    visual.CanCollide = false
    visual.CanTouch = false
    visual.CanQuery = false
    visual.Parent = self._folder
    local entry = {
        Visual = visual, Size = rock.Size, Pose = rock.CFrame,
        Hits = hits, MaxHits = _G.GameConfig.CommonConfig.MiningRockHits,
        Transparency = rock.LocalTransparencyModifier,
    }
    self._rocks[rock] = entry
    rock.LocalTransparencyModifier = 1
    entry.Connection = rock:GetAttributeChangedSignal("RemainingHits"):Connect(function()
        local remaining = rock:GetAttribute("RemainingHits")
        if remaining and remaining < entry.Hits then
            entry.Hits = remaining
            entry.Started = os.clock()
            self:PlayHitEffect(entry, remaining == 0)
            self:UpdateHealthBar(entry)
            if remaining == 0 then
                visual.Transparency = 1
            end
        end
    end)
    self:UpdateHealthBar(entry)
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
    local entry = self._rocks[rock]
    if entry then
        entry.Connection:Disconnect()
        entry.Visual:Destroy()
        if rock.Parent then
            rock.LocalTransparencyModifier = entry.Transparency
        end
        self._rocks[rock] = nil
    end
end

--- 沿用 Money 的闪光、冲击波、火星、破碎烟尘与碎石轨迹。
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
    local burst = math.min(radius * (broken and 1.1 or 0.85), 3.2)
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
        dust.Lifetime = NumberRange.new(0.3, 0.45)
        dust.Size = NumberSequence.new(3, 7)
        dust.Transparency = NumberSequence.new(0.25, 1)
        dust.Parent = dustOrigin
        dust:Emit(3)
    end
    local sound = self._templates.RockBreak:Clone()
    local settings = self._owner:GetTable(_G.PlayerDataConfig.Settings)
    sound.Volume *= settings.soundEffectsVolume / 100
    sound.Parent = effect
    sound:Play()
    Debris:AddItem(effect, 3)
    local fragmentOrigin = broken and CFrame.lookAt(center, center + normal) or effect.CFrame
    self:SpawnFragments(fragmentOrigin, entry.Size, broken)
end

--- 复用 Money 的碎石网格与抛物线参数，每次普通命中三片、击碎四片。
--- @param origin CFrame 碎片生成位置与飞散朝向。
--- @param rockSize Vector3 原始石头尺寸。
--- @param broken boolean 击碎时扩大碎片及飞散范围。
function Effects:SpawnFragments(origin, rockSize, broken)
    local source = self._templates.Fragment
    local count = broken and 4 or 3
    local phase = math.random() * math.pi * 2
    for index = 1, count do
        local part = table.remove(self._fragmentPool) or source:Clone()
        local size = (0.5 + math.random() * 0.4) * (broken and 1.8 or 0.65)
        part.Size = source.Size * (size / math.max(source.Size.X, source.Size.Y, source.Size.Z))
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
            Started = os.clock(), Lifetime = 0.45 + math.random() * 0.1,
            Velocity = Vector3.new(math.cos(angle) * spread, broken and (8 + math.random() * 3) or 5,
                math.sin(angle) * spread) + (broken and Vector3.zero or origin.LookVector * 6),
            Spin = Vector3.new(math.random() * 10 - 5, math.random() * 10 - 5, math.random() * 10 - 5),
        })
    end
end

--- 每帧执行受击弹缩与残血缩小，原始尺寸和落地位置始终作为基准，不累计变形。
function Effects:Update()
    local now = os.clock()
    for rock, entry in pairs(self._rocks) do
        if entry.Hits > 0 then
            local ratio = entry.Hits / entry.MaxHits
            local scale = ratio > 0.66 and 1 or (ratio > 0.33 and 0.92 or 0.84)
            local progress = entry.Started and math.clamp((now - entry.Started) / 0.35, 0, 1) or 1
            scale *= 1 + math.sin(progress * math.pi * 2) * (1 - progress) * 0.18
            local position = entry.Pose.Position + Vector3.new(0, entry.Size.Y * (scale - 1) / 2, 0)
            local kickProgress = entry.Started and math.clamp((now - entry.Started) / 0.16, 0, 1) or 1
            local kick = math.sin(kickProgress * math.pi * 2) * (1 - kickProgress)
            local direction = entry.Direction or Vector3.zAxis
            local tiltAxis = entry.Pose:VectorToObjectSpace(Vector3.yAxis:Cross(direction))
            entry.Visual.Size = entry.Size * scale
            entry.Visual.CFrame = CFrame.new(position + direction * (0.18 * kick)) * entry.Pose.Rotation
                * CFrame.fromAxisAngle(tiltAxis, math.rad(4) * kick)
            if entry.HealthBar then
                entry.HealthBar.StudsOffsetWorldSpace = Vector3.new(0, entry.Visual.Size.Y / 2 + 1.2, 0)
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

--- 断开标签和次数监听，恢复服务器石头显示并销毁本地特效与碎片池。
function Effects:Destroy()
    self._added:Disconnect()
    self._removed:Disconnect()
    for rock in pairs(self._rocks) do
        self:RemoveRock(rock)
    end
    self._folder:Destroy()
    for index, fragment in ipairs(self._fragmentPool) do
        fragment:Destroy()
    end
end

return Effects
