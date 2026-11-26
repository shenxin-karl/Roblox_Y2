--[[
变异界面接入契约

Config：
    无。

State（完整快照）：
    weapons / stones：有序可选物品列表，缺省为空。
    weapon / stone：当前放入槽中的物品，缺省为空。
    每件物品包含 id（稳定字符串）、name（配置原文）、可选 icon（资源 URI）
    和可选 count（持有数量）、badgeIcon（武器变异角标资源 URI；普通武器省略）。
    stone.details：可选，所选变异石的简短说明原文。
    preview：材料选齐后由接入方根据当前组合重算；任一材料清除时置 nil。
    包含 beforeMutationName / afterMutationName（配置原文）、
    beforeIncomePerSecond / afterIncomePerSecond（不含货币符号和单位的格式化值）、
    sameMutation（目标词条与当前词条相同，禁用提交）、incomeDecreases（预估收益低于当前）。
    result：服务端确认后的结果，可选，包含 weapon（物品展示数据）、
    beforeMutationName / afterMutationName（可选变异名称原文，无变异时传对应名称）、
    beforeMutationIcon / afterMutationIcon（可选角标资源 URI，无角标时省略）、
    afterMutationId（可选稳定变异 ID，用于成品主题；未知 ID 使用默认配色）、
    beforeIncomePerSecond / afterIncomePerSecond（可选的已格式化收益数值字符串，不含货币符号或单位）。
    未提供的对比项显示破折号。
    pending：请求处理中，锁定物品和提交。
    error：请求失败时展示的完整提示原文，pending 优先。

展示规则：默认在背包并排显示武器和变异石；点击右侧槽位后，背包只显示该类别。
    再点当前槽位会恢复双栏，保留已选材料。
    两种布局均可点击物品或拖入对应材料槽；无效落点不改变选择。

动作：
    ChooseItem：payload.kind 为 "weapon" 或 "stone"，payload.itemId 为稳定 ID。
        再点相同 ID 时 payload.clear=true，接入方应清空该槽；拖入时 clear=false。
    Mutate：payload.weaponId、payload.stoneId 为当前材料的稳定 ID。
    Done：payload 为空。清除结果，更新材料和库存后刷新。

接入接口与顺序：
    1. 在 Generated 外继承此 View。构造函数先调父 Ctor(owner)，再准备 Config/State。
    2. OnReady() 先调父实现，再调用 BindUIData()。有订阅时覆写 BindUIData，
       提供首次数据、注册订阅并调用 RefreshUI()。
    3. 必须覆写 OnUIAction(action: string, payload: table) -> nil。
       ChooseItem 只更新选材；Mutate 才发起实际请求，先设 pending 防重。
       成功用权威结果填 result，失败清 pending、保留材料并填 error。
    4. 仅调用 Show/Hide/RefreshUI；继承 GetUIConfig/GetUIState。
       需要释放额外资源时覆写 Dtor()，先清理业务资源再调父。
       不覆写 Render、按钮状态或重复连接设计按钮。
]]
local FX = _G.FX
local Loader = FX.Loader
local Text = Loader:RequireShared("Scripts.Framework.Shared.Core.FXText")
local CWeaponMutationView = FX.Class("CWeaponMutationView", "CUIView")
CWeaponMutationView.ScreenGuiName = "WeaponMutationUI"

local TranslationTexts = Text.Define("WeaponMutation", {
    PickItem = "Tap an item to add it. Tap again to remove it.",
    PickOrDragItem = "Tap or drag to add. Tap again to clear.",
    NeedWeapon = "Choose a weapon.",
    NeedStone = "Choose a mutation stone.",
    WaitingForStone = "Select a stone to see its details.",
    DetailsUnavailable = "No details available for this stone.",
    PreviewMutation = "Mutation: {before} → {after}",
    PreviewIncome = "Base income: ${before}/s →",
    PreviewUnavailable = "Effect preview is unavailable for these materials.",
    PreviewSameMutation = "Choose a stone with a different mutation.",
})
CWeaponMutationView.BaseViewTranslationTexts = TranslationTexts

