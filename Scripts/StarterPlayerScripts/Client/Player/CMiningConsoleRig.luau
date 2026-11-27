-- 采矿操作台的第一人称表现：摇杆、双手和发射键只在本机镜头中显示。
local Rig = {}
Rig.__index = Rig
-- 镜头略微抬高并后移；操作台仍以原眼位定位，保留矿盘和操作台的同一取景。
Rig.CameraOffset = CFrame.new(0, 0.34, 0.65)

local metal = Enum.Material.Metal
local rubber = Enum.Material.SmoothPlastic
local steel = Color3.fromRGB(77, 91, 101)
local graphite = Color3.fromRGB(39, 47, 51)
local brass = Color3.fromRGB(211, 152, 67)
local cylinderUp = CFrame.Angles(0, 0, math.pi / 2)
local controlX = 1.02

--- 创建使用本地原点摆放零件的活动部件组。
--- @param parent Instance 所属模型。
--- @param name string 部件组名称。
--- @return Model 使用固定枢轴的部件组。
local function MakeGroup(parent, name)
    local group = Instance.new("Model")
    group.Name = name
    group.WorldPivot = CFrame.identity
    group.Parent = parent
    return group
end

--- 所有操作台零件只用于显示，不拦截世界交互。
--- @param parent Model 部件组。
--- @param name string 零件名称。
--- @param size Vector3 本地尺寸。
--- @param pose CFrame 本地位置和朝向。
--- @param color Color3 外观颜色。
--- @param material Enum.Material 表面材质。
--- @param shape Enum.PartType? 特殊形状。
--- @return Part 新建的操作台零件。
local function AddPart(parent, name, size, pose, color, material, shape)
    local part = Instance.new("Part")
    part.Name, part.Size, part.CFrame = name, size, pose
    part.Color, part.Material = color, material
    part.Shape = shape or Enum.PartType.Block
    part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
    part.CastShadow = false
    part.Parent = parent
    return part
end

--- 用统一的方块手臂贴住操纵件，只从角色读取对应一侧的肤色。
--- @param model Model 本机操作台模型。
--- @param character Model 当前玩家角色。
--- @param side string 左右侧名称 Left 或 Right。
--- @return Model 以手端为枢轴的方块手臂。
local function MakeArm(model, character, side)
    local sign = if side == "Left" then -1 else 1
    local group = MakeGroup(model, side .. "ViewArm")
    local source = character:FindFirstChild(side .. "Hand") or character:FindFirstChild(side .. " Arm")
        or character:FindFirstChild(side .. "LowerArm")
    if source and source:IsA("BasePart") then
        local size = Vector3.new(0.48, 1.55, 0.48)
        local rotation = CFrame.Angles(0, math.rad(sign * 28), 0) * CFrame.Angles(math.rad(117), 0, 0)
        AddPart(group, "BlockArm", size, rotation * CFrame.new(0, size.Y / 2, 0), source.Color, rubber)
    end
    return group
end

--- 创建本机操作台和跟随操纵件的手臂副本。
--- @param character Model 当前角色。
--- @param camera Camera 视模所属镜头。
--- @return table 可按帧驱动及离座销毁的视模。
function Rig.New(camera, character)
    local self = setmetatable({}, Rig)
    local model = Instance.new("Model")
    model.Name = "MiningConsoleViewmodel"
    self._model, self._camera = model, camera
    self._frame = MakeGroup(model, "ControlDeck")
    self._stick = MakeGroup(model, "SteeringLever")
    self._trigger = MakeGroup(model, "LaunchPlunger")
    self._leftArm = MakeArm(model, character, "Left")
    self._rightArm = MakeArm(model, character, "Right")
    self._steer, self._press = 0, 0

    AddPart(self._frame, "Housing", Vector3.new(3.22, 0.27, 1.00), CFrame.new(0, -0.14, 0), graphite, metal)
    AddPart(self._frame, "Faceplate", Vector3.new(3.14, 0.06, 0.96), CFrame.identity, steel, metal)
    AddPart(self._frame, "EdgeTrim", Vector3.new(3.08, 0.05, 0.05), CFrame.new(0, 0.03, -0.45), brass, metal)
    for side = -1, 1, 2 do
        AddPart(self._frame, "Socket", Vector3.new(0.10, 0.58, 0.58),
            CFrame.new(side * controlX, 0.07, 0) * cylinderUp, graphite, metal, Enum.PartType.Cylinder)
    end
    AddPart(self._stick, "Shaft", Vector3.new(0.53, 0.12, 0.12),
        CFrame.new(0, 0.265, 0) * cylinderUp, steel, metal, Enum.PartType.Cylinder)
    self._grip = AddPart(self._stick, "Grip", Vector3.new(0.34, 0.34, 0.34),
        CFrame.new(0, 0.54, 0) * cylinderUp, brass, rubber, Enum.PartType.Ball)
    self._button = AddPart(self._trigger, "Button", Vector3.new(0.19, 0.50, 0.50),
        cylinderUp, Color3.fromRGB(236, 99, 56), rubber, Enum.PartType.Cylinder)

    self:Update(0, false, 0)
    model.Parent = camera
    return self
end

--- 让手掌贴住摇杆与按钮，按当前视口将操作台留在画面下沿。
--- @param steer number 左右转向的归一化偏转量，向右为正。
--- @param firing boolean 当前是否按下发射按钮。
--- @param dt number 本帧间隔秒数。
function Rig:Update(steer, firing, dt)
    local blend = 1 - math.exp(-18 * dt)
    self._steer += (steer - self._steer) * blend
    self._press += ((if firing then 1 else 0) - self._press) * blend
    local camera = self._camera
    local depth = 1.5
    local halfHeight = depth * math.tan(math.rad(camera.FieldOfView / 2))
    local viewport = camera.ViewportSize
    local halfWidth = halfHeight * viewport.X / math.max(1, viewport.Y)
    local scale = math.clamp(math.min(halfHeight / 1.13, halfWidth / 1.85), 0.15, 1.35)
    if self._scale ~= scale then
        self._scale = scale
        for index, group in ipairs({self._frame, self._stick, self._trigger}) do
            group:ScaleTo(scale)
        end
        self._leftArm:ScaleTo(scale * 0.62)
        self._rightArm:ScaleTo(scale * 0.62)
    end
    local base = camera.CFrame * Rig.CameraOffset:Inverse()
        * CFrame.new(0, -halfHeight * 0.76, -depth) * CFrame.Angles(math.rad(18), 0, 0)
    local stick = base * CFrame.new(-controlX * scale, 0.10 * scale, 0)
        * CFrame.Angles(0, 0, -self._steer * math.rad(30))
    local press = base * CFrame.new(controlX * scale, (0.19 - self._press * 0.08) * scale, 0)
    self._frame:PivotTo(base)
    self._stick:PivotTo(stick)
    self._trigger:PivotTo(press)
    self._leftArm:PivotTo(self._grip.CFrame * cylinderUp:Inverse() * CFrame.new(-0.11 * scale, 0, 0.04 * scale))
    self._rightArm:PivotTo(self._button.CFrame * cylinderUp:Inverse()
        * CFrame.new(0.07 * scale, (0.095 + 0.10 * (1 - self._press)) * scale, 0.09 * scale))
end

--- 离座时随操作台一起移除手臂副本。
function Rig:Destroy()
    self._model:Destroy()
end

return Rig
