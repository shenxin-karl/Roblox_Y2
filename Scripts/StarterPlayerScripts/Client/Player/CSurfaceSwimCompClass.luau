-- 水面游泳：沿用原生游泳控制，只限制角色下潜。
local RunService = game:GetService("RunService")
local FX = _G.FX
local Comp = FX.Class("CSurfaceSwimCompClass", "FCPlayerCompClass")

--- 只检测地形水面，避免角色或海边装饰遮挡水位查询。
--- @param owner CPlayerObjectClass 当前客户端玩家对象。
function Comp:Ctor(owner)
    Comp.Super.Ctor(self, owner)
    self._params = RaycastParams.new()
    self._params.FilterType = Enum.RaycastFilterType.Include
    self._params.FilterDescendantsInstances = { workspace.Terrain }
    self:TrackConnection(RunService.PostSimulation:Connect(function()
        self:KeepAtSurface()
    end))
end

--- 提供水面游泳组件的协作名称。
--- @return string 组件协作名称。
function Comp:GetCompName()
    return "CSurfaceSwimComp"
end

--- 角色游到水面以下时只修正高度和向下的速度，保留横向游动与出水动作。
function Comp:KeepAtSurface()
    local character = self:GetPlayerCharacter()
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid:GetState() ~= Enum.HumanoidStateType.Swimming then
        return
    end
    local root = humanoid.RootPart
    if not root then
        return
    end
    local hit = workspace:Raycast(root.Position + Vector3.yAxis * 128, -Vector3.yAxis * 132, self._params)
    if not hit or hit.Material ~= Enum.Material.Water then
        return
    end
    local lift = hit.Position.Y - root.Size.Y * 0.5 - root.Position.Y
    if lift >= 0 then
        root.CFrame += Vector3.yAxis * lift
        local velocity = root.AssemblyLinearVelocity
        if velocity.Y < 0 then
            root.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
        end
    end
end

return Comp
