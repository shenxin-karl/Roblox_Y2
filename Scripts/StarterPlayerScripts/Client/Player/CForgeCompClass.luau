-- 锻造交互与本地表现：台位与材料兑换由服务端裁定，命中动画只发起一次请求。
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local FX, FC = _G.FX, _G.FC
local FXLoader = FX.Loader
local Text = FX.Text
local Fields = _G.PlayerDataConfig
local Settings = FXLoader:RequireShared("Scripts.Game.Shared.ForgeSettings")
local Rules = FXLoader:RequireShared("Scripts.Game.Shared.SwordRules")
local Effects = FXLoader:RequireFromParent(script, "CForgeEffects")
local ForgeView = FXLoader:Require(script.Parent.Parent, "UI.CForgeView")
local ActionButton = FXLoader:Require(script.Parent.Parent, "UI.CActionButton")
local DiamondPurchase = FXLoader:Require(script.Parent.Parent, "UI.CDiamondPurchase")
local RecoveryOfferId = "forge_recovery"
local TranslationTexts = Text.Define("ForgeInteraction", {
    Leave = "Leave Forge",
    PersonalForge = "Forge Sword",
    PersonalSmelt = "Smelt Sword Blank",
    RecoveryTitle = "Restore Weapon",
    RecoveryCategory = "FORGE RECOVERY",
    RecoveryDescription = "Restore this destroyed weapon and continue forging.",
})
local PersonalActions = {
    {PartPath = Settings.PersonalForgePart, Text = TranslationTexts.PersonalForge, Message = "C2S_EnterForge"},
    {PartPath = Settings.PersonalFurnacePart, Text = TranslationTexts.PersonalSmelt, Message = "C2S_SmeltSword"},
}
local Comp = FX.Class("CForgeCompClass", "FCUICompClass")

--- 返回锻造按钮的稳定组件名。
--- @return string 组件名称。
function Comp:GetCompName()
    return "CForgeComp"
end

--- 数据就绪后绑定锻造界面，并用服务端同步的品质变化触发换剑。
function Comp:OnReady()
    self._view = ForgeView.New(FXLoader:PlayerGui("Forge"))
    self._mainHUD = FXLoader:PlayerGui("Main.HUD")
    self._renderName = "ForgeCamera_" .. self:GetPlayerId()
    self._actionName = "ForgeInput_" .. self:GetPlayerId()
    self._hiddenCharacter = {}
    self._personalPrompts = {}
    local button, title = ActionButton.New("ForgeInteraction")
    title.Text = Text.Tr(TranslationTexts.Leave)
    self._rootNode = button
    self._lastRequest = -math.huge
    self._lastRecoveryRequest = -math.huge
    self:TrackConnection(button.Activated:Connect(function()
        if not button.Visible or os.clock() - self._lastRequest < Settings.RequestCooldown then
            return
        end
        self._lastRequest = os.clock()
        FX.Network:SendMsgToServer("C2S_LeaveForge")
    end))
    self:WatchDataChanged(Fields.ForgeStation, function()
        self:Refresh()
    end)
    self:TrackConnection(FC.Localization.Changed:Connect(function()
        title.Text = Text.Tr(TranslationTexts.Leave)
        for action, prompt in pairs(self._personalPrompts) do
            prompt.ActionText = Text.Tr(action.Text)
        end
        self._view:RefreshText()
        self:Refresh()
    end))
    self:TrackConnection(self._view.StrikeButton.Activated:Connect(function()
        self:Strike(false)
    end))
    self:TrackConnection(self._view.GreatStrikeButton.Activated:Connect(function()
        self:FinishSword()
    end))
    self:TrackConnection(self._view.RecoveryButton.Activated:Connect(function()
        self:RequestRecovery()
    end))
    FX.Network:RegServerMsgCallback("S2C_ForgeRecoveryInsufficientDiamonds", function(failureId)
        if self._effects and self:GetTable(Fields.ForgeData).RecoveryId == failureId then
            DiamondPurchase.Open()
        end
    end)
    self:WatchDataChanged(Fields.ForgeData, function(data, previous)
        self:ApplyForgeData(data, previous)
    end)
    FX.Network:RegServerMsgCallback("S2C_ForgeSwordResult", function(stationId, success)
        if self._effects and self._stationId == stationId then
            if success then
                self._strikeCount += 1
                self._view:Impact(false, self._strikeCount)
            else
                self._view:ShowFailure()
            end
        end
    end)
    self:TrackConnection(self._view.LeaveButton.Activated:Connect(function()
        self:RequestLeave()
    end))
    self:TrackConnection(self:GetPlayerNode().CharacterRemoving:Connect(function()
        self:CloseView()
    end))
    self:TrackConnection(RunService.Heartbeat:Connect(function()
        self:Refresh()
    end))
    RunService:BindToRenderStep(self._renderName, Enum.RenderPriority.Camera.Value + 1, function(deltaTime)
        self:UpdateView(deltaTime)
    end)
