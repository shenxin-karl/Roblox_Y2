-- 槽位解锁与金币消耗共同预检，由框架统一提交；预检不修改场景或玩家档案。
local Fields = _G.PlayerDataConfig
local GameConfig = _G.GameConfig

return {
    --- 只允许购买当前基地已生成且未解锁的展示台，防止重复购买和越层授予。
    --- @param rewardComponent table 框架奖励组件。
    --- @param entry table 含 SlotId 的服务端奖励条目。
    --- @param tables table 本次交易待提交的表字段快照。
    --- @return boolean 是否允许将该槽位解锁加入交易。
    BaseSlotUnlock = function(rewardComponent, entry, tables)
        local baseComponent = rewardComponent:GetComponent("SBaseComp")
        if not baseComponent or not baseComponent:GetBase() or not GameConfig.BaseSlotData[entry.SlotId] then
            return false
        end
        local data = tables.BaseData or rewardComponent:GetTable(Fields.BaseData)
        local floor = baseComponent:GetBase().Floors[math.ceil(entry.SlotId / GameConfig.CommonConfig.BaseSlotsPerFloor)]
        if not floor or not floor.Slots[entry.SlotId] or data.UnlockedSlots[tostring(entry.SlotId)] then
            return false
        end
        data.UnlockedSlots[tostring(entry.SlotId)] = true
        data.UnlockedSlotCount += 1
        tables.BaseData = data
        return true
    end,
}
