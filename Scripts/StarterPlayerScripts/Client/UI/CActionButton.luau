-- 人物右侧交互按钮：背景独立渐变，标题与说明保持原色，复用框架悬停缩放。
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ActionButton = {}
local buttons = {}
local followConnection

--- 以人物的屏幕投影为锚点，动作纵向排列在人物右侧并限制在屏幕内。
local function Layout()
    local camera = workspace.CurrentCamera
    local character = Players.LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local totalHeight = 0
    for index, button in ipairs(buttons) do
        if button.Visible then
            totalHeight += button.AbsoluteSize.Y + 8
        end
    end
    local point, onScreen
    local rightPoint
    if camera and root then
        point, onScreen = camera:WorldToScreenPoint(root.Position)
        rightPoint = camera:WorldToScreenPoint(root.Position + camera.CFrame.RightVector * 2)
    end
    local offset = 0
    for index, button in ipairs(buttons) do
        if button.Visible then
            if not onScreen then
                button.Position = UDim2.fromOffset(-1000, -1000)
            else
                local parent = button.Parent
                local size = button.AbsoluteSize
                local origin = parent.AbsolutePosition
                local x = point.X + math.max(28, math.abs(rightPoint.X - point.X)) + 16 - origin.X
                local groupHeight = totalHeight - 8
                local y = math.clamp(point.Y - origin.Y - groupHeight / 2,
                    12, math.max(12, parent.AbsoluteSize.Y - groupHeight - 12)) + offset
                x = math.clamp(x, 12, math.max(12, parent.AbsoluteSize.X - size.X - 12))
                button.Position = UDim2.fromOffset(x, y)
            end
            offset += button.AbsoluteSize.Y + 8
        end
    end
end

--- 紧凑按钮使用适中的圆角，保持清晰的动作区域。
--- @param node GuiObject 需要圆角的节点。
local function Round(node)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 14)
    corner.Parent = node
end

--- 创建人物右侧的紧凑交互入口；业务方只更新标题、说明和可见性。
--- @param name string 稳定节点名称。
--- @param parent Instance 所属界面容器。
--- @return TextButton 点击入口。
--- @return TextLabel 主动作标题。
--- @return TextLabel 次要状态说明。
function ActionButton.New(name, parent)
    local button = Instance.new("TextButton")
    button.Name = name
    button.Position = UDim2.fromOffset(-1000, -1000)
    button.Size = UDim2.fromScale(0.14, 0.085)
    button.BackgroundColor3 = Color3.fromRGB(12, 57, 65)
    button.BorderSizePixel = 0
    button.Text = ""
    button.AutoButtonColor = false
    button.Visible = false
    Round(button)
    local bounds = Instance.new("UISizeConstraint")
    bounds.MinSize = Vector2.new(172, 58)
    bounds.MaxSize = Vector2.new(240, 72)
    bounds.Parent = button

    local face = Instance.new("Frame")
    face.Name = "Face"
    face.Size = UDim2.new(1, 0, 1, -4)
    face.BackgroundColor3 = Color3.new(1, 1, 1)
    face.BorderSizePixel = 0
    face.Parent = button
    Round(face)
    local gradient = Instance.new("UIGradient")
    gradient.Rotation = 90
    gradient.Color = ColorSequence.new(Color3.fromRGB(64, 211, 199), Color3.fromRGB(22, 153, 170))
    gradient.Parent = face
    local border = Instance.new("UIStroke")
    border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    border.Color = Color3.fromRGB(181, 255, 241)
    border.Thickness = 1.5
    border.Parent = face

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Position = UDim2.fromScale(0.08, 0.1)
    title.Size = UDim2.fromScale(0.76, 0.46)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.FredokaOne
    title.TextColor3 = Color3.new(1, 1, 1)
    title.TextStrokeTransparency = 1
    title.TextScaled = true
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.AutoLocalize = false
    title.Text = ""
    title.ZIndex = 2
    title.Parent = button
    local titleSize = Instance.new("UITextSizeConstraint")
    titleSize.MaxTextSize = 28
    titleSize.Parent = title
    local textOutline = Instance.new("UIStroke")
    textOutline.Name = "TextOutline"
    textOutline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
    textOutline.Color = Color3.new(0, 0, 0)
    textOutline.Thickness = 1.8
    textOutline.Parent = title

    local detail = title:Clone()
    detail.Name = "Detail"
    detail.Position = UDim2.fromScale(0.08, 0.59)
    detail.Size = UDim2.fromScale(0.76, 0.23)
    detail.Font = Enum.Font.GothamBold
    detail.TextColor3 = Color3.fromRGB(225, 255, 250)
    detail.TextStrokeTransparency = 1
    detail.TextOutline.Thickness = 1.2
    detail.UITextSizeConstraint.MaxTextSize = 16
    detail.Parent = button
    local arrow = title:Clone()
    arrow.Name = "Arrow"
    arrow.Position = UDim2.fromScale(0.86, 0.22)
    arrow.Size = UDim2.fromScale(0.09, 0.46)
    arrow.Text = "›"
    arrow.Parent = button

    --- 松开、移出或隐藏时复位，避免按钮留下按下状态。
    local function Release()
        face.Position = UDim2.fromOffset(0, 0)
    end
    button.MouseButton1Down:Connect(function()
        face.Position = UDim2.fromOffset(0, 3)
    end)
    button.MouseButton1Up:Connect(Release)
    button.MouseLeave:Connect(Release)
    button:GetPropertyChangedSignal("Visible"):Connect(Release)
    button.Parent = parent
    table.insert(buttons, button)
    if not followConnection then
        followConnection = RunService.RenderStepped:Connect(Layout)
    end
    button:GetPropertyChangedSignal("Visible"):Connect(Layout)
    button:GetPropertyChangedSignal("AbsoluteSize"):Connect(Layout)
    button.Destroying:Connect(function()
        table.remove(buttons, table.find(buttons, button))
        if #buttons == 0 then
            followConnection:Disconnect()
            followConnection = nil
        end
        Layout()
    end)
    return button, title, detail
end

return ActionButton
