--[[
离线收益窗口接入契约

职责边界：
  View负责钞票主视觉、金额、时长、按钮、翻译和点击许可。
  游戏接入提供真实待领金币、钻石余额、价格和请求结果；不覆写Render或重绑节点。

Config（完整对象）：
  diamondCost: number，必填，无默认值；双倍领取的非负整数钻石价格。
  双倍倍率固定为2，服务端独立校验，不接受客户端提供倍率或奖励金额。

State（完整快照，不合并增量）：
  amount: number，必填，无默认值；非负有限待领金币。
  actualSeconds / earnedSeconds: number?，本笔待领收益的实际离线与计入收益时长；旧存档缺失时两项均不显示。
  diamonds: number，必填，无默认值；非负有限钻石余额。
  pending: boolean，可选，省略为false；请求中，两种领取均禁用。
  failed: boolean，可选，省略为false；请求失败，保留金额并允许重试。
  数据未就绪时提供nil，清空动态文字并禁用领取。

初始化与刷新：
  GetUIConfig读取self.Config；GetUIState读取self.State。
  OnReady先父绑定，再由游戏准备Config/State、建立一次订阅并RefreshUI。
  有奖励时游戏调用Show；OnShow只刷新，不重复绑定。
  Render不控制整窗显隐；关闭不清除未领奖励。

展示与交互规则：
  优先级：缺失数据 > pending > failed > 已领取 > 钻石不足 > 可领取。
  普通领取：amount>0且非pending时可点击，获得amount。
  钻石双倍：amount>0且非pending时可点击，余额足够时获得amount*2。
  钻石不足时双倍按钮置灰但仍发出Claim；游戏检查余额并打开钻石购买页面，普通领取仍可用。
  金额仅在奖励区展示；按钮不显示奖励金额或钻石价格。
  pending显示“Claiming...”；失败显示重试提示。
  amount=0显示已领取，两按钮禁用；关闭始终可用。

动作：
  Claim，payload.boosted:boolean，必填；false普通，true钻石双倍。
  Close，payload为空table；游戏调用Hide，不取消已经提交的请求。
  点击不直接发奖或扣钻，由游戏服务端决定最终结果。

接口实现清单：
  必须实现：
    OnUIAction(action:string,payload:table) -> 无返回值，处理Claim与Close。
    OnReady() -> 无返回值；先Super.OnReady，再数据、订阅、刷新及按需Show。
  按条件覆写：
    Ctor(owner:table) -> 无返回值，先Super.Ctor，再准备Config/State。
    FormatAmount(amount:number) -> string，默认两位小数；游戏接统一数量缩写。
    Dtor() -> 无返回值，先解除未托管回调，再Super.Dtor。
  继承无需重写：GetUIConfig、GetUIState、OnShow。
  仅调用：RefreshUI、Show、Hide、TrackConnection。
  展示层内部禁止覆盖：Render、EmitUIAction、SetButtonEnabled及节点绑定。

项目接入步骤：
  1. Generated之外继承COfflineIncomeView，在入口加载并仅挂载业务子类。
  2. 提供真实diamondCost、待领金币、钻石余额；未就绪不Show。
  3. OnReady先父绑定，再准备完整状态、一次订阅，刷新后有奖励才自动Show。
  4. 双倍Claim且本地余额不足时打开钻石购买页面；其余Claim置pending=true、failed=false并发送请求。
  5. 服务端原子扣钻、发金币、清待领额；回执成功或失败均清pending。
  6. 成功采用权威数据并Hide；服务端确认钻石不足时打开钻石购买页面；其他失败保留金额、刷新并允许重试。
  7. Close只Hide，奖励保留，下次登录仍可领取；隐藏期间不移除订阅。
  8. Dtor解除网络回调后父清理，禁止过期回执回写已销毁组件。

最小完整数据：
  self.Config = {
      diamondCost = 10,
  }
  self.State = {
      amount = 12500,
      diamonds = 28,
      pending = false,
      failed = false,
  }
]]
local FX = _G.FX
local FXLoader = FX.Loader
local Text = FXLoader:RequireShared("Scripts.Framework.Shared.Core.FXText")
local COfflineIncomeView = FX.Class("COfflineIncomeView", "CUIView")

