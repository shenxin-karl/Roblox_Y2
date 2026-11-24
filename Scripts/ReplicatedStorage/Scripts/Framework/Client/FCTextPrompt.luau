-- 客户端通用提示文字与渐变效果；文案和显示条件由调用方提供。
local RunService = game:GetService("RunService")
local TextPrompt = {}
local AnimatedText = {}
AnimatedText.__index = AnimatedText

--- 以独立渐变控制文字颜色，调用方负责在移除文字前释放效果。
--- @param label TextLabel 由调用方管理内容、布局和显隐的文字节点。
--- @return table 可通过 Destroy 释放的文字特效。
function TextPrompt.AttachGradient(label)
    local self = setmetatable({}, AnimatedText)
    self._label = label
    self._originalColor = label.TextColor3
    label.TextColor3 = Color3.new(1, 1, 1)
    self._gradient = Instance.new("UIGradient")
    self._gradient.Name = "AnimatedTextGradient"
    self._gradient.Parent = label
    self:Update(0)
    local elapsed = 0
    local pending = 0
    --- 限制渐变重建频率，隐藏时跳过计算，恢复显示后沿用连续动画时间。
    --- @param deltaTime number 本帧经过的秒数。
    self._connection = RunService.RenderStepped:Connect(function(deltaTime)
        elapsed += deltaTime
        pending += deltaTime
        local gui = label:FindFirstAncestorWhichIsA("LayerCollector")
        if pending < 1 / 30 or not label.Visible or (gui and not gui.Enabled) then
            return
        end
        pending = 0
        self:Update(elapsed)
    end)
    return self
end

--- 在彩色渐变中插入移动的纯白峰值；扫光离开后留出停顿再重播。
--- @param elapsed number 特效已持续的秒数。
function AnimatedText:Update(elapsed)
    local center = (elapsed % 2.8) / 1.4 * 1.3 - 0.15
    local times = {0, 0.25, 0.5, 0.75, 1}
    for index, offset in ipairs({-0.09, 0, 0.09}) do
        local position = center + offset
        if position > 0 and position < 1 then
            table.insert(times, position)
        end
    end
    table.sort(times)
    local keypoints = {}
    local previous = -1
    for index, position in ipairs(times) do
        if position > previous then
            local color = Color3.fromHSV((elapsed / 8 + position * 0.35) % 1, 0.65, 1)
            local shine = math.max(0, 1 - math.abs(position - center) / 0.09)
            table.insert(keypoints, ColorSequenceKeypoint.new(position, color:Lerp(Color3.new(1, 1, 1), shine)))
            previous = position
        end
    end
    self._gradient.Color = ColorSequence.new(keypoints)
end

--- 断开动画并恢复原始文字颜色，不销毁调用方持有的文字节点。
function AnimatedText:Destroy()
    self._connection:Disconnect()
    self._gradient:Destroy()
    self._label.TextColor3 = self._originalColor
end

--- 创建已由调用方翻译的提示文字及黑色描边。
--- @param name string 文字节点名。
--- @param thickness number 描边厚度。
--- @param strokeName string? 指定描边节点名；省略时沿用默认名称。
--- @return TextLabel 还未挂载的文字节点。
local function CreateLabel(name, thickness, strokeName)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextWrapped = true
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.TextStrokeTransparency = 1
    label.AutoLocalize = false
    label.Text = ""
    local stroke = Instance.new("UIStroke")
    stroke.Name = strokeName or "UIStroke"
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
    stroke.Color = Color3.new(0, 0, 0)
    stroke.Thickness = thickness
    stroke.Parent = label
    return label
end

--- 创建底部提示；先放入原布局，允许调用方绑定已有文字适配。
--- @param parent GuiObject 提示使用的布局容器。
--- @return TextLabel 供文字适配和相邻提示测量的节点。
--- @return table 由调用方释放的渐变效果。
function TextPrompt.CreateReminder(parent)
    local label = CreateLabel("PurchaseReminder", 3, "TextOutline")
    label.AnchorPoint = Vector2.new(0.5, 1)
    label.Position = UDim2.fromScale(0.5, 1)
    label.Size = UDim2.fromScale(1, 1)
    label.TextYAlignment = Enum.TextYAlignment.Bottom
    label.TextSize = 28
    label.LineHeight = 1.35
    label.Visible = false
    label.Active = false
    label.Interactable = false
    label.Parent = parent
    return label, TextPrompt.AttachGradient(label)
end

--- 在富文本和整行渐变之间切换；传入 nil 隐藏提示。
--- @param label TextLabel 底部提示节点。
--- @param effect table 此节点的渐变效果。
--- @param text string? 调用方已处理的显示文案。
--- @param richText boolean 是否按富文本显示。
function TextPrompt.SetReminderText(label, effect, text, richText)
    label.RichText = richText
    effect._gradient.Enabled = not richText
    label.Text = text or ""
    label.Visible = text ~= nil
end

