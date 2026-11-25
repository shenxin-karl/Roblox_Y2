-- 项目引导只读取服务端目标，显示一条任务及当前位置对应的箭头。
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local FX = _G.FX
local Loader = FX.Loader
local Text = FX.Text
local Fields = _G.PlayerDataConfig
local Tutorial = Loader:RequireShared("Scripts.Game.Shared.TutorialGuideConfig")
local Mining = Loader:RequireShared("Scripts.Game.Shared.MiningSettings")
local Forge = Loader:RequireShared("Scripts.Game.Shared.ForgeSettings")
local Utility = Loader:RequireShared("Scripts.Game.Shared.GameUtility")
local TextPrompt = Loader:RequireShared("Scripts.Framework.Client.FCTextPrompt")
local UIRoot = Loader:RequireShared("Scripts.Framework.Client.FCUIRoot")
local TranslationTexts = Text.Define("Y2Tutorial", {
    Mine = "Go to the central quarry and pick up ore for a sword blank.",
    NeedOre = "You need {oreNeeded:int} ore. Pick one up at the central quarry.",
    Carry = "Carry the ore out of the quarry and back to your base.",
    Smelt = "Use your furnace to make a sword blank ({ore:int}/{oreNeeded:int} ore).",
    Forge = "Equip your sword blank and put it on your workbench.",
    Forging = "Strike as many times as you like, or finish the weapon now.",
    Pending = "Make room in your backpack, then collect the finished weapon at your workbench.",
    Place = "Equip your homemade weapon and place it in your base to earn cash.",
    Replace = "Remove the weapon in this slot, then place your homemade weapon here.",
    NoSlot = "Free up a starter slot for a homemade weapon.",
    Waiting = "Your homemade weapons earn ${rate}/s. Wait for cash to build up, then collect it.",
    Collect = "Collect your weapon income at your base's green pad. Your homemade weapons earn ${rate}/s.",
    Upgrade = "Upgrade a homemade weapon one level for ${price}.",
    UpgradeShort = "Upgrade for ${price}. You need ${short} more; ${pending} is waiting to be collected at your base.",
    Luck = "Open Upgrades and upgrade furnace luck for ${price}.",
    LuckCollect = "Collect cash at your base. You need ${short} more to upgrade furnace luck.",
    Unlock = "Unlock this weapon slot for ${price}.",
    UnlockShort = "Unlock this slot for ${price}. You need ${short} more.",
    Second = "Make another weapon and check the new blank's luck. {action}",
    SecondPlace = "Place your second homemade weapon in this slot.",
    UpgradeAgain = "Choose a homemade weapon and upgrade it once more. {action}",
    Fill = "Make and place more weapons ({count:int}/{goal:int} placed). {action}",
    Last = "Fill the last starter slot ({count:int}/{goal:int} placed). {action}",
    FirstWeapon = "You forged your first weapon!",
    FirstIncome = "Your weapon is now earning cash!",
    Complete = "All six weapons are earning cash!",
    Hide = "Hide tips",
    Show = "Show tips",
})
local Guide = FX.Class("CTutorialGuideCompClass", "FCTutorialGuideCompClass")
local Yellow = Color3.fromRGB(255, 215, 60)
local MilestoneTexts = {
    ["6"] = TranslationTexts.FirstWeapon,
    ["7"] = TranslationTexts.FirstIncome,
    ["18"] = TranslationTexts.Complete,
}

--- 共享引导约定。
--- @return table 项目引导配置。
function Guide:GetGuideConfig()
    return Tutorial
end

--- 读取同步的当前目标，持久进度由服务端保存。
--- @return table 引导同步字段。
function Guide:GetGuideStorage()
    return Fields.Guide
end

--- 返回玩家组件协作名。
--- @return string 引导组件名。
function Guide:GetCompName()
    return "CTutorialGuideComp"
end