local TranslationTexts = Text.Define("OfflineIncome", {
    Amount = "${value}",
    ActualTime = "Time Offline",
    EarnedTime = "Counted Toward Earnings",
    Duration = "{hours:int}h {minutes:int}m {seconds:int}s",
    DurationWithDays = "{days:int}d {hours:int}h {minutes:int}m {seconds:int}s",
    Claim = "Claim",
    DoubleClaim = "2× Claim",
    Pending = "Claiming...",
    Claimed = "Claimed",
    Insufficient = "Not enough diamonds for double claim.",
    Failed = "Claim failed. Please try again.",
})
COfflineIncomeView.BaseViewTranslationTexts = TranslationTexts

--- 绑定金额、普通领取与钻石双倍领取，不在展示层处理资产。
function COfflineIncomeView:OnReady()
    local root = FXLoader:PlayerGui("OfflineIncomeUI")
    self._amountTxt = FXLoader:Here(root, "PopupPanelImg.AmountTxt")
    self._statusTxt = FXLoader:Here(root, "PopupPanelImg.StatusTxt")
    local panel = FXLoader:Here(root, "PopupPanelImg")
    self._actualTimeCard = if game then FXLoader:Find(panel, "ActualTimeImg") else FXLoader:Here(panel, "ActualTimeImg")
    self._earnedTimeCard = if game then FXLoader:Find(panel, "EarnedTimeImg") else FXLoader:Here(panel, "EarnedTimeImg")
    if self._actualTimeCard and self._earnedTimeCard then
        self._actualTimeTitle = FXLoader:Here(self._actualTimeCard, "TitleTxt")
        self._earnedTimeTitle = FXLoader:Here(self._earnedTimeCard, "TitleTxt")
        self._actualTimeTxt = FXLoader:Here(self._actualTimeCard, "ActualTimeTxt")
        self._earnedTimeTxt = FXLoader:Here(self._earnedTimeCard, "EarnedTimeTxt")
    end
    self._claimBtn = FXLoader:Here(root, "PopupPanelImg.ClaimBtn")
    self._claimTxt = FXLoader:Here(self._claimBtn, "ButtonTxt")
    self._claimEdge = FXLoader:Here(self._claimBtn, "BottomEdgeImg")
    self._doubleBtn = FXLoader:Here(root, "PopupPanelImg.DoubleClaimBtn")
    self._doubleTxt = FXLoader:Here(self._doubleBtn, "ButtonTxt")
    self._doubleEdge = FXLoader:Here(self._doubleBtn, "BottomEdgeImg")
    local closeBtn = FXLoader:Here(root, "TitleBox.CloseSurfaceImg.CloseBtn")
    -- 普通领取只提交选项，不提交客户端奖励金额。
    self:TrackConnection(self._claimBtn.Activated:Connect(function()
        local state = self:GetUIState()
        if state and state.amount > 0 and not state.pending then
            self:EmitUIAction("Claim", {boosted = false})
        end
    end))
    -- 余额不足也发出点击动作，购买引导和真实扣钻由业务层处理。
    self:TrackConnection(self._doubleBtn.Activated:Connect(function()
        local state = self:GetUIState()
        local config = self:GetUIConfig()
        if state and config and state.amount > 0 and not state.pending then
            self:EmitUIAction("Claim", {boosted = true})
        end
    end))
    -- 关闭只隐藏，不清除奖励。
    self:TrackConnection(closeBtn.Activated:Connect(function()
        self:EmitUIAction("Close", {})
    end))
end

--- 每次打开刷新最新状态，不重复连接按钮。
function COfflineIncomeView:OnShow()
    self:RefreshUI()
end

--- 游戏可覆写统一的大数显示格式。
--- @param amount number 非负有限金币数。
--- @return string 格式化的金额。
function COfflineIncomeView:FormatAmount(amount)
    return string.format("%.2f", amount)
end

