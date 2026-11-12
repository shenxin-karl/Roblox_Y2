--[[
升级工坊游戏接入契约

职责边界：
  展示层绑定三种固定升级、更新文字与按钮状态、发送 Upgrade 动作。
  游戏接入提供权威状态、资源余额判断、请求防重、扣款与升级结果。
  不覆写 Render，不重复绑定按钮，不在子类修改展示层管理的属性。

Config：无；三行稳定业务 ID 固定为 smelt、forge、income。

State（完整快照，不合并增量）：
  entries: table，可选；省略或缺少单行时，该行不显示状态提示并清空旧值。
    entries[id]: table；id 为 smelt / forge / income，对应固定三行。
      level: number，必填，无默认值，当前整数等级。
      currentValue: string，必填，无默认值，格式化的纯数值效果，如 ×1.20。
      nextValue: string，非满级必填，无默认值，下一级的纯数值效果。
      price: number，非满级必填，无默认值，钞票消耗数量。
      canUpgrade: boolean，必填，无默认值，游戏业务给出的资格。
      maxed: boolean，可选，省略为 false；满级后隐藏箭头、下级数值和价格。
      pending: boolean，可选，省略为 false；请求进行中时禁止点击。

初始化与刷新：
  GetUIState() 继承读取 self.State；RefreshUI() 调用 Render(GetUIState())。
  接入 OnReady 先父 OnReady，再 BindUIData()、Show()。
  异步未就绪时不显示加载提示，可提供 { entries = {} }；后续写入完整快照后 RefreshUI。
  三枚 UpgradeIconImg 为静态图片位，正式资源确认后在设计节点替换；
  不依赖业务状态查询图片，也不把占位图当作业务标识。

展示与交互规则：
  优先级：缺失数据 > maxed > pending > canUpgrade。
  无数据、满级、请求中、资格不足均禁用；仅 canUpgrade 且非 maxed/pending 可点击。
  正常显示亮绿按钮、升级与价格；不可用显示灰绿按钮和对应状态文字。
  canUpgrade=false 在本页面表示钞票不足；其他资格限制须先扩展此契约。
  关闭按钮直接调用 Hide；不取消已发送请求，再次 Show 时刷新最新状态。

动作：
  Upgrade，payload.upgradeId: string，必填；只取 smelt / forge / income。
  游戏接入校验 ID、资格及重复请求，先 pending=true 并刷新，再请求服务端。
  成功使用权威结果更新等级、效果、价格、资格及满级状态；失败保留权威旧值。
  成功或失败都清 pending、重新计算所有行资格并刷新；失败提示由项目通知系统负责。

接口实现清单：
  必须实现：OnUIAction(action: string, payload: table) -> 无返回值。
    点击时由 EmitUIAction 调用；处理上述 Upgrade，不调用报错的父实现。
  生命周期：OnReady() -> 无返回值，必须先父方法，再 BindUIData、Show。
    Ctor(owner: table) -> 无返回值，准备依赖与 State 时先父 Ctor(self, owner)。
    BindUIData() -> 无返回值，需要实时数据时覆写，读取首次状态、刷新并订阅一次。
      无需调用仅刷新一次的父方法；订阅用 TrackConnection/TrackCleanup 托管。
    Dtor() -> 无返回值，仅有未托管资源时覆写，先释放自身资源，再父 Dtor。
  可选覆写：FormatAmount(amount: number) -> string，默认整数格式，无单位后缀。
    Render 调用；只负责纯数字格式，不改节点或资格。
  继承：GetUIState() -> 上述完整 State，GetUIConfig() -> 无业务配置。
    OnShow() -> 无返回值，本页面已实现刷新，不重写。
  仅调用：RefreshUI()、Show()、Hide() -> 无返回值。
    TrackConnection(connection: RBXScriptConnection) -> 同一连接，用于托管订阅。
  内部不得覆盖：Render、EmitUIAction、SetButtonEnabled 及节点与事件绑定。

项目接入步骤：
  1. 在 Generated 外编写继承 CUpgradeWorkshopView 的游戏类；玩家组件创建前
     require 并只挂载游戏子类，项目服务与协议使用已有实现。
  2. 父构造后准备真实数据��赖与完整 State；未就绪提供空 entries，不显示加载提示。
  3. OnReady 先父绑定，再 BindUIData 读取状态、托管一次订阅，最后 Show。
  4. 数据订阅写入完整快照并 RefreshUI；覆盖快照时保留尚未结束的 pending。
  5. Upgrade 请求前防重并刷新 pending，服务端校验资源与升级；结果按上节处理。
  6. Hide 关闭后保留订阅，Show 由继承行为刷新，不重新绑定按钮。
  7. 销毁时取消请求或忽略过期回调，释放未托管资源并调用父 Dtor。

最小完整 State 示例（三行可独立到达）：
  self.State = {
      entries = {
          smelt = {
              level = 3,
              currentValue = "×1.20",
              nextValue = "×1.30",
              price = 100,
              canUpgrade = true,
          },
      },
  }
  缺少的 forge、income 清空数值且不显示状态提示；真实就绪时按相同结构补齐。
]]
local FX = _G.FX
local FXLoader = FX.Loader
local Text = FX.Text
local CUpgradeWorkshopView = FX.Class("CUpgradeWorkshopView", "CUIView")

