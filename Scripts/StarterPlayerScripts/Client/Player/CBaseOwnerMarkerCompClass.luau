-- 基地主人标记仅在本地 PlayerGui 中创建，复用服务端已有的公开基地归属。
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local FX = _G.FX
local FXLoader = FX.Loader
local MiningSettings = FXLoader:RequireShared("Scripts.Game.Shared.MiningSettings")
local Comp = FX.Class("CBaseOwnerMarkerCompClass", "FCPlayerCompClass")
local MAX_DISTANCE = 200
local MARKER_HEIGHT = 26

--- 持有本客户端创建的标记，不向地图块模型添加任何实例。
--- @param owner CPlayerObjectClass 当前客户端玩家对象。
function Comp:Ctor(owner)
    Comp.Super.Ctor(self, owner)
    self._markers = {}
    self._bases = FXLoader:Workspace("BlockMeshs.bases")
    self._playerGui = FXLoader:Player("PlayerGui")
end

--- 返回基地主人标记的稳定协作名。
--- @return string 组件名称。
function Comp:GetCompName()
    return "CBaseOwnerMarkerComp"
end

--- 读取基地归属，并随镜头更新矿区内的自家基地方向提示。
function Comp:OnReady()
    self:RefreshMarkers()
    self:TrackConnection(RunService.PreRender:Connect(function()
        self:RefreshMineGuide()
    end))
end

--- 复用框架每秒更新，处理归属变化、玩家晚复制与场景流入流出。
--- @param serverTime number 框架传入的当前时间；标记无需自行计时。
function Comp:OnUpdate(serverTime)
    self:RefreshMarkers()
end

--- 创建固定屏幕尺寸的头像和白字黑边用户名，远距离显隐由 BillboardGui 处理。
--- @param baseId string 公开快照中的基地编号。
--- @return table 本组件拥有的界面节点。
function Comp:CreateMarker(baseId)
    local gui = Instance.new("BillboardGui")
    gui.Name = "BaseOwnerMarker" .. baseId
    gui.Size = UDim2.fromOffset(140, 74)
    gui.StudsOffsetWorldSpace = Vector3.new(0, MARKER_HEIGHT, 0)
    gui.AlwaysOnTop = true
    gui.LightInfluence = 0
    gui.MaxDistance = MAX_DISTANCE
    gui.ResetOnSpawn = false
    gui.Enabled = false

    local avatar = Instance.new("ImageLabel")
    avatar.Name = "Avatar"
    avatar.BackgroundTransparency = 1
    avatar.AnchorPoint = Vector2.new(0.5, 0)
    avatar.Position = UDim2.fromScale(0.5, 0)
    avatar.Size = UDim2.fromOffset(50, 50)
    avatar.Parent = gui

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "PlayerName"
    nameLabel.BackgroundTransparency = 1
    nameLabel.Position = UDim2.fromOffset(0, 50)
    nameLabel.Size = UDim2.new(1, 0, 0, 22)
    nameLabel.AutoLocalize = false
    nameLabel.Text = ""
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 16
    nameLabel.TextColor3 = Color3.new(1, 1, 1)
    nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    nameLabel.TextStrokeTransparency = 0
    nameLabel.Parent = gui

    gui.Parent = self._playerGui
    local marker = {Gui = gui, Avatar = avatar, NameLabel = nameLabel}
    self._markers[baseId] = marker
    return marker
end

--- 复用自家基地头像和用户名，作为不挡输入的屏幕方向提示。
--- @param marker table 本人的世界头像标记。
function Comp:CreateMineGuide(marker)
    local gui = Instance.new("ScreenGui")
    gui.Name = "MineHomeGuide"
    gui.ResetOnSpawn = false
    gui.Enabled = false

    local pointer = Instance.new("Frame")
    pointer.Name = "Pointer"
    pointer.BackgroundTransparency = 1
    pointer.AnchorPoint = Vector2.new(0.5, 0.5)
    pointer.Size = UDim2.fromOffset(140, 94)
    pointer.Parent = gui
    marker.Avatar:Clone().Parent = pointer
    marker.NameLabel:Clone().Parent = pointer

    local arrow = marker.NameLabel:Clone()
    arrow.Name = "Direction"
    arrow.AnchorPoint = Vector2.new(0.5, 0)
    arrow.Position = UDim2.new(0.5, 0, 0, 72)
    arrow.Size = UDim2.fromOffset(22, 22)
    arrow.Text = "▲"
    arrow.Parent = pointer

    gui.Parent = self._playerGui
    self._mineGuide = gui
