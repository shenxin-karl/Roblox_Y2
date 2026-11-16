-- 锻造木板：展示服务端同步的品质、幸运、单锤概率和出炉结果。
local TweenService = game:GetService("TweenService")
local FX = _G.FX
local FXLoader = FX.Loader
local Text = FX.Text
local TranslationTexts = Text.Define("ForgeView", {
    Title = "武器锻造",
    Station = "{station:int} 号锻造台",
    Strikes = "敲击次数",
    Ready = "需要剑胚才能锻造，请先到熔炉熔炼矿石。",
    SuccessEffect = "已获得成品武器",
    GreatSuccessEffect = "大成功效果",
    Broken = "锻造终止：保留当前品质",
    Damaged = "受损",
    Unchanged = "品质不变",
    Success = "锻造成功",
    GreatSuccess = "大成功",
    Notice = "品质 {quality:int} · 玩家幸运 {player:int} · 材料幸运 {material:int}",
    Hint = "F：敲击 · G：出炉 · E：暂停并离开",
    Failed = "没有可用的剑胚，请先到熔炉熔炼矿石。",
    Busy = "锻造中…",
    StrikeButton = "F · 敲击",
    GreatStrikeButton = "G · 武器出炉",
    LeaveButton = "E · 离开",
    Destroyed = "武器已损毁，未获得成品。",
    Finished = "武器已出炉，装备后可放入基地。",
    PendingClaim = "武器已完成，请腾出背包空间后按 G 领取。",
    Probabilities = "成功 {success}% · 不变 {unchanged}% · 终止 {broken}% · 损毁 {destroy}%",
})
local Rules = FXLoader:RequireShared("Scripts.Game.Shared.SwordRules")
local OutcomeNames = {"Broken", "Damaged", "Unchanged", "Success", "GreatSuccess"}
local View = {}
View.__index = View

--- 绑定 Studio 原生模板，节点布局与翻译属性沿用制作结果。
--- @param root ScreenGui 当前玩家的锻造界面。
--- @return table 本组件独享的展示对象。
function View.New(root)
    local self = setmetatable({}, View)
    self._root = root
    self._surface = FXLoader:Here(root, "BoardSurface")
    self._panel = FXLoader:Here(self._surface, "Panel")
    self._controls = FXLoader:Here(root, "Controls")
    self._flash = FXLoader:Here(root, "ImpactFlash")
    self._scale = FXLoader:Here(self._controls, "ResponsiveScale")
    self._resultScale = FXLoader:Here(self._panel, "Result.ImpactScale")
    self._labels, self._outcomes, self._pips = {}, {}, {}
    for index, name in ipairs({"Title", "Station", "Count", "CountCaption", "Result", "Notice"}) do
        self._labels[name] = FXLoader:Here(self._panel, name)
    end
    for index, name in ipairs(OutcomeNames) do
        self._outcomes[name] = FXLoader:Here(self._panel, "Outcomes." .. name .. ".Label")
    end
    for index = 1, 10 do
        self._pips[index] = FXLoader:Here(self._panel, "Pips.Pip" .. index)
    end
    self.StrikeButton = FXLoader:Here(self._controls, "Strike")
    self.GreatStrikeButton = FXLoader:Here(self._controls, "GreatStrike")
    self.GreatStrikeButton.Visible = true
    self.GreatStrikeButton.Position = UDim2.fromOffset(0, 144)
    self.GreatStrikeButton.Size = UDim2.fromOffset(300, 50)
    FXLoader:Here(self._panel, "Outcomes").Visible = false
    self.LeaveButton = FXLoader:Here(self._controls, "Leave")
    self.LeaveButton.Position = UDim2.fromOffset(0, 206)
    self._controls.Size = UDim2.fromOffset(300, 264)
    self._hint = FXLoader:Here(self._controls, "Hint")
    self._tweens = {}
    self._count, self._stationId = 0, 0
    return self
end

--- 为本次分配的木板开启展示，新的进入会话重新计数。
--- @param panel BasePart 已核对正面的木板。
--- @param stationId number 服务端同步的台位编号。
function View:Open(panel, stationId)
    self:Close()
    self._stationId, self._count, self._powerful, self._busy = stationId, 0, nil, nil
    self._failed = false
    self._surface.Adornee = panel
    self._surface.Enabled, self._root.Enabled = true, true
    for index, pip in ipairs(self._pips) do
        pip.BackgroundTransparency = 0.6
    end
    self:SetBusy(false)
end

--- 取消本展示对象持有的补间，不影响其他界面动画。
function View:CancelTweens()
    for index, tween in ipairs(self._tweens) do
        tween:Cancel()
    end
    table.clear(self._tweens)
end

--- 退出时清理残留闪屏与木板引用，不销毁 Studio 模板副本。
function View:Close()
    self:CancelTweens()
    self._root.Enabled, self._surface.Enabled = false, false
    self._surface.Adornee = nil
    self._flash.BackgroundTransparency = 1
    self._resultScale.Scale = 1
end

