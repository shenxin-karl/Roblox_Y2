-- 槽位剑展示：复用服务端的显示面与公开属性，客户端不计算金币或推测升级结果。
local CollectionService = game:GetService("CollectionService")
local FX, FC = _G.FX, _G.FC
local FXLoader = FX.Loader
local Text = FX.Text
local GameUtility = FXLoader:RequireShared("Scripts.Game.Shared.GameUtility")
local UIRoot = FXLoader:RequireShared("Scripts.Framework.Client.FCUIRoot")
local TranslationTexts = Text.Define("SlotSword", {
    Income = "Sword\n${value}/s",
    Upgrade = "${value}\nUpgrade {level:int} > {nextLevel:int}",
    Collected = "${value}",
    Place = "Place held finished sword",
    Remove = "Remove weapon",
    Slot = "Slot {slot:int}",
    CollectAll = "Collect All\n${value}",
})
local Comp = FX.Class("CSlotSwordCompClass", "FCPlayerCompClass")

--- 返回玩家组件协作名称。
--- @return string 槽位剑显示组件名。
function Comp:GetCompName()
    return "CSlotSwordComp"
end

--- 仅创建自有世界界面，支持晚复制的基地和玩家语言刷新。
function Comp:OnReady()
    self._views = {}
    self._prompts = {}
    self._uiRoot = Instance.new("Folder")
    self._uiRoot.Name = "SlotSwordUI"
    self._uiRoot.Parent = UIRoot.Get()
    self:TrackConnection(CollectionService:GetInstanceAddedSignal("SlotSwordDisplay"):Connect(function(display)
        self:TrackDisplay(display)
    end))
    self:TrackConnection(CollectionService:GetInstanceRemovedSignal("SlotSwordDisplay"):Connect(function(display)
        self:RemoveDisplay(display)
    end))
    self:TrackConnection(FC.Localization.Changed:Connect(function()
        for display in pairs(self._views) do
            self:Render(display)
        end
        self:RefreshPrompts()
    end))
    self:TrackConnection(CollectionService:GetInstanceAddedSignal("BaseWeaponPrompt"):Connect(function(prompt)
        self._prompts[prompt] = true
        self:RefreshPrompts()
    end))
    self:TrackConnection(CollectionService:GetInstanceRemovedSignal("BaseWeaponPrompt"):Connect(function(prompt)
        self._prompts[prompt] = nil
    end))
    for index, prompt in ipairs(CollectionService:GetTagged("BaseWeaponPrompt")) do
        self._prompts[prompt] = true
    end
    self:WatchDataChanged(_G.PlayerDataConfig.BaseData, function()
        self:RefreshPrompts()
    end)
    for index, display in ipairs(CollectionService:GetTagged("SlotSwordDisplay")) do
        self:TrackDisplay(display)
    end
end

--- 只显示本人已解锁槽位的放置或卸下提示；隐藏不替代服务端鉴权。
function Comp:RefreshPrompts()
    local data = self:GetTable(_G.PlayerDataConfig.BaseData)
    for prompt in pairs(self._prompts) do
        local slotId = prompt:GetAttribute("SlotId")
        prompt.Enabled = prompt:GetAttribute("OwnerUserId") == self:GetPlayerId()
            and data.UnlockedSlots[tostring(slotId)] == true
        if prompt.Enabled then
            prompt.ActionText = Text.Tr(data.SlotData[tostring(slotId)] and TranslationTexts.Remove or TranslationTexts.Place)
            prompt.ObjectText = Text.Tr(TranslationTexts.Slot, {slot = slotId})
        end
    end
end

--- 跟踪动态实例，不假定标签一定晚于其所有子节点复制。
--- @param display Model 服务端创建的槽位剑展示容器。
function Comp:TrackDisplay(display)
    if self._views[display] then
        return
    end
    local view = {Connections = {}}
    self._views[display] = view
    view.Connections[1] = display.ChildAdded:Connect(function()
        self:BuildView(display)
    end)
    view.Connections[2] = display.AttributeChanged:Connect(function()
        self:Render(display)
    end)
    self:BuildView(display)
end

--- 按展示面的实际比例创建画布；顶面文字转向牌子正面，避免金额沿地面短边排列。
--- @param part BasePart 已核对的服务端展示面。
--- @param face Enum.NormalId 展示面方向。
--- @param interactive boolean 是否创建升级按钮。
--- @return SurfaceGui 本地界面。
--- @return TextLabel|TextButton 由本脚本翻译的文本节点。
function Comp:CreateSurface(part, face, interactive)
    local surface = Instance.new("SurfaceGui")
    surface.Adornee, surface.Face = part, face
    surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
    local isTop = face == Enum.NormalId.Top
    surface.CanvasSize = isTop
        and Vector2.new(600 * part.Size.Z / part.Size.X, 600)
        or Vector2.new(600, 600 * part.Size.Y / part.Size.X)
    surface.MaxDistance = 80
    surface.Active = interactive
    surface.ResetOnSpawn = false
    surface.Parent = self._uiRoot
    local label = Instance.new(interactive and "TextButton" or "TextLabel")
    label.Name = interactive and "Upgrade" or "Amount"
    label.AutoLocalize = false
    label.BackgroundTransparency = 1
    label.AnchorPoint = Vector2.new(0.5, 0.5)
    label.Position = UDim2.fromScale(0.5, 0.5)
    label.Size = isTop
        and UDim2.fromOffset(surface.CanvasSize.Y * 0.9, surface.CanvasSize.X * 0.8)
        or UDim2.fromScale(0.92, 0.88)
    label.Rotation = isTop and -90 or 0
    label.Font = Enum.Font.GothamBlack
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextStrokeTransparency = 0
    label.TextScaled = true
    label.Text = ""
    label.Parent = surface
    return surface, label