--- 创建独立提示层，避免改动目标界面及其按钮。
function Guide:OnReady()
    local gui = Instance.new("ScreenGui")
    gui.Name = "TutorialHint"
    gui.DisplayOrder = 40
    gui.ResetOnSpawn = false
    gui.Parent = self:GetPlayerNode():WaitForChild("PlayerGui")
    self._gui = gui
    local panel = Instance.new("TextLabel")
    panel.AutoLocalize = false
    panel.AnchorPoint = Vector2.new(0.5, 0)
    panel.Position = UDim2.new(0.5, 0, 0, 52)
    panel.Size = UDim2.new(0.78, 0, 0, 59)
    local limit = Instance.new("UISizeConstraint")
    limit.MaxSize = Vector2.new(560, 59)
    limit.Parent = panel
    panel.BackgroundColor3 = Color3.fromRGB(30, 24, 18)
    panel.BackgroundTransparency = 0.12
    panel.TextColor3 = Color3.new(1, 1, 1)
    panel.Font = Enum.Font.GothamBold
    panel.TextSize = 15
    panel.TextWrapped = true
    panel.Parent = gui
    local padding = Instance.new("UIPadding")
    padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
    padding.Parent = panel
    self._panel = panel
    local toggle = Instance.new("TextButton")
    toggle.AutoLocalize = false
    toggle.AnchorPoint = Vector2.new(0.5, 0)
    toggle.Position = UDim2.new(0.5, 0, 0, 115)
    toggle.Size = UDim2.fromOffset(100, 27)
    toggle.TextColor3 = panel.TextColor3
    toggle.BackgroundColor3 = panel.BackgroundColor3
    toggle.Font = panel.Font
    toggle.TextSize = 13
    toggle.Parent = gui
    self._toggle = toggle
    self:TrackConnection(toggle.Activated:Connect(function()
        local target = self._guideTarget
        if target and target.step then
            FX.Network:SendMsgToServer("C2S_TutorialHint", target.type == "Hidden" and "Show" or "Hide", target.step)
        end
    end))
    local outline = Instance.new("Frame")
    outline.BackgroundTransparency = 1
    outline.Parent = gui
    local stroke = Instance.new("UIStroke")
    stroke.Color, stroke.Thickness = Yellow, 3
    stroke.Parent = outline
    self._outline = outline
    local highlight = Instance.new("Highlight")
    highlight.FillTransparency = 0.82
    highlight.OutlineColor = Yellow
    highlight.FillColor = Yellow
    highlight.Parent = gui
    self._highlight = highlight
    local noticeArea = Instance.new("Frame")
    noticeArea.Name = "TutorialMilestoneNotice"
    noticeArea.BackgroundTransparency = 1
    noticeArea.AnchorPoint = Vector2.new(0.5, 1)
    -- 与矿石刷新扫光错开，两个提示同时出现时各占一行。
    noticeArea.Position = UDim2.new(0.5, 0, 1, -158)
    noticeArea.Size = UDim2.new(0.9, 0, 0, 64)
    noticeArea.Parent = UIRoot.Get()
    self._noticeArea = noticeArea
    self._notice, self._noticeEffect = TextPrompt.CreateReminder(noticeArea)
    self._pendingMilestones = {}
    FX.Network:RegServerMsgCallback("S2C_TutorialMilestone", self.ShowMilestone, self)
    self:TrackConnection(_G.FC.Localization.Changed:Connect(function()
        if self._notice.Visible then
            self._notice.Text = Text.Tr(self._noticeText)
        end
    end))
    Guide.Super.OnReady(self)
    self:OnGuideDataChanged(self:GetTable(Fields.Guide))
    local elapsed = 0
    --- 定期重定位流入客户端的场景对象和移动中的 HUD。
    --- @param dt number 距上帧的秒数。
    self:TrackConnection(RunService.Heartbeat:Connect(function(dt)
        elapsed += dt
        if elapsed >= 0.15 then
            elapsed = 0
            if self._notice.Visible and os.clock() >= self._noticeUntil then
                self._notice.Visible = false
                local nextMilestone = table.remove(self._pendingMilestones, 1)
                if nextMilestone then
                    self:ShowMilestone(nextMilestone)
                end
            end
            self:Refresh()
        end
    end))
    self:Refresh()
end

--- 依次显示服务端首次确认的进展，避免后到的里程碑盖过当前提示。
--- @param step string 服务端已达成的里程碑编号。
function Guide:ShowMilestone(step)
    local definition = MilestoneTexts[step]
    if definition then
        if self._notice.Visible then
            table.insert(self._pendingMilestones, step)
            return
        end
        self._noticeText = definition
        self._noticeUntil = os.clock() + 3
        TextPrompt.SetReminderText(self._notice, self._noticeEffect, Text.Tr(definition), false)
    end
end