local Gold = Color3.fromHex("#FFD061")
local OutcomeColors = {
    Normal = Color3.fromHex("#ADB5CB"),
    Silver = Color3.fromHex("#C9DBF1"),
    Gold = Gold,
    Frost = Color3.fromHex("#73D9FF"),
    Inferno = Color3.fromHex("#FF8065"),
    Astral = Color3.fromHex("#BD9CFF"),
    Diamond = Color3.fromHex("#87F9EE"),
    Rainbow = Color3.fromHex("#FF9CDE"),
    Toxic = Color3.fromHex("#A9EB6C"),
    Storm = Color3.fromHex("#A2ACFF"),
}
local IdleStroke = Color3.fromHex("#574664")
local SlotStroke = Color3.fromHex("#111216")
local ConfirmColor = Color3.fromHex("#67ED14")
local DisabledColor = Color3.fromHex("#55505D")

local function SetSelected(button, selected, idleColor)
    local stroke = Loader:Here(button, "UIStroke")
    stroke.Color = selected and Gold or idleColor
    stroke.Thickness = selected and 3 or 2
end

local function IsPointerPress(input)
    return input and (input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch)
end

local function RenderItem(name, icon, placeholder, item)
    name.Text = item and Text.TrSource(item.name) or ""
    icon.Image = item and item.icon or ""
    icon.Visible = icon.Image ~= ""
    placeholder.Visible = not icon.Visible
end

--- 刷新角标；切换或清空武器时一起清除旧图标。
--- @param badge ImageLabel 物品角标节点。
--- @param item table? 当前物品展示数据。
local function RenderMutationBadge(badge, item)
    badge.Image = item and item.badgeIcon or ""
    badge.Visible = badge.Image ~= ""
end

