-- 框架自定义交互提示：沿用原生交互，仅接管标记 CustomPickup 的提示外观。
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local PickupPrompt = {}
local promptShownConnection

--- 创建圆角，保持提示框与进度条的统一轮廓。
--- @param parent Instance 所属界面节点。
--- @param radius number 圆角像素。
local function AddCorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = parent
end

--- 创建描边，在场景背景上保持提示可读。
--- @param parent Instance 所属界面节点。
local function AddStroke(parent)
    local stroke = Instance.new("UIStroke")
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Color = Color3.fromRGB(235, 240, 245)
    stroke.Thickness = 2
    stroke.Parent = parent
end

--- 为当前可交互拾取创建临时界面，退出范围时释放全部订阅。
--- @param prompt ProximityPrompt 原生拾取提示。
--- @param inputType Enum.ProximityPromptInputType 当前输入方式。
local function ShowPrompt(prompt, inputType)
    if prompt.Style ~= Enum.ProximityPromptStyle.Custom or prompt:GetAttribute("CustomPickup") ~= true then
        return
    end
    local gui = Instance.new("BillboardGui")
    gui.Name = "PickupPrompt"
    gui.Adornee = prompt.Parent
    gui.Size = UDim2.fromOffset(190, 62)
    gui.StudsOffsetWorldSpace = Vector3.new(0, -0.8, 0)
    gui.AlwaysOnTop = true
    gui.ResetOnSpawn = false
    gui.Active = true

    local canvas = Instance.new("Frame")
    canvas.Name = "Canvas"
    canvas.Size = UDim2.fromOffset(190, 62)
    canvas.BackgroundTransparency = 1
    canvas.Parent = gui
    local uiScale = Instance.new("UIScale")
    uiScale.Parent = canvas

    local button = Instance.new("TextButton")
    button.Name = "Panel"
    button.Size = UDim2.fromOffset(180, 54)
    button.Position = UDim2.fromOffset(5, 4)
    button.BackgroundColor3 = Color3.fromRGB(14, 23, 29)
    button.BackgroundTransparency = 0.18
    button.AutoButtonColor = false
    button.AutoLocalize = false
    button.Text = ""
    button.Parent = canvas
    AddCorner(button, 10)
    AddStroke(button)

    local key = Instance.new("TextLabel")
    key.Name = "Key"
    key.Position = UDim2.fromOffset(10, 7)
    key.Size = UDim2.fromOffset(36, 32)
    key.BackgroundColor3 = Color3.fromRGB(15, 18, 23)
    key.AutoLocalize = false
    key.TextColor3 = Color3.new(1, 1, 1)
    key.Font = Enum.Font.GothamMedium
    key.TextSize = 20
    if inputType == Enum.ProximityPromptInputType.Touch then
        key.Text = "☝"
    elseif inputType == Enum.ProximityPromptInputType.Gamepad then
        key.Text = UserInputService:GetStringForKeyCode(prompt.GamepadKeyCode)
        if key.Text == "" then
            key.Text = prompt.GamepadKeyCode.Name:gsub("Button", "")
        end
    else
        key.Text = UserInputService:GetStringForKeyCode(prompt.KeyboardKeyCode)
        if key.Text == "" then
            key.Text = prompt.KeyboardKeyCode.Name
        end
    end
    key.Parent = button
    AddCorner(key, 7)
    AddStroke(key)

    local action = Instance.new("TextLabel")
    action.Name = "Action"
    action.Position = UDim2.fromOffset(57, 6)
    action.Size = UDim2.fromOffset(113, 34)
    action.BackgroundTransparency = 1
    action.AutoLocalize = false
    action.TextColor3 = Color3.fromRGB(70, 255, 58)
    action.Font = Enum.Font.GothamBold
    action.TextSize = 22
    action.TextScaled = true
    action.TextXAlignment = Enum.TextXAlignment.Left
    action.Text = prompt.ActionText
    action.Parent = button
    local textSize = Instance.new("UITextSizeConstraint")
    textSize.MaxTextSize = 22
    textSize.Parent = action

    local track = Instance.new("Frame")
    track.Name = "ProgressTrack"
    track.Position = UDim2.fromOffset(10, 44)
    track.Size = UDim2.fromOffset(160, 4)
    track.BackgroundColor3 = Color3.fromRGB(80, 96, 100)
    track.BorderSizePixel = 0
    track.Visible = prompt.HoldDuration > 0
    track.Parent = button
    AddCorner(track, 2)
    local fill = Instance.new("Frame")
    fill.Name = "Progress"
    fill.Size = UDim2.fromScale(0, 1)
    fill.BackgroundColor3 = Color3.fromRGB(70, 255, 58)
    fill.BorderSizePixel = 0
    fill.Parent = track
    AddCorner(fill, 2)

    local connections = {}
    local tween
    local pointerInput
    local cleaned = false
    local viewportConnection
    --- 以屏幕短边适配横竖屏，限制缩放以保留手机点击面积和桌面可读性。
    local function UpdateScale()
        local camera = workspace.CurrentCamera
        if not camera then
            return
        end
        local viewport = camera.ViewportSize
        if viewport.X <= 0 or viewport.Y <= 0 then
            return
        end
        local scale = math.clamp(math.min(viewport.X, viewport.Y) / 720, 0.85, 1.3)
        scale = math.min(scale, viewport.X / 190)
        uiScale.Scale = scale
        gui.Size = UDim2.fromOffset(190 * scale, 62 * scale)
    end
    --- 相机切换后重新监听尺寸，避免重生或设备旋转遗留旧订阅。
    local function BindViewport()
        if viewportConnection then
            viewportConnection:Disconnect()
            viewportConnection = nil
        end
        local camera = workspace.CurrentCamera
        if camera then
            viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(UpdateScale)
        end
        UpdateScale()
    end
    --- 松开或失去交互资格时立即清空进度。
    local function ResetProgress()
        if tween then
            tween:Cancel()
            tween = nil
        end
        fill.Size = UDim2.fromScale(0, 1)
    end
    --- 鼠标和触屏复用引擎的长按输入，不直接触发领奖。
    local function ReleasePointer()
        if pointerInput then
            pointerInput = nil
            prompt:InputHoldEnd()
        end
    end
    --- 只记录按下拾取按钮的手指，摇杆或镜头触点松开不打断拾取。
    --- @param input InputObject 本次按钮输入。
    local function BeginPointer(input)
        if not pointerInput and (input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch) then
            pointerInput = input
            prompt:InputHoldBegin()
        end
    end
    --- 提示隐藏、删除或角色重生时释放本次展示。
    local function Cleanup()
        if cleaned then
            return
        end
        cleaned = true
        if viewportConnection then
            viewportConnection:Disconnect()
        end
        for connectionIndex, connection in ipairs(connections) do
            connection:Disconnect()
        end
        ResetProgress()
        ReleasePointer()
        gui:Destroy()
    end
    table.insert(connections, prompt.PromptButtonHoldBegan:Connect(function()
        ResetProgress()
        tween = TweenService:Create(fill, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), {
            Size = UDim2.fromScale(1, 1),
        })
        tween:Play()
    end))
    table.insert(connections, prompt.PromptButtonHoldEnded:Connect(ResetProgress))
    table.insert(connections, prompt.Triggered:Connect(ResetProgress))
    table.insert(connections, prompt.PromptHidden:Connect(Cleanup))
    table.insert(connections, prompt.Destroying:Connect(Cleanup))
    table.insert(connections, Players.LocalPlayer.CharacterRemoving:Connect(Cleanup))
    table.insert(connections, prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
        action.Text = prompt.ActionText
    end))
    table.insert(connections, button.InputBegan:Connect(BeginPointer))
    table.insert(connections, UserInputService.InputEnded:Connect(function(input)
        if input == pointerInput then
            ReleasePointer()
        end
    end))
    table.insert(connections, UserInputService.WindowFocusReleased:Connect(ReleasePointer))
    table.insert(connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(BindViewport))
    BindViewport()
    gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

--- 客户端入口仅注册一次，全局监听由引擎管理的拾取可见性。
function PickupPrompt.Init()
    if promptShownConnection then
        return
    end
    promptShownConnection = ProximityPromptService.PromptShown:Connect(ShowPrompt)
end

return PickupPrompt