--- 接到目标后更新表现；玩家隐藏引导时同时清掉扫光提示。
--- @param target table 服务器目标。
function Guide:OnEnterGuide(target)
    if target.type == "Hidden" then
        self._notice.Visible = false
        table.clear(self._pendingMilestones)
    end
    self:Refresh()
end

--- 目标退出后释放世界箭头，后续目标由刷新接管。
--- @param target table 框架传入的上一目标。
function Guide:OnExitGuide(target)
    self._highlight.Adornee = nil
    if target.type ~= "Hidden" then
        self:HideGuideArrow()
    end
end

--- 按归属寻找槽位展示、领取点或原生交互提示。
--- @param tag string 现有业务使用的实例标记。
--- @param slot number? 目标槽位，未给出时查找领取区。
--- @return Instance? 当前已复制的目标。
function Guide:FindOwned(tag, slot)
    for index, node in ipairs(CollectionService:GetTagged(tag)) do
        if node:IsDescendantOf(workspace) and node:GetAttribute("OwnerUserId") == self:GetPlayerId()
            and ((slot and node:GetAttribute("SlotId") == slot) or (not slot and node:GetAttribute("CollectAll"))) then
            return node
        end
    end
    return nil
end

--- 使用已发布的动态矿石，以及当前基地分配对应的工位和槽位。
--- @param target table 服务端允许展示的目标。
--- @param root BasePart 存活角色根部。
--- @return Instance? 世界目标。
--- @return number? 触发高亮的距离。
--- @return Instance? 可见的高亮模型（交互锚点透明时使用）。
function Guide:FindWorldTarget(target, root)
    local kind, slot = target.type, target.slot
    local baseId = self:GetNumber(Fields.BaseId)
    if kind == "Mine" or kind == "NeedOre" then
        local distance, result = math.huge, nil
        for index, rock in ipairs(CollectionService:GetTagged(Mining.RockTag)) do
            if rock:IsA("Model") and rock:IsDescendantOf(workspace) then
                local magnitude = (rock:GetPivot().Position - root.Position).Magnitude
                if magnitude < distance then
                    distance, result = magnitude, rock
                end
            end
        end
        return result or Loader:FindFromWorkspace(Mining.GroundPath), Mining.InteractDistance
    elseif kind == "Carry" then
        return Loader:FindFromWorkspace("BlockMeshs.bases.base" .. baseId .. ".BaseLower.Architecture.LowerFloor"), 9
    elseif kind == "Smelt" or kind == "Forge" or kind == "Pending" then
        if target.inForge then
            return nil
        end
        local workshop = Forge.FindPersonalWorkshop(baseId)
        local part = kind == "Smelt" and Forge.PersonalFurnacePart or Forge.PersonalForgePart
        return workshop and Loader:Find(workshop, part), Forge.PersonalInteractDistance
    elseif kind == "Collect" or kind == "LuckCollect" then
        local display = self:FindOwned("SlotSwordDisplay")
        local plate = Loader:FindFromWorkspace("BlockMeshs.bases.base" .. baseId .. ".BaseLower.CollectAllPlate")
        return display and Loader:Find(display, "CollectArea") or plate, 5, plate
    elseif kind == "Upgrade" then
        local display = self:FindOwned("SlotSwordDisplay", slot)
        return display and Loader:Find(display, "UpgradeSign"), 7
    elseif kind == "Place" or kind == "Replace" or kind == "Unlock" then
        local prompt = slot and self:FindOwned(kind == "Unlock" and "BaseUpgradePrompt" or "BaseWeaponPrompt", slot)
        if prompt then
            for index, model in ipairs(CollectionService:GetTagged("BaseDisplaySlot")) do
                if model:GetAttribute("BaseId") == baseId and model:GetAttribute("SlotId") == slot
                    and model:IsDescendantOf(workspace) then
                    return prompt.Parent, prompt.MaxActivationDistance, model
                end
            end
            return prompt.Parent, prompt.MaxActivationDistance
        end
    end
    return nil
end

--- 先指 HUD 的升级入口；工坊打开后指向熔炼行按钮。
--- @return GuiObject? 当前可见的目标按钮。
function Guide:FindLuckButton()
    local screen = self._gui.Parent:FindFirstChild("UpgradeWorkshopUI")
    local popup = screen and screen:FindFirstChild("PopupPanelImg")
    if screen and screen.Enabled and popup and popup.Visible then
        return Loader:Find(popup, "SmeltRowImg.UpgradeBtn")
    end
    return Loader:Find(self._gui.Parent, "Main.HUD.SideNav.Upgrade")
