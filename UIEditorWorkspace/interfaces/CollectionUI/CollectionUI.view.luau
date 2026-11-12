--[[
图鉴接入契约

【Config：完整配置】
  strengthPerEntryPercent: number，必填，无默认值；每激活一项的力量加成
    百分数，2 表示 +2%，不是倍率 0.02；仅用于规则说明。
  items: {Item}，必填连续数组；顺序即展示顺序，可为空 {}。
    Item.id: string，必填，无默认值；全列表唯一、稳定且不含点的道具配置 ID。
    Item.name: string，必填，无默认值；已激活时显示的名称原文。
    Item.icon: string，可选；Roblox Image 资源地址；省略或 "" 清除图像，
      显示原型问号，不保留上次图标。

【State：Render 的完整输入】
  open: boolean，必填，无默认值；当前实现直接赋给 ScreenGui.Enabled。
  totalStrengthPercent: number，必填，无默认值；已生效累计力量加成百分数，
    6 显示 +6%；由业务计算，不由 View 按激活数推导。
  entries: {[itemId: string]: Entry}，必填字典；键对应 Config.items[].id。
    每个配置 ID 必须有状态，不自动补齐；空配置对应 {}。
    Entry.active: boolean，必填，无默认值；true 已激活，false 未激活。
  未激活项名称为 ???、隐藏真实图标；已激活但缺图也显示问号。
  统计数由 active 项数与配置总数计算。没有领取、pending、error 或激活动作。
  没有独立加载态；加载期间可提供 items={}、entries={}、
  totalStrengthPercent=0，界面显示空列表与 0 项统计。

【最小完整数据（接入 Ctor 调用父构造之后）】
  self.Config = {
      strengthPerEntryPercent = 2,
      items = { { id = "sword", name = "Wood Sword" } },
  }
  self.State = {
      open = true, totalStrengthPercent = 2,
      entries = { sword = { active = true } },
  }

【初始化与刷新】
  游戏接入类继承 CCollectionView。
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
  唯一动作 Close -> {}；接入层更新 open=false 并刷新。
  Config.unlockCount:number?，提供时使用按收集门槛的训练加成规则。
  Config.lockedSilhouette:boolean?，true 未解锁项显示真实图标黑色剪影。
  FormatNumber(value:number)->string 可选覆写，默认 tostring，用于百分比。
  Render / CreateRow 继承，不在接入层写节点；发现道具后由业务同步 entries 与
  totalStrengthPercent，再 RefreshUI。View 不写入激活记录或玩家力量。

【列表、显隐与资源边界】
  Templates.ItemRowImg 按 Item.id 克隆为四列卡片；空配置清理所有副本，
  原型保留；数组顺序改变时重排，不按名称或数组下标识别道具。
  当前 Render 直接改根 Enabled，与通用 Show/Hide 动画约定有差异；
  再次 Show 前须恢复 open=true，本次仅说明现有行为。
  Templates.ItemRowImg.ItemIconImg 为动态图槽，由配置 icon 替换。
  真实激活、存档、资源权限及设备显示另验。
]]
local FX = _G.FX
local FXLoader = FX.Loader
local Text = FXLoader:RequireShared("Scripts/Game/Shared/Text")
local CCollectionView = FX.Class("CCollectionView", "CUIView")

local TranslationTexts = Text.Define("CollectionUI", {
    StrengthRule = "+{percent}% Strength",
    StrengthBoost = "+{percent}%",
    ActivatedCount = "Activated {active:int} / {total:int}",
    TrainingRule = "Collect {count:int} items for +{percent}% training.",
    CollectedCount = "{count:int}/{total:int} collected",
})

-- 暴露只读文案定义，供接入子类通过 self.BaseViewTranslationTexts 复用。
CCollectionView.BaseViewTranslationTexts = TranslationTexts

-- 百分比接入项目数量格式，不改变业务计算。
-- @param value number 百分比数值。
-- @return string 展示数值。
function CCollectionView:FormatNumber(value)
    return tostring(value)
end