end

--- 刚上台时保留剑胚的外观和变异光环，首次升品质时切换到新武器。
--- @param data table 服务端同步的最新锻造状态。
--- @param previous table? 上一次同步状态；进台时不传。
function Comp:ApplyForgeData(data, previous)
    self._view:SetForgeData(data)
    if not self._effects then
        return
    end
    local upgraded = false
    if previous then
        if data.Outcome == "Success" then
            upgraded = not previous.Active or data.HammerCount > previous.HammerCount
        elseif data.Outcome == "Finished" and previous.Active then
            -- 最后一锤的升级和自动领取可能合并成一条状态。
            upgraded = data.HammerCount > previous.HammerCount and data.Quality > previous.Quality
        end
    end
    local displayQuality = data.HammerCount == 0 and 1 or data.Quality
    local upgradeFrom = upgraded and (previous.HammerCount == 0 and 1 or data.Quality - 1) or nil
    local mutationId = data.HammerCount == 0 and data.MutationId or nil
    self._effects:ApplyWeapon(displayQuality, data.Active == true and data.Outcome ~= "Destroyed", upgradeFrom, mutationId)
end

--- 显示当前损毁武器的恢复报价，玩家确认后才提交。
function Comp:RequestRecovery()
    if not self._effects or self._effects:IsBusy()
        or os.clock() - self._lastRecoveryRequest < Settings.RequestCooldown then
        return
    end
    local data = self:GetTable(Fields.ForgeData)
    if data.Outcome == "Destroyed" and data.RecoveryId then
        local failureId = data.RecoveryId
        DiamondPurchase.Confirm({
            itemId = RecoveryOfferId,
            name = TranslationTexts.RecoveryTitle.Source,
            category = TranslationTexts.RecoveryCategory.Source,
            description = TranslationTexts.RecoveryDescription.Source,
            price = Settings.RecoveryDiamondCost,
            icon = "rbxassetid://115692379614617",
        }, function()
            return self:SubmitRecovery(failureId)
        end)
    end
end

--- 确认时重新核对当前台位和损毁进度，不能对已经切换的武器发起恢复。
--- @param failureId string 打开确认页时的损毁标识。
--- @return string 请求已提交或当前不能恢复的原因。
function Comp:SubmitRecovery(failureId)
    local data = self:GetTable(Fields.ForgeData)
    if not self._effects or self._effects:IsBusy() or data.Outcome ~= "Destroyed"
        or data.RecoveryId ~= failureId or os.clock() - self._lastRecoveryRequest < Settings.RequestCooldown then
        return "Stale"
    end
    if self:GetNumber(Fields.Diamonds) < Settings.RecoveryDiamondCost then
        return "InsufficientDiamonds"
    end
    self._lastRecoveryRequest = os.clock()
    FX.Network:SendMsgToServer("C2S_RecoverForgeSword", failureId)
    return "Submitted"
end

--- 仅为本人基地创建本地提示，节点流送回来后重新挂到对应桌面或炉台。
--- @param workshop Model? 当前客户端可见的本人小工坊。
--- @param enabled boolean 角色存活且没有进入锻造界面时允许提示。
function Comp:RefreshPersonalPrompts(workshop, enabled)
    for index, action in ipairs(PersonalActions) do
        local part = workshop and FXLoader:Find(workshop, action.PartPath)
        local prompt = self._personalPrompts[action]
        if prompt and (not part or prompt.Parent ~= part) then
            prompt:Destroy()
            self._personalPrompts[action] = nil
            prompt = nil
        end
        if not prompt and part then
            prompt = Instance.new("ProximityPrompt")
            prompt.AutoLocalize = false
            prompt.ActionText = Text.Tr(action.Text)
            prompt.MaxActivationDistance = Settings.PersonalInteractDistance
            prompt.RequiresLineOfSight = false
            prompt.Enabled = enabled
            prompt.Triggered:Connect(function()
                FX.Network:SendMsgToServer(action.Message)
            end)
            prompt.Parent = part
            self._personalPrompts[action] = prompt
        elseif prompt then
            prompt.Enabled = enabled
        end
    end
end

--- 仅显示本人基地的工位提示，台位尚未加载时仍可退出。
function Comp:Refresh()
    local character = self:GetPlayerCharacter()
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = humanoid and humanoid.RootPart
    local stationId = self:GetNumber(Fields.ForgeStation)
    local assigned = stationId > 0
    local workshop = Settings.FindPersonalWorkshop(self:GetNumber(Fields.BaseId))
    self:RefreshPersonalPrompts(workshop, root ~= nil and humanoid.Health > 0 and not assigned)
    local visible = assigned and root ~= nil and humanoid.Health > 0
    if self._stationId and (stationId ~= self._stationId or not visible) then
        self:CloseView()
    end
    if visible and not self._effects and not self._opening then
        self:TryOpenView(stationId)
    end
    self._rootNode.Visible = visible and not self._effects

