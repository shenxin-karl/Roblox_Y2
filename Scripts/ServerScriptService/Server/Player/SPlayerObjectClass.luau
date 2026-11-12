-- 项目玩家扩展；持久化、同步和登录生命周期由框架负责。
local FX = _G.FX
local Player = FX.Class("SPlayerObjectClass", "FSPlayerObjectClass")

--- 挂载背包、矿场、基地、锻造与槽位剑组件，存档和握手仍由框架负责。
--- @param id number Roblox UserId。
function Player:Ctor(id)
    Player.Super.Ctor(self, id)
    self:AddComponent("FSRewardCompClass")
    self:AddComponent("SInventoryCompClass")
    self:AddComponent("SMiningCompClass")
    self:AddComponent("SBaseCompClass")
    self:AddComponent("SForgeCompClass")
    self:AddComponent("SSlotSwordCompClass")
    self:AddComponent("SUpgradeWorkshopCompClass")
    self:AddComponent("SMiscCompClass")
    self:AddComponent("SGMCompClass")
    self:AddComponent("SAnalyticsCompClass")
end

--- 项目尚未上线，保留框架迁移入口，当前不兼容旧测试存档。
--- @param version number 框架读取的存档版本，当前无需迁移。
function Player:MigrateData(version)
end

return Player
