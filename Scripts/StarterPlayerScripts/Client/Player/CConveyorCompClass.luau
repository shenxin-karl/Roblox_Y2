-- 传送带横条滚动、提示与行走加速；横条仅作本地视觉，不参与物理输送。
local RunService = game:GetService("RunService")
local FX = _G.FX
local FXLoader = FX.Loader
local Comp = FX.Class("CConveyorCompClass", "FCPlayerCompClass")

--- 创建可复用的滚动横条和箭头，并将逐帧监听交给组件生命周期管理。
--- @param owner CPlayerObjectClass 当前客户端玩家对象。
function Comp:Ctor(owner)
    Comp.Super.Ctor(self, owner)
    self._decorations = FXLoader:Workspace("Decorations")
    local conveyor = FXLoader:Here(self._decorations, "SquareConveyor")
    local decks = FXLoader:Here(conveyor, "Decks")
    self._baseSpeed = conveyor:GetAttribute("Speed") * 2
    self._raycastParams = RaycastParams.new()
    self._raycastParams.FilterType = Enum.RaycastFilterType.Include
    self._raycastParams.FilterDescendantsInstances = { decks }
    self._stripeSpeed = conveyor:GetAttribute("Speed")
    self:CreateStripes(decks)
    self._arrow = Instance.new("Folder")
    self._arrow.Name = "ConveyorDirectionArrow"
    self._parts = {}
    self._offsets = {
        CFrame.new(0, 0, 0.3),
        CFrame.new(-0.4, 0, -0.65) * CFrame.Angles(0, math.rad(-45), 0),
        CFrame.new(0.4, 0, -0.65) * CFrame.Angles(0, math.rad(45), 0),
    }
    for index = 1, 3 do
        local part = Instance.new("Part")
        part.Name = "Arrow" .. index
        part.Size = Vector3.new(0.25, 0.08, index == 1 and 1.8 or 1.2)
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.CastShadow = false
        part.Material = Enum.Material.Neon
        part.Color = Color3.fromRGB(80, 235, 255)
        part.Parent = self._arrow
        self._parts[index] = part
    end
    self:TrackConnection(RunService.RenderStepped:Connect(function(deltaTime)
        self:RefreshStripes(deltaTime)
        self:RefreshArrow()
    end))
    self:TrackConnection(RunService.PreSimulation:Connect(function()
        self:RefreshMovementSpeed()
    end))
end

--- 沿现有八段闭合路径铺设蓝色横条，复用实例且不改变承载面的物理属性。
--- @param decks Folder 场景中按 01 到 08 排列的承载面容器。
function Comp:CreateStripes(decks)
    self._stripePaths = {}
    self._stripeLength = 0
    self._stripeOffset = 0
    self._stripeParts = {}
    self._stripeFolder = Instance.new("Folder")
    self._stripeFolder.Name = "ConveyorScrollingStripes"
    for index = 1, 8 do
        local deck = FXLoader:Here(decks, string.format("%02d", index))
        local startPosition = deck:GetAttribute("PathStart")
        local path = deck:GetAttribute("PathEnd") - startPosition
        self._stripeLength += path.Magnitude
        self._stripePaths[index] = {
            Start = startPosition,
            Direction = path.Unit,
            Length = path.Magnitude,
            EndDistance = self._stripeLength,
            Width = (math.min(deck.Size.X, deck.Size.Z) - 4) * 0.8,
        }
    end
    local count = math.ceil(self._stripeLength / 6)
    self._stripeSpacing = self._stripeLength / count
    for index = 1, count do
        local part = Instance.new("Part")
        part.Name = "Stripe" .. index
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.CastShadow = false
        part.Material = Enum.Material.SmoothPlastic
        part.Color = Color3.fromRGB(55, 135, 255)
        part.Parent = self._stripeFolder
        self._stripeParts[index] = part
    end
    self:RefreshStripes(0)
    self._stripeFolder.Parent = self._decorations
end

