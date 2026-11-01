-- 锻造入口按钮：只显示交互和发送请求，占用、距离与传送均由服务端裁定。
local RunService = game:GetService("RunService")
local FX, FC = _G.FX, _G.FC
local FXLoader = FX.Loader
local Text = FX.Text
local Fields = _G.PlayerDataConfig
local Settings = FXLoader:RequireShared("Scripts.Game.Shared.ForgeSettings")
local UIRoot = FXLoader:RequireShared("Scripts.Framework.Client.FCUIRoot")
local TranslationTexts = Text.Define("ForgeInteraction", {
    Enter = "Forge",
    Leave = "Leave forge station",
})
local Comp = FX.Class("CForgeCompClass", "FCUICompClass")

--- 返回锻造按钮的稳定组件名。
--- @return string 组件名称。
function Comp:GetCompName()
    return "CForgeComp"
end

--- 数据就绪后创建独立按钮，不修改 Generated 或共享画布本身。
function Comp:OnReady()
    self._area = FXLoader:Workspace(Settings.AreaPath)
    local button = Instance.new("TextButton")
    button.Name = "ForgeInteraction"
    button.AnchorPoint = Vector2.new(0.5, 1)
    button.Position = UDim2.new(0.5, 0, 1, -130)
    button.Size = UDim2.fromOffset(240, 54)
    button.BackgroundColor3 = Color3.fromRGB(150, 77, 30)
    button.TextColor3 = Color3.new(1, 1, 1)
    button.Font = Enum.Font.GothamBold
    button.TextSize = 20
    button.AutoLocalize = false
    button.Visible = false
    button.Parent = UIRoot.Get()
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
        self:Refresh()
    end))
    self:TrackConnection(RunService.Heartbeat:Connect(function()
        self:Refresh()
    end))
end

--- 根据权威占用切换文案；未占用时只在锻造庭院附近显示按钮。
function Comp:Refresh()
    local character = self:GetPlayerCharacter()
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = humanoid and humanoid.RootPart
    local assigned = self:GetNumber(Fields.ForgeStation) > 0
    local visible = false
    if root and humanoid.Health > 0 then
        local offset = self._area.CFrame:PointToObjectSpace(root.Position)
        visible = assigned or (math.abs(offset.X) <= self._area.Size.X / 2 + Settings.ShowDistance
            and math.abs(offset.Z) <= self._area.Size.Z / 2 + Settings.ShowDistance
            and math.abs(offset.Y - self._area.Size.Y / 2) <= Settings.HeightTolerance)
    end
    self._rootNode.Visible = visible
    if self._textAssigned ~= assigned then
        self._textAssigned = assigned
        self._rootNode.Text = Text.Tr(assigned and TranslationTexts.Leave or TranslationTexts.Enter)
    end
end

--- 只销毁本组件的按钮，不清理框架共享画布。
function Comp:Dtor()
    Comp.Super.Dtor(self)
    if self._rootNode then
        self._rootNode:Destroy()
    end
end

return Comp
