--[[
GM 面板接入契约（仅管理员自用）

【Config / State】
  Config：不读取配置字段，可设置 self.Config = {}。
  State：必填完整表；pending: boolean 可选，省略 false。
    true 禁用全部命令按钮并取消本地重置确认；关闭按钮仍可操作。
  无列表或独立加载态；首次刷新前准备 State，等待请求时用 pending=true。
  面板不读取管理员身份、存档或结果消息，不改写正在输入的 TextBox 文本。

【最小完整数据（接入 Ctor 调用父构造之后）】
  self.Config = {}
  self.State = { pending = false }

【初始化与刷新】
  游戏接入类继承 CGMPanelView。
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
  无其他页面专用必需或可选覆写。每个命令参数如下：
  SetLevel / SetRebirth / SetMoney / SetDiamonds
    -> { value: number, param2: string, param3: string }。
    value 来自参数1，支持科学计数法，例如 1e16。
    SetMoney 接受有限非负整数，超出安全整数范围时遵循 number 浮点精度。
    其他数值命令接受 0..9007199254740991 的安全整数；SetLevel 至少 1。
    单位依次为级、重生次数、金币、钻石。param2/param3 是参数2/3原文，
    空框为 ""；当前这四项业务不消费它们，不将备用框当作玩家 ID。
  AddItem -> { itemId: number, count: number }。
    参数1为道具配置 ID、参数2为数量，均为 1..9007199254740991 的安全整数；
    参数3不发送。服务端验证配置存在后向当前管理员添加道具。
  ResetData -> {}；连续两次点击重置才发送一次。点击其他命令、关闭、
    重新打开或 pending=true 均取消本地确认；不要求接入层再发送确认动作。
  SaveNow -> {}；请求立即持久化当前管理员数据。
  ReachRebirthLevel -> {}；无需输入，由服务端按最新重生次数/配置算门槛，
    将等级升至 max(当前等级, 所需等级)，不执行重生；已达上限则不变。
  UnlockAllCollections -> {}；无需输入，校验权限和图鉴配置后解锁全部图鉴
    并持久化；不发道具，不写背包。
  Close -> {}；View 已取消确认并隐藏底板/标题，接入可处理关闭通知。
  输入无效调用 OnInvalidInput(action:string)->无返回值，可选覆写以显示业务提示，默认 warn。
  ExecuteCommand、CancelReset 与 Render 继承，不在接入层重复校验或覆盖。
  客户端校验不能替代服务端权限和数值校验。
  命令作用于当前管理员本人，目标身份由可信业务层决定，不信任客户端权限。
  请求前 pending=true 并刷新；成功/失败后 pending=false 并刷新；
  实际写入、重置、存档及结果/错误提示均由接入负责，本面板无状态提示文本。

【显隐与输入边界】
  View 当前关闭时直接隐藏底板/标题，OnShow 再恢复，非完整 Show/Hide 动画流程。
  State 无 open 字段，Render 只控制命令按钮及重置确认，不回填输入框。
  静态标签、输入提示和重置确认保留中文；输入原文不翻译。
  ScreenGui 实际名称为 GMPanelUI，不是文档目录名 GMPanel。
]]
local FX = _G.FX
local FXLoader = FX.Loader
local CGMPanelView = FX.Class("CGMPanelView", "CUIView")