--- 绑定界面节点和动作，并缓存成品展示的设计节点。
function CWeaponMutationView:OnReady()
    local root = self:GetRootNode()
    local bag = Loader:Here(root, "PopupPanelImg.InventoryImg")
    local station = Loader:Here(root, "PopupPanelImg.SelectionBox")
    if game then
        self._dragLayer = root:FindFirstChild("DragLayerBox")
    else
        self._dragLayer = Loader:Here(root, "DragLayerBox")
    end
    self._slots = {
        weapon = Loader:Here(station, "WeaponSlotBtn"),
        stone = Loader:Here(station, "StoneSlotBtn"),
    }
    self._weaponBadge = Loader:Here(self._slots.weapon, "IconWellImg.MutationBadgeImg")
    self._inventoryHint = Loader:Here(bag, "InventoryHintTxt")
    self._inventory = {
        weapon = {
            title = Loader:Here(bag, "WeaponTitleTxt"),
            list = Loader:Here(bag, "ItemList"),
            empty = Loader:Here(bag, "EmptyTxt"),
            cards = {},
        },
        stone = {
            title = Loader:Here(bag, "StoneTitleTxt"),
            list = Loader:Here(bag, "StoneList"),
            empty = Loader:Here(bag, "StoneEmptyTxt"),
            cards = {},
        },
    }
    for kind, column in pairs(self._inventory) do
        column.grid = Loader:Here(column.list, "UIGridLayout")
        column.splitTitlePosition = column.title.Position
        column.splitListPosition = column.list.Position
        column.splitEmptyPosition = column.empty.Position
        column.splitWidth = column.list.Size.X.Offset
        column.splitCellSize = column.grid.CellSize
    end
    self._template = Loader:Here(root, "Templates.InventoryItemTemplate")
    self._selectionTitle = Loader:Here(station, "SelectionTitleTxt")
    self._detailsPanel = Loader:Here(station, "MutationInfoImg")
    self._details = Loader:Here(self._detailsPanel, "DetailsTxt")
    self._detailsTitle = Loader:Here(self._detailsPanel, "InfoTitleTxt")
    self._previewTitle = Loader:Here(self._detailsPanel, "PreviewTitleTxt")
    self._previewMutation = Loader:Here(self._detailsPanel, "PreviewMutationTxt")
    self._previewIncome = Loader:Here(self._detailsPanel, "PreviewIncomeTxt")
    self._previewTargetIncome = Loader:Here(self._detailsPanel, "PreviewTargetIncomeTxt")
    self._outcome = Loader:Here(station, "OutcomeBox")
    self._outcomeWeapon = Loader:Here(self._outcome, "WeaponImg")
    self._outcomeTitle = Loader:Here(self._outcomeWeapon, "CompletedTitleTxt")
    self._outcomeBorder = Loader:Here(self._outcomeWeapon, "UIStroke")
    self._heroScale = Loader:Here(self._outcomeWeapon, "IconWellImg.HeroScale")
    self._heroBackdrop = Loader:Here(self._outcomeWeapon, "IconWellImg.HeroBackdropImg")
    self._beforeMutation = Loader:Here(self._outcome, "IncomeImg.BeforeMutationTxt")
    self._afterMutation = Loader:Here(self._outcome, "IncomeImg.AfterMutationTxt")
    self._beforeMutationIcon = Loader:Here(self._outcome, "IncomeImg.BeforeMutationIconImg")
    self._afterMutationIcon = Loader:Here(self._outcome, "IncomeImg.AfterMutationIconImg")
    self._beforeIncome = Loader:Here(self._outcome, "IncomeImg.BeforeIncomeTxt")
    self._afterIncome = Loader:Here(self._outcome, "IncomeImg.AfterIncomeTxt")
    self._status = Loader:Here(station, "StatusTxt")
    self._confirm = Loader:Here(station, "StartMutationBtn")

    for kind, slot in pairs(self._slots) do
        self:TrackConnection(slot.Activated:Connect(function()
            local state = self:GetUIState()
            if not state.pending and not state.result then
                self:SetActiveSlot(if self._activeSlot == kind then nil else kind)
                self:RefreshUI()
            end
        end))
    end
    self:TrackConnection(self._confirm.Activated:Connect(function()
        local state = self:GetUIState()
        if state.pending then
            return
        end
        if state.result then
            self:SetActiveSlot(nil)
            self:EmitUIAction("Done", {})
        elseif state.weapon and state.stone and not (state.preview and state.preview.sameMutation) then
            self:EmitUIAction("Mutate", {weaponId = state.weapon.id, stoneId = state.stone.id})
        end
    end))
    local close = Loader:Here(root, "TitleBox.CloseSurfaceImg.CloseBtn")
    self:TrackConnection(close.Activated:Connect(function()
        self:SetActiveSlot(nil)
        self:RefreshUI()
        self:StopOutcomeReveal()
        self:Hide()
    end))
end

--- 切换类别时结束拖拽，新显示的列表从顶部开始。
--- @param kind string? 武器或变异石；nil 表示同时显示两类。
function CWeaponMutationView:SetActiveSlot(kind)
    if self._activeSlot == kind then
        return
    end
    self:ClearInventoryDrag()
    self._activeSlot = kind
    for columnKind, column in pairs(self._inventory) do
        if not kind or columnKind == kind then
            column.list.CanvasPosition = Vector2.new(0, 0)
        end
    end
end

--- 结束拖动预览，选材清空、材料消失或界面锁定时也会调用。
function CWeaponMutationView:ClearInventoryDrag()
    if self._drag and self._drag.preview then
        self._drag.preview:Destroy()
        self._dragLayer.Visible = false
    end
    self._drag = nil
end

