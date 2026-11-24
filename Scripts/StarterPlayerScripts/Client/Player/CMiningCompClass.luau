-- 公共矿场界面：显示同服倒计时、自动拾取和木棍操作。
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local FX, FC = _G.FX, _G.FC
local Text = FX.Text
local Settings = FX.Loader:RequireShared("Scripts.Game.Shared.MiningSettings")
local MiningEffects = FX.Loader:RequireFromParent(script, "CMiningEffects")
local UIRoot = FX.Loader:RequireShared("Scripts.Framework.Client.FCUIRoot")
local ActionButton = FX.Loader:Require(script.Parent.Parent, "UI.CActionButton")
local TextPrompt = FX.Loader:RequireShared("Scripts.Framework.Client.FCTextPrompt")
local TranslationTexts = Text.Define("MiningInteraction", {
    Preparing = "Preparing ore…",
    Refreshed = "Ore has refreshed!",
    EquipStick = "Equip wooden stick",
    SwingStick = "Swing wooden stick",
    StickDetail = "Knock ore loose in the quarry",
})
local Comp = FX.Class("CMiningCompClass", "FCUICompClass")

-- 依次是抬到右肩、扫过身前、随势收棍、回到竖持。左臂留给原角色动画。
local SwingJoints = {"RightShoulder", "RightElbow", "RightWrist", "Waist"}
local SwingPoses = {
    {Time = 0, Weight = 0, {78, 0, 0}, {12, 0, 0}, {0, 0, 0}, {0, 0, 0}},
    {Time = 0.22, Weight = 1, {99, -12, 34}, {66, 0, 0}, {5, 0, 0}, {0, -20, 4}},
    {Time = 0.32, Weight = 1, {73, 28, 8}, {25, 0, 0}, {-88, 0, 0}, {6, 15, -3}},
    {Time = 0.42, Weight = 1, {57, 55, -12}, {38, 0, 0}, {-77, 0, 0}, {4, 30, -4}},
    {Time = 0.66, Weight = 0, {78, 0, 0}, {12, 0, 0}, {0, 0, 0}, {0, 0, 0}},
}
for poseIndex, pose in ipairs(SwingPoses) do
    for jointIndex, angles in ipairs(pose) do
        pose[jointIndex] = CFrame.fromOrientation(math.rad(angles[1]), math.rad(angles[2]), math.rad(angles[3]))
    end
end

--- 恢复上一帧覆盖前的关节姿势，避免动画降频时重复叠加。
function Comp:ResetSwingPose()
    for joint, transform in pairs(self._swingTransforms) do
        if joint.Parent then
            joint.Transform = transform
        end
    end
    table.clear(self._swingTransforms)
end