--- 把底部提示放到遮罩上方，同时继续跟随原容器的布局、缩放和显隐。
--- @param owner table 持有布局监听的客户端组件。
--- @param source ScreenGui 原界面。
--- @param group GuiObject 原布局容器。
--- @param responsiveScale UIScale 原布局的缩放节点。
--- @param label TextLabel 需要显示在遮罩上方的提示。
--- @return ScreenGui 由调用方在销毁时释放的提示层。
function TextPrompt.CreateReminderOverlay(owner, source, group, responsiveScale, label)
    local screen = Instance.new("ScreenGui")
    screen.Name = "MainReminderUI"
    screen.ResetOnSpawn = false
    screen.DisplayOrder = 101
    local layout = Instance.new("Frame")
    layout.BackgroundTransparency = 1
    layout.Parent = screen
    local scale = Instance.new("UIScale")
    scale.Parent = layout
    --- 沿用原界面的倍率，避免重复计算安全区或缩放。
    local function SyncLayout()
        layout.Position = group.Position
        layout.Size = group.Size
        layout.AnchorPoint = group.AnchorPoint
        layout.Visible = group.Visible
        scale.Scale = responsiveScale.Scale
        screen.Enabled = source.Enabled
        screen.ScreenInsets = source.ScreenInsets
    end
    for index, property in ipairs({"Position", "Size", "AnchorPoint", "Visible"}) do
        owner:TrackConnection(group:GetPropertyChangedSignal(property):Connect(SyncLayout))
    end
    for index, property in ipairs({"Enabled", "ScreenInsets"}) do
        owner:TrackConnection(source:GetPropertyChangedSignal(property):Connect(SyncLayout))
    end
    owner:TrackConnection(responsiveScale:GetPropertyChangedSignal("Scale"):Connect(SyncLayout))
    SyncLayout()
    screen.Parent = source.Parent
    label.Parent = layout
    return screen
end

--- 创建独立的顶部说明层；通用提示显示或淡出时为它让位。
--- @param owner table 持有布局监听的客户端组件。
--- @param playerGui PlayerGui 所属玩家的界面容器。
--- @param tips TextLabel 通用提示组件使用的模板节点，作为位置参照。
--- @return ScreenGui 由调用方在销毁时释放的提示层。
--- @return TextLabel 供调用方写入已翻译文案的节点。
function TextPrompt.CreateInstruction(owner, playerGui, tips)
    local screen = Instance.new("ScreenGui")
    screen.Name = "TutorialGuideUI"
    screen.ResetOnSpawn = false
    screen.DisplayOrder = 101
    local label = CreateLabel("Instruction", 2)
    label.AnchorPoint = Vector2.new(0.5, 0)
    label.Size = UDim2.fromOffset(1024, 48)
    label.TextSize = 32
    label.TextScaled = true
    label.TextColor3 = Color3.fromRGB(255, 223, 75)
    label.Parent = screen
    local textSizeConstraint = Instance.new("UITextSizeConstraint")
    textSizeConstraint.MinTextSize = 12
    textSizeConstraint.Parent = label
    local scale = Instance.new("UIScale")
    scale.Parent = label
    local tipsScreen = tips.Parent
    --- 沿用通用提示的安全区；只有可用视口较小时才降低字号上限，给长译文留出换行空间。
    local function UpdateLayout()
        screen.ScreenInsets = tipsScreen.ScreenInsets
        local size = screen.AbsoluteSize
        if size.X <= 0 or size.Y <= 0 then
            return
        end
        local layoutScale = math.min(size.X / 1280, size.Y / 720)
        textSizeConstraint.MaxTextSize = layoutScale < 0.6 and 16 or 32
        scale.Scale = layoutScale
        label.Size = UDim2.fromOffset(1024, math.max(48, 48 / layoutScale))
        local y = tips.Position.Y.Offset
        if tipsScreen.Enabled and tipsScreen:FindFirstChild("ActiveTip") then
            y += tips.Size.Y.Offset + 12 * layoutScale
        end
        label.Position = UDim2.new(0.5, 0, 0, y)
    end
    --- 通用提示显示或淡出完毕时调整说明的位置。
    --- @param child Instance 新增或移除的直属节点。
    local function OnTipChanged(child)
        if child.Name == "ActiveTip" then
            UpdateLayout()
        end
    end
    owner:TrackConnection(screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdateLayout))
    owner:TrackConnection(tipsScreen:GetPropertyChangedSignal("ScreenInsets"):Connect(UpdateLayout))
    owner:TrackConnection(tipsScreen:GetPropertyChangedSignal("Enabled"):Connect(UpdateLayout))
    owner:TrackConnection(tipsScreen.ChildAdded:Connect(OnTipChanged))
    owner:TrackConnection(tipsScreen.ChildRemoved:Connect(OnTipChanged))
    owner:TrackConnection(tips:GetPropertyChangedSignal("Position"):Connect(UpdateLayout))
    owner:TrackConnection(tips:GetPropertyChangedSignal("Size"):Connect(UpdateLayout))
    screen.Parent = playerGui
    UpdateLayout()
    return screen, label
end

return TextPrompt
