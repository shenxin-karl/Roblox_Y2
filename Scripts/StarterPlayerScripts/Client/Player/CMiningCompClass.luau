-- 公共矿场：显示矿石与倒计时，入座后用第一人称操作钩爪。
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local CLAW_KEYS = "MiningClawKeys"
local FX, FC = _G.FX, _G.FC
local FXLoader = FX.Loader
local Text = FX.Text
local Settings = FX.Loader:RequireShared("Scripts.Game.Shared.MiningSettings")
local MiningEffects = FX.Loader:RequireFromParent(script, "CMiningEffects")
local ConsoleRig = FX.Loader:RequireFromParent(script, "CMiningConsoleRig")
local UIRoot = FX.Loader:RequireShared("Scripts.Framework.Client.FCUIRoot")
local TextPrompt = FX.Loader:RequireShared("Scripts.Framework.Client.FCTextPrompt")
local TranslationTexts = Text.Define("MiningInteraction", {
    Preparing = "Preparing ore…",
    Refreshed = "Ore has refreshed!",
    Fire = "Fire",
    Keep = "Keep",
    Discard = "Discard",
    Leave = "Leave Seat",
})
local Comp = FX.Class("CMiningCompClass", "FCUICompClass")

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

--- 在主 HUD 下创建座椅操作按钮，隐藏时不拦截屏幕输入。
function Comp:CreateMiningControls()
    local panel = Instance.new("Frame")
    panel.Name = "MiningControls"
    panel.Size = UDim2.fromScale(1, 1)
    panel.BackgroundTransparency = 1
    panel.Visible = false
    panel.ZIndex = 8
    self._controls = panel
    self._heldArrows = {}

    --- 使用固定触摸尺寸，按钮位置随安全区宽度变化。
    --- @param name string 按钮节点名。
    --- @param caption string 按钮显示文字或方向符号。
    --- @param position UDim2 按钮中心位置。
    --- @param width number 按钮宽度。
    --- @param color Color3 按钮底色。
    --- @return TextButton 原生交互按钮。
    local function makeButton(name, caption, position, width, color)
        local button = Instance.new("TextButton")
        button.Name = name
        button.AnchorPoint = Vector2.new(0.5, 0.5)
        button.Position, button.Size = position, UDim2.fromOffset(width, 52)
        button.BackgroundColor3 = color
        button.Font = Enum.Font.GothamBold
        button.TextSize, button.TextColor3 = 24, Color3.new(1, 1, 1)
        button.AutoLocalize = false
        button.Text, button.ZIndex = caption, panel.ZIndex + 1
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 9)
        corner.Parent = button
        local stroke = Instance.new("UIStroke")
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Thickness, stroke.Parent = 2, button
        button.Parent = panel
        return button
    end

    --- 多根手指分别记录；同时按两个方向时停止转动。
    local function refreshSteer()
        local left, right = false, false
        for input, direction in pairs(self._heldArrows) do
            left = left or direction == -1
            right = right or direction == 1
        end
        self:SetMiningSteer((if right then 1 else 0) - (if left then 1 else 0))
    end
    self._handleClawKey = function(_, state, input)
        local key = input.KeyCode
        local view = self._miningView
        if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
            self._heldArrows[key] = nil
            refreshSteer()
        end
        if not view or UserInputService:GetFocusedTextBox() then
            return Enum.ContextActionResult.Pass
        end
        if state == Enum.UserInputState.Begin and not view.Claw:GetAttribute("PendingCatch") then
            if key == Enum.KeyCode.Space then
                self:FireMiningClaw()
            else
                self._heldArrows[key] = if key == Enum.KeyCode.A then -1 else 1
                refreshSteer()
            end
        end
        return Enum.ContextActionResult.Sink
    end
    self:TrackConnection(UserInputService.TextBoxFocused:Connect(function()
        self._heldArrows[Enum.KeyCode.A], self._heldArrows[Enum.KeyCode.D] = nil, nil
        refreshSteer()
    end))
    for direction = -1, 1, 2 do
        local left = direction == -1
        local button = makeButton(if left then "Left" else "Right", if left then "◀" else "▶",
            UDim2.new(0.22, direction * 34, 0.74, 0), 58, Color3.fromRGB(57, 93, 110))
        self:TrackConnection(button.InputBegan:Connect(function(input)
            if panel.Visible and (input.UserInputType == Enum.UserInputType.Touch
                or input.UserInputType == Enum.UserInputType.MouseButton1) then
                self._heldArrows[input] = direction
                refreshSteer()
            end
        end))
    end
    -- 在按钮外松手也要结束转向；另一根手指松开发射键不影响方向。
    self:TrackConnection(UserInputService.InputEnded:Connect(function(input)
        if self._heldArrows[input] then
            self._heldArrows[input] = nil
            refreshSteer()
        end
    end))
    self:TrackConnection(UserInputService.WindowFocusReleased:Connect(function()
        table.clear(self._heldArrows)
        refreshSteer()
    end))
    self._fireButton = makeButton("Fire", Text.Tr(TranslationTexts.Fire),
        UDim2.fromScale(0.82, 0.74), 90, Color3.fromRGB(42, 139, 64))
    self:TrackConnection(self._fireButton.Activated:Connect(function()
        self:FireMiningClaw()
    end))
    local leaveButton = makeButton("Leave", Text.Tr(TranslationTexts.Leave),
        UDim2.new(0.5, 0, 0.74, -62), 160, Color3.fromRGB(57, 93, 110))
    self:TrackConnection(leaveButton.Activated:Connect(function()
        local view = self._miningView
        local character = view and self:GetPlayerCharacter()
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health > 0 and humanoid.SeatPart == view.Seat then
            -- 空格仍用于发射；按钮通过原生跳跃离座，不传送角色。
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end))
    for _, name in ipairs({"Keep", "Discard"}) do
        local keep = name == "Keep"
        local button = makeButton(name, Text.Tr(TranslationTexts[name]),
            UDim2.new(0.5, if keep then -61 else 61, 0.74, 0), 112,
            if keep then Color3.fromRGB(42, 139, 64) else Color3.fromRGB(128, 68, 54))
        button.Visible = false
        self:TrackConnection(button.Activated:Connect(function()
            local view = self._miningView
            local catchId = view and view.Claw:GetAttribute("PendingCatch")
            if catchId then
                self._clawSound:PlayMiningClawSound(name)
                FX.Network:SendMsgToServer("C2S_ChooseMiningOre", catchId, keep)
            end
        end))
    end
    panel.Parent = FXLoader:PlayerGui("Main.HUD")