--- 按服务器广播的时刻播放挥击；扛起矿石时结束正在播放的挥击。
function Comp:UpdateSwingPoses()
    local now = workspace:GetServerTimeNow()
    for playerIndex, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local tool = character and character:FindFirstChild(Settings.StickName)
        local started = tool and not character:GetAttribute(Settings.CarryAttribute)
            and tool:GetAttribute(Settings.StickSwingAttribute)
        local elapsed = started and math.max(0, now - started)
        if not elapsed or elapsed >= SwingPoses[#SwingPoses].Time then
            continue
        end
        for index = 2, #SwingPoses do
            local target = SwingPoses[index]
            if elapsed <= target.Time then
                local from = SwingPoses[index - 1]
                local alpha = (elapsed - from.Time) / (target.Time - from.Time)
                alpha = alpha * alpha * (3 - 2 * alpha)
                local weight = from.Weight + (target.Weight - from.Weight) * alpha
                for jointIndex, name in ipairs(SwingJoints) do
                    local joint = character:FindFirstChild(name, true)
                    if joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
                        local base = joint.Transform
                        self._swingTransforms[joint] = base
                        joint.Transform = base:Lerp(CFrame.new(base.Position) * from[jointIndex]:Lerp(target[jointIndex], alpha), weight)
                    end
                end
                break
            end
        end
    end
end

--- 返回矿场界面的组件名。
--- @return string 组件协作名。
function Comp:GetCompName()
    return "CMiningComp"
end

--- 在共享画布底部显示 Y1 的彩色提示，留出快捷栏空间。
function Comp:CreateRefreshNotice()
    local label = Instance.new("TextLabel")
    label.Name = "OreRefreshNotice"
    label.AnchorPoint = Vector2.new(0.5, 1)
    label.Position = UDim2.new(0.5, 0, 1, -78)
    label.Size = UDim2.new(0.9, 0, 0, 80)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextWrapped = true
    label.TextYAlignment = Enum.TextYAlignment.Bottom
    label.TextSize = 28
    label.AutoLocalize = false
    label.Text = Text.Tr(TranslationTexts.Refreshed)
    label.Visible = false
    label.Parent = UIRoot.Get()
    local stroke = Instance.new("UIStroke")
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
    stroke.Color = Color3.new(0, 0, 0)
    stroke.Thickness = 3
    stroke.Parent = label
    self._refreshNotice = label
    self._refreshTextEffect = TextPrompt.AttachGradient(label)
end

--- 沿用矿场 HUD，并在角色动画之后叠加已确认的挥击动作。
function Comp:OnReady()
    self._swingTransforms = {}
    self:TrackConnection(RunService.PreAnimation:Connect(function()
        self:ResetSwingPose()
    end))
    self:TrackConnection(RunService.PreSimulation:Connect(function()
        self:UpdateSwingPoses()
    end))
    self._effects = MiningEffects.New(self)
    self._countdown = FX.Loader:PlayerGui("Main.HUD.Wallet.RefreshStat.Countdown")
    self:CreateRefreshNotice()
    self._button, self._buttonTitle, self._buttonDetail = ActionButton.New("MiningInteraction")
    self._lastPickup, self._lastSwing = -math.huge, -math.huge
    self:TrackConnection(self._button.Activated:Connect(function()
        if self._button.Visible then
            self:SwingStick()
        end
    end))
    self:TrackConnection(FC.Localization.Changed:Connect(function()
        self._refreshNotice.Text = Text.Tr(TranslationTexts.Refreshed)
        self:Refresh()
    end))
    local elapsed = 0
    --- 限制交互扫描频率；矿石特效仍按帧更新。
    --- @param deltaTime number 本帧经过秒数。
    self:TrackConnection(RunService.Heartbeat:Connect(function(deltaTime)
        self._effects:Update()
        elapsed += deltaTime
        if elapsed >= 0.1 then
            elapsed = 0
            self:Refresh()
        end
    end))
    self:Refresh()
end

--- 背矿时不发挥击请求；装备和命中仍由服务端判定。
function Comp:SwingStick()
    local character = self:GetPlayerCharacter()
    if not character or character:GetAttribute(Settings.CarryAttribute) then
        return
    end
    local now = os.clock()
    if now - self._lastSwing < Settings.StickCooldown then
        return
    end
    self._lastSwing = now
    FX.Network:SendMsgToServer("C2S_SwingMiningStick")
end

--- 自定义背包不列出场景工具，矿区按钮可装备；装备后也能用普通 Tool 输入挥棍。
--- @param character Model? 当前玩家角色。
function Comp:RefreshStick(character)
    local backpack = self:GetPlayerNode():FindFirstChildOfClass("Backpack")
    local stick = character and character:FindFirstChild(Settings.StickName)
        or backpack and backpack:FindFirstChild(Settings.StickName)
    if stick == self._stick then
        return
    end
    if self._stickActivated then
        self._stickActivated:Disconnect()
        self._stickActivated = nil
    end
    self._stick = stick
    if stick and stick:IsA("Tool") then
        self._stickActivated = stick.Activated:Connect(function()
            self:SwingStick()
        end)
    end
end

--- 原生 Tool 名称来自配置翻译，堆叠数仅显示整数，不复制私有背包数据。
function Comp:RefreshToolNames()
    local player = self:GetPlayerNode()
    local containers = {player:FindFirstChildOfClass("Backpack"), player.Character}
    for index = 1, 2 do
        local container = containers[index]
        if container then
            for childIndex, tool in ipairs(container:GetChildren()) do
                local itemId = tool:GetAttribute("FrameworkItemId")
                local display = itemId and _G.ItemConfig.Display[itemId]
                if tool:IsA("Tool") and display then
                    local name = Text.TrSource(display.Name)
                    local count = tool:GetAttribute("FrameworkStackCount") or 1
                    if count > 1 then
                        name ..= " ×" .. count
                    end
                    if tool.Name ~= name then
                        tool.Name = name
                    end
                    local description = Text.TrSource(display.Desc)
                    if tool.ToolTip ~= description then
                        tool.ToolTip = description
                    end
                end
            end
        end
    end
end

--- 靠近时请求拾取最近的落地矿石，最终距离和归属由服务端重验。
--- @param position Vector3 当前角色位置。
--- @param now number 本地节流时钟。
function Comp:TryPickUp(position, now)
    if now - self._lastPickup < Settings.RequestCooldown then
        return
    end
    local nearestId
    local distance = Settings.InteractDistance
    for index, rock in ipairs(CollectionService:GetTagged(Settings.RockTag)) do
        if rock:IsA("Model") and rock.PrimaryPart then
            local current = (rock:GetPivot().Position - position).Magnitude
            if current <= distance then
                nearestId, distance = rock:GetAttribute("MiningRockId"), current
            end
        end
    end
    if nearestId then
        self._lastPickup = now
        FX.Network:SendMsgToServer("C2S_PickUpOre", nearestId)
    end
end

--- 刷新公共倒计时和矿区操作；背矿时隐藏挥击按钮并停止拾取。
function Comp:Refresh()
    local now = os.clock()
    local deadline = workspace:GetAttribute(Settings.RefreshAttribute)
    if deadline and self._miningDeadline and deadline > self._miningDeadline then
        self._refreshNoticeUntil = now + 4
    end
    self._miningDeadline = deadline
    self._refreshNotice.Visible = self._refreshNoticeUntil ~= nil and now < self._refreshNoticeUntil
    if deadline then
        local seconds = math.max(0, math.ceil(deadline - workspace:GetServerTimeNow()))
        self._countdown.Text = string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
    else
        self._countdown.Text = Text.Tr(TranslationTexts.Preparing)
    end
    local character = self:GetPlayerCharacter()
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = humanoid and humanoid.RootPart
    local ground = FX.Loader:FindFromWorkspace(Settings.GroundPath)
    local inQuarry = root and ground and humanoid.Health > 0 and not humanoid.PlatformStand
        and self:GetNumber(_G.PlayerDataConfig.ForgeStation) <= 0 and Settings.IsInQuarry(ground, root.Position)
    self:RefreshStick(character)
    local canInteract = inQuarry == true and not character:GetAttribute(Settings.CarryAttribute)
    self._button.Visible = canInteract and self._stick ~= nil
    if self._button.Visible then
        self._buttonTitle.Text = Text.Tr(self._stick.Parent == character
            and TranslationTexts.SwingStick or TranslationTexts.EquipStick)
        self._buttonDetail.Text = Text.Tr(TranslationTexts.StickDetail)
    end
    if canInteract then
        self:TryPickUp(root.Position, now)
    end
    self:RefreshToolNames()
end

--- 清理矿场自有的按钮、提示、特效，恢复被挥击覆盖的关节。
function Comp:Dtor()
    if self._swingTransforms then
        self:ResetSwingPose()
    end
    if self._stickActivated then
        self._stickActivated:Disconnect()
    end
    if self._effects then
        self._effects:Destroy()
    end
    Comp.Super.Dtor(self)
    if self._refreshTextEffect then
        self._refreshTextEffect:Destroy()
        self._refreshNotice:Destroy()
    end
    if self._button then
        self._button:Destroy()
    end
end

return Comp
