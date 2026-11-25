local FX = _G.FX
local FXLoader = FX.Loader
FXLoader:RequireFromParent(script, "CConveyorCompClass")
FXLoader:RequireFromParent(script, "CLuckyShopCompClass")
FXLoader:RequireFromParent(script, "CSoundCompClass")
FXLoader:RequireFromParent(script, "CTutorialGuideCompClass")
local Player = FX.Class("CPlayerObjectClass", "FCPlayerObjectClass")
_G.CPlayerObjectClass = Player

--- 构建客户端玩家对象并挂载当前项目的通用组件。
--- @param playerId number 当前玩家的 Roblox UserId。
function Player:Ctor(playerId)
    Player.Super.Ctor(self, playerId)
    self:AddComponent("FCFriendCompClass")
    self:AddComponent("CConveyorCompClass")
    self:AddComponent("CLuckyShopCompClass")
    self:AddComponent("CSoundCompClass")
    self:AddComponent("CTutorialGuideCompClass")
end

return Player
