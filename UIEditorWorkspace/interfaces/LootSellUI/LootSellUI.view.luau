--[[
背包整体出售接入契约

【Config：完整配置】
  capacity: number，必填，无默认值；正整数背包条目容量，不固定为示例的 12。
  doubleSaleGemCost: number，必填，无默认值；非负，单次钻石双倍出售的钻石费用。
  qualities: {[qualityId: string]: string}，必填；品质 ID 到 #RRGGBB 颜色，
    每个 State.items[].qualityId 都须有键，不硬编码品质枚举。
  qualityGradientEnds: {[qualityId: string]: string}，可选；#RRGGBB 渐变终色，
    表或键省略时使用 GetItemQualityColor(item) 的起色，不沿用旧条目颜色。

【State：Render 的完整输入】
  isOpen: boolean，必填，无默认值；当前实现控制底板/标题及二级菜单显隐。
  items: {Item}，必填连续数组；当前拥有的实例，数组顺序即显示/提交顺序。
    Item.id: string，必填，无默认值；全列表唯一稳定的背包实例 ID，
      不是道具配置 ID、名称或数组下标；同名道具可有不同实例 ID。
    Item.name: string，必填，无默认值；显示名称原文，经 Text.TrSource 查询。
    Item.qualityId: string，必填，无默认值；对应 Config.qualities 的键。
    Item.value: number，必填，无默认值；非负，此实例的基础出售金币金额。
  pending: boolean，可选，省略 false；禁用出售，不禁用普通列表的关闭。
  doubleSaleCards: number，可选，省略 0；非负整数，双倍卡数量。
  gems: number，可选，省略 0；非负钻石余额。
  isVip: boolean，可选，省略 false；是否具备 VIP 双倍资格。
  message: string，可选，省略 nil；提示原文，经 Text.TrSource 查询。
  soldAmount: number，可选，省略 nil；最近实际出售所得金币，0 也是有效结果，
    存在时优先于 message 显示出售结果；新请求须清空两者。
  空背包 items={}；无结果和 message 时显示 No items to sell。
  message="" 会留下空提示而非空背包提示；需要默认提示时用 nil。
  无独立 loading 字段；加载时可提供 items={}、pending=true、
  message="Loading items..."，其他必填数据仍须齐全。

【最小完整数据（接入 Ctor 调用父构造之后）】
  self.Config = {
      capacity = 12, doubleSaleGemCost = 40,
      qualities = { common = "#A5ADB8" },
  }
  self.State = {
      isOpen = true,
      items = {
          { id = "scroll_001", name = "Ancient Scroll",
            qualityId = "common", value = 18200000 },
      },
  }

【初始化与刷新】
  游戏接入类继承 CLootSellView。
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
  Sell -> { entryIds: {string}, multiplier: number, method: string? }。
    entryIds 是当前全部 items[].id 的连续数组，不支持仅出售选择项；
    普通出售 multiplier=1，省略 method，即使 VIP 也不自动翻倍。
    method="Card"：消耗双倍卡；非 VIP multiplier=2，VIP multiplier=4。
    method="Gems"：支付 Config.doubleSaleGemCost；非 VIP 为 2，VIP 为 4。
    method="Vip"：要求 isVip=true，multiplier 固定为 2。
    只允许上述组合，method 为 nil 时不是双倍出售。
  Close -> {}；由接入层设置 isOpen=false 并刷新。
  可选覆写 GetItemQualityColor(item: Item) -> Color3；
    默认从 qualities[item.qualityId] 转 Color3，缺失明确报错。
    返回色用于条目渐变起色、图标底色、描边及色条，不修改物品数据。
  Item.nameText:string? 最终译文，优先 name 原文；Item.icon:string? 动态真实贴图。
  FormatNumber(value:number)->string 可选覆写，默认 tostring，数量计算不使用译文。
  Config.allowEmptyAction:boolean?，保留兼容字段；空包禁用出售，不发送 Empty。
  Config.allowVipPurchase:boolean?，true 未具备VIP点击发送 PurchaseVip->{}，不发送Sell。
  Render / ConfirmDoubleSale 继承，项目不再改写展示或重新绑定按钮。
  请求前 pending=true、message=nil、soldAmount=nil 并刷新；服务端重查
  entryIds 的归属/库存、价格、卡券、钻石和 VIP 资格，重新计算实际所得。
  成功同步 items、卡券/余额及 soldAmount；失败保留最新库存并填写 message；
  两者均 pending=false 并刷新。不信任客户端 multiplier，不由 View 发金币。

【局部菜单、列表与资源边界】
  双倍按钮仅打开本地 DoubleSaleBox，不发动作；选择方式后才发送 Sell；
  返回按钮只关闭菜单。菜单打开时禁用底层出售，主窗口关闭保持可用。
  isOpen=false 或 items 为空会关闭菜单；菜单状态不是 State 字段。
  Templates.LootTemplateImg 按实例 ID 复用/排序/清理；每条占一容量，
  不合并同名物品；满容量仅改变统计颜色，不负责拦截背包写入。
  总价为所有 value 之和，展示钱图标与金额，格式由 FormatNumber 决定，
  不截断实际提交值或业务金额。
  所有条目图标沿用模板问号，没有消费 Item.icon 的动态图片接口。
  当前 Render 直接设置底板/标题 Visible，并非完整 Show/Hide 动画流程；
  再次 Show 前须恢复 isOpen=true。本次仅说明现有行为。
]]
local FX = _G.FX
local FXLoader = FX.Loader
local Text = FXLoader:RequireShared("Scripts/Game/Shared/Text")
local CLootSellView = FX.Class("CLootSellView", "CUIView")

