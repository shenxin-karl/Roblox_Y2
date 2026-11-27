-- 玩家矿场入口：校验矿区传送与私人工坊熔炼请求。
local FX = _G.FX
local Settings = FX.Loader:RequireShared("Scripts.Game.Shared.MiningSettings")
local Comp = FX.Class("SMiningCompClass", "FSPlayerCompClass")

--- 建立各类请求的服务端冷却。
--- @param owner table 服务端玩家对象。
function Comp:Ctor(owner)
    Comp.Super.Ctor(self, owner)
    self._lastRequest = -math.huge
end

--- 返回协议转发使用的组件名。
--- @return string 组件协作名。
function Comp:GetCompName()
    return "SMiningComp"
end

--- 通过存活角色的服务端位置执行矿区传送。
function Comp:TeleportToMine()
    local manager = _G.SMiningManager
    if not self._active or os.clock() - self._lastRequest < Settings.RequestCooldown then
        return
    end
    local forge = self:RequireComponent("SForgeComp")
    local character, humanoid = forge:GetLivingCharacter()
    if not character or humanoid.PlatformStand then
        return
    end
    self._lastRequest = os.clock()
    forge:Teleport(character, humanoid, manager:GetArrival())
    forge:Release()
end

--- 只有已登录、未倒地且未在锻造的存活角色才能请求熔炼。
function Comp:RequestSmelt()
    if not self._active or os.clock() - self._lastRequest < Settings.RequestCooldown then
        return
    end
    local character, humanoid = self:RequireComponent("SForgeComp"):GetLivingCharacter()
    if not character or humanoid.PlatformStand or self:GetNumber(_G.PlayerDataConfig.ForgeStation) > 0 then
        return
    end
    self._lastRequest = os.clock()
    _G.SMiningManager:Smelt(self:GetPlayerObject(), humanoid)
end

--- 按当前角色和会话校验发射；矿场服务只接受实际坐在操作椅上的玩家。
--- @param target any 客户端点击的世界 XZ 坐标。
function Comp:RequestClaw(target)
    local now = os.clock()
    if not self._active or now - self._lastRequest < Settings.RequestCooldown then
        return
    end
    self._lastRequest = now
    local character, humanoid = self:RequireComponent("SForgeComp"):GetLivingCharacter()
    if character and not humanoid.PlatformStand and self:GetNumber(_G.PlayerDataConfig.ForgeStation) <= 0 then
        _G.SMiningManager:CastClaw(self, humanoid, target)
    end
end

--- 只允许仍在原会话里的抓取结算。
--- @return boolean 会话是否仍允许矿场操作。
function Comp:IsMiningActive()
    return self._active == true
end

--- 玩家登录后开放矿区交互。
function Comp:OnPlayerLogin()
    self._active = true
end

--- 离服后拒绝后续交互。
function Comp:OnPlayerLogout()
    self._active = false
end

return Comp
