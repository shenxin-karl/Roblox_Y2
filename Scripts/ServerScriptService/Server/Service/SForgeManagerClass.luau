-- 私人锻造台跟随基地归属，进台时校验本人台位。
local FX = _G.FX
local FXLoader = FX.Loader
local Settings = FXLoader:RequireShared("Scripts.Game.Shared.ForgeSettings")
local Manager = FX.Class("SForgeManagerClass")

--- 用从地面到桌面的平整碰撞体挡住角色，避免横梁和桌沿被当成梯级。
--- @param desktop BasePart 保留给交互和锻造表现使用的原桌面。
--- @param groundY number 工位地面的上表面高度。
local function SetTableCollision(desktop, groundY)
    local model = desktop.Parent
    local topY = desktop.Position.Y + desktop.Size.Y / 2
    local height = topY - groundY
    local collider = Instance.new("Part")
    collider.Name = "ForgeTableCollision"
    collider.Size = Vector3.new(desktop.Size.X, height, desktop.Size.Z)
    collider.CFrame = desktop.CFrame + Vector3.new(0, (groundY + topY) / 2 - desktop.Position.Y, 0)
    collider.Anchored = true
    collider.Transparency = 1
    collider.CastShadow = false
    collider.CanTouch = false
    collider.CollisionGroup = desktop.CollisionGroup
    for index, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = false
        end
    end
    collider.Parent = model
end

--- 初始化私人锻造台碰撞，避免角色踩上桌沿。
function Manager:Ctor()
    self._personalGround = FXLoader:Workspace(Settings.PersonalGroundPath)
    local decorations = FXLoader:Workspace("Decorations")
    local personalGroundY = self._personalGround.Position.Y + self._personalGround.Size.Y / 2
    for index, workshop in ipairs(decorations:GetChildren()) do
        if workshop.Name:match("^PersonalWorkshop_Base%d+$") then
            local desktop = FXLoader:Find(workshop, Settings.PersonalForgePart)
            if desktop then
                SetTableCollision(desktop, personalGroundY)
            end
        end
    end

end

--- 只取本人基地的桌面，按桌子正面和草地高度计算操作落点。
--- @param base table? 玩家会话当前分到的基地。
--- @param userId number 已认证玩家 ID。
--- @param position Vector3 服务端读取的角色根节点位置。
--- @return table? 可进入的私人台位。
function Manager:GetPersonalStation(base, userId, position)
    if not base or base.OwnerUserId ~= userId then
        return nil
    end
    local workshop = Settings.FindPersonalWorkshop(base.Id)
    local desktop = workshop and FXLoader:Find(workshop, Settings.PersonalForgePart)
    if not desktop or (desktop.Position - position).Magnitude > Settings.PersonalInteractDistance then
        return nil
    end
    local front = desktop.CFrame * CFrame.new(0, 0, -desktop.Size.Z / 2 - Settings.StationClearance)
    local height = self._personalGround.Position.Y + self._personalGround.Size.Y / 2 + Settings.ArrivalHeight
    local arrival = Vector3.new(front.X, height, front.Z)
    local target = Vector3.new(desktop.Position.X, height, desktop.Position.Z)
    return {
        Id = Settings.PersonalStationOffset + base.Id,
        Arrival = CFrame.lookAt(arrival, target),
        OwnerUserId = userId,
        Base = base,
    }
end

return Manager