--- 移除指定类别的物品卡，并清理它的拖动预览。
--- @param kind string 物品类别。
--- @param id string 物品的稳定 ID。
--- @param card table 该物品的卡片。
function CWeaponMutationView:RemoveInventoryCard(kind, id, card)
    if self._drag and self._drag.card == card then
        self:ClearInventoryDrag()
    end
    card.button:Destroy()
    self._inventory[kind].cards[id] = nil
end

--- 回收两个类别的所有库存格子。
function CWeaponMutationView:ClearInventory()
    for kind, column in pairs(self._inventory or {}) do
        for id, card in pairs(column.cards) do
            self:RemoveInventoryCard(kind, id, card)
        end
    end
end

--- 拖动预览放在列表外，避免被滚动区裁切；原格继续留在网格里。
--- @param card table 当前库存卡片。
--- @param kind string 物品对应的材料槽类别。
--- @param id string 物品的稳定 ID。
function CWeaponMutationView:BindInventoryDrag(card, kind, id)
    local button, detector = card.button, card.detector
    if game then
        detector.ResponseStyle = Enum.UIDragDetectorResponseStyle.CustomOffset
    end

    button.InputBegan:Connect(function(input)
        if IsPointerPress(input) then
            card.didDrag = false
        end
    end)
    detector.DragStart:Connect(function(position)
        self:ClearInventoryDrag()
        self._drag = {card = card, start = position}
    end)
    detector.DragContinue:Connect(function(position)
        local drag = self._drag
        if not drag or drag.card ~= card then
            return
        end
        if not drag.preview then
            -- UIEditor 的模拟坐标只提供 X/Y，不支持 Vector2 运算。
            local dx, dy = position.X - drag.start.X, position.Y - drag.start.Y
            if dx * dx + dy * dy < 36 then
                return
            end
            card.didDrag = true
            local preview = button:Clone()
            Loader:Here(preview, "UIDragDetector"):Destroy()
            preview.Size = self._inventory[kind].grid.CellSize
            preview.AnchorPoint = Vector2.new(0.5, 0.5)
            preview.ZIndex = self._dragLayer.ZIndex
            local foregroundZIndex = preview.ZIndex + 1
            Loader:Here(preview, "ItemIconImg").ZIndex = foregroundZIndex
            Loader:Here(preview, "WeaponIconImg").ZIndex = foregroundZIndex
            Loader:Here(preview, "PlaceholderTxt").ZIndex = foregroundZIndex
            Loader:Here(preview, "ItemNameTxt").ZIndex = foregroundZIndex + 1
            Loader:Here(preview, "QuantityTxt").ZIndex = foregroundZIndex
            Loader:Here(preview, "MutationBadgeImg").ZIndex = foregroundZIndex
            preview.Parent = self._dragLayer
            self:SetButtonEnabled(preview, false)
            self._dragLayer.Visible = true
            drag.preview = preview
        end
        if game then
            local origin, size = self._dragLayer.AbsolutePosition, self._dragLayer.AbsoluteSize
            if size.X > 0 and size.Y > 0 then
                drag.preview.Position = UDim2.fromScale(
                    (position.X - origin.X) / size.X, (position.Y - origin.Y) / size.Y
                )
            end
        else
            -- 预览坐标以画布为原点，写入节点时偏移必须是整数。
            drag.preview.Position = UDim2.fromOffset(math.round(position.X), math.round(position.Y))
        end
    end)
    detector.DragEnd:Connect(function(position)
        local drag = self._drag
        if not drag or drag.card ~= card then
            return
        end
        self:ClearInventoryDrag()
        local state = self:GetUIState()
        if not card.didDrag or state.pending or state.result then
            return
        end
        local playerGui = self:GetRootNode().Parent
        for _, hit in ipairs(playerGui:GetGuiObjectsAtPosition(math.floor(position.X), math.floor(position.Y))) do
            if hit == self._slots[kind] then
                self:EmitUIAction("ChooseItem", {kind = kind, itemId = id, clear = false})
                return
            end
        end
    end)