local TranslationTexts = Text.Define("LootSellUI", {
    Capacity = "{count:int}/{capacity:int}",
    NoItems = "No items to sell",
    Coins = "{amount}",
    Sold = "{amount} Sold!",
})

-- 暴露只读文案定义，供接入子类通过 self.BaseViewTranslationTexts 复用。
CLootSellView.BaseViewTranslationTexts = TranslationTexts

-- 将金币金额格式化为参考图的短文案。
-- @param amount number 金币数量
-- @return string 金币展示文本
function CLootSellView:FormatCoins(amount)
    return Text.Tr(TranslationTexts.Coins, {
        amount = self:FormatNumber(amount),
    })
end

-- 统一数值展示扩展点，原始金额仍用于计算与请求。
-- @param value number 原始数量。
-- @return string 展示数量。
function CLootSellView:FormatNumber(value)
    return tostring(value)
end

-- 绑定静态节点，事件只连接一次。
function CLootSellView:OnReady()
    local root = FXLoader:PlayerGui("LootSellUI")
    self.Panel = FXLoader:Here(root, "PopupPanelImg")
    self.Title = FXLoader:Here(root, "TitleBox")
    self.Total = FXLoader:Here(root, "PopupPanelImg.TotalImg.TotalValueTxt")
    self.List = FXLoader:Here(root, "PopupPanelImg.LootListBox")
    self.Template = FXLoader:Here(root, "Templates.LootTemplateImg")
    self.CapacityTxt = FXLoader:Here(root, "PopupPanelImg.CapacityTxt")
    self.Rows = {}
    self.List.CanvasPosition = Vector2.new(0, 0)
    self.StatusTxt = FXLoader:Here(root, "PopupPanelImg.StatusTxt")
    self.StatusMoneyIcon = FXLoader:Here(root, "PopupPanelImg.StatusMoneyIconImg")
    self.SellAllBtn = FXLoader:Here(root, "PopupPanelImg.TotalImg.SellAllBtn")
    self.SellDoubleBtn = FXLoader:Here(root, "PopupPanelImg.TotalImg.SellDoubleBtn")
    self.DoubleSaleBox = FXLoader:Here(root, "DoubleSaleBox")
    self.CardBtn = FXLoader:Here(root, "DoubleSaleBox.PopupPanelImg.CardBtn")
    self.GemsBtn = FXLoader:Here(root, "DoubleSaleBox.PopupPanelImg.GemsBtn")
    self.VipBtn = FXLoader:Here(root, "DoubleSaleBox.PopupPanelImg.VipBtn")
    self.GemsPriceTxt = FXLoader:Here(root, "DoubleSaleBox.PopupPanelImg.GemsBtn.ButtonTxt")
    self.DoubleSaleOpen = false
    local backBtn = FXLoader:Here(root, "DoubleSaleBox.TitleBox.CloseSurfaceImg.CloseBtn")
    -- 二级菜单关闭只返回列表，不提交出售。
    self:TrackConnection(backBtn.Activated:Connect(function()
        self.DoubleSaleOpen = false
        self:RefreshUI()
    end))
    self:TrackConnection(self.CardBtn.Activated:Connect(function()
        self:ConfirmDoubleSale("Card")
    end))
    self:TrackConnection(self.GemsBtn.Activated:Connect(function()
        self:ConfirmDoubleSale("Gems")
    end))
    self:TrackConnection(self.VipBtn.Activated:Connect(function()
        self:ConfirmDoubleSale("Vip")
    end))
    self.CloseBtn = FXLoader:Here(root, "TitleBox.CloseSurfaceImg")
    -- 点击时发送当前配置中的稳定 ID。
    self:TrackConnection(self.SellAllBtn.Activated:Connect(function()
        local state = self:GetUIState()
        if not state.isOpen or state.pending or #state.items == 0 or self.DoubleSaleOpen then
            return
        end
        self:EmitUIAction("Sell", {entryIds = self:GetEntryIds(), multiplier = 1})
    end))
    self:TrackConnection(self.SellDoubleBtn.Activated:Connect(function()
        local state = self:GetUIState()
        if not state.isOpen or state.pending or #state.items == 0 or self.DoubleSaleOpen then
            return
        end
        self.DoubleSaleOpen = true
        self:RefreshUI()
    end))
    self:TrackConnection(self.CloseBtn.Activated:Connect(function()
        self:EmitUIAction("Close", {})
    end))
