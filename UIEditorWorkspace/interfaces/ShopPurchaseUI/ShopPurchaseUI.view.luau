--[[
单件商品购买接入契约

【Config：完整配置，以下均必填、无默认值】
  itemId: string；稳定商品配置 ID，不用名称或图标作身份。
  name: string；商品名称原文。
  category: string；分类原文。
  description: string；描述原文，可含换行；以上文案经 Text.TrSource 查询。
  price: number；非负单件价格，单位钻石，按钮使用设计中的 Gem 静态图。
  icon: string；Roblox Image 资源地址；缺图必须传 ""，此时显示问号
    rbxassetid://86795093617566；不要省略 icon 或传本地文件路径。

【State：Render 的完整输入】
  status: "Ready" | "Purchased"，必填，无默认值；待购买 / 已购买。
  pending: boolean，可选，省略 false；true 显示 Buying... 并禁用购买。
  error: string，可选，省略 nil；Ready 且非 pending 时，只作为失败标记
    将按钮改为 Retry，错误原文不会显示。"" 在 Luau 中也会触发 Retry，
    清除失败请用 nil，不用空字符串。
  按钮文字优先级：pending > Purchased > Ready 下的 error > 价格 · Buy。
  只有 Ready 且非 pending 可购买；没有独立加载态、数量字段或商品列表。

【最小完整数据（接入 Ctor 调用父构造之后）】
  self.Config = {
      itemId = "training_x2", name = "2× Training Boost", category = "TRAINING BOOST",
      description = "Double your training gains.", price = 28, icon = "",
  }
  self.State = { status = "Ready" }

【初始化与刷新】
  游戏接入类继承 CShopPurchaseView。
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
  Buy -> { itemId: string }，对应当前 Config.itemId；不发送客户端价格。
  Close -> {}；由接入层 self:Hide()。
  FormatNumber(value:number)->string 可选覆写，默认 tostring，用于价格。
  Config.nameText / descriptionText:string? 已翻译组合文案，优先于对应原文。
  Config.unavailable:boolean? 与 State.busy:boolean? 禁用购买；继承 Render / EmitUIAction。
  请求前 pending=true、error=nil 并刷新；服务端验证商品、余额、价格并发放。
  成功后 status="Purchased"、pending=false、error=nil；
  失败后 status="Ready"、pending=false、error=失败标记；均需 RefreshUI。
  Close 不自动取消未完成请求；跨商品的过期响应由接入层按 itemId 隔离。

【显示与资源边界】
  设计态部分商品内容隐藏；首次 Render 填充完整商品并显示图标/描述/按钮。
  没有内置加载流程，数据不全时延后 BindUIData/Show。
  切换商品须同步替换完整 Config/State 再 RefreshUI，避免沿用 Purchased/error。
  图标槽 ItemSurfaceImg.ItemIconImg 由 Config.icon 替换；
  贴图异步加载和过期响应由游戏负责，App 不验证下载完成或资源权限。
  窗口使用 Show/Hide 和基类默认动画/适配，Render 不提前隐藏整窗。
]]
local FX = _G.FX
local FXLoader = FX.Loader
local Text = FXLoader:RequireShared("Scripts/Game/Shared/Text")
local CShopPurchaseView = FX.Class("CShopPurchaseView", "CUIView")

local TranslationTexts = Text.Define("ShopPurchaseUI", {
    Buy = "{price} · Buy",
    Buying = "Buying...",
    Purchased = "Purchased",
    Retry = "Retry",
})

-- 暴露只读文案定义，供接入子类通过 self.BaseViewTranslationTexts 复用。
CShopPurchaseView.BaseViewTranslationTexts = TranslationTexts

-- 单件价格使用接入项目的统一数量工具。
-- @param value number 原始价格。
-- @return string 展示价格。
function CShopPurchaseView:FormatNumber(value)
    return tostring(value)
end

-- 绑定设计节点；事件只连接一次，点击时读取当前稳定商品 ID。
function CShopPurchaseView:OnReady()
    local root = FXLoader:PlayerGui("ShopPurchaseUI")
    self.ItemNameTxt = FXLoader:Here(root, "PopupPanelImg.ItemNameTxt")
    self.CategoryTxt = FXLoader:Here(root, "PopupPanelImg.CategoryTxt")
    self.DescriptionTxt = FXLoader:Here(root, "PopupPanelImg.DescriptionTxt")
    self.ItemSurfaceImg = FXLoader:Here(root, "PopupPanelImg.ItemSurfaceImg")
    self.ItemIconImg = FXLoader:Here(root, "PopupPanelImg.ItemSurfaceImg.ItemIconImg")
    self.BuyBtn = FXLoader:Here(root, "PopupPanelImg.BuyBtn")
    self.ButtonTxt = FXLoader:Here(root, "PopupPanelImg.BuyBtn.ButtonTxt")
    local closeBtn = FXLoader:Here(root, "TitleBox.CloseSurfaceImg.CloseBtn")
    -- 购买动作只发送 ID，价格与资格由游戏接入层校验。
    self:TrackConnection(self.BuyBtn.Activated:Connect(function()
        local state = self:GetUIState()
        if state.status == "Ready" and not state.pending and not state.busy and not self:GetUIConfig().unavailable then
            self:EmitUIAction("Buy", { itemId = self:GetUIConfig().itemId })
        end
    end))
    -- 关闭沿用公共 Hide，避免自行控制窗口各部分显隐。
    self:TrackConnection(closeBtn.Activated:Connect(function()
        self:EmitUIAction("Close", {})
    end))
end

-- 每次打开读取当前配置和完整状态。
function CShopPurchaseView:OnShow()
    self:RefreshUI()
end

-- 刷新商品信息与购买状态；不修改输入数据。
-- @param state table 完整 State，字段与枚举见文件头契约
function CShopPurchaseView:Render(state)
    local config = self:GetUIConfig()
    self.ItemNameTxt.Text = config.nameText or Text.TrSource(config.name)
    self.CategoryTxt.Text = Text.TrSource(config.category)
    self.DescriptionTxt.Text = config.descriptionText or Text.TrSource(config.description)
    if config.icon == "" then
        self.ItemIconImg.Image = "rbxassetid://86795093617566"
    else
        self.ItemIconImg.Image = config.icon
    end
    self.ItemSurfaceImg.Visible = true
    self.ItemIconImg.Visible = true
    self.DescriptionTxt.Visible = true
    self.BuyBtn.Visible = true
    self.ButtonTxt.Text = Text.Tr(TranslationTexts.Buy, {
        price = self:FormatNumber(config.price),
    })
    if state.pending then
        self.ButtonTxt.Text = Text.Tr(TranslationTexts.Buying)
    elseif state.status == "Purchased" then
        self.ButtonTxt.Text = Text.Tr(TranslationTexts.Purchased)
    elseif state.status == "Ready" then
        if state.error then
            self.ButtonTxt.Text = Text.Tr(TranslationTexts.Retry)
        end
    else
        error("Unknown purchase status: " .. tostring(state.status))
    end
    self:SetButtonEnabled(self.BuyBtn, state.status == "Ready" and not state.pending and not state.busy and not config.unavailable)
end

-- 游戏接入必须实现购买和关闭动作。
-- @param action string Buy 或 Close
-- @param payload table Buy 为 {itemId:string}，Close 为空表
function CShopPurchaseView:OnUIAction(action, payload)
    error("Purchase integration must implement OnUIAction: " .. tostring(action))
end

return CShopPurchaseView
