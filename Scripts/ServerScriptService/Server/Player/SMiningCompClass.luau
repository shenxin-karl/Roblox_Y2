-- 玩家矿场会话：独立刷新、登录、存活和节流校验，矿石与配方由服务端裁定。
local FX = _G.FX
local Settings = FX.Loader:RequireShared("Scripts.Game.Shared.MiningSettings")
local Comp = FX.Class("SMiningCompClass", "FSPlayerCompClass")

--- 建立本次会话的请求冷却，不持久化交互状态。
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

--- 玩家完成握手后才允许获得矿石或兑换剑。
function Comp:OnPlayerLogin()
    self._active = true
    _G.SMiningManager:Refresh(self:GetPlayerObject())
end

--- 沿用玩家每秒更新，离线到期只生成当前一轮，不累计离线矿石。
--- @param serverTime number 框架传入的服务器时间；刷新使用跨会话绝对时间。
function Comp:OnUpdate(serverTime)
    if self._active then
        _G.SMiningManager:Refresh(self:GetPlayerObject())
    end
end

--- 所有操作共用冷却，拒绝未登录、死亡、远程伪造坐标和连点请求。
--- @param action string 由服务端协议固定的 Mine 或 Smelt。
--- @param rock any 私人矿石的本轮编号，兑换时不需要。
function Comp:Request(action, rock)
    local player = self:GetPlayerNode()
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not self._active or not humanoid or humanoid.Health <= 0 or not humanoid.RootPart
        or os.clock() - self._lastRequest < Settings.RequestCooldown then
        return
    end
    self._lastRequest = os.clock()
    local position = humanoid.RootPart.Position
    if action == "Mine" then
        _G.SMiningManager:Mine(self:GetPlayerObject(), position, rock)
    elseif action == "Smelt" then
        _G.SMiningManager:Smelt(self:GetPlayerObject(), position)
    end
end

--- 停止旧会话操作，避免退出期间仍能发奖。
function Comp:OnPlayerLogout()
    self._active = false
end

return Comp
