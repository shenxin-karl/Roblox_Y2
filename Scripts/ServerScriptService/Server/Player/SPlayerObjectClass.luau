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
    self:AddComponent("SEconomyCompClass")
    self:AddComponent("SMiscCompClass")
    self:AddComponent("SGMCompClass")
    self:AddComponent("SAnalyticsCompClass")
end

--- 旧测试武器补品质1并保留等级、金币和变异；旧倍率幸运取整为至少1，适配整数幸运规则。
--- @param version number 框架读取的持久化版本。
function Player:MigrateData(version)
    if version >= 1 then
        return
    end
    local fields = _G.PlayerDataConfig
    local base = self:GetTable(fields.BaseData)
    for slotId, sword in pairs(base.SlotData) do
        sword.Quality = sword.Quality or 1
        sword.MutationId = sword.MutationId or "Normal"
        sword.Luck = math.max(1, math.floor(sword.Luck or 1))
    end
    local items = self:GetTable(fields.Inventory)
    for grid, item in pairs(items) do
        if item.itemId == 1002 or item.itemId == 1003 then
            local extra = item.extraData or {}
            extra.MutationId = extra.MutationId or "Normal"
            extra.Luck = math.max(1, math.floor(extra.Luck or 1))
            if item.itemId == 1003 then
                extra.Quality, extra.Level, extra.StoredMoney = extra.Quality or 1, extra.Level or 1, extra.StoredMoney or 0
            end
            item.extraData = extra
        end
    end
    self:RunDataTransaction(function()
        return self:SetTable(fields.BaseData, base) and self:SetTable(fields.Inventory, items)
            and self:SetNumber(fields.DataVersion, 1)
    end)
end

return Player
