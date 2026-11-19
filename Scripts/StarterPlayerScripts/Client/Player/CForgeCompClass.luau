-- 锻造交互与本地表现：台位与材料兑换由服务端裁定，命中动画只发起一次请求。
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local FX, FC = _G.FX, _G.FC
local FXLoader = FX.Loader
local Text = FX.Text
local Fields = _G.PlayerDataConfig
local Settings = FXLoader:RequireShared("Scripts.Game.Shared.ForgeSettings")
local UIRoot = FXLoader:RequireShared("Scripts.Framework.Client.FCUIRoot")
local Effects = FXLoader:RequireFromParent(script, "CForgeEffects")
local ForgeView = FXLoader:Require(script.Parent.Parent, "UI.CForgeView")
local ActionButton = FXLoader:Require(script.Parent.Parent, "UI.CActionButton")
local TranslationTexts = Text.Define("ForgeInteraction", {
    Enter = "前往锻造台",
    Leave = "离开锻造台",
    Recipe = "使用剑胚逐锤锻造，可随时出炉。",
    Return = "返回庭院",
    PersonalForge = "Forge Sword",
    PersonalSmelt = "Smelt Sword Blank",
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

--- 数据就绪后绑定原生锻造界面与右侧入口，沿用现有服务端进出协议。
function Comp:OnReady()
    self._area = FXLoader:Workspace(Settings.AreaPath)
    self._forge = FXLoader:Workspace(Settings.StationPath)
    self._view = ForgeView.New(FXLoader:PlayerGui("Forge"))
    self._mainHUD = FXLoader:PlayerGui("Main.HUD")
    self._renderName = "ForgeCamera_" .. self:GetPlayerId()
    self._actionName = "ForgeInput_" .. self:GetPlayerId()
    self._hiddenCharacter = {}
    self._personalPrompts = {}
    local button, title, detail = ActionButton.New("ForgeInteraction", UIRoot.Get())
    self._buttonTitle, self._buttonDetail = title, detail
    self._rootNode = button
    self._lastRequest = -math.huge
    self:TrackConnection(button.Activated:Connect(function()
        if not button.Visible or os.clock() - self._lastRequest < Settings.RequestCooldown then
            return
        end
        self._lastRequest = os.clock()
        local message = self:GetNumber(Fields.ForgeStation) > 0 and "C2S_LeaveForge" or "C2S_EnterForge"
        FX.Network:SendMsgToServer(message)
    end))
    self:WatchDataChanged(Fields.ForgeStation, function()
        self:Refresh()
    end)
    self:TrackConnection(FC.Localization.Changed:Connect(function()
        self._textAssigned = nil
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
    self:WatchDataChanged(Fields.ForgeData, function()
        local data = self:GetTable(Fields.ForgeData)
        self._view:SetForgeData(data)
        if self._effects then
            if data.Quality then
                self._effects:SetQuality(data.Quality)
            end
            self._effects:SetWeaponVisible(data.Active == true and data.Outcome ~= "Destroyed")
        end
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

--- 根据权威占用切换文案，并分别显示公共庭院按钮和本人基地的工位提示。
function Comp:Refresh()
    local character = self:GetPlayerCharacter()
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = humanoid and humanoid.RootPart
    local stationId = self:GetNumber(Fields.ForgeStation)
    local assigned = stationId > 0
    local workshop = Settings.FindPersonalWorkshop(self:GetNumber(Fields.BaseId))
    self:RefreshPersonalPrompts(workshop, root ~= nil and humanoid.Health > 0 and not assigned)
    local visible = false
    if root and humanoid.Health > 0 then
        local offset = self._area.CFrame:PointToObjectSpace(root.Position)
        visible = assigned or (math.abs(offset.X) <= self._area.Size.X / 2 + Settings.ShowDistance
            and math.abs(offset.Z) <= self._area.Size.Z / 2 + Settings.ShowDistance
            and math.abs(offset.Y - self._area.Size.Y / 2) <= Settings.HeightTolerance)
    end
    if self._stationId and (stationId ~= self._stationId or not visible) then
        self:CloseView()
    end
    if assigned and visible and not self._effects and not self._opening then
        self:TryOpenView(stationId)
    end
    self._rootNode.Visible = visible and not self._effects
    if self._textAssigned ~= stationId then
        self._textAssigned = stationId
        self._buttonTitle.Text = Text.Tr(assigned and TranslationTexts.Leave or TranslationTexts.Enter)
        if stationId > Settings.PersonalStationOffset then
            self._buttonDetail.Text = ""
        else
            self._buttonDetail.Text = Text.Tr(assigned and TranslationTexts.Return or TranslationTexts.Recipe)
        end
    end
end

--- StreamingEnabled 下先等实际台位复制齐全，不在逐帧入口中等待必需子节点。
--- @param stationId number 服务端同步的当前台位编号。
function Comp:TryOpenView(stationId)
    local station
    if stationId > Settings.PersonalStationOffset then
        local workshop = Settings.FindPersonalWorkshop(stationId - Settings.PersonalStationOffset)
        station = workshop and workshop:FindFirstChild("ForgeTable")
    else
        local side = stationId <= 4 and "Lower_" or "Upper_"
        station = self._forge:FindFirstChild(side .. ((stationId - 1) % 4 + 1))
    end
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
    local data = self:GetTable(Fields.ForgeData)
    self._view:SetForgeData(data)
    if data.Quality then
        effects:SetQuality(data.Quality)
    end
    effects:SetWeaponVisible(data.Active == true and data.Outcome ~= "Destroyed")
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

--- 主动出炉沿用服务端进度与容量校验，挥锤期间不提交收手请求。
function Comp:FinishSword()
    if self._effects and not self._effects:IsBusy() then
        FX.Network:SendMsgToServer("C2S_FinishSword")
    end
end

--- 落锤时只请求一次服务端敲击，结果由同步进度与回执驱动。
--- @param powerful boolean 沿用动画接口，实际锻造固定使用普通敲击。
function Comp:Strike(powerful)
    if self._effects and self._effects:Strike(powerful, function()
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

--- 退出、死亡与组件销毁统一还原镜头、角色显示和主 HUD。
function Comp:CloseView()
    if not self._effects then
        return
    end
    ContextActionService:UnbindAction(self._actionName)
    self._effects:Destroy()
    self._effects, self._stationId, self._station = nil, nil, nil
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
