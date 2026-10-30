-- 基地主人标记仅在本地 PlayerGui 中创建，复用服务端已有的公开基地归属。
local Players = game:GetService("Players")
local FX = _G.FX
local FXLoader = FX.Loader
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

--- 首次握手完成后读取已有的基地归属快照。
function Comp:OnReady()
    self:RefreshMarkers()
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

--- 按公开归属刷新标记；不推测空基地的主人，也不等待流式场景节点。
function Comp:RefreshMarkers()
    local states = FX.SyncManager:GetTable(_G.ServerDataConfig.Bases)
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
        end
    end
end

--- 只释放本组件的界面，不影响地图、角色或其他客户端。
function Comp:Dtor()
    Comp.Super.Dtor(self)
    for baseId, marker in pairs(self._markers) do
        marker.Gui:Destroy()
    end
    table.clear(self._markers)
end

return Comp
