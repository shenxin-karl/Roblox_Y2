--[[
双货币商店接入契约

【Config：完整配置】
  products: {Product}，必填连续数组；可为空 {}，过滤后仍保留配置顺序。
    Product.id: string，必填，无默认值；全列表唯一、稳定的商品配置 ID。
    Product.currency: "Diamond" | "Robux"，必填，无默认值；商品所属页签。
    Product.title: string，必填，无默认值；商品标题原文。
    Product.description: string，必填，无默认值；商品描述原文。
    Product.price: number，必填，无默认值；非负，对应 currency 的货币数量。
    Product.icon: string，可选；Roblox Image 资源地址；省略或 "" 赋空图。
      当前 View 没有显式���置问号回退，是否有占位取决于设计原型。
    Product.cardStyle: "Green" | "Gold" | "Cyan" | "Orange" | "Purple" | "Pink"，
      可选；省略时 Diamond 使用 Green、Robux 使用 Gold。
      其他值不支持，查找原型会失败；卡片渐变、文字、按钮取设计原型。
  旧 cardColor 字段不再消费，不用它覆盖底色。

【State：Render 的完整输入】
  tab: "Diamond" | "Robux"，必填，无默认值；当前显示商品分组。
  open: boolean，必填，无默认值；当前实现直接赋给 ScreenGui.Enabled。
  pending: {[productId: string]: boolean}，可选；键对应 Product.id。
    表省略或键缺失视为无请求，true 仅禁用该商品购买，不禁用页签或关闭。
  不读取余额、购买结果或 error；无售罄状态，不按余额禁用购买。
  没有独立加载态；异步可先提供 products={}，空分组仅显示空列表。

【最小完整数据（接入 Ctor 调用父构造之后）】
  self.Config = {
      products = {
          { id = "speed", currency = "Diamond", title = "Speed Potion",
            description = "Boost your movement speed", price = 100 },
      },
  }
  self.State = { tab = "Diamond", open = true }

【初始化与刷新】
  游戏接入类继承 CCurrencyShopView。
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
  SelectTab -> { tab: "Diamond" | "Robux" }；接入层更新 State.tab 并刷新；
    View 不自行切换业务状态。若需切页回顶部，接入层可重置 List.CanvasPosition。
  Purchase -> { productId: string, currency: "Diamond" | "Robux" }；
    productId 对应 Product.id，currency 为该配置货币，不含价格或平台商品 ID。
  Close -> {}；接入层更新 open=false 并刷新。
  FormatNumber(value:number)->string 可选覆写，默认 tostring，仅格式化价格。
  Product.titleText / descriptionText: string? 已翻译组合文案，优先于对应原文字段。
  Product.unavailable / soldOut: boolean?，分别显示不可用/售罄并禁用。
  Product.allowSoldOutAction: boolean?，true 售罄仍允许点击解释原因。
  State.busy:boolean? 全局禁用购买；pending[id] 显示等待。
  Render / CreateCard / EmitUIAction 继承，不重复展示或绑定事件。
  业务通过 productId 查询真实价格与平台购买标识，校验余额/支付/发放。
  请求前 pending[id]=true 并刷新；成功或失败均清除该键再刷新，
  提示由接入层另行展示。本页不自动扣款，也不把平台购买弹窗视为发放成功。

【列表、显隐与资源边界】
  Templates 中货币/样式原型按稳定 ID 克隆为两列；切换页签清理非当前页，
  同 ID 改 currency/cardStyle 会换原型；空分组清理副本，保留隐藏原型。
  当前 Render 直接改根 Enabled，与通用 Show/Hide 动画约定有差异；
  再次 Show 前须恢复 open=true，本次不改变执行逻辑。
  ProductIconImg 由配置 icon 提供；钻石按钮 DiamondIcon 是设计中的静态图，
  需替换时修改设计资源，不向 State 增加字段。
  真实支付、资源权限及设备显示另验。
]]
local FX = _G.FX
local FXLoader = FX.Loader
local Text = FXLoader:RequireShared("Scripts/Game/Shared/Text")
local CCurrencyShopView = FX.Class("CCurrencyShopView", "CUIView")

local TranslationTexts = Text.Define("CurrencyShopUI", {
    DiamondShop = "DIAMOND SHOP",
    RobuxShop = "ROBUX SHOP",
    Price = "{price}",
    Waiting = "Waiting...",
    Unavailable = "Unavailable",
    SoldOut = "Sold out",
})

-- 暴露只读文案定义，供接入子类通过 self.BaseViewTranslationTexts 复用。
CCurrencyShopView.BaseViewTranslationTexts = TranslationTexts

-- 价格展示接入项目统一数量格式。
-- @param value number 原始价格。
-- @return string 展示价格。
function CCurrencyShopView:FormatNumber(value)
    return tostring(value)
end