end

--- 等台位复制齐全后打开近景，直接呈现进入时的权威武器状态。
--- @param stationId number 服务端同步的当前台位编号。
function Comp:TryOpenView(stationId)
    local workshop = Settings.FindPersonalWorkshop(stationId - Settings.PersonalStationOffset)
    local station = workshop and workshop:FindFirstChild("ForgeTable")
    local desktop = station and station:FindFirstChild("ThickSteelDesktop")
    local board = station and station:FindFirstChild("BlankDisplayBoard")
    local panel = board and board:FindFirstChild("BlankWoodPanel")
    local hammer = station and station:FindFirstChild("BlackHammer")
    if not desktop or not panel or not board:FindFirstChild("BottomTimberFrame")
        or not hammer or not hammer:FindFirstChild("BlackHammerHandle")
        or not hammer:FindFirstChild("BlackForgedHammerHead") or not hammer:FindFirstChild("BlackHammerCollar") then
        return
    end
    local camera = workspace.CurrentCamera
    if not camera then
        return
    end
    self._opening = true
    local effects = Effects.New(station)
    -- 资源加载可能让出执行，恢复后仍需属于同一权威台位。
    if self._destroyed or self:GetNumber(Fields.ForgeStation) ~= stationId then
        effects:Destroy()
        self._opening = false
        return
    end
    self._effects, self._stationId, self._station = effects, stationId, station
    self._strikeCount = 0
    self._camera = camera
    self._savedCamera = {
        Type = camera.CameraType, Subject = camera.CameraSubject,
        CFrame = camera.CFrame, Focus = camera.Focus, FieldOfView = camera.FieldOfView,
    }
    local base = desktop.CFrame
    local position = base:PointToWorldSpace(Vector3.new(-1.3, 5.5, -8.7))
    local target = base:PointToWorldSpace(Vector3.new(-1.3, 2.5, 1))
    self._cameraFrame = CFrame.lookAt(position, target)
    self._cameraFocus = CFrame.new(target)
    self._savedHUDVisible = self._mainHUD.Visible
    self._mainHUD.Visible = false
    camera.CameraType = Enum.CameraType.Scriptable
    self._view:Open(effects:GetBoardPanel(), stationId)
    self:ApplyForgeData(self:GetTable(Fields.ForgeData))
    ContextActionService:BindActionAtPriority(self._actionName, function(actionName, inputState, inputObject)
        return self:HandlePreviewInput(actionName, inputState, inputObject)
    end, false, 3000, Enum.KeyCode.F, Enum.KeyCode.G, Enum.KeyCode.E,
        Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonB,
        Enum.PlayerActions.CharacterForward, Enum.PlayerActions.CharacterBackward,
        Enum.PlayerActions.CharacterLeft, Enum.PlayerActions.CharacterRight, Enum.PlayerActions.CharacterJump)
    self._opening = false
end

--- 键盘和手柄只操作本人锻造台，聊天框输入不触发敲击。
--- @param actionName string ContextActionService 传入的本组件动作名。
--- @param inputState Enum.UserInputState 当前输入阶段。
--- @param inputObject InputObject 当前按键或手柄输入。
--- @return Enum.ContextActionResult 是否消费此次输入。
function Comp:HandlePreviewInput(actionName, inputState, inputObject)
    if actionName ~= self._actionName or UserInputService:GetFocusedTextBox() then
        return Enum.ContextActionResult.Pass
    end
    if inputState == Enum.UserInputState.Begin then
        local key = inputObject.KeyCode
        if key == Enum.KeyCode.F or key == Enum.KeyCode.ButtonR2 then
            self:Strike(false)
        elseif key == Enum.KeyCode.G then
            self:FinishSword()
        elseif key == Enum.KeyCode.E or key == Enum.KeyCode.ButtonB then
            self:RequestLeave()
        end
    end
    return Enum.ContextActionResult.Sink
end

--- 台上有剑即可主动出炉，挥锤期间等待当前结果。
function Comp:FinishSword()
    if self._effects and not self._effects:IsBusy() then
        local data = self:GetTable(Fields.ForgeData)
        if data.Active then
            FX.Network:SendMsgToServer("C2S_FinishSword")
        end
    end
end

