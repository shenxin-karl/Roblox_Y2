--[[
光环商店接入契约

【Config：完整配置】
  title: string，必填，无默认值；标题原文，经 Text.TrSource 查询。
  qualities: {[qualityId: string]: Quality}，必填；品质 ID 由项目定义。
    Quality.color: string，必填，无默认值；#RRGGBB 渐变起色。
    Quality.colorEnd: string，可选；省略使用 color，作为竖向渐变终色。
  auras: {Item}，必填连续数组；数组顺序即显示顺序，空列表传 {}。
    Item.id: string，必填，无默认值；全列表唯一且稳定的光环配置 ID。
    Item.name: string，必填，无默认值；名称原文，经 Text.TrSource 查询。
    Item.qualityId: string，必填，无默认值；必须对应 qualities 中存在的键。
    Item.strength: number，必填，无默认值；力量加成点数，不是倍率。
    Item.price: number，必填，无默认值；非负金币数量，展示为钱图标与金额。
    Item.icon: string，可选；Roblox Image 资源地址。
      省略时使用问号 rbxassetid://86795093617566；
      当前代码对 "" 直接赋空图，不回退问号。需要占位时省略此字段。

【State：Render 的完整输入】
  open: boolean，必填，无默认值；当前实现控制内容底板及标题 Visible。
  owned: {[auraId: string]: boolean}，必填字典；键对应 Item.id，
    缺失键或 false 表示未拥有，true 表示已拥有；无已拥有项传 {}。
  equippedId: string，必填，无默认值；已装备的 Item.id；未装备传 ""。
    非空 ID 应属于 owned 中为 true 的配置项，View 不校验此业务一致性。
  coins: number，必填，无默认值；可用金币余额，非负。
  pending: {[auraId: string]: boolean}，可选；表省略或键缺失均视为无请求；
    true 禁用对应条目的购买/装备按钮，不锁住其他条目。
  loading: boolean，可选，省略 false；true 清理显示条目并显示 Loading...。
    加载时仍提供所有必填字段，可使用空配置数组和空 owned。
  不消费 error 字段；失败提示由接入层处理。

【最小完整数据（接入 Ctor 调用父构造之后）】
  self.Config = {
      title = "AURAS",
      qualities = { common = { color = "#A5ADB8" } },
      auras = {
          { id = "calm", name = "Calm Aura", qualityId = "common",
            strength = 1, price = 0 },
      },
  }
  self.State = { open = true, owned = { calm = true },
      equippedId = "calm", coins = 700 }

【初始化与刷新】
  游戏接入类继承 CAuraShopView。
  接入 Ctor(owner) 先调用自身类的 Super.Ctor(self, owner)，再准备下例数据。
  接入 OnReady() 先调用自身类的 Super.OnReady(self)，再依次
  self:BindUIData()、self:Show()；父 OnReady 负责绑定节点，OnShow 会刷新。
  GetUIConfig() 默认返回 self.Config；GetUIState() 默认返回 self.State。
  RefreshUI() 调用 Render(GetUIState())，输入是完整快照，不合并增量，
  不自动补齐业务字段。可修改已有表或替换整表，但每次刷新须满足完整契约。
  后续先更新 Config/State，再 self:RefreshUI()；异步未就绪按本页规则处理。
  无需覆写 Render 或手动重复调用 OnReady；业务类覆写生命周期时须保留父调用。

【动作与覆写】
  必需覆写 OnUIAction(action: string, payload: table)，无返回值；
  默认实现报错。页面专用可选格式化接口见下文。
  Buy   -> { auraId: string }，未拥有时发出，值为当前 Item.id。
  Equip -> { auraId: string }，已拥有但未装备时发出，值为当前 Item.id。
  Close -> {}，由接入层处理关闭。
  Config.strengthIsMultiplier: boolean?，true 展示力量倍率，否则力量点数。
  Config.allowUnaffordableAction: boolean?，true 时余额不足保持灰色但允许点击提示。
  Config.allowUnequip: boolean?，true 时已装备显示卸下且发送 Equip（原 auraId）。
  State.busy: boolean?，全局请求锁；pending[id] 的等待文案优先于已装备状态。
  FormatNumber(value:number)->string 可选覆写，默认 tostring；接入统一数量工具。
  FormatPrice(value:number)->string 可选覆写，仅格式化购买价格；
  默认调用 self:FormatNumber(value)，不改变力量或倍率格式；Render 刷新时调用。
  value 为原始价格，返回展示字符串；覆写时无需调用 Super，不修改原始数据。
  仅覆盖 OnUIAction 与上述格式化接口；禁止覆写 Render 或重绑条目事件。
  请求前设置 pending[id] = true 并刷新；成功后用真实结果更新
  owned/equippedId/coins，失败保留真实状态；两者均清除 pending[id] 并刷新。
  服务端重新校验 ID、所有权、价格与余额；客户端按钮禁用不构成业务校验。

【列表、显隐与资源边界】
  隐藏 Templates 原型按 Item.id 克隆、复用和清理；空数组显示空列表提示。
  loading=false 后按最新配置重建缺失条目；运行副本不写回设计节点。
  当前 Render 直接设置底板/标题 Visible，并非仅由 Show/Hide 管理；
  关闭后重新 Show 前须将 open=true。此为现有实现限制，不保证整页关闭动画。
  动态图槽为 AuraIconImg，真实贴图由配置 icon 提供；
  本地预览不证明 Roblox 资源权限或设备显示通过。
]]
local FX = _G.FX
local FXLoader = FX.Loader
local Text = FXLoader:RequireShared("Scripts.Framework.Shared.Core.FXText")
local CAuraShopView = FX.Class("CAuraShopView", "CUIView")

