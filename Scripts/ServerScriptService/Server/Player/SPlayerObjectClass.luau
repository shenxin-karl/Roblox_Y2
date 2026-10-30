-- 项目玩家扩展；持久化、同步和登录生命周期由框架负责。
local FX = _G.FX
local Player = FX.Class("SPlayerObjectClass", "FSPlayerObjectClass")

--- 挂载通用能力与基地组件，存档和握手仍由框架负责。
--- @param id number Roblox UserId。
function Player:Ctor(id)
    Player.Super.Ctor(self, id)
    self:AddComponent("FSRewardCompClass")
    self:AddComponent("SBaseCompClass")
    self:AddComponent("SMiscCompClass")
    self:AddComponent("SGMCompClass")
    self:AddComponent("SAnalyticsCompClass")
end

--- 将旧版连续解锁进度补成槽位集合；已有集合时保留玩家任选的位置。
--- @param version number 框架读取的存档版本，本次按字段是否存在兼容旧档。
function Player:MigrateData(version)
    local field = _G.PlayerDataConfig.BaseData
    local data = self:GetTable(field)
    if data.UnlockedSlots == nil then
        data.UnlockedSlots = {}
        for slotId = 1, data.UnlockedSlotCount do
            data.UnlockedSlots[tostring(slotId)] = true
        end
        self:SetTable(field, data)
    end
end

return Player