end

--- 根据右侧槽的焦点显示两类库存，或让当前类别占满左侧。
--- @param state table 当前展示状态。
--- @param locked boolean 是否禁止选择和拖拽。
--- @param showOutcome boolean 是否正在展示成品。
function CWeaponMutationView:RenderInventory(state, locked, showOutcome)
    if locked then
        self:ClearInventoryDrag()
    end
    local activeSlot = self._activeSlot
    local hint = self._dragLayer and TranslationTexts.PickOrDragItem or TranslationTexts.PickItem
    self._inventoryHint.Text = not showOutcome and Text.Tr(hint) or ""
    for kind, column in pairs(self._inventory) do
        local visible = not showOutcome and (not activeSlot or activeSlot == kind)
        column.title.Visible = visible
        column.list.Visible = visible
        column.empty.Visible = false
        if visible then
            self:RenderInventoryColumn(kind, column, state, locked, activeSlot ~= nil)
        end
    end
    if showOutcome then
        self:ClearInventory()
    end
end

--- 按类别和稳定 ID 复用物品卡；聚焦时恢复整宽的三列网格。
--- @param kind string 当前类别。
--- @param column table 当前类别的标题、列表和条目缓存。
--- @param state table 当前展示状态。
--- @param locked boolean 是否禁止选择和拖拽。
--- @param focused boolean 当前类别是否占满库存区。
function CWeaponMutationView:RenderInventoryColumn(kind, column, state, locked, focused)
    local left = self._inventory.weapon
    local list, grid, cards = column.list, column.grid, column.cards
    local width = if focused then 370 else column.splitWidth
    local height = list.Size.Y.Offset
    local columns = if focused then 3 else 1
    column.title.Position = if focused then left.splitTitlePosition else column.splitTitlePosition
    list.Position = if focused then left.splitListPosition else column.splitListPosition
    list.Size = UDim2.fromOffset(width, height)
    column.empty.Position = if focused then left.splitEmptyPosition else column.splitEmptyPosition
    column.empty.Size = UDim2.fromOffset(width, column.empty.Size.Y.Offset)
    grid.CellSize = if focused then self._template.Size else column.splitCellSize
    grid.FillDirectionMaxCells = columns

    local selected = state[kind]
    local items = if kind == "weapon" then state.weapons or {} else state.stones or {}
    local keep = {}
    for index, item in ipairs(items) do
        local id = item.id
        keep[id] = true
        local card = cards[id]
        if not card then
            local button = self._template:Clone()
            button.Parent = list
            card = {button = button}
            if self._dragLayer then
                if game then
                    card.detector = button:FindFirstChild("UIDragDetector")
                else
                    card.detector = Loader:Here(button, "UIDragDetector")
                end
                if card.detector then
                    self:BindInventoryDrag(card, kind, id)
                end
            end
            button.Activated:Connect(function(input)
                local current = self:GetUIState()
                if (game and card.didDrag and IsPointerPress(input))
                    or current.pending or current.result then
                    return
                end
                local currentItem = current[kind]
                self:EmitUIAction("ChooseItem", {
                    kind = kind,
                    itemId = id,
                    clear = currentItem ~= nil and currentItem.id == id,
                })
            end)
            cards[id] = card
        end
        local button = card.button
        button.Visible = true
        button.LayoutOrder = index
        local iconName = if kind == "weapon" then "WeaponIconImg" else "ItemIconImg"
        RenderItem(Loader:Here(button, "ItemNameTxt"), Loader:Here(button, iconName),
            Loader:Here(button, "PlaceholderTxt"), item)
        RenderMutationBadge(Loader:Here(button, "MutationBadgeImg"), item)
        Loader:Here(button, "QuantityTxt").Text = item.count and item.count > 1 and ("×" .. tostring(item.count)) or ""
        SetSelected(button, selected ~= nil and selected.id == id, IdleStroke)
        self:SetButtonEnabled(button, not locked)
        if card.detector then
            card.detector.Enabled = not locked
        end
    end
    for id, card in pairs(cards) do
        if not keep[id] then
            self:RemoveInventoryCard(kind, id, card)
        end
    end
    column.empty.Visible = #items == 0
    local rows = math.ceil(#items / columns)
    local cellHeight, padding = grid.CellSize.Y.Offset, grid.CellPadding.Y.Offset
    local insets = Loader:Here(list, "UIPadding")
    local contentHeight = rows * cellHeight + math.max(0, rows - 1) * padding
        + insets.PaddingTop.Offset + insets.PaddingBottom.Offset
    local canvasSize = UDim2.fromOffset(0, math.max(height, contentHeight))
    if list.CanvasSize ~= canvasSize then
        list.CanvasSize = canvasSize
    end
end

--- 停止上一份结果的登场动画，并恢复设计比例。
function CWeaponMutationView:StopOutcomeReveal()
    if self._outcomeTween then
        self._outcomeTween:Cancel()
        self._outcomeTween:Destroy()
        self._outcomeTween = nil
    end
    self._revealedResult = nil
    if self._heroScale then
        self._heroScale.Scale = 1
    end
end

--- 按稳定变异 ID 上色，新结果只播放一次局部登场；无引擎服务时保持最终布局。
--- @param result table 服务端确认的成品展示数据。
function CWeaponMutationView:RenderOutcomeHero(result)
    local color = OutcomeColors[result.afterMutationId] or Gold
    self._outcomeTitle.TextColor3 = color
    self._outcomeBorder.Color = color
    self._heroBackdrop.BackgroundColor3 = color

    if self._revealedResult == result then
        return
    end
    self:StopOutcomeReveal()
    self._revealedResult = result
    if game then
        self._heroScale.Scale = 0.78
        self._outcomeTween = game:GetService("TweenService"):Create(
            self._heroScale,
            TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Scale = 1 }
        )
        self._outcomeTween:Play()
    end
