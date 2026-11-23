--[[
【职责】View 绑定输入、按钮、开关文案和关闭。项目负责开发者鉴权、实际操作和结果提示。

【Config / State】
Config = {}；本页不读取配置。
State 是完整快照，以下必填布尔值由接入方提供：
    pending：请求中时禁止所有命令，仍可关闭。
    freeUpgrades：服务端确认的免升级费用状态。
    guaranteedForge：服务端确认的锻造必成功状态。

【动作】
SetFreeUpgrades、SetGuaranteedForge：{ enabled: boolean }。
GiveBlank、GiveOre：{ id: number, quantity: number }，留空数量按 1。
GiveSword：{}，固定发放 1 个普通剑胚；保留原命令名。
GiveLevelOneSword、PrepareUpgrade、BreakSword：{}。
所有输入数字为正整数；服务端仍须核对 ID、范围和权限。

【接入】
继承 CGMPanelView，Ctor(owner) 先调用父构造，再准备 Config/State。
OnReady() 调用父方法和 BindUIData()，保持关闭；主界面按钮调用 Show()。
必须覆写 OnUIAction(action: string, payload: table)，无返回值。
可覆写 OnInvalidInput(action: string) 显示输入提示；默认仅记日志。
接入先置 pending 再发送请求，结束后更新权威开关状态和 pending 并 RefreshUI()。
继承 Show、Hide、Render 和节点事件，不重复绑定或覆写展示。
请求任务由接入方清理，节点事件由父类清理。

【首次数据示例】
self.Config = {}
self.State = {
    pending = false,
    freeUpgrades = false,
    guaranteedForge = false,
}
]]
local FX = _G.FX
local FXLoader = FX.Loader
local View = FX.Class("CGMPanelView", "CUIView")
View.ScreenGuiName = "GMPanelUI"

local Actions = {
    "SetFreeUpgrades",
    "SetGuaranteedForge",
    "GiveBlank",
    "GiveOre",
    "GiveSword",
    "GiveLevelOneSword",
    "PrepareUpgrade",
    "BreakSword",
}
local FormFields = {
    GiveBlank = "quantity",
    GiveOre = "quantity",
}

--- 输入必须是可精确表达的正整数；配置存在性由服务端核验。
--- @param value string 输入框原文。
--- @return number? 有效整数。
local function ReadPositiveInteger(value)
    local number = tonumber(value)
    if number and number >= 1 and number <= 9007199254740991 and number % 1 == 0 then
        return number
    end
    return nil
end

--- 绑定固定按钮和表单，窗口显隐由基础类管理。
function View:OnReady()
    local root = FXLoader:PlayerGui("GMPanelUI")
    local panel = FXLoader:Here(root, "PopupPanelImg")
    self._buttons = {}
    self._forms = {}
    for index, action in ipairs(Actions) do
        local button = FXLoader:Here(panel, action .. "Btn")
        self._buttons[action] = button
        if FormFields[action] then
            self._forms[action] = {
                id = FXLoader:Here(panel, action .. "IdInput"),
                amount = FXLoader:Here(panel, action .. "AmountInput"),
            }
        end
        -- 使用稳定命令名，将操作交给接入层。
        self:TrackConnection(button.Activated:Connect(function()
            self:ExecuteCommand(action)
        end))
    end
    self._freeText = FXLoader:Here(panel, "SetFreeUpgradesBtn.ButtonTxt")
    self._forgeText = FXLoader:Here(panel, "SetGuaranteedForgeBtn.ButtonTxt")
    local close = FXLoader:Here(root, "TitleBox.CloseSurfaceImg")
    -- 关闭窗口不修改测试开关。
    self:TrackConnection(close.Activated:Connect(function()
        self:Hide()
    end))
end

--- 根据完整状态更新开关文案和按钮的点击许可。
--- @param state table 契约中声明的状态。
function View:Render(state)
    for action, button in pairs(self._buttons) do
        self:SetButtonEnabled(button, not state.pending)
    end
    self._freeText.Text = state.freeUpgrades and "开启" or "关闭"
    self._forgeText.Text = state.guaranteedForge and "开启" or "关闭"
end

--- 只在输入有效时派发实际命令。
--- @param action string 命令名。
function View:ExecuteCommand(action)
    local state = self:GetUIState()
    if state.pending then
        return
    end
    local form = self._forms[action]
    if form then
        local field = FormFields[action]
        local id = ReadPositiveInteger(form.id.Text)
        local amount = ReadPositiveInteger(form.amount.Text)
        if field == "quantity" and form.amount.Text:match("^%s*$") then
            amount = 1
        end
        if not id or not amount then
            self:OnInvalidInput(action)
            return
        end
        self:EmitUIAction(action, { id = id, [field] = amount })
    elseif action == "SetFreeUpgrades" then
        self:EmitUIAction(action, { enabled = not state.freeUpgrades })
    elseif action == "SetGuaranteedForge" then
        self:EmitUIAction(action, { enabled = not state.guaranteedForge })
    else
        self:EmitUIAction(action, {})
    end
end

--- 将不合法的输入报告给项目接入。
--- @param action string 输入不合法的命令。
function View:OnInvalidInput(action)
    warn("GM invalid input: " .. action)
end

--- 由项目接入处理权限、真实操作和反馈。
--- @param action string 稳定命令名。
--- @param payload table 契约中声明的参数。
function View:OnUIAction(action, payload)
    error("GM integration must implement OnUIAction")
end

return View