-- 绑定已有节点与页签事件；每张商品卡只连接一次。
function CCurrencyShopView:OnReady()
    local root = FXLoader:PlayerGui("CurrencyShopUI")
    self.Root = root
    self.List = FXLoader:Here(root, "PopupPanelImg.ProductListBox")
    self.ContentTitle = FXLoader:Here(root, "PopupPanelImg.ProductsContentImg.ProductsTitleTxt")
    self.DiamondTab = FXLoader:Here(root, "PopupPanelImg.DiamondTabBtn")
    self.RobuxTab = FXLoader:Here(root, "PopupPanelImg.RobuxTabBtn")
    self.Templates = {}
    for currencyIndex, currency in ipairs({ "Diamond", "Robux" }) do
        self.Templates[currency] = {}
        for styleIndex, style in ipairs({ "Green", "Gold", "Cyan", "Orange", "Purple", "Pink" }) do
            self.Templates[currency][style] = FXLoader:Here(root, "Templates." .. currency .. style .. "CardImg")
        end
    end
    self.Cards = {}
    -- 页签动作仅提交目标货币。
    self:TrackConnection(self.DiamondTab.Activated:Connect(function()
        self:EmitUIAction("SelectTab", { tab = "Diamond" })
    end))
    self:TrackConnection(self.RobuxTab.Activated:Connect(function()
        self:EmitUIAction("SelectTab", { tab = "Robux" })
    end))
    local close = FXLoader:Here(root, "TitleBox.CloseSurfaceImg")
    -- 关闭动作交给接入层记录显隐状态。
    self:TrackConnection(close.Activated:Connect(function()
        self:EmitUIAction("Close", {})
    end))
end

-- 打开时刷新完整数据。
function CCurrencyShopView:OnShow()
    self:RefreshUI()
end

-- 创建原型副本并记录当前商品身份。
-- @param product table Config.products 中的商品
-- @param style string 已选择的渐变原型名称
-- @return table 卡片节点、连接与清理函数
function CCurrencyShopView:CreateCard(product, style)
    local node = self.Templates[product.currency][style]:Clone()
    node.Name = "Product_" .. product.id
    node.Parent = self.List
    node.Visible = true
    local card = {
        node = node,
        title = FXLoader:Here(node, "ProductTitleTxt"),
        description = FXLoader:Here(node, "ProductDescriptionTxt"),
        icon = FXLoader:Here(node, "ProductIconImg"),
        button = FXLoader:Here(node, "PurchaseBtn"),
        price = FXLoader:Here(node, "PurchaseBtn.ButtonTxt"),
        currency = product.currency,
        style = style,
    }
    -- 点击读取稳定 ID，货币由当前配置关联。
    local connection = card.button.Activated:Connect(function()
        self:EmitUIAction("Purchase", {
            productId = product.id,
            currency = card.currency,
        })
    end)
    card.release = self:TrackCleanup(function()
        connection:Disconnect()
        node:Destroy()
    end)
    return card
end

-- 用完整状态刷新两列商品，复用已有 ID 并清理已移除条目。
-- @param state table 文件头定义的完整 State
function CCurrencyShopView:Render(state)
    self.Root.Enabled = state.open
    local diamondSelected = state.tab == "Diamond"
    if diamondSelected then
        self.ContentTitle.Text = Text.Tr(TranslationTexts.DiamondShop)
    else
        self.ContentTitle.Text = Text.Tr(TranslationTexts.RobuxShop)
    end
    local diamondColor = Color3.fromHex("638079")
    local robuxColor = Color3.fromHex("638079")
    if diamondSelected then
        diamondColor = Color3.fromHex("67ED14")
    else
        robuxColor = Color3.fromHex("249CB5")
    end
    self.DiamondTab.BackgroundColor3 = diamondColor
    self.RobuxTab.BackgroundColor3 = robuxColor
    local diamondEdge = FXLoader:Here(self.DiamondTab, "BottomEdgeImg")
    local robuxEdge = FXLoader:Here(self.RobuxTab, "BottomEdgeImg")
    diamondEdge.BackgroundColor3 = diamondSelected and Color3.fromHex("225A07") or Color3.fromHex("263E36")
    robuxEdge.BackgroundColor3 = diamondSelected and Color3.fromHex("263E36") or Color3.fromHex("105464")
    local kept = {}
    local count = 0
    for index, product in ipairs(self:GetUIConfig().products) do
        if product.currency == state.tab then
            count = count + 1
            local style = product.cardStyle or (product.currency == "Diamond" and "Green" or "Gold")
            local card = self.Cards[product.id]
            if card and (card.currency ~= product.currency or card.style ~= style) then
                card.release()
                card = nil
            end
            if not card then
                card = self:CreateCard(product, style)
                self.Cards[product.id] = card
            end
            kept[product.id] = true
            card.node.Position = UDim2.fromOffset(((count - 1) % 2) * 304, math.floor((count - 1) / 2) * 156)
            card.title.Text = product.titleText or Text.TrSource(product.title)
            card.description.Text = product.descriptionText or Text.TrSource(product.description)
            card.icon.Image = product.icon or ""
            card.price.Text = Text.Tr(TranslationTexts.Price, {
                price = self:FormatNumber(product.price),
            })
            local pending = state.pending and state.pending[product.id]
            if pending then
                card.price.Text = Text.Tr(TranslationTexts.Waiting)
            elseif product.unavailable then
                card.price.Text = Text.Tr(TranslationTexts.Unavailable)
            elseif product.soldOut then
                card.price.Text = Text.Tr(TranslationTexts.SoldOut)
            end
            card.price.TextSize = (product.unavailable or product.soldOut) and 16.25 or 19.5
            self:SetButtonEnabled(card.button, not state.busy and not pending and not product.unavailable
                and (not product.soldOut or product.allowSoldOutAction == true))
        end
    end
    for id, card in pairs(self.Cards) do
        if not kept[id] then
            card.release()
            self.Cards[id] = nil
        end
    end
    self.List.CanvasSize = UDim2.fromOffset(595, math.max(314, math.ceil(count / 2) * 156 - 10))
end

-- 游戏接入必须处理声明的动作。
-- @param action string SelectTab、Purchase 或 Close
-- @param payload table 文件头定义的动作参数
function CCurrencyShopView:OnUIAction(action, payload)
    error("Currency shop integration must implement OnUIAction")
end

return CCurrencyShopView
