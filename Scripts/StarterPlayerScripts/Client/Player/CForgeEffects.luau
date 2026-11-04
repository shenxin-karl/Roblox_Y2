-- 锻造表现：仅克隆外观并在本地挥锤，不修改装备、材料或地图原模型。
local FX = _G.FX
local FXLoader = FX.Loader
local Effects = {}
Effects.__index = Effects

local ImpactTime = 0.29
local SwingDuration = 0.68
local WarmColor = Color3.fromRGB(255, 173, 66)
local PerfectColor = Color3.fromRGB(255, 250, 225)
local SparkGravity = Vector3.new(0, -22, 0)

--- 在现有台位上建立本地放大木牌、剑、锤子和接触点，原模型只对本人隐藏。
--- @param station Model 服务端分配且已复制的场景台位。
--- @return table 本次锻造会话拥有的表现对象。
function Effects.New(station)
    local desktop = FXLoader:Here(station, "ThickSteelDesktop")
    local board = FXLoader:Here(station, "BlankDisplayBoard")
    local original = FXLoader:Here(station, "BlackHammer")
    local handle = FXLoader:Here(original, "BlackHammerHandle")
    local head = FXLoader:Here(original, "BlackForgedHammerHead")
    local swordTemplate = FXLoader:Shared("Assets.Decorations.Sword.ClassicSword.Handle")
    local self = setmetatable({}, Effects)
    self._base = desktop.CFrame
    -- 镜头从桌面负 Z 看向正 Z；握柄朝负 X 才位于画面右侧。
    self._hammerBase = self._base * CFrame.new(0, 0, 0.8) * CFrame.Angles(0, math.pi, 0)
    self._hidden = {}
    self._pulseAge = 1
    self._clock = 0
    self._random = Random.new()
    self._streaks = {}
    self._activeSparks = 0
    self._root = Instance.new("Model")
    self._root.Name = "ForgePresentation"

    local localBoard = board:Clone()
    localBoard.Name = "EnlargedBoard"
    self._boardPanel = FXLoader:Here(localBoard, "BlankWoodPanel")
    local bottom = FXLoader:Here(localBoard, "BottomTimberFrame")
    -- 仅放大本地副本，保持下沿和前后位置不变，沿用已核对的近景构图。
    local anchor = Vector3.new(self._boardPanel.Position.X,
        bottom.Position.Y - bottom.Size.Y / 2, self._boardPanel.Position.Z)
    localBoard:ScaleTo(board:GetScale() * 1.45)
    local scaledAnchor = Vector3.new(self._boardPanel.Position.X,
        bottom.Position.Y - bottom.Size.Y / 2, self._boardPanel.Position.Z)
    localBoard:PivotTo(localBoard:GetPivot() + anchor - scaledAnchor)
    for index, node in ipairs(localBoard:GetDescendants()) do
        if node:IsA("BasePart") then
            node.Anchored, node.CanCollide, node.CanTouch, node.CanQuery = true, false, false, false
            node.LocalTransparencyModifier = 0
        end
    end
    localBoard.Parent = self._root

    self._hammer = original:Clone()
    self._hammer.Name = "AnimatedHammer"
    -- 模板平放在桌上；绕握柄长轴翻转 90 度，让锤头长边竖直并用底端敲击。
    local hammerRoll = CFrame.Angles(math.pi / 2, 0, 0)
    self._handleToPivot = hammerRoll * handle.CFrame:ToObjectSpace(original:GetPivot())
    local headFrame = hammerRoll * handle.CFrame:ToObjectSpace(head.CFrame)
    local headOffset = headFrame.Position
    local headHalfHeight = (math.abs(headFrame.RightVector.Y) * head.Size.X
        + math.abs(headFrame.UpVector.Y) * head.Size.Y
        + math.abs(headFrame.LookVector.Y) * head.Size.Z) / 2
    self._gripX = handle.Size.X * 0.44
    self._swordHeight = desktop.Size.Y / 2 + swordTemplate.Size.Y / 2 + 0.03
    local contactHeight = self._swordHeight + swordTemplate.Size.Y / 2
    self._grip = CFrame.new(self._gripX - headOffset.X,
        contactHeight + headHalfHeight - headOffset.Y, -headOffset.Z)
    for index, node in ipairs(self._hammer:GetDescendants()) do
        if node:IsA("BasePart") then
            node.Anchored, node.CanCollide, node.CanTouch, node.CanQuery = true, false, false, false
            node.LocalTransparencyModifier = 0
        end
    end
    self._hammer.Parent = self._root

    self._sword = swordTemplate:Clone()
    self._sword.Name = "ForgeSword"
    self._sword.Anchored, self._sword.CanCollide, self._sword.CanTouch, self._sword.CanQuery = true, false, false, false
    self._sword.CFrame = self._base * CFrame.new(-0.35, self._swordHeight, 0.8)
        * CFrame.Angles(0, -math.pi / 2, 0)
    for index, node in ipairs(self._sword:GetDescendants()) do
        if node:IsA("Sound") or node:IsA("BaseScript") then
            node:Destroy()
        end
    end
    self._sword.Parent = self._root
    -- 独立白炽层短闪后淡出，保留原剑贴图；不再用 Highlight 把模型染成橙色。
    self._bladeFlash = self._sword:Clone()
    self._bladeFlash.Name = "BladeWhiteFlash"
    self._bladeFlash.Material = Enum.Material.Neon
    self._bladeFlash.Color = PerfectColor
    self._bladeFlash.Reflectance = 0
    self._bladeFlash.Transparency = 1
    self._bladeFlash.CastShadow = false
    local flashMesh = FXLoader:Here(self._bladeFlash, "Mesh")
    flashMesh.TextureId = ""
    flashMesh.Scale *= 1.008
    self._bladeFlash.Parent = self._root

    local anchor = Instance.new("Part")
    anchor.Name = "ImpactPoint"
    anchor.Anchored, anchor.CanCollide, anchor.CanTouch, anchor.CanQuery = true, false, false, false
    anchor.Size = Vector3.new(0.1, 0.1, 0.1)
    anchor.Transparency = 1
    anchor.CFrame = self._base * CFrame.new(0, contactHeight + 0.03, 0.8)
    anchor.Parent = self._root
    -- 火星由白热尖端与橙色细尾构成，沿飞行方向拉长，而不是星形贴图向上冒。
    for index = 1, 40 do
        local tail, tip = Instance.new("Attachment"), Instance.new("Attachment")
        tail.Name, tip.Name = "SparkTail" .. index, "SparkTip" .. index
        tail.Parent, tip.Parent = anchor, anchor
        local core = Instance.new("Beam")
        core.Name = "SparkCore" .. index
        core.Attachment0, core.Attachment1 = tail, tip
        core.FaceCamera, core.Enabled = true, false
        core.LightEmission, core.LightInfluence, core.Brightness = 0.65, 0, 1.4
        core.Segments = 3
        core.Width0, core.Width1 = 0.025, 0
        core.Color = ColorSequence.new(Color3.fromRGB(255, 85, 12), Color3.fromRGB(255, 218, 145))
        core.Parent = anchor
        local glow = core:Clone()
        glow.Name = "SparkGlow" .. index
        glow.Width0 = 0.07
        glow.LightEmission = 1
        glow.Brightness = 0.8
        glow.Color = ColorSequence.new(WarmColor)
        glow.Transparency = NumberSequence.new(0.8)
        glow.Parent = anchor
        self._streaks[index] = {Tail = tail, Tip = tip, Core = core, Glow = glow}
    end
    self._light = Instance.new("PointLight")
    self._light.Name = "ImpactFlash"
    self._light.Brightness = 0
    self._light.Range = 5
    self._light.Parent = anchor
    self._bloom = Instance.new("BloomEffect")
    self._bloom.Name = "ForgeContactBloom"
    self._bloom.Intensity, self._bloom.Size, self._bloom.Threshold = 0, 12, 1.5
    self._bloom.Parent = workspace.CurrentCamera

    self:SetAngle(-70, 3.8)
    self._root.Parent = FXLoader:Workspace("Decorations")
    for sourceIndex, source in ipairs({original, board}) do
        for index, node in ipairs(source:GetDescendants()) do
            if node:IsA("BasePart") then
                self._hidden[node] = node.LocalTransparencyModifier
                node.LocalTransparencyModifier = 1
            end
        end
    end
    return self
