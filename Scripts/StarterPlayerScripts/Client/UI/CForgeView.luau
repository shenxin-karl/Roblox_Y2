-- 锻造木板：展示服务端同步的品质、幸运、单锤概率和出炉结果。
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local FX = _G.FX
local FXLoader = FX.Loader
local Text = FX.Text
local TranslationTexts = Text.Define("ForgeView", {
    Title = "武器锻造",
    Station = "Base income",
    Strikes = "敲击次数",
    Ready = "Equip a sword blank to start forging. You can smelt one at the furnace.",
    BlankPlaced = "Sword blank placed. Strike to start forging.",
    SuccessEffect = "已获得成品武器",
    GreatSuccessEffect = "大成功效果",
    Broken = "锻造终止：保留当前品质",
    Damaged = "Finish broken",
    Unchanged = "Unchanged",
    Success = "锻造成功",
    Quality = "+{quality:int}",
    DestroyChance = "Destroyed",
    Hint = "F：敲击 · G：出炉 · E：暂停并离开",
    Failed = "Hold a sword blank before striking.",
    Busy = "锻造中…",
    StrikeButton = "F · 敲击",
    GreatStrikeButton = "G · 武器出炉",
    LeaveButton = "E · 离开",
    Destroyed = "武器已损毁，未获得成品。",
    RecoveryButton = "Restore · {value} Diamonds",
    Recovered = "Weapon restored. You can continue forging.",
    Finished = "武器已出炉，装备后可放入基地。",
    PendingClaim = "武器已完成，请腾出背包空间后按 G 领取。",
})
local Rules = FXLoader:RequireShared("Scripts.Game.Shared.SwordRules")
local Settings = FXLoader:RequireShared("Scripts.Game.Shared.ForgeSettings")
local GameUtility = FXLoader:RequireShared("Scripts.Game.Shared.GameUtility")
local OutcomeNames = {"Broken", "Damaged", "Unchanged", "Success"}
local ProbabilityKeys = {"destroy", "broken", "unchanged", "success"}
local View = {}
View.__index = View

--- 复用出炉按钮的配色与描边，在屏幕右上创建独立的恢复操作。
--- @param root ScreenGui 当前玩家的锻造界面。
--- @param template TextButton 用于继承原界面的样式。
--- @return TextButton, TextLabel 恢复按钮和本地化价格标签。
local function CreateRecoveryButton(root, template)
    local button = template:Clone()
    button.Name = "Recover"
    button.Text = ""
    button.AnchorPoint = Vector2.new(1, 0)
    button.Position = UDim2.new(1, -16, 0, 16)
    button.Size = UDim2.fromOffset(224, 48)
    button.Visible = false
    button.AutoLocalize = true
    local padding = button:FindFirstChildOfClass("UIPadding")
    if padding then
        padding:Destroy()
    end

    local icon = Instance.new("ImageLabel")
    icon.Name = "RecoveryIcon"
    icon.BackgroundTransparency = 1
    icon.Position = UDim2.fromOffset(10, 0)
    icon.Size = UDim2.new(0, 30, 1, 0)
    icon.Image = "rbxassetid://126644722107975"
    icon.ScaleType = Enum.ScaleType.Fit
    icon.Parent = button

    local label = Instance.new("TextLabel")
    label.Name = "RecoveryPrice"
    label.AutoLocalize = false
    label.BackgroundTransparency = 1
    label.Position = UDim2.fromOffset(48, 0)
    label.Size = UDim2.new(1, -58, 1, 0)
    label.FontFace = template.FontFace
    label.TextColor3 = template.TextColor3
    label.TextSize = 16
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = button
    button.Parent = root
    return button, label
end