end

-- 选定出售方式后提交稳定条目 ID；扣费和资格校验由接入层负责。
-- @param method string Card / Gems / Vip
function CLootSellView:ConfirmDoubleSale(method)
    local state = self:GetUIState()
    if not state.isOpen or not self.DoubleSaleOpen or state.pending or #state.items == 0 then
        return
    end
    if method == "Card" and (state.doubleSaleCards or 0) < 1 then
        return
    elseif method == "Gems" and (state.gems or 0) < self:GetUIConfig().doubleSaleGemCost then
        return
    elseif method == "Vip" and not state.isVip then
        if self:GetUIConfig().allowVipPurchase then
            self:EmitUIAction("PurchaseVip", {})
        end
        return
    end
    local multiplier = 2
    if state.isVip and method ~= "Vip" then
        multiplier = 4
    end
    self.DoubleSaleOpen = false
    self:EmitUIAction("Sell", {entryIds = self:GetEntryIds(), multiplier = multiplier, method = method})
    self:RefreshUI()
end

-- 打开时刷新最新数据。
function CLootSellView:OnShow()
    self:RefreshUI()
end

-- 发送当前背包条目的稳定身份，不使用名称或列表位置。
-- @return table 稳定条目 ID 数组
function CLootSellView:GetEntryIds()
    local ids = {}
    for index, item in ipairs(self:GetUIState().items) do
        table.insert(ids, item.id)
    end
    return ids
end

-- 从游戏提供的品质映射获取每个道具的颜色，可由接入层覆写。
-- @param item table 当前道具，含 qualityId
-- @return Color3 此道具的品质颜色
function CLootSellView:GetItemQualityColor(item)
    local color = self:GetUIConfig().qualities[item.qualityId]
    assert(color, "Missing quality color: " .. tostring(item.qualityId))
    return Color3.fromHex(color)
end

