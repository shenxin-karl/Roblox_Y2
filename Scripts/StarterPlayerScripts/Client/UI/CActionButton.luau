-- 人物右侧交互按钮：背景独立渐变，整组按主界面可用空间缩放。
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local FXLoader = _G.FX.Loader
local ActionButton = {}
local PopupNames = {"UpgradeWorkshopUI", "OfflineIncomeUI", "WelfareUI", "GMPanelUI", "AuraShopUI"}
local BUTTON_WIDTH, BUTTON_HEIGHT = 180, 60
local BUTTON_GAP, EDGE_PADDING = 8, 12
local worldLayer
local buttons = {}
local followConnection

--- 角色提示独占 HUD 层；点开弹窗时整组隐藏，避免透出或抢点击。
--- @return Frame 人物交互和装备说明共用的容器。
function ActionButton.GetWorldLayer()
    if not worldLayer then
        worldLayer = Instance.new("Frame")
        worldLayer.Name = "WorldInteractionLayer"
        worldLayer.BackgroundTransparency = 1
        worldLayer.Size = UDim2.fromScale(1, 1)
        worldLayer.Parent = FXLoader:PlayerGui("Main")
    end
    return worldLayer
end

--- 以人物投影为锚点，按主界面参考分辨率缩放按钮组，并把它限制在可用区域内。
local function Layout()
    local playerGui = worldLayer.Parent.Parent
    for index, name in ipairs(PopupNames) do
        local popup = playerGui:FindFirstChild(name)
        if popup and popup:IsA("ScreenGui") and popup.Enabled then
            worldLayer.Visible = false
            return
        end
    end
    worldLayer.Visible = true
    local size = worldLayer.AbsoluteSize
    local visibleCount = 0
    for index, button in ipairs(buttons) do
        if button.Visible then
            visibleCount += 1
        end
    end
    if visibleCount == 0 or size.X <= 0 or size.Y <= 0 then
        return
    end

    local groupHeight = visibleCount * BUTTON_HEIGHT + (visibleCount - 1) * BUTTON_GAP
    -- 小屏通常保留至少 45 个 UI 单位的点击高度；空间不足时优先容纳整组。
    local scale = math.clamp(math.min(size.X / 1280, size.Y / 720), 0.75, 1.25)
    scale = math.min(scale, size.X / (BUTTON_WIDTH + 2 * EDGE_PADDING), size.Y / (groupHeight + 2 * EDGE_PADDING))
    local padding = EDGE_PADDING * scale
    local origin = worldLayer.AbsolutePosition
    local camera = workspace.CurrentCamera
    local character = Players.LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local point, onScreen
    local rightPoint
    if camera and root then
        point, onScreen = camera:WorldToScreenPoint(root.Position)
        rightPoint = camera:WorldToScreenPoint(root.Position + camera.CFrame.RightVector * 2)
    end
    local offset = 0
    for index, button in ipairs(buttons) do
        if button.Visible then
            button.ResponsiveScale.Scale = scale
            if not onScreen then
                button.Position = UDim2.fromOffset(-1000, -1000)
            else
                local x = point.X + math.max(28 * scale, math.abs(rightPoint.X - point.X)) + 16 * scale - origin.X
                local y = math.clamp(point.Y - origin.Y - groupHeight * scale / 2,
                    padding, math.max(padding, size.Y - groupHeight * scale - padding)) + offset
                x = math.clamp(x, padding, math.max(padding, size.X - BUTTON_WIDTH * scale - padding))
                button.Position = UDim2.fromOffset(x, y)
            end
            offset += (BUTTON_HEIGHT + BUTTON_GAP) * scale
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
--- @return TextButton 点击入口。
--- @return TextLabel 主动作标题。
--- @return TextLabel 次要状态说明。
function ActionButton.New(name)
    local isGift = name == "GiftRawWeapon"
    local textWidth = isGift and 0.69 or 0.76
    local button = Instance.new("TextButton")
    button.Name = name
    button.Position = UDim2.fromOffset(-1000, -1000)
    button.Size = UDim2.fromOffset(BUTTON_WIDTH, BUTTON_HEIGHT)
    button.BackgroundColor3 = Color3.fromRGB(12, 57, 65)
    button.BorderSizePixel = 0
    button.Text = ""
    button.AutoButtonColor = false
    button.Visible = false
    Round(button)
    local scale = Instance.new("UIScale")
    scale.Name = "ResponsiveScale"
    scale.Parent = button

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
    title.Size = UDim2.fromScale(textWidth, 0.46)
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
    detail.Size = UDim2.fromScale(textWidth, 0.23)
    detail.Font = Enum.Font.GothamBold
    detail.TextColor3 = Color3.fromRGB(225, 255, 250)
    detail.TextStrokeTransparency = 1
    detail.TextOutline.Thickness = 1.2
    detail.UITextSizeConstraint.MaxTextSize = 16
    detail.Parent = button
    if isGift then
        local icon = Instance.new("ImageLabel")
        icon.Name = "GiftIcon"
        icon.AnchorPoint = Vector2.new(0.5, 0.5)
        icon.Position = UDim2.fromScale(0.875, 0.46)
        icon.Size = UDim2.fromOffset(28, 28)
        icon.BackgroundTransparency = 1
        icon.Image = "rbxassetid://107535063127657"
        icon.ZIndex = 2
        icon.Parent = button
    else
        local arrow = title:Clone()
        arrow.Name = "Arrow"
        arrow.Position = UDim2.fromScale(0.86, 0.22)
        arrow.Size = UDim2.fromScale(0.09, 0.46)
        arrow.Text = "›"
        arrow.Parent = button
    end

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
    button.Parent = ActionButton.GetWorldLayer()
    table.insert(buttons, button)
    if not followConnection then
        followConnection = RunService.RenderStepped:Connect(Layout)
    end
    button:GetPropertyChangedSignal("Visible"):Connect(Layout)
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