--- 绑定 Studio 原生模板，节点布局与翻译属性沿用制作结果。
--- @param root ScreenGui 当前玩家的锻造界面。
--- @return table 本组件独享的展示对象。
function View.New(root)
    local self = setmetatable({}, View)
    self._root = root
    -- 锻造仍留在屏幕上；缺钻时让货币商店（30）盖在锻造操作之上。
    root.DisplayOrder = 25
    self._surface = FXLoader:Here(root, "BoardSurface")
    self._panel = FXLoader:Here(self._surface, "Panel")
    self._controls = FXLoader:Here(root, "Controls")
    self._flash = FXLoader:Here(root, "ImpactFlash")
    self._scale = FXLoader:Here(self._controls, "ResponsiveScale")
    self._resultScale = FXLoader:Here(self._panel, "Result.ImpactScale")
    self._labels, self._outcomes, self._values, self._segments, self._pips = {}, {}, {}, {}, {}
    for index, name in ipairs({"Title", "Station", "Count", "CountCaption", "Result", "Notice", "Quality"}) do
        self._labels[name] = FXLoader:Here(self._panel, name)
    end
    self._resultTextSize = self._labels.Result.TextSize
    for index, name in ipairs(OutcomeNames) do
        self._outcomes[name] = FXLoader:Here(self._panel, "Outcomes." .. name .. ".Label")
        self._values[name] = FXLoader:Here(self._panel, "Outcomes." .. name .. ".Value")
        self._segments[name] = FXLoader:Here(self._panel, "Spectrum." .. name)
    end
    for index = 1, 10 do
        self._pips[index] = FXLoader:Here(self._panel, "Pips.Pip" .. index)
    end
    self.StrikeButton = FXLoader:Here(self._controls, "Strike")
    self.GreatStrikeButton = FXLoader:Here(self._controls, "GreatStrike")
    self.RecoveryButton, self._recoveryPrice = CreateRecoveryButton(root, self.GreatStrikeButton)
    self.GreatStrikeButton.Visible = true
    self.GreatStrikeButton.Position = UDim2.fromOffset(0, 144)
    self.GreatStrikeButton.Size = UDim2.fromOffset(300, 50)
    self.LeaveButton = FXLoader:Here(self._controls, "Leave")
    self.LeaveButton.Position = UDim2.fromOffset(0, 206)
    self._controls.Size = UDim2.fromOffset(300, 264)
    self._hint = FXLoader:Here(self._controls, "Hint")
    self._tweens = {}
    self._count, self._stationId = 0, 0
    self._gmChanceConnection = Players.LocalPlayer:GetAttributeChangedSignal("GMGuaranteedForge"):Connect(function()
        if self._root.Enabled then
            self:RefreshText()
        end
    end)
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
    self.RecoveryButton.Visible = false
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
--- @param count number 动画回调的会话锤数；木牌计数沿用 SetForgeData 的累计锤数。
function View:Impact(powerful, count)
    self._failed = false
    self._powerful = powerful
    self:RefreshText()
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

--- 开锻缺少手持剑胚时，在木牌上提示如何继续。
function View:ShowFailure()
    self._failed = true
    self:RefreshText()
end