end

--- 木牌界面只绑定本人副本，不改变其他玩家看到的场景原牌。
--- @return BasePart 本次会话的本地放大木牌面板。
function Effects:GetBoardPanel()
    return self._boardPanel
end

--- 围绕握柄尾端旋转，负角度抬起位于负 X 方向的锤头。
--- @param degrees number 桌面局部 Z 轴旋转角度。
--- @param rightOffset number 向画面右侧移开的距离，命中时必须为零。
function Effects:SetAngle(degrees, rightOffset)
    local base = self._hammerBase - self._base.RightVector * rightOffset
    local pose = base * self._grip * CFrame.Angles(0, 0, math.rad(degrees))
        * CFrame.new(-self._gripX, 0, 0)
    self._hammer:PivotTo(pose * self._handleToPivot)
end

--- 一锤播完才接受下一锤，结果回调只在锤头接触时执行一次。
--- @param powerful boolean 是否使用较强的展示反馈，不代表装备强化结果。
--- @param onImpact function 命中时通知所属 UI 的回调。
--- @return boolean 是否开始本次挥锤。
function Effects:Strike(powerful, onImpact)
    if self._destroyed or self._swingAge then
        return false
    end
    self._swingAge = 0
    self._powerful = powerful
    self._onImpact = onImpact
    self._impacted = false
    return true