end

--- 生成一条当前任务，使用实际金币费用、待领收益与当前摆放数量。
--- @param target table 服务端同步的当前目标。
--- @return string 已翻译的提示。
function Guide:Format(target)
    local kind, step = target.type, target.step
    local key = kind
    if kind == "Forge" and target.inForge then
        key = "Forging"
    elseif kind == "Collect" and target.waiting then
        key = "Waiting"
    elseif (kind == "Upgrade" or kind == "Unlock") and target.short and target.short > 0 then
        key = kind .. "Short"
    end
    local format = Utility.NumberToText
    local action = Text.Tr(TranslationTexts[key], {
        price = format(target.price or 0), short = format(target.short or 0), pending = format(target.pending or 0),
        ore = Tutorial.RequiredOre, oreNeeded = Tutorial.RequiredOre, rate = format(target.rate or 0),
    })
    if step == 9 then
        if kind == "Place" then
            return Text.Tr(TranslationTexts.SecondPlace)
        end
        return Text.Tr(TranslationTexts.Second, {action = action})
    elseif step == 10 then
        return Text.Tr(TranslationTexts.UpgradeAgain, {action = action})
    elseif step == 11 or step == 12 then
        return Text.Tr(TranslationTexts[step == 11 and "Fill" or "Last"],
            {action = action, count = target.count, goal = target.goal})
    end
    return action
end

--- 刷新提示与箭头；六槽完成只通过短暂扫光提示。
function Guide:Refresh()
    local target = self._guideTarget
    local character = self:GetPlayerCharacter()
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = humanoid and humanoid.Health > 0 and humanoid.RootPart
    local visible = target and target.type ~= "None" and target.type ~= "Complete" and root ~= nil and root ~= false
    local hidden = visible and target.type == "Hidden"
    self._panel.Visible = visible and not hidden or false
    self._toggle.Visible = visible and target.step >= 9 and target.step <= 12 or false
    self._outline.Visible = false
    self._highlight.Adornee = nil
    if self._toggle.Visible then
        self._toggle.Text = Text.Tr(hidden and TranslationTexts.Show or TranslationTexts.Hide)
    end
    if not self._panel.Visible then
        self:HideGuideArrow()
        return
    end
    self._panel.Text = self:Format(target)
    if target.type ~= "Complete" and self._shownStep ~= target.step then
        self._shownStep = target.step
        FX.Network:SendMsgToServer("C2S_TutorialHint", "Shown", target.step)
    end
    local button = target.type == "Luck" and self:FindLuckButton()
    if button and button:IsA("GuiObject") and button.Visible then
        local position, size = button.AbsolutePosition, button.AbsoluteSize
        self._outline.Position = UDim2.fromOffset(position.X, position.Y)
        self._outline.Size = UDim2.fromOffset(size.X, size.Y)
        self._outline.Visible = true
    end
    local worldTarget, distance, visibleModel = self:FindWorldTarget(target, root)
    if worldTarget and worldTarget:IsA("PVInstance") then
        local position = worldTarget:GetPivot().Position
        if (position - root.Position).Magnitude > distance then
            self:ShowGuideArrowToPosition(position)
            return
        end
        self._highlight.Adornee = visibleModel or worldTarget
    end
    self:HideGuideArrow()
end

--- 复用 Y1 的彩色路线箭头与白色穿透轮廓。
--- @param position Vector3 世界目标。
function Guide:ShowGuideArrowToPosition(position)
    self._worldTargetPosition = position
    if not self._arrowTrans then
        local decorations = Loader:Workspace("Decorations")
        local arrow = Instance.new("Part")
        arrow.Name = "TutorialGuideArrow"
        arrow.Size = Vector3.new(0.1, 0.1, 0.1)
        arrow.Anchored = true
        arrow.CanCollide, arrow.CanTouch, arrow.CanQuery = false, false, false
        arrow.Transparency = 1
        arrow.CastShadow = false
        self._arrowTriangles = {}
        arrow.Parent = decorations
        self._arrowTrans = arrow
        local overlay = Instance.new("WireframeHandleAdornment")
        overlay.Name = "OcclusionOverlay"
        overlay.Adornee = arrow
        overlay.AlwaysOnTop = true
        overlay.ZIndex = 1
        overlay.Color3 = Color3.fromRGB(255, 255, 255)
        overlay.Transparency = 0
        overlay.Parent = arrow
        self._arrowOverlay = overlay
        self._renderSteppedConn = RunService.RenderStepped:Connect(function()
            self:UpdateGuideArrow()
        end)
    end
    self:UpdateGuideArrow()
