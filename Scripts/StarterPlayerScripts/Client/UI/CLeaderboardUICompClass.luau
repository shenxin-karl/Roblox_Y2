-- 月榜显示层：在 PlayerGui 创建 SurfaceGui，场景榜板只作为显示面引用。
local FX, FC = _G.FX, _G.FC
local Text = FX.Text
local FXLoader = FX.Loader
local GameUtility = FXLoader:RequireShared("Scripts.Game.Shared.GameUtility")
local RankingDataConfig = _G.Provider:GetRankingEnum()
local Component = FX.Class("CLeaderboardUICompClass", "FCUICompClass")

local TranslationTexts = Text.Define("MonthlyLeaderboard", {
    Income = "Monthly Income per Second",
    Playtime = "Monthly Playtime",
    Rank = "Rank",
    Player = "Player",
    Score = "Score",
    You = "You",
    IncomeValue = "${value}/s",
    Duration = "{days:int}d {hours:int}h {minutes:int}m",
    ShortDuration = "{minutes:int}m {seconds:int}s",
    Loading = "Loading...",
    Empty = "No rankings yet.",
    Unavailable = "Leaderboard unavailable.",
})
local Panels = {
    {Path = "BlockMeshs.Leaderboard01.橙木空白排行榜.空白深色面板", Title = TranslationTexts.Income,
        Color = Color3.fromRGB(255, 194, 46)},
    {Path = "BlockMeshs.Leaderboard02.橙木空白排行榜.空白深色面板", Title = TranslationTexts.Playtime,
        Color = Color3.fromRGB(110, 235, 245)},
}

--- 收益沿用项目的数值缩写；在线时长保留短会话的秒数。
--- @param kind number 榜单配置索引。
--- @param score number 原始榜单分数。
--- @return string 本地化后的显示值。
local function FormatScore(kind, score)
    if score == nil then
        return "—"
    end
    if RankingDataConfig[kind].Name == "IncomeRate" then
        return Text.Tr(TranslationTexts.IncomeValue, {value = GameUtility.NumberToText(score)})
    end
    if score < 3600 then
        return Text.Tr(TranslationTexts.ShortDuration, {minutes = math.floor(score / 60), seconds = score % 60})
    end
    return Text.Tr(TranslationTexts.Duration, {
        days = math.floor(score / 86400), hours = math.floor(score / 3600) % 24,
        minutes = math.floor(score / 60) % 60,
    })
end

--- 创建只归本组件所有的节点，先设置属性再加入父级。
--- @param className string Roblox 原生实例类型。
--- @param parent Instance 节点的父级。
--- @param properties table 需要设置的实例属性。
--- @return Instance 新建节点。
local function Create(className, parent, properties)
    local node = Instance.new(className)
    for key, value in pairs(properties) do
        node[key] = value
    end
    node.Parent = parent
    return node
end

--- 榜板文字由组件翻译，避免自动翻译玩家名和已本地化的文案。
--- @param parent Instance 文字所属节点。
--- @param position UDim2 文字在父级中的位置。
--- @param size UDim2 文字占用尺寸。
--- @param color Color3 文字颜色。
--- @param textSize number 最大字号。
--- @return TextLabel 新建文字节点。
local function Label(parent, position, size, color, textSize)
    local label = Create("TextLabel", parent, {
        AutoLocalize = false, Text = "", BackgroundTransparency = 1,
        Position = position, Size = size, Font = Enum.Font.FredokaOne,
        TextColor3 = color, TextScaled = true, TextTruncate = Enum.TextTruncate.AtEnd,
    })
    Create("UITextSizeConstraint", label, {MinTextSize = 18, MaxTextSize = textSize})
    return label
end

--- 使用相同的列布局展示榜头、普通条目和固定个人行。
--- @param parent Instance 列表或榜板背景。
--- @param position UDim2 行位置。
--- @param order number 用于列表排序的行号。
--- @param background Color3 行背景。
--- @param color Color3 行文字颜色。
--- @return table 行容器和名次、玩家、分数列。
local function CreateRow(parent, position, order, background, color)
    local frame = Create("Frame", parent, {
        Position = position, Size = UDim2.new(1, 0, 0, 78), LayoutOrder = order,
        BackgroundColor3 = background, BorderSizePixel = 0,
    })
    return {
        Frame = frame,
        Rank = Label(frame, UDim2.fromScale(0.02, 0), UDim2.fromScale(0.15, 1), color, 36),
        Player = Label(frame, UDim2.fromScale(0.18, 0), UDim2.fromScale(0.45, 1), color, 38),
        Score = Label(frame, UDim2.fromScale(0.64, 0), UDim2.fromScale(0.34, 1), color, 36),
    }
end