--- 台上有剑才挥锤；仍在台位上时可先放入手持的新剑胚。
--- @param powerful boolean 沿用动画接口，实际锻造固定使用普通敲击。
function Comp:Strike(powerful)
    if not self._effects or self._effects:IsBusy() then
        return
    end
    if not self:GetTable(Fields.ForgeData).Active then
        local character = self:GetPlayerCharacter()
        local tool = character and character:FindFirstChildOfClass("Tool")
        if not tool or tool:GetAttribute("FrameworkItemId") ~= Rules.BlankItemId then
            self._view:ShowFailure()
            return
        end
        FX.Network:SendMsgToServer("C2S_EnterForge")
        return
    end
    if self._effects:Strike(powerful, function()
        FX.Network:SendMsgToServer("C2S_ForgeSword")
    end) then
        self._view:SetBusy(true)
    end
end

--- 离开仍由服务端执行与释放台位，挥锤期间也允许退出。
function Comp:RequestLeave()
    if not self._effects or os.clock() - self._lastRequest < Settings.RequestCooldown then
        return
    end
    self._lastRequest = os.clock()
    FX.Network:SendMsgToServer("C2S_LeaveForge")
end

--- 在默认相机之后更新近景，横竖屏都保留完整木板宽度。
--- @param deltaTime number 本渲染帧经过的秒数。
function Comp:UpdateView(deltaTime)
    if not self._effects then
        return
    end
    local character = self:GetPlayerCharacter()
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 or not self._station:IsDescendantOf(workspace) then
        self:CloseView()
        return
    end
    local camera = workspace.CurrentCamera
    if camera ~= self._camera then
        self:CloseView()
        return
    end
    -- 只覆盖本帧移动指令，不改 WalkSpeed、JumpPower 或服务端角色锚定状态。
    humanoid:Move(Vector3.zero, false)
    humanoid.Jump = false
    for index, node in ipairs(character:GetDescendants()) do
        if node:IsA("BasePart") then
            if self._hiddenCharacter[node] == nil then
                self._hiddenCharacter[node] = node.LocalTransparencyModifier
            end
            node.LocalTransparencyModifier = 1
        end
    end
    self._effects:Update(deltaTime)
    self._view:SetBusy(self._effects:IsBusy())
    local size = camera.ViewportSize
    local aspect = size.X / math.max(1, size.Y)
    local fieldOfView = math.deg(2 * math.atan(12.8 / (2 * 9 * aspect)))
    camera.FieldOfView = math.clamp(fieldOfView, 44, 95)
    local frame = self._cameraFrame
    if fieldOfView > 95 then
        -- 窄竖屏达到视角上限后沿视线后退，保留完整锤子而不是继续拉伸视角。
        local retreat = 12.8 / (2 * aspect * math.tan(math.rad(95) / 2)) - 9
        frame *= CFrame.new(0, 0, retreat)
    end
    camera.CameraType = Enum.CameraType.Scriptable
    camera.CFrame = frame * self._effects:GetShake()
    camera.Focus = self._cameraFocus
    self._view:Resize(size)
    self._mainHUD.Visible = false
end

--- 退出、死亡与组件销毁统一关闭恢复报价，并还原镜头、角色显示和主 HUD。
function Comp:CloseView()
    if not self._effects then
        return
    end
    ContextActionService:UnbindAction(self._actionName)
    self._effects:Destroy()
    self._effects, self._stationId, self._station = nil, nil, nil
    DiamondPurchase.CloseConfirmation(RecoveryOfferId)
    self._view:Close()
    for part, transparency in pairs(self._hiddenCharacter) do
        if part.Parent then
            part.LocalTransparencyModifier = transparency
        end
    end
    table.clear(self._hiddenCharacter)
    self._mainHUD.Visible = self._savedHUDVisible
    local camera, saved = self._camera, self._savedCamera
    if camera and camera.Parent then
        camera.CFrame, camera.Focus, camera.FieldOfView = saved.CFrame, saved.Focus, saved.FieldOfView
        local character = self:GetPlayerCharacter()
        camera.CameraSubject = saved.Subject and saved.Subject.Parent and saved.Subject
            or (character and character:FindFirstChildOfClass("Humanoid"))
        camera.CameraType = saved.Type
    end
    self._camera, self._savedCamera = nil, nil
end

--- 清理本组件按钮、输入、相机和表现，不销毁框架画布或 Studio 模板。
function Comp:Dtor()
    self._destroyed = true
    FX.Network:UnRegServerMsgCallback("S2C_ForgeSwordResult")
    FX.Network:UnRegServerMsgCallback("S2C_ForgeRecoveryInsufficientDiamonds")
    self:CloseView()
    if self._personalPrompts then
        self:RefreshPersonalPrompts(nil, false)
    end
    if self._renderName then
        RunService:UnbindFromRenderStep(self._renderName)
    end
    if self._view then
        self._view:Destroy()
    end
    Comp.Super.Dtor(self)
    if self._rootNode then
        self._rootNode:Destroy()
    end
end

return Comp
