-- 公共矿场：显示矿石与倒计时，入座后切换到钩爪第一人称操作。
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
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

--- 离座、重生或组件清理时还原进入矿场前的镜头设置。
function Comp:RestoreMiningCamera()
    local view = self._miningView
    if not view then
        return
    end
    self._miningView = nil
    view.Rig:Destroy()
    local camera = view.Camera
    if camera == workspace.CurrentCamera and camera.CameraType == Enum.CameraType.Scriptable then
        camera.CFrame, camera.Focus, camera.FieldOfView = view.CFrame, view.Focus, view.FieldOfView
        camera.CameraType = view.CameraType
    end
end

--- 从本人座椅看向矿盘，按当前视口摆放方块手。
--- @param deltaTime number 本帧经过的秒数。
function Comp:UpdateMiningCamera(deltaTime)
    local camera = workspace.CurrentCamera
    local character = self:GetPlayerCharacter()
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local seat = humanoid and humanoid.Health > 0 and humanoid.SeatPart
    if not camera or not seat or not seat:GetAttribute(Settings.SeatAttribute) then
        self:RestoreMiningCamera()
        return
    end
    local view = self._miningView
    if view and (view.Seat ~= seat or view.Camera ~= camera) then
        self:RestoreMiningCamera()
        view = nil
    end
    if not view then
        if camera.CameraType == Enum.CameraType.Scriptable then
            return
        end
        local ground = FXLoader:FindFromWorkspace(Settings.GroundPath)
        local entry = FXLoader:FindFromWorkspace(Settings.BeltPath .. ".BeltEntry")
        local head = character:FindFirstChild("Head")
        if not ground or not entry or not head then
            return
        end
        local center = Vector3.new(ground.Position.X, entry.Position.Y + Settings.ClawHeight, ground.Position.Z)
        local toCenter = Vector3.new(center.X - seat.Position.X, 0, center.Z - seat.Position.Z)
        local beltOffset = Vector2.new(entry.Position.X - center.X, entry.Position.Z - center.Z)
        local forward = toCenter.Unit
        local beltRadius = beltOffset.Magnitude
        view = {
            Seat = seat, Camera = camera, Center = center, Forward = forward,
            GrabRadius = beltRadius + Settings.ClawEdgeMargin,
            CFrame = camera.CFrame, Focus = camera.Focus, FieldOfView = camera.FieldOfView,
            CameraType = camera.CameraType,
        }
        self._miningView = view
        camera.CameraType = Enum.CameraType.Scriptable
        local eye = head.Position + forward * (head.Size.Z * 0.24)
        camera.FieldOfView = 68
        camera.CFrame = CFrame.lookAt(eye, eye + forward * 20 - Vector3.yAxis * 5.5) * ConsoleRig.CameraOffset
        camera.Focus = CFrame.new(center)
        view.Rig = ConsoleRig.New(camera, character)
    end
    local viewport = camera.ViewportSize
    if viewport.X <= 1 or viewport.Y <= 1 then
        return
    end
    view.Viewport = viewport
    view.Rig:Update(view.Steer or 0, os.clock() - self._lastClawRequest < 0.18, deltaTime)
end

--- 把鼠标或触屏位置落到水平抓取面，只有盘内点击才发送请求。
--- @param position Vector3 已计入界面 inset 的输入坐标。
function Comp:AimMiningClaw(position)
    local view = self._miningView
    local now = os.clock()
    if not view or not view.Viewport or view.Camera ~= workspace.CurrentCamera
        or now - self._lastClawRequest < Settings.RequestCooldown then
        return
    end
    local ray = view.Camera:ScreenPointToRay(position.X, position.Y)
    if ray.Direction.Y >= 0 then
        return
    end
    local point = ray.Origin + ray.Direction * ((view.Center.Y - ray.Origin.Y) / ray.Direction.Y)
    local offset = Vector2.new(point.X - view.Center.X, point.Z - view.Center.Z)
    if offset.Magnitude <= view.GrabRadius then
        view.Steer = math.clamp((point - view.Center):Dot(view.Forward:Cross(Vector3.yAxis)) / view.GrabRadius, -1, 1)
        self._lastClawRequest = now
        FX.Network:SendMsgToServer("C2S_CastMiningClaw", Vector2.new(point.X, point.Z))
    end
end

--- 初始化抓取输入、矿石表现和同服刷新提示。
function Comp:OnReady()
    self._effects = MiningEffects.New(self)
    self._countdown = FX.Loader:PlayerGui("Main.HUD.Wallet.RefreshStat.Countdown")
    self:CreateRefreshNotice()
    self._lastClawRequest = -math.huge
    self:TrackConnection(RunService.RenderStepped:Connect(function(deltaTime)
        self:UpdateMiningCamera(deltaTime)
        self._effects:UpdateBelt()
        self._effects:UpdateClaws()
    end))
    self:TrackConnection(UserInputService.InputBegan:Connect(function(input, processed)
        if not processed and (input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch) then
            self:AimMiningClaw(input.Position)
        end
    end))
    self:TrackConnection(FC.Localization.Changed:Connect(function()
        self._refreshNotice.Text = Text.Tr(TranslationTexts.Refreshed)
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
    if self._refreshTextEffect then
        self._refreshTextEffect:Destroy()
        self._refreshNotice:Destroy()
    end
end

return Comp
