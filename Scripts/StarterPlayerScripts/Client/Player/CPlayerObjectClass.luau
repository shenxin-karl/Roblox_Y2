local FX = _G.FX
local Player = FX.Class("CPlayerObjectClass", "FCPlayerObjectClass")
_G.CPlayerObjectClass = Player

--- 构建客户端玩家对象并挂载当前项目的通用组件。
--- @param playerId number 当前玩家的 Roblox UserId。
function Player:Ctor(playerId)
    Player.Super.Ctor(self, playerId)
    self:AddComponent("FCFriendCompClass")
end

return Player