end

--- 告知界面挥锤是否尚未结束，不把动画时长重复写到交互层。
--- @return boolean 当前是否正在播放一锤。
function Effects:IsBusy()
    return not self._destroyed and self._swingAge ~= nil
end

--- 接触瞬间炸开橙金色飞溅并闪白剑身；大成功只加强数量和射程。
function Effects:EmitImpact()
    self._pulseAge = 0
    self._sparkAge = 0
    self._activeSparks = self._powerful and 40 or 22
    self._light.Color = WarmColor
    for index, streak in ipairs(self._streaks) do
        local active = index <= self._activeSparks
        streak.Core.Enabled, streak.Glow.Enabled = active, active
        if active then
            local angle = self._random:NextNumber(0, math.pi * 2)
            local speed = self._random:NextNumber(14, self._powerful and 38 or 26)
            streak.Velocity = Vector3.new(math.cos(angle) * speed,
                (math.sin(angle) * 0.8 + 0.25) * speed, self._random:NextNumber(-14, -5))
            streak.Lifetime = self._random:NextNumber(0.17, self._powerful and 0.42 or 0.31)
            local longStreak = self._random:NextNumber() < 0.2
            streak.TailTime = longStreak
                and self._random:NextNumber(0.025, self._powerful and 0.045 or 0.035)
                or self._random:NextNumber(0.006, 0.018)
            streak.Width = self._random:NextNumber(0.018, 0.033)
            streak.Tail.Position, streak.Tip.Position = Vector3.zero, Vector3.zero
        end
    end
end