local TranslationTexts = Text.Define("UpgradeWorkshop", {
    Maxed = "Max level",
    Pending = "Upgrading...",
    Insufficient = "Not enough cash",
})
CUpgradeWorkshopView.BaseViewTranslationTexts = TranslationTexts

local RowNames = {
    smelt = "SmeltRowImg",
    forge = "ForgeRowImg",
    income = "IncomeRowImg",
}

-- 绑定固定三行；每个按钮仅连接一次，动作携带稳定升级 ID。
function CUpgradeWorkshopView:OnReady()
    local root = FXLoader:PlayerGui("UpgradeWorkshopUI")
    self._rows = {}
    for upgradeId, rowName in pairs(RowNames) do
        local row = FXLoader:Here(root, "PopupPanelImg." .. rowName)
        local button = FXLoader:Here(row, "UpgradeBtn")
        self._rows[upgradeId] = {
            button = button,
            buttonText = FXLoader:Here(button, "ButtonTxt"),
            price = FXLoader:Here(row, "PriceTxt"),
            status = FXLoader:Here(button, "StatusTxt"),
            edge = FXLoader:Here(button, "BottomEdgeImg"),
            level = FXLoader:Here(row, "LevelTxt"),
            current = FXLoader:Here(row, "CurrentValueTxt"),
            next = FXLoader:Here(row, "NextValueTxt"),
            arrow = FXLoader:Here(row, "ArrowBox"),
        }
        -- 点击时读取最新状态，禁止过期资格与请求中重复动作。
        self:TrackConnection(button.Activated:Connect(function()
            local state = self:GetUIState()
            local entry = state.entries and state.entries[upgradeId]
            if entry and entry.canUpgrade and not entry.maxed and not entry.pending then
                self:EmitUIAction("Upgrade", { upgradeId = upgradeId })
            end
        end))
    end
    local close = FXLoader:Here(root, "TitleBox.CloseSurfaceImg.CloseBtn")
    -- 关闭统一走基类显隐与动画，不修改根 Enabled。
    self:TrackConnection(close.Activated:Connect(function()
        self:Hide()
    end))
end

-- 重开时刷新完整状态，不重新建立连接。
function CUpgradeWorkshopView:OnShow()
    self:RefreshUI()
end

-- 默认显示整数钞票数量，项目可只覆写数字格式。
-- @param amount number 非负钞票数量
-- @return string 不含货币符号的数字
function CUpgradeWorkshopView:FormatAmount(amount)
    return string.format("%.0f", amount)
end

-- 将完整状态映射为已有设计节点；缺失数据清空旧内容。
-- @param state table 文件头定义的完整 State
function CUpgradeWorkshopView:Render(state)
    for upgradeId, row in pairs(self._rows) do
        local entry = state.entries and state.entries[upgradeId]
        local enabled = entry ~= nil and entry.canUpgrade and not entry.maxed and not entry.pending
        local statusText = ""
        if not entry then
            statusText = ""
        elseif entry.maxed then
            statusText = Text.Tr(TranslationTexts.Maxed)
        elseif entry.pending then
            statusText = Text.Tr(TranslationTexts.Pending)
        elseif not entry.canUpgrade then
            statusText = Text.Tr(TranslationTexts.Insufficient)
        end
        row.current.Text = ""
        row.next.Text = ""
        row.level.Text = ""
        row.price.Text = ""
        row.arrow.Visible = entry ~= nil and not entry.maxed
        if entry then
            row.current.Text = entry.currentValue
            row.level.Text = tostring(entry.level)
            if not entry.maxed then
                row.level.Text = tostring(entry.level) .. " → " .. tostring(entry.level + 1)
                row.next.Text = entry.nextValue
                row.price.Text = "$" .. self:FormatAmount(entry.price)
            end
        end
        row.buttonText.Visible = enabled == true
        row.price.Visible = entry ~= nil and not entry.maxed
        row.status.Text = statusText
        row.status.Visible = statusText ~= ""
        row.button.BackgroundColor3 = Color3.fromHex("#638079")
        row.edge.BackgroundColor3 = Color3.fromHex("#263E36")
        if enabled then
            row.button.BackgroundColor3 = Color3.fromHex("#67ED14")
            row.edge.BackgroundColor3 = Color3.fromHex("#225A07")
        end
        self:SetButtonEnabled(row.button, enabled == true)
    end
end

-- 真实升级动作必须由项目业务实现。
-- @param action string Upgrade
-- @param payload table 含稳定 upgradeId
function CUpgradeWorkshopView:OnUIAction(action, payload)
    error("Upgrade integration must implement OnUIAction")
end

return CUpgradeWorkshopView