end

--- 离座、重生或组件清理时归还镜头和输入，并移除本人视模。
function Comp:RestoreMiningCamera()
    local view = self._miningView
    if not view then
        return
    end
    self._miningView = nil
    self._clawSound:StopMiningClawReel()
    ContextActionService:UnbindAction(CLAW_KEYS)
    self._controls.Visible = false
    table.clear(self._heldArrows)
    view.Rig:Destroy()
    view.Guide:Destroy()
    if view.Claw and view.Claw.Parent and not view.Claw:GetAttribute("ShotStarted") then
        view.Claw:PivotTo(view.Claw:GetAttribute("RestPose"))
    end
    local camera = view.Camera
    if camera == workspace.CurrentCamera and camera.CameraType == Enum.CameraType.Scriptable then
        camera.CFrame, camera.Focus, camera.FieldOfView = view.CFrame, view.Focus, view.FieldOfView
        camera.CameraType = view.CameraType
        UserInputService.MouseBehavior = view.MouseBehavior
    end
end

--- 座椅的左右键只转动钩头；轻点微调，长按连续调向。
--- @param direction number 当前方向；左 -1，松开 0，右 1。
function Comp:SetMiningSteer(direction)
    local view = self._miningView
    if not view or view.Steer == direction then
        return
    end
    view.Steer = direction
    view.Angle = math.clamp(view.Angle + direction * math.rad(1.5), -view.Limit, view.Limit)
end

--- 由座位朝向和摇杆角计算出爪直线，与矿带远侧相交的位置就是空爪折返点。
--- @param view table 当前操作台镜头状态。
--- @return Vector3 钩爪发射方向。
--- @return Vector3 钩爪最远终点。
local function GetShotLine(view)
    local direction = view.Forward * math.cos(view.Angle) + view.Right * math.sin(view.Angle)
    local toCenter = view.Center - view.Home
    local projection = direction:Dot(toCenter)
    local span = math.sqrt(math.max(0, view.Radius ^ 2 - (toCenter:Dot(toCenter) - projection ^ 2)))
    return direction, view.Home + direction * (projection + span)
end

--- 发射按钮只提交朝向对应的终点；矿石命中和回收由服务端判定。
function Comp:FireMiningClaw()
    local view = self._miningView
    local now = os.clock()
    if not view or not view.Claw or view.Claw:GetAttribute("ShotStarted")
        or now - self._lastClawRequest < Settings.RequestCooldown then
        return
    end
    local target = select(2, GetShotLine(view))
    self._lastClawRequest = now
    FX.Network:SendMsgToServer("C2S_CastMiningClaw", Vector2.new(target.X, target.Z))
