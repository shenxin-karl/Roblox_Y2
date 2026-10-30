-- 幸运商店店员：仅向靠近、面向店员且视线无遮挡的本地玩家招手。
local RunService = game:GetService("RunService")
local FX = _G.FX
local FXLoader = FX.Loader
local Comp = FX.Class("CLuckyShopCompClass", "FCPlayerCompClass")

--- 复用玩家组件生命周期管理招手，不依赖外部动画资源或新增执行入口。
--- @param owner CPlayerObjectClass 当前客户端玩家对象。
function Comp:Ctor(owner)
    Comp.Super.Ctor(self, owner)
    self._npc = FXLoader:Workspace("Decorations.LuckyShop.NPC")
    self._head = FXLoader:Here(self._npc, "Head")
    self._torso = FXLoader:Here(self._npc, "Torso")
    self._arm = FXLoader:Here(self._npc, "RightArm")
    self._restPose = self._arm:GetPivot()
    self._cooldown = 0
    self._raycastParams = RaycastParams.new()
    self._raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    self:TrackConnection(RunService.RenderStepped:Connect(function(deltaTime)
        self:RefreshWave(deltaTime)
    end))
end

--- 提供独立的商店迎宾组件协作名称。
--- @return string 组件协作名称。
function Comp:GetCompName()
    return "CLuckyShopComp"
end

--- 按角色朝向而非镜头朝向判断，避免从店后或隔墙触发迎宾。
--- @return boolean 当前玩家是否在店前 28 studs 内面向店员。
function Comp:IsFacingShopkeeper()
    local character = self:GetPlayerCharacter()
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = humanoid and humanoid.RootPart
    local head = character and character:FindFirstChild("Head")
    if not root or not head or humanoid.Health <= 0 then
        return false
    end
    local offset = self._torso.Position - root.Position
    local horizontal = Vector3.new(offset.X, 0, offset.Z)
    local forward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
    if offset.Magnitude > 28 or horizontal.Magnitude < 0.1 or forward.Magnitude < 0.1 then
        return false
    end
    if forward.Unit:Dot(horizontal.Unit) < math.cos(math.rad(35))
        or self._torso.CFrame.LookVector:Dot(-horizontal.Unit) <= 0 then
        return false
    end
    self._raycastParams.FilterDescendantsInstances = { character, self._npc }
    return workspace:Raycast(head.Position, self._head.Position - head.Position, self._raycastParams) == nil
end

--- 平滑抬手、摆手、收手；转身或离开后收手，持续注视时每五秒再次迎宾。
--- @param deltaTime number 距离上一渲染帧的秒数。
function Comp:RefreshWave(deltaTime)
    self._cooldown = math.max(0, self._cooldown - deltaTime)
    if not self._arm:IsDescendantOf(workspace) then
        return
    end
    if not self:IsFacingShopkeeper() then
        if self._waveTime then
            self._waveTime = nil
            self._arm:PivotTo(self._restPose)
        end
        return
    end
    if not self._waveTime and self._cooldown == 0 then
        self._waveTime = 0
        self._cooldown = 5
    end
    if not self._waveTime then
        return
    end
    self._waveTime += deltaTime
    local elapsed = self._waveTime
    if elapsed >= 2.4 then
        self._waveTime = nil
        self._arm:PivotTo(self._restPose)
        return
    end
    local blend = math.clamp(math.min(elapsed, 2.4 - elapsed) / 0.35, 0, 1)
    blend = blend * blend * (3 - 2 * blend)
    local angle = math.rad(140 + 18 * math.sin(elapsed * math.pi * 4)) * blend
    self._arm:PivotTo(self._restPose * CFrame.Angles(math.rad(-12) * blend, 0, angle))
end

--- 释放监听并还原本地手臂，不销毁 Studio 中维护的商店和店员。
function Comp:Dtor()
    Comp.Super.Dtor(self)
    if self._arm.Parent then
        self._arm:PivotTo(self._restPose)
    end
end

return Comp