-- 按稳定 ID 更新条目，只创建新增条目并清理已移除条目。
-- @param state table 完整列表状态，见文件头
function CLootSellView:Render(state)
    if not state.isOpen or #state.items == 0 then
        self.DoubleSaleOpen = false
    end
    self.Panel.Visible = state.isOpen
    self.Title.Visible = state.isOpen
    self.DoubleSaleBox.Visible = state.isOpen and self.DoubleSaleOpen
    self.GemsPriceTxt.Text = self:FormatNumber(self:GetUIConfig().doubleSaleGemCost)
    local canSell = #state.items > 0 and not state.pending
    self:SetButtonEnabled(self.CardBtn, canSell and (state.doubleSaleCards or 0) > 0)
    self:SetButtonEnabled(self.GemsBtn, canSell and (state.gems or 0) >= self:GetUIConfig().doubleSaleGemCost)
    self:SetButtonEnabled(self.VipBtn, canSell and (state.isVip == true or self:GetUIConfig().allowVipPurchase == true))
    local present = {}
    local total = 0
    for index, item in ipairs(state.items) do
        present[item.id] = true
        total = total + item.value
        local record = self.Rows[item.id]
        if not record then
            local row = self.Template:Clone()
            row.Name = "OwnedItem" .. index .. "Img"
            row.Parent = self.List
            row.Visible = true
            record = {
                node = row,
                name = FXLoader:Here(row, "LootNameTxt"),
                value = FXLoader:Here(row, "LootValueTxt"),
                icon = FXLoader:Here(row, "LootIconImg"),
                stripe = FXLoader:Here(row, "QualityStripeImg"),
                border = FXLoader:Here(row, "LootIconImg.UIStroke"),
                gradient = FXLoader:Here(row, "QualityGradient"),
                studGradient = FXLoader:Here(row, "StudTileImg.QualityGradient"),
                iconBackground = FXLoader:Here(row, "LootIconBackgroundImg"),
            }
            -- 此清理函数仅拥有本次克隆的行。
            record.release = self:TrackCleanup(function()
                row:Destroy()
            end)
            self.Rows[item.id] = record
        end
        record.node.Position = UDim2.fromOffset(1, 1 + (index - 1) * 73)
        record.name.Text = item.nameText or Text.TrSource(item.name)
        record.value.Text = self:FormatCoins(item.value)
        record.icon.Image = item.icon or "rbxassetid://86795093617566"
        local qualityColor = self:GetItemQualityColor(item)
        local gradientEnds = self:GetUIConfig().qualityGradientEnds
        local endColor = qualityColor
        if gradientEnds and gradientEnds[item.qualityId] then
            endColor = Color3.fromHex(gradientEnds[item.qualityId])
        end
        -- Roblox 使用原生色序列；App 预览仅支持起止色属性。
        if ColorSequence then
            local colors = ColorSequence.new(qualityColor, endColor)
            record.gradient.Color = colors
            record.studGradient.Color = colors
        else
            record.gradient.ColorStart = qualityColor
            record.gradient.ColorEnd = endColor
            record.studGradient.ColorStart = qualityColor
            record.studGradient.ColorEnd = endColor
        end
        record.iconBackground.BackgroundColor3 = qualityColor
        record.icon.BackgroundColor3 = qualityColor
        record.stripe.BackgroundColor3 = qualityColor
        record.border.Color = qualityColor
    end
    for id, record in pairs(self.Rows) do
        if not present[id] then
            record.release()
            self.Rows[id] = nil
        end
    end
    local count = #state.items
    local canvasHeight = math.max(164, count * 73 - 5)
    self.List.CanvasSize = UDim2.fromOffset(534, canvasHeight)
    self.List.CanvasPosition = Vector2.new(0, math.min(self.List.CanvasPosition.Y, canvasHeight - 164))
    self.Total.Text = self:FormatCoins(total)
    self.CapacityTxt.Text = Text.Tr(TranslationTexts.Capacity, {
        count = count,
        capacity = self:GetUIConfig().capacity,
    })
    self.CapacityTxt.TextColor3 = Color3.fromHex("#FFFFFF")
    if count >= self:GetUIConfig().capacity then
        self.CapacityTxt.TextColor3 = Color3.fromHex("#FFD34F")
    end
    self.StatusTxt.Text = Text.TrSource(state.message or "")
    self.StatusMoneyIcon.Visible = state.soldAmount ~= nil
    if state.soldAmount ~= nil then
        self.StatusTxt.Text = Text.Tr(TranslationTexts.Sold, {
            amount = self:FormatNumber(state.soldAmount),
        })
    elseif count == 0 and not state.message then
        self.StatusTxt.Text = Text.Tr(TranslationTexts.NoItems)
    end
    self:SetButtonEnabled(self.SellAllBtn, canSell and not self.DoubleSaleOpen)
    self:SetButtonEnabled(self.SellDoubleBtn, canSell and not self.DoubleSaleOpen)
    self:SetButtonEnabled(self.CloseBtn, true)
end

-- 业务接入必须处理出售和关闭。
-- @param action string Sell 或 Close
-- @param payload table 动作参数见文件头
function CLootSellView:OnUIAction(action, payload)
    error("Loot sell integration must implement OnUIAction")
end

return CLootSellView