--- 细长火星高速向外飞散，尾迹随速度方向移动并冷却消失，不铺满常驻粒子。
--- @param deltaTime number 本渲染帧经过的秒数。
function Effects:UpdateSparks(deltaTime)
    if self._activeSparks == 0 then
        return
    end
    self._sparkAge += deltaTime
    local age = self._sparkAge
    for index = 1, self._activeSparks do
        local streak = self._streaks[index]
        if age >= streak.Lifetime then
            streak.Core.Enabled, streak.Glow.Enabled = false, false
        else
            local tailAge = math.max(0, age - streak.TailTime)
            -- 发射面略靠锤头前缘，让刚炸开的火星不被锤头整个挡住。
            local origin = Vector3.new(0, 0, -0.45)
            streak.Tip.Position = origin + streak.Velocity * age + SparkGravity * (age * age / 2)
            streak.Tail.Position = origin + streak.Velocity * tailAge + SparkGravity * (tailAge * tailAge / 2)
            local progress = age / streak.Lifetime
            local fade = math.clamp((progress - 0.45) / 0.55, 0, 1)
            streak.Core.Width0 = streak.Width * (1 - progress * 0.55)
            streak.Glow.Width0 = streak.Core.Width0 * 2.5
            streak.Core.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, fade),
                NumberSequenceKeypoint.new(1, fade),
            })
            streak.Glow.Transparency = NumberSequence.new(0.8 + fade * 0.2)
        end
    end
    if age >= 0.42 then
        self._activeSparks = 0
    end
end

--- 由所属组件逐帧推进，避免异步任务在退出后继续回写界面。
--- @param deltaTime number 当前渲染帧经过的秒数。
function Effects:Update(deltaTime)
    if self._destroyed then
        return
    end
    self._clock += deltaTime
    self._pulseAge += deltaTime
    local sparkDelta = deltaTime
    if self._swingAge then
        self._swingAge += deltaTime
        local age = self._swingAge
        if not self._impacted and age >= ImpactTime then
            self._impacted = true
            self:SetAngle(0, 0)
            self:EmitImpact()
            -- 新火星只推进本帧命中后的余量，避免低帧率时首帧就跳到远处。
            sparkDelta = math.max(0, age - ImpactTime)
            self._pulseAge = sparkDelta
            self._onImpact()
            if self._destroyed then
                return
            end
        end
        local angle, rightOffset
        if age < 0.18 then
            local progress = age / 0.18
            angle = -70 - 8 * math.sin(progress * math.pi / 2)
            rightOffset = 3.8
        elseif age < ImpactTime then
            local progress = (age - 0.18) / (ImpactTime - 0.18)
            angle = -78 * (1 - progress * progress * progress)
            rightOffset = 3.8 * (1 - progress * progress * progress)
        elseif age < 0.37 then
            angle = -13 * math.sin((age - ImpactTime) / 0.08 * math.pi / 2)
            rightOffset = 0
        else
            local progress = math.clamp((age - 0.37) / (SwingDuration - 0.37), 0, 1)
            local eased = progress * progress * (3 - 2 * progress)
            angle = -13 - 57 * eased
            rightOffset = 3.8 * eased
        end
        self:SetAngle(angle, rightOffset)
        if age >= SwingDuration then
            self._swingAge, self._onImpact = nil, nil
        end
    end
    self:UpdateSparks(sparkDelta)
    local flash = math.max(0, 1 - math.max(0, self._pulseAge - 0.025) / (self._powerful and 0.14 or 0.1))
    self._bladeFlash.Transparency = 1 - math.sqrt(flash)
    self._light.Brightness = flash * flash * (self._powerful and 3.5 or 2)
    self._bloom.Intensity = flash * (self._powerful and 0.28 or 0.18)
end

--- 返回衰减的近景轻震动，不直接接管玩家相机。
--- @return CFrame 所属组件应叠加到固定近景镜头上的局部偏移。
function Effects:GetShake()
    local strength = math.max(0, 1 - self._pulseAge / 0.2) ^ 2
        * (self._powerful and 0.09 or 0.045)
    return CFrame.new(math.sin(self._clock * 91) * strength,
        math.cos(self._clock * 107) * strength, 0)
        * CFrame.Angles(0, 0, math.sin(self._clock * 83) * strength * 0.12)
end

--- 退出、死亡和销毁共用清理，恢复本人隐藏的原木牌和锤子。
function Effects:Destroy()
    if self._destroyed then
        return
    end
    self._destroyed = true
    self._onImpact = nil
    for part, transparency in pairs(self._hidden) do
        if part.Parent then
            part.LocalTransparencyModifier = transparency
        end
    end
    self._bloom:Destroy()
    self._root:Destroy()
end

return Effects