end

--- 按本人钩爪的服务端状态配音；回程补抓同样只播一次夹中音。
--- @param view table 当前操作台镜头状态。
--- @param started number? 当前这抓的服务端开始时间。
--- @param pending boolean 钩爪是否已到站等待选择。
function Comp:UpdateMiningClawSound(view, started, pending)
    local sound = self._clawSound
    if not started or pending then
        if not started then
            view.SoundShot = nil
        end
        sound:StopMiningClawReel()
        return
    end
    local now = workspace:GetServerTimeNow()
    if started ~= view.SoundShot then
        sound:StopMiningClawReel()
        view.SoundShot = started
        view.SoundCaught = false
        -- 原版先播短咔哒声，两帧后再播出爪主音。
        view.CastSoundAt = now + 2 / 18
        sound:PlayMiningClawSound("CastClick")
    end
    if view.CastSoundAt and now >= view.CastSoundAt then
        view.CastSoundAt = nil
        sound:PlayMiningClawSound("Cast")
    end
    if not view.SoundCaught then
        local carried = view.Claw:FindFirstChild("CarriedRock")
        local rock = carried and carried.Value
        if rock then
            view.SoundCaught = true
            local grade = rock:GetAttribute("RockGrade")
            local cue = if grade == 1 then "CatchStone" elseif grade and grade >= 7 then "CatchRare" else "Catch"
            sound:PlayMiningClawSound(cue)
        end
    end
    local returnAt = view.Claw:GetAttribute("ShotReturnAt")
    if returnAt and now >= returnAt then
        sound:UpdateMiningClawReel(now, returnAt)
    end
end

--- 从本人座椅的眼高固定看向矿盘；镜头不跟手指或鼠标转动。
--- @param deltaTime number 本帧经过的秒数。
function Comp:UpdateMiningCamera(deltaTime)
    local camera = workspace.CurrentCamera
    local character = self:GetPlayerCharacter()
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local seat = humanoid and humanoid.Health > 0 and humanoid.SeatPart
    local view = self._miningView
    if view and (view.Seat ~= seat or view.Camera ~= camera or camera.CameraType ~= Enum.CameraType.Scriptable) then
        self:RestoreMiningCamera()
        return
    end
    if not camera or not seat or not seat:GetAttribute(Settings.SeatAttribute) then
        self:RestoreMiningCamera()
        return
    end
    if not view then
        if camera.CameraType == Enum.CameraType.Scriptable then
            return
        end
        local ground = FXLoader:FindFromWorkspace(Settings.GroundPath)
        local entry = FXLoader:FindFromWorkspace(Settings.BeltPath .. ".BeltEntry")
        local claw = seat:FindFirstChild("MiningClaw")
        local rest = claw and claw:GetAttribute("RestPose")
        if not ground or not entry or not rest or not claw.PrimaryPart then
            return
        end
        local home = rest.Position
        local center = Vector3.new(ground.Position.X, home.Y, ground.Position.Z)
        local forward = (center - home).Unit
        local radius = Vector2.new(entry.Position.X - center.X, entry.Position.Z - center.Z).Magnitude
        local head = character:FindFirstChild("Head")
        if not head then
            return
        end
        local eye = head.Position + forward * (head.Size.Z * 0.24)
        local guide = Instance.new("Part")
        guide.Name = "ClawAimLine"
        guide.Anchored, guide.CanCollide, guide.CanTouch, guide.CanQuery = true, false, false, false
        guide.CastShadow, guide.Material = false, Enum.Material.Neon
        guide.Color, guide.Transparency = Color3.fromRGB(255, 192, 64), 0.55
        local tip = guide:Clone()
        tip.Name = "RangeTip"
        tip.Shape = Enum.PartType.Ball
        tip.Size = Vector3.one * 0.8
        tip.Color = Color3.fromRGB(255, 232, 148)
        tip.Parent = guide
        guide.Parent = camera
        view = {
            Seat = seat, Camera = camera, CameraType = camera.CameraType, CFrame = camera.CFrame,
            Focus = camera.Focus, FieldOfView = camera.FieldOfView, MouseBehavior = UserInputService.MouseBehavior,
            Home = home, Center = center, Radius = radius, Forward = forward, Right = forward:Cross(Vector3.yAxis),
            BeltLimit = math.asin(math.min(1, radius / (center - home).Magnitude)) - math.rad(1),
            Limit = 0,
            Angle = 0, Steer = 0, Claw = claw, Guide = guide, GuideTip = tip,
        }
        self._miningView = view
        camera.CameraType = Enum.CameraType.Scriptable
        camera.FieldOfView = 68
        camera.CFrame = CFrame.lookAt(eye, eye + forward * 20 - Vector3.yAxis * 5.5) * ConsoleRig.CameraOffset
        camera.Focus = CFrame.new(center)
        view.Rig = ConsoleRig.New(camera, character)
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        self._controls.Visible = true
        ContextActionService:BindActionAtPriority(CLAW_KEYS, self._handleClawKey, false,
            Enum.ContextActionPriority.High.Value, Enum.KeyCode.A, Enum.KeyCode.D, Enum.KeyCode.Space)
    end
    if view.Claw.Parent ~= seat then
        self:RestoreMiningCamera()
        return
    end
    local pending = view.Claw:GetAttribute("PendingCatch") ~= nil
    local started = view.Claw:GetAttribute("ShotStarted")
    self:UpdateMiningClawSound(view, started, pending)
    if view.Pending ~= pending then
        view.Pending = pending
        self._controls.Keep.Visible, self._controls.Discard.Visible = pending, pending
        self._controls.Left.Visible, self._controls.Right.Visible, self._fireButton.Visible = not pending, not pending, not pending
        table.clear(self._heldArrows)
        view.Steer = 0
    end
    local viewport = camera.ViewportSize
    if viewport.X < 2 or viewport.Y < 2 then
        return
    end
    -- 竖屏也要看得见钩头的瞄准方向；横屏则可转至矿带切线附近。
    local halfFov = math.atan(math.tan(math.rad(camera.FieldOfView / 2)) * viewport.X / viewport.Y)
    view.Limit = math.min(view.BeltLimit, halfFov * 0.9)
    view.Angle = math.clamp(view.Angle + view.Steer * math.rad(33) * deltaTime, -view.Limit, view.Limit)
    local direction, target = GetShotLine(view)
    local firing = started ~= nil
    view.Guide.Transparency = if firing or pending then 1 else 0.55
    view.GuideTip.Transparency = if firing or pending then 1 else 0.1
    if not firing then
        local pose = CFrame.lookAt(view.Home, view.Home + direction)
        view.Claw:PivotTo(pose)
        -- 保留爪头前方的空隙，终点与实际空爪折返点对齐。
        local length = (target - view.Home).Magnitude - 3
        view.Guide.Size = Vector3.new(0.15, 0.07, length)
        view.Guide.CFrame = pose * CFrame.new(0, -0.35, -(3 + length / 2))
        view.GuideTip.Position = target - Vector3.yAxis * 0.35
    end
    view.Rig:Update(view.Angle / view.Limit, os.clock() - self._lastClawRequest < 0.18, deltaTime)