end

--- 两件材料齐全时显示当前组合的预估；缺料时恢复变异石说明。
--- @param state table 当前展示状态。
--- @param showOutcome boolean 是否正在展示服务端结果。
function CWeaponMutationView:RenderMaterialInfo(state, showOutcome)
    local showPreview = not showOutcome and state.weapon ~= nil and state.stone ~= nil
    local preview = if showPreview then state.preview else nil
    self._detailsPanel.Visible = not showOutcome
    self._detailsTitle.Visible = not showPreview
    self._previewTitle.Visible = showPreview
    self._previewMutation.Visible = preview ~= nil
    self._previewIncome.Visible = preview ~= nil
    self._previewTargetIncome.Visible = preview ~= nil
    self._details.Visible = preview == nil
    if preview then
        self._previewMutation.Text = Text.Tr(TranslationTexts.PreviewMutation, {
            before = Text.TrSource(preview.beforeMutationName),
            after = Text.TrSource(preview.afterMutationName),
        })
        self._previewIncome.Text = Text.Tr(TranslationTexts.PreviewIncome, {
            before = preview.beforeIncomePerSecond,
        })
        self._previewTargetIncome.Text = "$" .. preview.afterIncomePerSecond .. "/s"
        self._previewTargetIncome.TextColor3 = if preview.incomeDecreases then Color3.fromHex("#FF9F68") else Color3.fromHex("#FFFFFF")
    elseif showPreview then
        self._details.Text = Text.Tr(TranslationTexts.PreviewUnavailable)
    elseif state.stone then
        self._details.Text = state.stone.details and Text.TrSource(state.stone.details)
            or Text.Tr(TranslationTexts.DetailsUnavailable)
    else
        self._details.Text = Text.Tr(TranslationTexts.WaitingForStone)
    end
end

