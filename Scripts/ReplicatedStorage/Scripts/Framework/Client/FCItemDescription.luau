-- 框架道具说明面板：按需创建，复用框架通用画布，不读取项目节点、配置或装备状态。
local TextService = game:GetService("TextService")
local FCUIRoot = require(script.Parent:WaitForChild("FCUIRoot"))
local FCItemDescription = {}
FCItemDescription.__index = FCItemDescription

--- 创建本实例拥有的界面节点，先设置属性再挂载。
--- @param className string Roblox 实例类型。
--- @param parent Instance 父节点。
--- @param properties table 初始属性。
--- @return Instance 创建的界面节点。
local function Node(className, parent, properties)
    local node = Instance.new(className)
    for key, value in pairs(properties) do
        node[key] = value
    end
    node.Parent = parent
    return node
end

--- 在共享画布内创建独立面板；Root 是调用方可定位或标记的自有 Frame。
--- @return table 道具说明实例，由调用方负责 Destroy。
function FCItemDescription.New()
    local self = setmetatable({}, FCItemDescription)
    self._screen = FCUIRoot.Get()
    self.Root = Node("Frame", self._screen, {
        Name = "ItemDescription", AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.fromScale(0.5, 0.18),
        Size = UDim2.fromOffset(220, 72),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, ZIndex = 0,
    })
    Node("UICorner", self.Root, {CornerRadius = UDim.new(0, 12)})
    Node("UIStroke", self.Root, {
        Name = "OuterOutline", ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Color = Color3.fromRGB(23, 17, 12), Thickness = 3,
    })
    local smoke = Node("Frame", self.Root, {
        Name = "Smoke", Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(48, 38, 30), BackgroundTransparency = 0.22,
        BorderSizePixel = 0, ZIndex = 1,
    })
    Node("UICorner", smoke, {CornerRadius = UDim.new(0, 12)})
    Node("UIStroke", smoke, {
        Name = "CardBorder", ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Color = Color3.fromRGB(209, 182, 130), Thickness = 2, Transparency = 0.18,
    })
    local glow = Node("Frame", smoke, {
        Name = "WarmMist", Position = UDim2.fromScale(0, 0.04), Size = UDim2.fromScale(1, 0.44),
        BackgroundColor3 = Color3.fromRGB(144, 109, 66), BackgroundTransparency = 0.8,
        BorderSizePixel = 0,
    })
    Node("UICorner", glow, {CornerRadius = UDim.new(0, 12)})
    Node("UIGradient", glow, {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0.2),
            NumberSequenceKeypoint.new(0.65, 0.2), NumberSequenceKeypoint.new(1, 1),
        }),
    })
    self._icon = Node("ImageLabel", self.Root, {
        Name = "Icon", Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(48, 48),
        BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Image = "", ZIndex = 2,
    })
    self._content = Node("Frame", self.Root, {
        Name = "Content", Position = UDim2.fromOffset(72, 10), Size = UDim2.new(1, -88, 0, 0),
        BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 2,
    })
    Node("UIPadding", self._content, {PaddingBottom = UDim.new(0, 12)})
    -- 标题和描述按实际换行高度向下排列，保持大字号而不互相遮挡。
    Node("UIListLayout", self._content, {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder})
    self._title = Node("TextLabel", self._content, {
        Name = "Title", Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 1,
        BackgroundTransparency = 1, AutoLocalize = false, Font = Enum.Font.GothamBlack,
        TextSize = 26, TextColor3 = Color3.fromRGB(255, 243, 215), TextXAlignment = Enum.TextXAlignment.Left,
        TextScaled = false, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Text = "", ZIndex = 2,
    })
    self._description = Node("TextLabel", self._content, {
        Name = "Description", Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 2,
        BackgroundTransparency = 1, AutoLocalize = false, Font = Enum.Font.GothamBold,
        TextSize = 22, TextColor3 = Color3.fromRGB(250, 247, 237),
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true, TextScaled = false, AutomaticSize = Enum.AutomaticSize.Y, Text = "", ZIndex = 2,
    })
    for index, label in ipairs({self._title, self._description}) do
        Node("UIStroke", label, {
            ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
            Color = Color3.fromRGB(23, 17, 12), Transparency = 0,
            Thickness = label == self._title and 2 or 1.5,
        })
    end
    self._resizeConnection = self._screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        self:_Layout()
    end)
    return self
end

--- 按文字自然宽度和屏幕可用宽度布局，长文字由文本节点自动换行撑高。
function FCItemDescription:_Layout()
    local left = self._icon.Visible and 72 or 16
    local titleSize = TextService:GetTextSize(self._title.Text, self._title.TextSize, self._title.Font, Vector2.new(10000, 10000))
    local descriptionSize = TextService:GetTextSize(self._description.Text, self._description.TextSize, self._description.Font, Vector2.new(10000, 10000))
    local width = math.min(math.clamp(math.ceil(math.max(titleSize.X, descriptionSize.X)) + left + 22, 220, 420),
        math.max(1, self._screen.AbsoluteSize.X - 32))
    self.Root.Size = UDim2.fromOffset(width, 72)
    self._content.Position = UDim2.fromOffset(left, 10)
    self._content.Size = UDim2.new(1, -left - 16, 0, 0)
end

--- 展示调用方准备好的内容，不读取 Tool、配置或执行二次翻译。
--- @param data table 已翻译的 Title、Description 字符串，以及 Icon URI；Icon 为空字符串时隐藏图标。
function FCItemDescription:Show(data)
    self._title.Text = data.Title
    self._description.Text = data.Description
    self._icon.Image = data.Icon
    self._icon.Visible = data.Icon ~= ""
    self:_Layout()
    self.Root.Visible = true
end

--- 隐藏面板并保留节点，供后续内容复用。
function FCItemDescription:Hide()
    self.Root.Visible = false
end

--- 释放本实例的屏幕监听和面板，保留其他框架 UI 共用的 ScreenGui。
function FCItemDescription:Destroy()
    self._resizeConnection:Disconnect()
    self.Root:Destroy()
end

return FCItemDescription
