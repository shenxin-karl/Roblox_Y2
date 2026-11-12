--[[
重生界面接入契约（字段大小写须保持一致）

【Config / State】
  Config：本页不消费配置字段，无需设置。
  State：Render 的完整快照；以下必填字段均无默认值。
    Open: boolean；当前实现控制内容底板和标题 Visible。
    Level: number；当前等级，单位级。
    RequiredLevel: number；重生门槛，单位级；<=0 表示条件未就绪，
      进度显示 Level 当前等级/--、空进度条，禁用重生及 Skip。
    Completed: boolean；本次重生是否已经完成。
    CurrentStrengthMultiplier: number；当前力量倍率。
    NextStrengthMultiplier: number；下次重生后的力量倍率。
    CurrentMoneyMultiplier: number；当前收益倍率。
    NextMoneyMultiplier: number；下次重生后的收益倍率。
    SkipCost: number；跳过所需钻石数量，必填、非负、无默认值；
      由业务数据提供，不从等级推导，不在客户端写死。
    SkipAvailable: boolean，可选；省略 true，false 时禁用 Skip，价格仍显示。
    Pending: boolean，可选，省略 false；请求期间禁用重生和 Skip，不禁用关闭。
  四项倍率均无量纲，2 表示 x2；由业务提供，不从等级推导。
  View 用 15 位有效数字显示倍率，并通过 FormatNumber 显示 SkipCost；
  不修改原始数值。
  没有列表或 error 字段，失败提示由接入层负责。
  异步未就绪时可设 RequiredLevel=0，但其他必填字段仍须提供；
  若倍率等数据也未就绪，延后 BindUIData/Show，而不是传残缺 State。

【最小完整数据（接入 Ctor 调用父构造之后）】
  self.State = {
      Open = true, Level = 317, RequiredLevel = 325, Completed = false,
      CurrentStrengthMultiplier = 7, NextStrengthMultiplier = 7.5,
      CurrentMoneyMultiplier = 3.4, NextMoneyMultiplier = 3.6, SkipCost = 60,
  }

【初始化与刷新】
  游戏接入类继承 CRebirthUICompClass。
  接入 Ctor(owner) 先调用自身类的 Super.Ctor(self, owner)，再准备下例数据。
  接入 OnReady() 先调用自身类的 Super.OnReady(self)，再依次
  self:BindUIData()、self:Show()；父 OnReady 负责绑定节点，OnShow 会刷新。
  GetUIConfig() 默认返回 self.Config；GetUIState() 默认返回 self.State。
  RefreshUI() 调用 Render(GetUIState())，输入是完整快照，不合并增量，
  不自动补齐业务字段。可修改已有表或替换整表，但每次刷新须满足完整契约。
  后续先更新 Config/State，再 self:RefreshUI()；异步未就绪按本页规则处理。
  无需覆写 Render 或手动重复调用 OnReady；业务类覆写生命周期时须保留父调用。

【动作与覆写】
  必需覆写 OnUIAction(action: string, payload: table)，无返回值；默认报错。
  CloseRebirth -> {}；接入层设置 Open=false 并刷新。
  RequestSkip -> {}；请求跳过等级条件，payload 不传 SkipCost 或其他客户端价格。
  余额、价格与支付校验由接入层负责，View 不执行��付。
  RequestRebirth -> {}；请求重生，不传等级、倍率或客户端计算的资格。
  Config.allowIneligibleAction:boolean?，true 时未满足门槛或到达上限仍允许点击提示。
  State.AtMax:boolean?，true 显示重生上限提示并保持灰色。
  FormatNumber(value:number)->string 可选覆写，默认 tostring，用于倍率与 SkipCost。
  继承 Render 与输入绑定，不覆盖按钮资格或进度文案。
  重生可用条件：Open、RequiredLevel>0、未 Completed、未 Pending、
  Level>=RequiredLevel；Skip 不要求等级不足，前四项满足且未到上限即可。
  Skip 禁用条件为 SkipAvailable=false、Pending=true、AtMax=true，或页面不满足上述公共条件；
  禁用时 SkipCostTxt 仍显示业务提供并与余额无关的价格。
  真实接入须重新校验资格、余额、价格与支付；请求前 Pending=true 并刷新；
  成功后按真实结果更新等级、Completed、四项倍率，失败保留真实状态并另行提示；
  两种结果均 Pending=false 后刷新。下一轮由业务更新门槛并设 Completed=false。

【显隐边界】
  当前 Render 直接控制底板/标题，不是仅由 Show/Hide 管理整页；
  再次 Show 前恢复 Open=true，不据此宣称关闭动画通过。
  进度宽度截断到 0..1，文字保留原始等级；Completed 显示完成提示。
  图标沿用设计静态资源，不通过 State 替换。
  保留现有类名 CRebirthUICompClass。
]]
local FX = _G.FX
local FXLoader = FX.Loader
local Text = FXLoader:RequireShared("Scripts/Game/Shared/Text")
local UI = FX.Class("CRebirthUICompClass", "CUIView")

local TranslationTexts = Text.Define("RebirthUI", {
    Multiplier = "x{value}",
    Progress = "Level {level:int}/{required:int}",
    ProgressUnavailable = "Level {level:int}/--",
    Complete = "Rebirth complete! Strength reset.",
    ResetWarning = "Rebirth resets your strength!",
    MaxCount = "You have reached the rebirth limit.",
})

-- 暴露只读文案定义，供接入子类通过 self.BaseViewTranslationTexts 复用。
UI.BaseViewTranslationTexts = TranslationTexts

-- 倍率与跳过价格接入统一数量工具，等级继续保留等级语义。
-- @param value number 原始倍率或钻石数量。
-- @return string 展示文本。
function UI:FormatNumber(value)
    return tostring(value)