--- 按闭合路径总长度回绕，保持横条间距并让转角及首尾连续衔接。
--- @param deltaTime number 距离上一渲染帧的秒数。
function Comp:RefreshStripes(deltaTime)
    self._stripeOffset = (self._stripeOffset + self._stripeSpeed * deltaTime) % self._stripeLength
    for index, part in ipairs(self._stripeParts) do
        local distance = ((index - 1) * self._stripeSpacing + self._stripeOffset) % self._stripeLength
        for pathIndex = 1, #self._stripePaths do
            local path = self._stripePaths[pathIndex]
            if distance < path.EndDistance then
                local along = distance - (path.EndDistance - path.Length)
                local position = path.Start + path.Direction * along
                part.Size = Vector3.new(path.Width, 0.04, 1.6)
                part.CFrame = CFrame.lookAt(position, position + path.Direction)
                break
            end
        end
    end
end

--- 提供传送带提示组件的稳定协作名称。
--- @return string 组件协作名称。
function Comp:GetCompName()
    return "CConveyorComp"
end

--- 查询本地玩家当前踩住的承载面，供方向提示和行走加速共用。
--- @return RaycastResult? 脚下传送带的命中结果。
--- @return Humanoid? 当前存活且着地的角色控制器。
function Comp:GetConveyorContact()
    local character = self:GetPlayerCharacter()
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = humanoid and humanoid.RootPart
    if not root or not humanoid or humanoid.Health <= 0 or humanoid.Sit or humanoid.FloorMaterial == Enum.Material.Air then
        return
    end
    local rayLength = humanoid.HipHeight + root.Size.Y / 2 + 1
    if humanoid.RigType == Enum.HumanoidRigType.R6 then
        rayLength += 2
    end
    local hit = workspace:Raycast(root.Position, Vector3.new(0, -rayLength, 0), self._raycastParams)
    return hit, humanoid
end

--- 设置本地承载面的输送速度，保留碰撞和角色原生行走控制。
--- @param deck BasePart 本地玩家踩住的承载面。
--- @param multiplier number 相对正常输送速度的倍率。
function Comp:SetDeckSpeed(deck, multiplier)
    local direction = (deck:GetAttribute("PathEnd") - deck:GetAttribute("PathStart")).Unit
    deck.AssemblyLinearVelocity = direction * self._baseSpeed * multiplier
end

--- 仅主动行走时将本地输送速度翻倍；停步、换道或离开时恢复正常速度。
function Comp:RefreshMovementSpeed()
    local hit, humanoid = self:GetConveyorContact()
    local deck = hit and hit.Instance
    if self._activeDeck and self._activeDeck ~= deck then
        self:SetDeckSpeed(self._activeDeck, 1)
    end
    self._activeDeck = deck
    if deck then
        local isWalking = humanoid.MoveDirection.Magnitude > 0.01 and humanoid.WalkSpeed > 0
        self:SetDeckSpeed(deck, isWalking and 2 or 1)
    end
end

--- 仅在脚下命中传送带时显示箭头，优先使用角色实际水平移动方向。
function Comp:RefreshArrow()
    local hit, humanoid = self:GetConveyorContact()
    if not hit then
        self._arrow.Parent = nil
        return
    end
    local velocity = humanoid.RootPart.AssemblyLinearVelocity
    local direction = Vector3.new(velocity.X, 0, velocity.Z)
    if direction.Magnitude < 1 then
        local path = hit.Instance:GetAttribute("PathEnd") - hit.Instance:GetAttribute("PathStart")
        direction = Vector3.new(path.X, 0, path.Z)
    end
    direction = direction.Unit
    local position = hit.Position + direction * 3 + Vector3.new(0, 0.12, 0)
    local frame = CFrame.lookAt(position, position + direction)
    for index, part in ipairs(self._parts) do
        part.CFrame = frame * self._offsets[index]
    end
    self._arrow.Parent = self._decorations
end

--- 恢复本地承载面速度，并释放横条、箭头及逐帧监听。
function Comp:Dtor()
    Comp.Super.Dtor(self)
    if self._activeDeck then
        self:SetDeckSpeed(self._activeDeck, 1)
    end
    self._arrow:Destroy()
    self._stripeFolder:Destroy()
end

return Comp