-- 绑定窗口、统计与隐藏卡片原型，只连接关闭操作。
function CCollectionView:OnReady()
    local root = FXLoader:PlayerGui("CollectionUI")
    self.Root = root
    self.List = FXLoader:Here(root, "PopupPanelImg.ItemListBox")
    self.Count = FXLoader:Here(root, "TitleBox.CountTxt")
    self.Boost = FXLoader:Here(root, "PopupPanelImg.SummaryImg.BoostTxt")
    self.Rule = FXLoader:Here(root, "PopupPanelImg.SummaryImg.StatusTxt")
    self.Template = FXLoader:Here(root, "Templates.ItemRowImg")
    self.Rows = {}
    local close = FXLoader:Here(root, "TitleBox.CloseSurfaceImg")
    -- 关闭由接入层更新显隐状态。
    self:TrackConnection(close.Activated:Connect(function()
        self:EmitUIAction("Close", {})
    end))
end

-- 打开时刷新完整业务数据。
function CCollectionView:OnShow()
    self:RefreshUI()
end

-- 新增稳定 ID 的卡片，仅保存图标、名称与清理方法。
-- @param item table Config.items 中的道具配置
-- @return table 卡片节点引用及释放方法
function CCollectionView:CreateRow(item)
    local node = self.Template:Clone()
    node.Name = "Item_" .. item.id
    node.Parent = self.List
    node.Visible = true
    local row = {
        node = node,
        name = FXLoader:Here(node, "ItemNameTxt"),
        icon = FXLoader:Here(node, "ItemIconImg"),
        unknown = FXLoader:Here(node, "UnknownTxt"),
    }
    row.release = self:TrackCleanup(function()
        node:Destroy()
    end)
    return row
end

-- 刷新四列卡片及累计力量，复用已有 ID 并清理移除项。
-- @param state table 文件头定义的完整 State
function CCollectionView:Render(state)
    self.Root.Enabled = state.open
    local config = self:GetUIConfig()
    self.Rule.Text = Text.Tr(TranslationTexts.StrengthRule, {
        percent = self:FormatNumber(config.strengthPerEntryPercent),
    })
    if config.unlockCount then
        self.Rule.Text = Text.Tr(TranslationTexts.TrainingRule, {
            count = config.unlockCount, percent = self:FormatNumber(config.strengthPerEntryPercent),
        })
    end
    self.Boost.Text = Text.Tr(TranslationTexts.StrengthBoost, {
        percent = self:FormatNumber(state.totalStrengthPercent),
    })
    local kept = {}
    local activeCount = 0
    for index, item in ipairs(config.items) do
        local entry = state.entries[item.id]
        local row = self.Rows[item.id]
        if not row then
            row = self:CreateRow(item)
            self.Rows[item.id] = row
        end
        kept[item.id] = true
        row.node.Position = UDim2.fromOffset(
            1 + ((index - 1) % 4) * 148,
            1 + math.floor((index - 1) / 4) * 107
        )
        if entry.active then
            activeCount = activeCount + 1
        end
        row.name.Text = entry.active and Text.TrSource(item.name) or "???"
        row.icon.Image = entry.active and (item.icon or "") or ""
        row.unknown.Visible = not entry.active or not item.icon or item.icon == ""
        row.icon.ImageTransparency = row.unknown.Visible and 1 or 0
        row.icon.ImageColor3 = Color3.new(1, 1, 1)
        if config.lockedSilhouette then
            row.icon.Image = item.icon or ""
            row.icon.ImageColor3 = entry.active and Color3.new(1, 1, 1) or Color3.new(0, 0, 0)
            row.icon.ImageTransparency = 0
            row.icon.BackgroundTransparency = 1
            row.unknown.Visible = not item.icon or item.icon == ""
        end
    end
    for id, row in pairs(self.Rows) do
        if not kept[id] then
            row.release()
            self.Rows[id] = nil
        end
    end
    self.List.CanvasSize = UDim2.fromOffset(
        584,
        math.max(212, math.ceil(#config.items / 4) * 107 - 8)
    )
    self.Count.Text = Text.Tr(TranslationTexts.ActivatedCount, {
        active = activeCount,
        total = #config.items,
    })
    if config.unlockCount then
        self.Count.Text = Text.Tr(TranslationTexts.CollectedCount, {count = activeCount, total = #config.items})
    end
end

-- 游戏接入必须处理关闭操作。
-- @param action string Close
-- @param payload table 空表
function CCollectionView:OnUIAction(action, payload)
    error("Collection integration must implement OnUIAction")
end

return CCollectionView