end

--- 自家基地在镜头外时，把头像沿目标方向贴到安全画面内；回到画面后使用原标记。
function Comp:RefreshMineGuide()
    local marker = self._ownMarker
    local guide = self._mineGuide
    if not marker or not guide then
        return
    end
    local character = self:GetPlayerNode().Character
    local root = character and character.PrimaryPart
    local ground = self._quarryGround
    local camera = workspace.CurrentCamera
    if not root or not ground or not ground:IsDescendantOf(workspace) or not camera or not marker.Position
        or not MiningSettings.IsInQuarry(ground, root.Position) then
        guide.Enabled = false
        return
    end

    local point, onScreen = camera:WorldToScreenPoint(marker.Position)
    local distance = (marker.Position - camera.CFrame.Position).Magnitude
    guide.Enabled = not (marker.Gui.Enabled and onScreen and distance <= MAX_DISTANCE)
    if not guide.Enabled then
        return
    end

    local center = guide.AbsoluteSize / 2
    local offset = Vector2.new(point.X, point.Y) - center
    if point.Z <= 0 then
        -- 背后的目标没有可用的透视坐标，用镜头局部方向指向侧下方。
        local relative = camera.CFrame:PointToObjectSpace(marker.Position)
        offset = Vector2.new(relative.X, math.max(1, relative.Z * 0.35))
    end
    local bounds = Vector2.new(math.max(1, center.X - 86), math.max(1, center.Y - 106))
    local scale = math.max(math.abs(offset.X) / bounds.X, math.abs(offset.Y) / bounds.Y)
    local position = center + offset / (if onScreen then math.max(1, scale) else math.max(0.001, scale))
    local pointer = guide.Pointer
    pointer.Position = UDim2.fromOffset(position.X, position.Y)
    pointer.Direction.Visible = not onScreen
    pointer.Direction.Rotation = math.deg(math.atan2(offset.X, -offset.Y))
end

--- 按公开归属刷新标记；矿区提示使用同步的基地坐标，不等待流式场景节点。
function Comp:RefreshMarkers()
    local states = FX.SyncManager:GetTable(_G.ServerDataConfig.Bases)
    self._ownMarker = nil
    self._quarryGround = FXLoader:FindFromWorkspace(MiningSettings.GroundPath)
    for baseId, marker in pairs(self._markers) do
        local state = states[baseId]
        if not state or state.OwnerUserId == 0 then
            marker.Gui:Destroy()
            self._markers[baseId] = nil
        end
    end
    for baseId, state in pairs(states) do
        if state.OwnerUserId > 0 then
            local marker = self._markers[baseId] or self:CreateMarker(baseId)
            local player = Players:GetPlayerByUserId(state.OwnerUserId)
            local floor = FXLoader:Find(self._bases, "base" .. baseId .. ".BaseLower.Architecture.LowerFloor")
            marker.Gui.Adornee = floor
            marker.Gui.Enabled = player ~= nil and floor ~= nil
            if player and marker.OwnerUserId ~= player.UserId then
                marker.OwnerUserId = player.UserId
                marker.NameLabel.Text = player.Name
                marker.Avatar.Image = string.format(
                    "rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", player.UserId
                )
            end
            if player == self:GetPlayerNode() then
                self._ownMarker = marker
                marker.Position = state.Position and state.Position + marker.Gui.StudsOffsetWorldSpace
                if not self._mineGuide then
                    self:CreateMineGuide(marker)
                end
            end
        end
    end
    if not self._ownMarker and self._mineGuide then
        self._mineGuide.Enabled = false
    end
end

--- 只释放本组件的界面，不影响地图、角色或其他客户端。
function Comp:Dtor()
    Comp.Super.Dtor(self)
    if self._mineGuide then
        self._mineGuide:Destroy()
    end
    for baseId, marker in pairs(self._markers) do
        marker.Gui:Destroy()
    end
    table.clear(self._markers)
end

return Comp