end

--- 初始化抓取输入、矿石表现和同服刷新提示。
function Comp:OnReady()
    self._clawSound = self:RequireComponent("CSoundComp")
    self._effects = MiningEffects.New(self)
    self._countdown = FX.Loader:PlayerGui("Main.HUD.Wallet.RefreshStat.Countdown")
    self:CreateRefreshNotice()
    self:CreateMiningControls()
    self._lastClawRequest = -math.huge
    self:TrackConnection(RunService.RenderStepped:Connect(function(deltaTime)
        self._effects:UpdateBelt()
        self._effects:UpdateClaws()
        self:UpdateMiningCamera(deltaTime)
    end))
    self:TrackConnection(FC.Localization.Changed:Connect(function()
        self._refreshNotice.Text = Text.Tr(TranslationTexts.Refreshed)
        self._fireButton.Text = Text.Tr(TranslationTexts.Fire)
        self._controls.Keep.Text = Text.Tr(TranslationTexts.Keep)
        self._controls.Discard.Text = Text.Tr(TranslationTexts.Discard)
        self._controls.Leave.Text = Text.Tr(TranslationTexts.Leave)
        self:Refresh()
    end))
    local elapsed = 0
    --- 限制倒计时刷新频率；矿石外观仍按帧跟随。
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

--- 刷新公共倒计时和换批提示，并保持背包道具名称本地化。
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
    self:RefreshToolNames()
end

--- 还原镜头，并清理矿场提示、特效及监听。
function Comp:Dtor()
    self:RestoreMiningCamera()
    if self._effects then
        self._effects:Destroy()
    end
    Comp.Super.Dtor(self)
    if self._controls then
        self._controls:Destroy()
    end
    if self._refreshTextEffect then
        self._refreshTextEffect:Destroy()
        self._refreshNotice:Destroy()
    end
end

return Comp