end

--- 收益面板固定朝向升级牌正前方，底边高于剑尖；只有本人能点击升级牌子。
--- @param display Model 服务端槽位剑容器。
function Comp:BuildView(display)
    local view = self._views[display]
    local sword, sign, collect = display:FindFirstChild("Sword"), display:FindFirstChild("UpgradeSign"), display:FindFirstChild("CollectArea")
    if view and display:GetAttribute("CollectAll") then
        if collect and not view.Collect then
            view.Collect, view.Amount = self:CreateSurface(collect, Enum.NormalId.Top, false)
            view.Collect.CanvasSize = Vector2.new(800, 300)
            view.Amount.Size, view.Amount.Rotation = UDim2.fromScale(0.92, 0.88), 0
            self:Render(display)
        end
        return
    end
    if not view or view.IncomeGui or not sword or not sign or not collect then
        return
    end
    view.Sign, view.Upgrade = self:CreateSurface(sign, Enum.NormalId.Front, true)
    view.Collect, view.Amount = self:CreateSurface(collect, Enum.NormalId.Top, false)
    local anchor = Instance.new("Part")
    anchor.Name = "IncomeUIAnchor"
    anchor.Size = Vector3.new(4.6, 1.5, 0.01)
    anchor.Anchored, anchor.CanCollide, anchor.CanTouch, anchor.CanQuery = true, false, false, false
    anchor.Transparency = 1
    anchor.CastShadow = false
    local halfHeight = (math.abs(sword.CFrame.RightVector.Y) * sword.Size.X
        + math.abs(sword.CFrame.UpVector.Y) * sword.Size.Y
        + math.abs(sword.CFrame.LookVector.Y) * sword.Size.Z) / 2
    local position = sword.Position + Vector3.new(0, halfHeight + 1 + anchor.Size.Y / 2, 0)
    local forward = Vector3.new(sign.CFrame.LookVector.X, 0, sign.CFrame.LookVector.Z).Unit
    anchor.CFrame = CFrame.lookAt(position, position + forward)
    view.IncomeGui, view.Income = self:CreateSurface(anchor, Enum.NormalId.Front, false)
    view.IncomeAnchor = anchor
    -- 先登记界面再挂入展示容器，避免 ChildAdded 回调重复创建。
    anchor.Parent = display
    view.Income.Name = "Income"
    view.Income.TextColor3 = Color3.fromRGB(120, 255, 80)
    table.insert(view.Connections, view.Upgrade.Activated:Connect(function()
        if display:GetAttribute("OwnerUserId") == self:GetPlayerId() then
            FX.Network:SendMsgToServer("C2S_UpgradeSlotSword", display:GetAttribute("SlotId"))
        end
    end))
    self:Render(display)
end

--- 只显示服务端属性，数量统一格式化，等级使用整数参数。
--- @param display Model 正在刷新的槽位剑容器。
function Comp:Render(display)
    local view = self._views[display]
    if view and display:GetAttribute("CollectAll") then
        if view.Collect then
            local stored = display:GetAttribute("StoredMoney")
            view.Collect.Enabled = stored ~= nil
            if stored ~= nil then
                view.Amount.Text = Text.Tr(TranslationTexts.CollectAll, {value = GameUtility.NumberToText(stored)})
            end
        end
        return
    end
    local level, income = display:GetAttribute("Level"), display:GetAttribute("Income")
    local price, stored = display:GetAttribute("UpgradePrice"), display:GetAttribute("StoredMoney")
    if not view or not view.IncomeGui then
        return
    end
    local ready = display:GetAttribute("HasSword") == true
        and level ~= nil and income ~= nil and price ~= nil and stored ~= nil
    view.Sign.Enabled, view.Collect.Enabled, view.IncomeGui.Enabled = ready, ready, ready
    view.Upgrade.Active = display:GetAttribute("OwnerUserId") == self:GetPlayerId()
    if ready then
        view.Income.Text = Text.Tr(TranslationTexts.Income, {value = GameUtility.NumberToText(income)})
        view.Upgrade.Text = Text.Tr(TranslationTexts.Upgrade, {
            level = level, nextLevel = level + 1, value = GameUtility.NumberToText(price),
        })
        view.Amount.Text = Text.Tr(TranslationTexts.Collected, {value = GameUtility.NumberToText(stored)})
    end
end

--- 基地释放或流出时清理自身界面，不修改服务端锚点和地图模板。
--- @param display Model 不再展示的槽位剑容器。
function Comp:RemoveDisplay(display)
    local view = self._views[display]
    if not view then
        return
    end
    for index, connection in ipairs(view.Connections) do
        connection:Disconnect()
    end
    if view.IncomeGui then
        view.IncomeGui:Destroy()
        view.IncomeAnchor:Destroy()
        view.Sign:Destroy()
    end
    if view.Collect then
        view.Collect:Destroy()
    end
    self._views[display] = nil
end

--- 销毁本组件拥有的界面与连接，不接管玩家的其他 UI。
function Comp:Dtor()
    for display in pairs(self._views or {}) do
        self:RemoveDisplay(display)
    end
    if self._uiRoot then
        self._uiRoot:Destroy()
    end
    Comp.Super.Dtor(self)
end

return Comp