--- 刷新木牌、概率和操作文案；放大简短的成功提示，长提示保留模板字号。
function View:RefreshText()
    local data = self._forgeData
    local canRecover = self._root.Enabled and data ~= nil and data.Outcome == "Destroyed" and data.RecoveryId ~= nil
    self.RecoveryButton.Visible = canRecover
    self.RecoveryButton.Interactable = canRecover and not self._busy
    if canRecover then
        self._recoveryPrice.Text = Text.Tr(TranslationTexts.RecoveryButton, {
            value = GameUtility.NumberToText(Settings.RecoveryDiamondCost),
        })
    end
    self._labels.Title.Text = data and data.Quality and Text.TrSource(_G.GameConfig.WeaponData[data.Quality].Name)
        or Text.Tr(TranslationTexts.Title)
    self._labels.Station.Text = Text.Tr(TranslationTexts.Station)
    self._labels.Count.Text = tostring(self._count)
    self._labels.CountCaption.Text = Text.Tr(TranslationTexts.Strikes)
    self._labels.Quality.Text = data and data.Quality and Text.Tr(TranslationTexts.Quality, {quality = data.Quality}) or ""
    local income = data and data.Quality
        and Rules.GetIncome({Quality = data.Quality, Level = 1, MutationId = data.MutationId})
    self._labels.Notice.Text = income and "$" .. GameUtility.NumberToText(income) .. "/s" or "—"
    local resultKey = TranslationTexts.Ready
    local resultColor = Color3.fromRGB(255, 241, 217)
    if self._failed then
        resultKey = TranslationTexts.Failed
        resultColor = Color3.fromRGB(255, 130, 110)
    elseif data and data.Active and data.HammerCount == 0 then
        resultKey = TranslationTexts.BlankPlaced
    elseif self._powerful ~= nil then
        resultKey = self._powerful and TranslationTexts.GreatSuccessEffect or TranslationTexts.SuccessEffect
        resultColor = self._powerful and Color3.fromRGB(221, 166, 255) or Color3.fromRGB(128, 215, 255)
    end
    if not self._failed and data and data.Outcome then
        if data.Active and data.Finished then
            resultKey = TranslationTexts.PendingClaim
        elseif data.Outcome == "Destroyed" then
            resultKey = TranslationTexts.Destroyed
            resultColor = Color3.fromRGB(255, 133, 111)
        elseif data.Outcome == "Recovered" then
            resultKey = TranslationTexts.Recovered
        elseif data.Outcome == "Broken" then
            resultKey = TranslationTexts.Broken
            resultColor = Color3.fromRGB(244, 192, 106)
        elseif data.Outcome == "Finished" then
            resultKey = TranslationTexts.Finished
        elseif data.Outcome == "Unchanged" then
            resultKey = TranslationTexts.Unchanged
            resultColor = Color3.fromRGB(177, 226, 180)
        elseif data.Outcome == "Success" then
            resultKey = TranslationTexts.Success
            resultColor = Color3.fromRGB(167, 219, 245)
        end
    end
    self._labels.Result.Text = Text.Tr(resultKey)
    self._labels.Result.TextColor3 = resultColor
    self._labels.Result.TextSize = resultKey == TranslationTexts.Success and 36 or self._resultTextSize
    local probabilities
    if data and data.Active and not data.Finished then
        if Players.LocalPlayer:GetAttribute("GMGuaranteedForge") == true then
            probabilities = {success = 100, unchanged = 0, broken = 0, destroy = 0}
        else
            probabilities = Rules.GetForgeProbabilities(data.blankLuckLevel, data.forgeLevel, data.Quality)
        end
    end
    local offset = 0
    for index, name in ipairs(OutcomeNames) do
        self._outcomes[name].Text = Text.Tr(name == "Broken" and TranslationTexts.DestroyChance or TranslationTexts[name])
        local chance = probabilities and probabilities[ProbabilityKeys[index]]
        self._values[name].Text = chance and string.format("%.1f%%", chance) or "—"
        local segment = self._segments[name]
        segment.Visible = chance ~= nil and chance > 0
        segment.Position = UDim2.fromScale(offset / 100, 0)
        segment.Size = UDim2.fromScale((chance or 0) / 100, 1)
        offset += chance or 0
    end
    for index, pip in ipairs(self._pips) do
        pip.BackgroundTransparency = index <= self._count and 0 or 0.6
    end
    self._hint.Text = Text.Tr(self._busy and TranslationTexts.Busy or TranslationTexts.Hint)
    self.StrikeButton.Text = Text.Tr(TranslationTexts.StrikeButton)
    self.GreatStrikeButton.Text = Text.Tr(TranslationTexts.GreatStrikeButton)
    self.LeaveButton.Text = Text.Tr(TranslationTexts.LeaveButton)
end

--- 新进度替换上次尝试的提示；不在客户端抽取或预测锻造结果。
--- @param data table 服务端同步的锻造状态。
function View:SetForgeData(data)
    self._failed = false
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
    self._gmChanceConnection:Disconnect()
    self:Close()
    self.RecoveryButton:Destroy()
end

return View
