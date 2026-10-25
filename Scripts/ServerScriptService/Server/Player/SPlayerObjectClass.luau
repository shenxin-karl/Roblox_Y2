-- 项目玩家扩展；持久化、同步和登录生命周期由框架负责。
local FX = _G.FX
local Player = FX.Class("SPlayerObjectClass", "FSPlayerObjectClass")

--- 挂载模板通用能力，后续玩法组件在此显式添加。
--- @param id number Roblox UserId。
function Player:Ctor(id)
    Player.Super.Ctor(self, id)
    self:AddComponent("FSRewardCompClass")
    self:AddComponent("SMiscCompClass")
    self:AddComponent("SGMCompClass")
    self:AddComponent("SAnalyticsCompClass")
end

--- 模板没有历史业务迁移；新增存档结构时在此按版本迁移。
--- @param version number 框架读取的存档版本，目前保持原值。
function Player:MigrateData(version)
end

return Player