local TranslationTexts = Text.Define("AuraShopUI", {
    Strength = "Strength +{strength}",
    Price = "{price}",
    Equip = "Equip",
    Equipped = "Equipped",
    Waiting = "Waiting...",
    NoAuras = "No auras available",
    Loading = "Loading...",
    TrainingRate = "Strength ×{rate}",
    Unequip = "Unequip",
})

-- 暴露只读文案定义，供接入子类通过 self.BaseViewTranslationTexts 复用。
CAuraShopView.BaseViewTranslationTexts = TranslationTexts

-- 接入项目统一数量格式，保留计算用的原始数值。
-- @param value number 原始数量。
-- @return string 展示数量。
function CAuraShopView:FormatNumber(value)
    return tostring(value)
end

-- 价格可独立指定精度，默认沿用数量格式以兼容现有接入。
-- @param value number 未格式化的价格。
-- @return string 展示价格。
function CAuraShopView:FormatPrice(value)
    return self:FormatNumber(value)
end

-- 绑定窗口与隐藏原型，只在首次准备时连接关闭按钮。
function CAuraShopView:OnReady()
    local root = FXLoader:PlayerGui("AuraShopUI")
    self.Root = root
    self.Panel = FXLoader:Here(root, "PopupPanelImg")
    self.TitleBox = FXLoader:Here(root, "TitleBox")
    self.TitleTxt = FXLoader:Here(root, "TitleBox.TitleTxt")
    self.List = FXLoader:Here(root, "PopupPanelImg.AuraListBox")
    self.EmptyTxt = FXLoader:Here(root, "PopupPanelImg.EmptyTxt")
    self.Template = FXLoader:Here(root, "Templates.AuraRowImg")
    self.Rows = {}
    local closeBtn = FXLoader:Here(root, "TitleBox.CloseSurfaceImg")
    self:TrackConnection(closeBtn.Activated:Connect(function()
        self:EmitUIAction("Close", {})
    end))
end

-- 打开时应用当前完整数据。
function CAuraShopView:OnShow()
    self:RefreshUI()
end

