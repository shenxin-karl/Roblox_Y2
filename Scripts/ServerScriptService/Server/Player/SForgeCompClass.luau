-- 玩家锻造区会话：校验距离与角色，持有一个台位，并在死亡或离服时释放。
local FX = _G.FX
local Fields = _G.PlayerDataConfig
local Settings = FX.Loader:RequireShared("Scripts.Game.Shared.ForgeSettings")
local Comp = FX.Class("SForgeCompClass", "FSPlayerCompClass")

--- 每次登录重新分配会话，不将台位写入存档。
--- @param owner table 当前服务端玩家对象。
function Comp:Ctor(owner)
    Comp.Super.Ctor(self, owner)
    self._manager = _G.SForgeManager
    self._lastRequest = -math.huge
end

--- 返回玩家组件协作名。
--- @return string 锻造组件名称。
function Comp:GetCompName()
    return "SForgeComp"
end

--- 握手完成后才接受交互，换角色时释放旧角色的台位。
function Comp:OnPlayerLogin()
    self._active = true
    self:TrackConnection(self:GetPlayerNode().CharacterRemoving:Connect(function()
        self:Release()
    end))
end

--- 只允许当前会话的存活角色发起传送，不等待或复用旧角色节点。
--- @return Model? 当前有效角色。
--- @return Humanoid? 当前存活角色控制器。
function Comp:GetLivingCharacter()
    local player = self:GetPlayerNode()
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if self._active and humanoid and humanoid.Health > 0 and humanoid.RootPart then
        return character, humanoid
    end
    return nil
end

--- 传送后清除原角色速度，避免高速进入时撞上台面或滑出通道。
--- @param character Model 服务端校验过的当前角色。
--- @param humanoid Humanoid 当前角色控制器。
--- @param target CFrame 服务端固定的目标落点。
function Comp:Teleport(character, humanoid, target)
    humanoid.Sit = false
    character:PivotTo(target)
    humanoid.RootPart.AssemblyLinearVelocity = Vector3.zero
    humanoid.RootPart.AssemblyAngularVelocity = Vector3.zero
end

--- 仅在庭院附近随机取得一个空台位，分配与传送之间不让出执行。
function Comp:Enter()
    local character, humanoid = self:GetLivingCharacter()
    if not character or self._station or os.clock() - self._lastRequest < Settings.RequestCooldown
        or not self._manager:IsNear(humanoid.RootPart.Position) then
        return
    end
    self._lastRequest = os.clock()
    local station = self._manager:Allocate(self:GetPlayerId())
    if not station then
        return
    end
    self._station = station
    self._deathConnection = humanoid.Died:Connect(function()
        self:Release()
    end)
    self:Teleport(character, humanoid, station.Arrival)
    self:SetNumber(Fields.ForgeStation, station.Id)
end

--- 已分配玩家可随时离开，落点不由客户端提交；释放后空台位即可再分配。
function Comp:Leave()
    local character, humanoid = self:GetLivingCharacter()
    if not character or not self._station or os.clock() - self._lastRequest < Settings.RequestCooldown then
        return
    end
    self._lastRequest = os.clock()
    self:Teleport(character, humanoid, self._manager:GetExit())
    self:Release()
end

--- 清理台位、死亡监听与同步状态；多次调用不会释放别人的台位。
function Comp:Release()
    if self._deathConnection then
        self._deathConnection:Disconnect()
        self._deathConnection = nil
    end
    self._manager:Release(self:GetPlayerId())
    if self._station then
        self._station = nil
        self:SetNumber(Fields.ForgeStation, 0)
    end
end

--- 停止交互并释放台位，不在离服时传送角色。
function Comp:OnPlayerLogout()
    self._active = false
    self:Release()
end

--- 覆盖异常销毁路径，仍由基类清理其余连接。
function Comp:Dtor()
    self:OnPlayerLogout()
    Comp.Super.Dtor(self)
end

return Comp