--- 按最新完整快照更新选材和结果展示。
--- @param state table 当前展示状态。
function CWeaponMutationView:Render(state)
    local showOutcome = state.result ~= nil and not state.pending
    local locked = state.pending == true or showOutcome
    local ready = state.weapon ~= nil and state.stone ~= nil
    self:RenderInventory(state, locked, showOutcome)
    for kind, slot in pairs(self._slots) do
        slot.Visible = not showOutcome
        self:SetButtonEnabled(slot, not locked)
        local item = state[kind]
        RenderItem(Loader:Here(slot, "ItemNameTxt"), Loader:Here(slot, "IconWellImg.ItemIconImg"),
            Loader:Here(slot, "IconWellImg.PlaceholderTxt"), item)
        Loader:Here(slot, "HintTxt").Visible = item == nil
        SetSelected(slot, self._activeSlot == kind, SlotStroke)
    end

    RenderMutationBadge(self._weaponBadge, state.weapon)
    self._selectionTitle.Visible = not showOutcome
    self:RenderMaterialInfo(state, showOutcome)
    self._outcome.Visible = showOutcome
    if not showOutcome and self._revealedResult then
        self:StopOutcomeReveal()
    end
    if showOutcome then
        local result = state.result
        self:RenderOutcomeHero(result)
        RenderItem(Loader:Here(self._outcomeWeapon, "ItemNameTxt"),
            Loader:Here(self._outcomeWeapon, "IconWellImg.ItemIconImg"),
            Loader:Here(self._outcomeWeapon, "IconWellImg.PlaceholderTxt"), result.weapon)
        self._beforeMutation.Text = result.beforeMutationName and Text.TrSource(result.beforeMutationName) or "—"
        self._afterMutation.Text = result.afterMutationName and Text.TrSource(result.afterMutationName) or "—"
        self._beforeMutationIcon.Image = result.beforeMutationIcon or ""
        self._beforeMutationIcon.Visible = self._beforeMutationIcon.Image ~= ""
        self._afterMutationIcon.Image = result.afterMutationIcon or ""
        self._afterMutationIcon.Visible = self._afterMutationIcon.Image ~= ""
        self._beforeIncome.Text = if result.beforeIncomePerSecond then "$" .. result.beforeIncomePerSecond else "—"
        self._afterIncome.Text = if result.afterIncomePerSecond then "$" .. result.afterIncomePerSecond else "—"
    end

    local sameMutation = state.preview and state.preview.sameMutation
    local canConfirm = not state.pending and (showOutcome or (ready and not sameMutation))
    self:SetButtonEnabled(self._confirm, canConfirm)
    self._confirm.BackgroundColor3 = canConfirm and ConfirmColor or DisabledColor
    self._confirm.ImageTransparency = canConfirm and 0 or 0.55
    Loader:Here(self._confirm, "BottomEdgeImg").Visible = canConfirm
    Loader:Here(self._confirm, "ButtonTxt").Visible = not showOutcome
    Loader:Here(self._confirm, "DoneTxt").Visible = showOutcome
    self._status.Text = ""
    if not state.pending and not showOutcome then
        if state.error then
            self._status.Text = Text.TrSource(state.error)
        elseif sameMutation then
            self._status.Text = Text.Tr(TranslationTexts.PreviewSameMutation)
        elseif not state.weapon then
            self._status.Text = Text.Tr(TranslationTexts.NeedWeapon)
        elseif not state.stone then
            self._status.Text = Text.Tr(TranslationTexts.NeedStone)
        end
    end
end

function CWeaponMutationView:OnUIAction(action, payload)
    error("Weapon mutation handler missing: " .. action)
end

--- 回收成品登场动画和库存格子。
function CWeaponMutationView:Dtor()
    self:StopOutcomeReveal()
    self:ClearInventory()
    CWeaponMutationView.Super.Dtor(self)
end

return CWeaponMutationView