end

-- 绑定已有设计节点与按钮；刷新时不重复连接事件。
function UI:OnReady()
    local root = FXLoader:PlayerGui("RebirthUI")
    self.Panel = FXLoader:Here(root, "PopupPanelImg")
    self.TitleBox = FXLoader:Here(root, "TitleBox")
    self.RebirthBtn = FXLoader:Here(root, "PopupPanelImg.RebirthBtn")
    self.SkipBtn = FXLoader:Here(root, "PopupPanelImg.SkipBtn")
    self.SkipCostTxt = FXLoader:Here(root, "PopupPanelImg.SkipBtn.SkipPriceBox.SkipCostTxt")
    self.ProgressFill = FXLoader:Here(root, "PopupPanelImg.ProgressBarImg.ProgressFillImg")
    self.ProgressTxt = FXLoader:Here(root, "PopupPanelImg.ProgressBarImg.ProgressTxt")
    self.WarningTxt = FXLoader:Here(root, "PopupPanelImg.ResetWarningTxt")
    self.CurrentStrengthTxt = FXLoader:Here(root, "PopupPanelImg.CurrentStrengthImg.MultiplierTxt")
    self.NextStrengthTxt = FXLoader:Here(root, "PopupPanelImg.NextStrengthImg.MultiplierTxt")
    self.CurrentMoneyTxt = FXLoader:Here(root, "PopupPanelImg.CurrentMoneyImg.MultiplierTxt")
    self.NextMoneyTxt = FXLoader:Here(root, "PopupPanelImg.NextMoneyImg.MultiplierTxt")
    self.RebirthGradient = FXLoader:Here(root, "PopupPanelImg.RebirthBtn.SurfaceGradient")
    local close = FXLoader:Here(root, "TitleBox.CloseSurfaceImg")
    -- 关闭由接入层更新 Open，不销毁设计节点。
    self:TrackConnection(close.Activated:Connect(function()
        self:EmitUIAction("CloseRebirth", {})
    end))
    -- 重生资格与请求结果由接入层处理。
    self:TrackConnection(self.RebirthBtn.Activated:Connect(function()
        self:EmitUIAction("RequestRebirth", {})
    end))
    -- Skip 仅发送请求，展示层不执行支付。
    self:TrackConnection(self.SkipBtn.Activated:Connect(function()
        self:EmitUIAction("RequestSkip", {})
    end))
end

-- 打开时刷新最新完整状态，不重新绑定事件。
function UI:OnShow()
    self:RefreshUI()
end

-- 更新完整状态对应的展示；字段定义见文件头。
-- @param state table 重生 State，Pending 可省略
function UI:Render(state)
    self.Panel.Visible = state.Open
    self.TitleBox.Visible = state.Open
    self.CurrentStrengthTxt.Text = Text.Tr(TranslationTexts.Multiplier, {
        value = self:FormatNumber(state.CurrentStrengthMultiplier),
    })
    self.NextStrengthTxt.Text = Text.Tr(TranslationTexts.Multiplier, {
        value = self:FormatNumber(state.NextStrengthMultiplier),
    })
    self.CurrentMoneyTxt.Text = Text.Tr(TranslationTexts.Multiplier, {
        value = self:FormatNumber(state.CurrentMoneyMultiplier),
    })
    self.NextMoneyTxt.Text = Text.Tr(TranslationTexts.Multiplier, {
        value = self:FormatNumber(state.NextMoneyMultiplier),
    })
    self.SkipCostTxt.Text = self:FormatNumber(state.SkipCost)
    local ready = state.RequiredLevel > 0
    local ratio = 0
    if ready then
        self.ProgressTxt.Text = Text.Tr(TranslationTexts.Progress, {
            level = state.Level,
            required = state.RequiredLevel,
        })
        ratio = math.clamp(state.Level / state.RequiredLevel, 0, 1)
    else
        self.ProgressTxt.Text = Text.Tr(TranslationTexts.ProgressUnavailable, {
            level = state.Level,
        })
    end
    self.ProgressFill.Size = UDim2.fromScale(ratio, 1)
    self.ProgressTxt.Text = string.gsub(self.ProgressTxt.Text, "%s+$", "")
    local available = state.Open and ready and not state.Completed and not state.Pending
    local eligible = available and not state.AtMax and state.Level >= state.RequiredLevel
    self:SetButtonEnabled(self.RebirthBtn, eligible or (self:GetUIConfig() ~= nil and self:GetUIConfig().allowIneligibleAction == true
        and state.Open and not state.Pending))
    self:SetButtonEnabled(self.SkipBtn, available and not state.AtMax and state.SkipAvailable ~= false)
    if eligible then
        self.RebirthBtn.BackgroundColor3 = Color3.fromHex("#67ED14")
    else
        self.RebirthBtn.BackgroundColor3 = Color3.fromHex("#B7B7B7")
    end
    self.RebirthGradient.Enabled = not eligible
    if state.AtMax then
        self.WarningTxt.Text = Text.Tr(TranslationTexts.MaxCount)
    elseif state.Completed then
        self.WarningTxt.Text = Text.Tr(TranslationTexts.Complete)
    else
        self.WarningTxt.Text = Text.Tr(TranslationTexts.ResetWarning)
    end
end

-- 必须由游戏接入实现，不在展示层执行业务。
-- @param action string CloseRebirth / RequestSkip / RequestRebirth
-- @param payload table 空表，不传业务 ID 或客户端价格
function UI:OnUIAction(action, payload)
    error("Rebirth integration must implement OnUIAction: " .. tostring(action))
end

return UI