end

--- 彩色三角形沿路线滚动并淡出首尾；白色穿透轮廓复用同一组顶点。
function Guide:UpdateGuideArrow()
    local character = self:GetPlayerCharacter()
    local root = character and Loader:Find(character, "HumanoidRootPart")
    if not self._arrowTrans then
        return
    end
    local camera = workspace.CurrentCamera
    local origin = root and root.Position - Vector3.new(0, 2.5, 0)
    local target = self._worldTargetPosition and self._worldTargetPosition + Vector3.new(0, 0.5, 0)
    local direction = origin and target and target - origin
    local distance = direction and direction.Magnitude or 0
    local spacing = 4
    local count = root and camera and math.min(32, math.max(0, math.ceil((distance - 3.32) / spacing))) or 0
    local now = os.clock()
    local forward, side, normal, flatForward
    local flatDirection = direction and Vector3.new(direction.X, 0, direction.Z)
    local flatDistance = flatDirection and flatDirection.Magnitude or 0
    if count > 0 and flatDistance > 0.01 then
        forward = direction.Unit
        flatForward = flatDirection / flatDistance
        side = Vector3.new(0, 1, 0):Cross(flatForward)
        normal = Vector3.new(0, 1, 0)
    else
        count = 0
    end
    local overlayLines = {}
    for index = 1, math.max(count, #self._arrowTriangles) do
        local triangle = self._arrowTriangles[index]
        if not triangle then
            triangle = {}
            for half = 1, 2 do
                local wedge = Instance.new("WedgePart")
                wedge.Name = "Triangle" .. index .. "Half" .. half
                wedge.Size = Vector3.new(0.048, 1.2, 2.64)
                wedge.Anchored = true
                wedge.CanCollide, wedge.CanTouch, wedge.CanQuery = false, false, false
                wedge.CastShadow = false
                wedge.Material = Enum.Material.Neon
                wedge.Parent = self._arrowTrans
                triangle[half] = wedge
            end
            self._arrowTriangles[index] = triangle
        end
        local along = index <= count and 2 + (index - 1) * spacing + (now * 1.5) % spacing
        local visible = along and along < distance - 1.32
        if visible then
            local center = origin + forward * along
            local tip = self._arrowTrans.CFrame:PointToObjectSpace(center + flatForward * 1.32)
            local left = self._arrowTrans.CFrame:PointToObjectSpace(center - flatForward * 1.32 - side * 1.2)
            local right = self._arrowTrans.CFrame:PointToObjectSpace(center - flatForward * 1.32 + side * 1.2)
            table.insert(overlayLines, tip)
            table.insert(overlayLines, left)
            table.insert(overlayLines, left)
            table.insert(overlayLines, right)
            table.insert(overlayLines, right)
            table.insert(overlayLines, tip)
        end
        for half, wedge in ipairs(triangle) do
            local visibility = visible and math.clamp(math.min(along - 2, distance - 1.32 - along) / 0.6, 0, 1) or 0
            wedge.Transparency = 1 - 0.95 * visibility
            if visible then
                local sign = half == 1 and 1 or -1
                local center = origin + forward * along + side * (sign * 0.6)
                wedge.CFrame = CFrame.fromMatrix(center, normal * sign, side * sign, -flatForward)
                wedge.Color = Color3.fromHSV((along / distance - now * 0.2) % 1, 0.85, 1)
            end
        end
    end
    self._arrowOverlay:Clear()
    self._arrowOverlay:AddLines(overlayLines)
end

--- 复用基类的节点和连接清理，并释放路线箭头的实例引用。
function Guide:HideGuideArrow()
    Guide.Super.HideGuideArrow(self)
    self._arrowTriangles = nil
    self._arrowOverlay = nil
end

--- 释放本组件的扫光、消息订阅与自建节点；箭头及引导订阅由基类释放。
function Guide:Dtor()
    if self._noticeArea then
        FX.Network:UnRegServerMsgCallback("S2C_TutorialMilestone")
        self._noticeEffect:Destroy()
        self._noticeArea:Destroy()
    end
    if self._gui then
        self._gui:Destroy()
    end
    Guide.Super.Dtor(self)
end

return Guide