--- 挥锤期间禁用重复敲击，退出按钮始终可用。
--- @param busy boolean 当前锤击动画是否尚未完成。
function View:SetBusy(busy)
    if self._busy == busy then
        return
    end
    self._busy = busy
    self.StrikeButton.Active, self.GreatStrikeButton.Active = not busy, not busy
    self.StrikeButton.AutoButtonColor, self.GreatStrikeButton.AutoButtonColor = not busy, not busy
    self.StrikeButton.TextTransparency = busy and 0.4 or 0
    self.GreatStrikeButton.TextTransparency = busy and 0.4 or 0
    self:RefreshText()
end

--- 服务端确认本次敲击后播放命中反馈，实际品质与结果沿用同步数据。
--- @param powerful boolean 是否显示大成功的视觉预览。
--- @param count number 当前进入会话已经落下的锤数。
function View:Impact(powerful, count)
    self._failed = false
    self._powerful, self._count = powerful, count
    self:RefreshText()
    for index, pip in ipairs(self._pips) do
        pip.BackgroundTransparency = index <= count and 0 or 0.6
    end
    self:CancelTweens()
    self._resultScale.Scale = powerful and 1.08 or 1.04
    self._flash.BackgroundTransparency = powerful and 0.88 or 0.96
    local resultTween = TweenService:Create(self._resultScale,
        TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1})
    local flashTween = TweenService:Create(self._flash,
        TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1})
    self._tweens = {resultTween, flashTween}
    resultTween:Play()
    flashTween:Play()
end

--- 服务端拒绝剑胚时说明材料来源，不将缺少材料误报为背包容量问题。
function View:ShowFailure()
    self._failed = true
    self:RefreshText()
end

--- 语言切换时重新翻译原始定义，不缓存旧语言结果。
function View:RefreshText()
    self._labels.Title.Text = Text.Tr(TranslationTexts.Title)
    self._labels.Station.Text = Text.Tr(TranslationTexts.Station, {station = self._stationId})
    self._labels.Count.Text = tostring(self._count)
    self._labels.CountCaption.Text = Text.Tr(TranslationTexts.Strikes)
    local data = self._forgeData
    self._labels.Notice.Text = data and data.Quality and Text.Tr(TranslationTexts.Notice, {
        quality = data.Quality, player = data.PlayerLuck, material = data.Luck,
    }) or ""
    local resultKey = TranslationTexts.Ready
    local resultColor = Color3.fromRGB(255, 241, 217)
    if self._failed then
        resultKey = TranslationTexts.Failed
        resultColor = Color3.fromRGB(255, 130, 110)
    elseif self._powerful ~= nil then
        resultKey = self._powerful and TranslationTexts.GreatSuccessEffect or TranslationTexts.SuccessEffect
        resultColor = self._powerful and Color3.fromRGB(221, 166, 255) or Color3.fromRGB(128, 215, 255)
    end
    if data and data.Outcome then
        if data.Active and data.Finished then
            resultKey = TranslationTexts.PendingClaim
        elseif data.Outcome == "Destroyed" then
            resultKey = TranslationTexts.Destroyed
        elseif data.Outcome == "Broken" then
            resultKey = TranslationTexts.Broken
        elseif data.Outcome == "Finished" then
            resultKey = TranslationTexts.Finished
        elseif data.Outcome == "Unchanged" then
            resultKey = TranslationTexts.Unchanged
        elseif data.Outcome == "Success" then
            resultKey = TranslationTexts.Success
        end
    end
    self._labels.Result.Text = Text.Tr(resultKey)
    self._labels.Result.TextColor3 = resultColor
    for index, name in ipairs(OutcomeNames) do
        self._outcomes[name].Text = Text.Tr(TranslationTexts[name])
    end
    self._hint.Text = Text.Tr(self._busy and TranslationTexts.Busy or TranslationTexts.Hint)
    if data and data.Active and not data.Finished and not self._busy then
        local probabilities = Rules.GetForgeProbabilities(data.Luck, data.PlayerLuck, data.Quality)
        self._hint.Text = Text.Tr(TranslationTexts.Probabilities, probabilities)
    end
    self.StrikeButton.Text = Text.Tr(TranslationTexts.StrikeButton)
    self.GreatStrikeButton.Text = Text.Tr(TranslationTexts.GreatStrikeButton)
    self.LeaveButton.Text = Text.Tr(TranslationTexts.LeaveButton)
end

--- 只展示同步的进度；不在客户端抽取或预测锻造结果。
--- @param data table 服务端同步的锻造状态。
function View:SetForgeData(data)
    self._forgeData = data
    self._count = data.HammerCount or 0
    self:RefreshText()
end

--- 根据视口短边缩放右侧敲击与离开操作区，手机保留可点击尺寸。
--- @param viewportSize Vector2 当前相机视口的像素尺寸。
function View:Resize(viewportSize)
    self._scale.Scale = math.clamp(math.min(viewportSize.X, viewportSize.Y) / 720, 0.75, 1)
end

--- 组件释放时只关闭本视图和自有补间。
function View:Destroy()
    self:Close()
end

return View