--- 两块板共用一份布局；挂在 PlayerGui 才能让场景榜板上的列表接收输入。
--- @param kind number 榜单配置索引。
--- @param panel BasePart 已复制到客户端的场景显示面。
--- @return table 展示节点和榜单缓存。
function Component:CreateBoard(kind, panel)
    local style = Panels[kind]
    local gui = Create("SurfaceGui", self._playerGui, {
        Name = RankingDataConfig[kind].Name, Adornee = panel, Face = Enum.NormalId.Back,
        SizingMode = Enum.SurfaceGuiSizingMode.FixedSize, CanvasSize = Vector2.new(720, 912),
        LightInfluence = 0, MaxDistance = 180, ZOffset = 0.02, Active = true, ResetOnSpawn = false,
    })
    local root = Create("Frame", gui, {
        Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(39, 27, 27), BorderSizePixel = 0,
    })
    local body = Create("Frame", root, {
        BackgroundTransparency = 1, Position = UDim2.fromScale(0.04, 0), Size = UDim2.fromScale(0.92, 1),
    })
    local list = Create("ScrollingFrame", body, {
        Position = UDim2.fromOffset(0, 174), Size = UDim2.new(1, 0, 0, 620),
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 10,
        VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar, Active = true,
        BackgroundTransparency = 1, BorderSizePixel = 0,
    })
    Create("UIListLayout", list, {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4)})
    return {
        Gui = gui, Panel = panel, List = list, Rows = {}, NextRefresh = 0,
        Title = Label(body, UDim2.fromOffset(0, 10), UDim2.new(1, 0, 0, 76), style.Color, 54),
        Status = Label(body, UDim2.fromOffset(0, 174), UDim2.new(1, 0, 0, 78), style.Color, 34),
        Header = CreateRow(body, UDim2.fromOffset(0, 90), 0, Color3.fromRGB(68, 45, 38), style.Color),
        Personal = CreateRow(body, UDim2.fromOffset(0, 810), 0, style.Color, Color3.fromRGB(43, 28, 18)),
    }
end

--- 根据真实榜单刷新现有行；复用行节点，刷新时保留玩家的滚动位置。
--- @param kind number 榜单配置索引。
--- @param board table 本地榜板节点和缓存。
function Component:Render(kind, board)
    local data = board.Data
    local rows = data and data.itemData or {}
    local failure = board.Requested and TranslationTexts.Unavailable or TranslationTexts.Loading
    board.Title.Text = Text.Tr(Panels[kind].Title)
    board.Header.Rank.Text = Text.Tr(TranslationTexts.Rank)
    board.Header.Player.Text = Text.Tr(TranslationTexts.Player)
    board.Header.Score.Text = Text.Tr(TranslationTexts.Score)
    board.Status.Visible = #rows == 0
    board.Status.Text = Text.Tr(data and TranslationTexts.Empty or failure)
    board.Personal.Rank.Text = data and data.myNo and tostring(data.myNo) or "—"
    board.Personal.Player.Text = Text.Tr(TranslationTexts.You)
    board.Personal.Score.Text = FormatScore(kind, data and data.myScore)

    for index, entry in ipairs(rows) do
        local row = board.Rows[index]
        if not row then
            local color = index % 2 == 0 and Color3.fromRGB(48, 33, 31) or Color3.fromRGB(59, 41, 37)
            row = CreateRow(board.List, UDim2.new(), index, color, Panels[kind].Color)
            board.Rows[index] = row
        end
        row.Frame.Visible = true
        row.Rank.Text = tostring(entry.rankNo)
        row.Player.Text = entry.playerName
        row.Score.Text = FormatScore(kind, entry.rankScore)
    end
    for index = #rows + 1, #board.Rows do
        board.Rows[index].Frame.Visible = false
    end
end

--- @return string 玩家内的榜板组件名。
function Component:GetCompName()
    return "CLeaderboardUIComp"
end

--- 榜板可能随场景流送进出；只为当前存在的面板挂载界面及定时拉取全服榜。
function Component:OnReady()
    self._playerGui = FXLoader:Here(self:GetPlayerNode(), "PlayerGui", math.huge)
    self._boards = {}
    self:TrackConnection(FC.Localization.Changed:Connect(function()
        for kind, board in pairs(self._boards) do
            self:Render(kind, board)
        end
    end))
    self._refreshTask = task.defer(function()
        while true do
            for kind, style in ipairs(Panels) do
                local panel = FXLoader:Find(workspace, style.Path)
                local board = self._boards[kind]
                if board and board.Panel ~= panel then
                    board.Gui:Destroy()
                    self._boards[kind], board = nil, nil
                end
                if panel and not board then
                    board = self:CreateBoard(kind, panel)
                    self._boards[kind] = board
                    self:Render(kind, board)
                end
                if board and os.clock() >= board.NextRefresh then
                    local ok, result = pcall(FX.Network.InvokeServer, FX.Network,
                        "C2S_RankingData", 2, kind, 1, RankingDataConfig[kind].MaxCount)
                    board.Data = ok and result or nil
                    board.Requested = true
                    board.NextRefresh = os.clock() + (board.Data and 30 or 5)
                    self:Render(kind, board)
                end
            end
            task.wait(2)
        end
    end)
end

--- 销毁本组件创建的界面并解除监听，不改动地图模型。
function Component:Dtor()
    if self._refreshTask then
        task.cancel(self._refreshTask)
    end
    for index, board in pairs(self._boards or {}) do
        board.Gui:Destroy()
    end
    Component.Super.Dtor(self)
end

return Component