-- 一次绑定静态节点和按钮，输入值在点击时读取。
function CGMPanelView:OnReady()
    local root = FXLoader:PlayerGui("GMPanelUI")
    self.Panel = FXLoader:Here(root, "PopupPanelImg")
    self.Title = FXLoader:Here(root, "TitleBox")
    self.Inputs = {}
    self.Buttons = {}
    self.ResetArmed = false
    for index = 1, 3 do
        self.Inputs[index] = FXLoader:Here(root, "PopupPanelImg.Param" .. index .. "Input")
    end
    local actions = { "SetLevel", "SetRebirth", "SetMoney", "SetDiamonds", "ResetData", "SaveNow", "AddItem", "ReachRebirthLevel", "UnlockAllCollections" }
    for index, action in ipairs(actions) do
        local button = FXLoader:Here(root, "PopupPanelImg." .. action .. "Btn")
        self.Buttons[action] = button
        -- 绑定稳定命令名，不按显示文字判断动作。
        self:TrackConnection(button.Activated:Connect(function()
            self:ExecuteCommand(action)
        end))
    end
    self.ResetTxt = FXLoader:Here(root, "PopupPanelImg.ResetDataBtn.ButtonTxt")
    local close = FXLoader:Here(root, "TitleBox.CloseSurfaceImg")
    -- 关闭隐藏当前面板，并取消尚未执行的重置确认。
    self:TrackConnection(close.Activated:Connect(function()
        self:CancelReset()
        self.Panel.Visible = false
        self.Title.Visible = false
        self:EmitUIAction("Close", {})
    end))
end

-- 每次打开用最新完整状态刷新。
function CGMPanelView:OnShow()
    self.Panel.Visible = true
    self.Title.Visible = true
    self:CancelReset()
    self:RefreshUI()
end

-- 清除本地二次确认，不改业务状态。
function CGMPanelView:CancelReset()
    self.ResetArmed = false
    self.ResetTxt.Text = "重置数据"
end

-- 校验输入后发送命令；仅金钱允许超出安全整数范围，重置需要连续两次点击。
-- @param action string 契约中声明的稳定命令名
function CGMPanelView:ExecuteCommand(action)
    if self:GetUIState().pending then
        return
    end
    if action == "ResetData" then
        if not self.ResetArmed then
            self.ResetArmed = true
            self.ResetTxt.Text = "确认重置"
            return
        end
        self:CancelReset()
        self:EmitUIAction(action, {})
        return
    end
    self:CancelReset()
    if action == "SaveNow" or action == "ReachRebirthLevel" or action == "UnlockAllCollections" then
        self:EmitUIAction(action, {})
        return
    end
    if action == "AddItem" then
        local itemId = tonumber(self.Inputs[1].Text)
        local count = tonumber(self.Inputs[2].Text)
        if not itemId or itemId ~= itemId or itemId < 1 or itemId > 9007199254740991 or itemId % 1 ~= 0 then
            self:OnInvalidInput(action)
            return
        end
        if not count or count ~= count or count < 1 or count > 9007199254740991 or count % 1 ~= 0 then
            self:OnInvalidInput(action)
            return
        end
        self:EmitUIAction(action, { itemId = itemId, count = count })
        return
    end
    local value = tonumber(self.Inputs[1].Text)
    if not value or value ~= value or value < 0 or value == math.huge or value % 1 ~= 0
        or (action ~= "SetMoney" and value > 9007199254740991) then
        self:OnInvalidInput(action)
        return
    end
    if action == "SetLevel" and value < 1 then
        self:OnInvalidInput(action)
        return
    end
    self:EmitUIAction(action, {
        value = value,
        param2 = self.Inputs[2].Text,
        param3 = self.Inputs[3].Text,
    })
end

-- 非法输入交给接入层提示，不改变确认流程或业务状态。
-- @param action string 参数不合法的稳定动作名。
function CGMPanelView:OnInvalidInput(action)
    warn("GM invalid input: " .. action)
end

-- 渲染完整业务状态，保留正在输入的参数。
-- @param state table pending，字段缺省规则见文件头
function CGMPanelView:Render(state)
    for action, button in pairs(self.Buttons) do
        self:SetButtonEnabled(button, not state.pending)
    end
    if state.pending then
        self:CancelReset()
    end
end

-- 由游戏接入覆写本方法。
-- @param action string 稳定命令名
-- @param payload table 对应命令参数，见文件头
function CGMPanelView:OnUIAction(action, payload)
    error("GM integration must implement OnUIAction")
end

return CGMPanelView