local function FormatDuration(seconds)
    local days = math.floor(seconds / 86400)
    local definition = days > 0 and TranslationTexts.DurationWithDays or TranslationTexts.Duration
    return Text.Tr(definition, {
        days = days,
        hours = math.floor(seconds / 3600) % 24,
        minutes = math.floor(seconds / 60) % 60,
        seconds = seconds % 60,
    })
end

--- 以完整业务状态更新两种领取资格与文案。
--- @param state table? 待领金额、离线时长及领取请求状态，见文件头契约。
function COfflineIncomeView:Render(state)
    local config = self:GetUIConfig()
    if self._actualTimeTxt and self._earnedTimeTxt then
        local showDuration = config ~= nil and state ~= nil and state.amount > 0
            and state.actualSeconds ~= nil and state.earnedSeconds ~= nil
        self._actualTimeTitle.Text = showDuration and Text.Tr(TranslationTexts.ActualTime) or ""
        self._earnedTimeTitle.Text = showDuration and Text.Tr(TranslationTexts.EarnedTime) or ""
        self._actualTimeTxt.Text = showDuration and FormatDuration(state.actualSeconds) or ""
        self._earnedTimeTxt.Text = showDuration and FormatDuration(state.earnedSeconds) or ""
        self._actualTimeCard.Visible = showDuration
        self._earnedTimeCard.Visible = showDuration
    end
    if not state or not config then
        self._amountTxt.Text = ""
        self._statusTxt.Text = ""
        self._claimTxt.Text = ""
        self._doubleTxt.Text = ""
        self:SetButtonEnabled(self._claimBtn, false)
        self:SetButtonEnabled(self._doubleBtn, false)
        return
    end
    local canClaim = state.amount > 0 and not state.pending
    local highlightDouble = canClaim and state.diamonds >= config.diamondCost
    local statusText = nil
    if state.pending then
        statusText = TranslationTexts.Pending
    elseif state.failed then
        statusText = TranslationTexts.Failed
    elseif state.amount <= 0 then
        statusText = TranslationTexts.Claimed
    elseif state.diamonds < config.diamondCost then
        statusText = TranslationTexts.Insufficient
    end
    self._amountTxt.Text = Text.Tr(TranslationTexts.Amount, {value = self:FormatAmount(state.amount)})
    self._statusTxt.Text = statusText and Text.Tr(statusText) or ""
    if state.pending then
        self._claimTxt.Text = Text.Tr(TranslationTexts.Pending)
        self._doubleTxt.Text = Text.Tr(TranslationTexts.Pending)
    elseif state.amount <= 0 then
        self._claimTxt.Text = Text.Tr(TranslationTexts.Claimed)
        self._doubleTxt.Text = Text.Tr(TranslationTexts.Claimed)
    else
        self._claimTxt.Text = Text.Tr(TranslationTexts.Claim)
        self._doubleTxt.Text = Text.Tr(TranslationTexts.DoubleClaim)
    end
    self._claimBtn.BackgroundColor3 = canClaim and Color3.fromRGB(103, 237, 20) or Color3.fromRGB(99, 128, 121)
    self._claimEdge.BackgroundColor3 = canClaim and Color3.fromRGB(34, 90, 7) or Color3.fromRGB(38, 62, 54)
    self._doubleBtn.BackgroundColor3 = highlightDouble and Color3.fromRGB(208, 59, 242) or Color3.fromRGB(99, 128, 121)
    self._doubleEdge.BackgroundColor3 = highlightDouble and Color3.fromRGB(105, 21, 130) or Color3.fromRGB(38, 62, 54)
    self:SetButtonEnabled(self._claimBtn, canClaim)
    self:SetButtonEnabled(self._doubleBtn, canClaim)
end

--- 由项目实现请求与关闭，展示层不直接扣钻或发奖。
--- @param action string Claim或Close。
--- @param payload table Claim含boosted:boolean，Close为空。
function COfflineIncomeView:OnUIAction(action, payload)
    error("Offline income integration must implement OnUIAction")
end

return COfflineIncomeView