-- 根据稳定 ID 增删和更新条目，颜色始终从品质配置读取。
-- @param state table 完整状态，字段见文件头。
function CAuraShopView:Render(state)
    local config = self:GetUIConfig()
    self.Panel.Visible = state.open
    self.TitleBox.Visible = state.open
    self.TitleTxt.Text = Text.TrSource(config.title)
    local active = {}
    local count = 0
    if not state.loading then
        for index, aura in ipairs(config.auras) do
            count = index
            active[aura.id] = true
            local entry = self.Rows[aura.id]
            if not entry then
                local row = self.Template:Clone()
                row.Name = "Aura_" .. aura.id
                row.Parent = self.List
                row.Visible = true
                local button = FXLoader:Here(row, "ActionBtn")
                local auraId = aura.id
                -- 每个实例只连接一次；点击时读取当前状态，以稳定 ID 发出动作。
                local connection = self:TrackConnection(button.Activated:Connect(function()
                    local currentState = self:GetUIState()
                    local action = "Buy"
                    if currentState.owned[auraId] then
                        action = "Equip"
                    end
                    self:EmitUIAction(action, {auraId = auraId})
                end))
                local release = self:TrackCleanup(function()
                    connection:Disconnect()
                    row:Destroy()
                end)
                entry = {row = row, button = button, release = release}
                self.Rows[aura.id] = entry
            end
            local row = entry.row
            local quality = config.qualities[aura.qualityId]
            row.Position = UDim2.fromOffset(1, (index - 1) * 112 + 1)
            row.BackgroundColor3 = Color3.fromHex("#FFFFFF")
            local startColor = Color3.fromHex(quality.color)
            local endColor = Color3.fromHex(quality.colorEnd or quality.color)
            local gradient = FXLoader:Here(row, "QualityGradient")
            local studGradient = FXLoader:Here(row, "StudTileImg.QualityGradient")
            -- Roblox 使用原生色序列；App 预览仅支持起止色属性。
            if ColorSequence then
                local colors = ColorSequence.new(startColor, endColor)
                gradient.Color = colors
                studGradient.Color = colors
            else
                gradient.ColorStart = startColor
                gradient.ColorEnd = endColor
                studGradient.ColorStart = startColor
                studGradient.ColorEnd = endColor
            end
            FXLoader:Here(row, "NameTxt").Text = Text.TrSource(aura.name)
            local strengthTxt = FXLoader:Here(row, "StrengthTxt")
            strengthTxt.Text = Text.Tr(TranslationTexts.Strength, {
                strength = self:FormatNumber(aura.strength),
            })
            if config.strengthIsMultiplier then
                strengthTxt.Text = Text.Tr(TranslationTexts.TrainingRate, {rate = self:FormatNumber(aura.strength)})
            end
            local icon = FXLoader:Here(row, "AuraIconImg")
            icon.Image = aura.icon or "rbxassetid://86795093617566"
            local owned = state.owned[aura.id] == true
            local equipped = state.equippedId == aura.id
            local pending = state.pending and state.pending[aura.id]
            local caption = Text.Tr(TranslationTexts.Price, {
                price = self:FormatPrice(aura.price),
            })
            local color = "#67ED14"
            local edge = "#225A07"
            if owned then
                caption = Text.Tr(TranslationTexts.Equip)
            end
            if pending then
                caption = Text.Tr(TranslationTexts.Waiting)
                color = "#638079"
            elseif equipped then
                caption = Text.Tr(TranslationTexts.Equipped)
                color = "#397BA7"
                edge = "#193E73"
                if config.allowUnequip then
                    caption = Text.Tr(TranslationTexts.Unequip)
                    color = "#F2654D"
                    edge = "#7D2519"
                end
            elseif not owned and state.coins < aura.price then
                color = "#638079"
            end
            FXLoader:Here(row, "OwnedTxt").Visible = false
            local showMoney = not owned and not equipped and not pending
            FXLoader:Here(row, "ActionBtn.MoneyIconImg").Visible = showMoney
            local buttonText = FXLoader:Here(row, "ActionBtn.ButtonTxt")
            buttonText.Text = caption
            buttonText.TextSize = 19
            local buttonTextStroke = FXLoader:Here(buttonText, "TextStroke")
            buttonTextStroke.Thickness = 1.3
            -- 使用固定字号，避免短状态文案自动放大撑满按钮。
            buttonText.Position = UDim2.fromOffset(0, 0)
            buttonText.Size = UDim2.fromScale(1, 1)
            buttonText.TextXAlignment = Enum.TextXAlignment.Center
            if showMoney then
                buttonText.TextSize = 22
                buttonTextStroke.Thickness = 1.6
                buttonText.Position = UDim2.fromOffset(42, 0)
                buttonText.Size = UDim2.new(1, -47, 1, 0)
                buttonText.TextXAlignment = Enum.TextXAlignment.Left
            end
            FXLoader:Here(row, "ActionBtn.BottomEdgeImg").BackgroundColor3 = Color3.fromHex(edge)
            entry.button.BackgroundColor3 = Color3.fromHex(color)
            self:SetButtonEnabled(entry.button, not state.busy and not pending
                and (not equipped or config.allowUnequip == true)
                and (owned or state.coins >= aura.price or config.allowUnaffordableAction == true))
        end
    end
    for auraId, entry in pairs(self.Rows) do
        if not active[auraId] then
            entry.release()
            self.Rows[auraId] = nil
        end
    end
    self.List.CanvasSize = UDim2.fromOffset(0, math.max(341, count * 112))
    self.EmptyTxt.Visible = count == 0
    self.EmptyTxt.Text = Text.Tr(TranslationTexts.NoAuras)
    if state.loading then
        self.EmptyTxt.Text = Text.Tr(TranslationTexts.Loading)
    end
end

-- 必须由游戏接入处理业务动作。
-- @param action string Buy、Equip 或 Close。
-- @param payload table auraId 或空表。
function CAuraShopView:OnUIAction(action, payload)
    error("Aura shop integration must implement OnUIAction")
end

return CAuraShopView
