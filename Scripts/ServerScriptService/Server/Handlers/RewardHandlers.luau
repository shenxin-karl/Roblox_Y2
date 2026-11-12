-- 槽位解锁、赠剑、领钱与升级由框架统一预检提交；处理器不直接修改场景或档案。
local Fields = _G.PlayerDataConfig
local GameConfig = _G.GameConfig
local FX = _G.FX
local SwordRules = FX.Loader:RequireShared("Scripts.Game.Shared.SwordRules")
local WorkshopRules = FX.Loader:RequireShared("Scripts.Game.Shared.UpgradeWorkshopRules")

return {
    --- 将工坊等级与金币消耗放入同一次兑换，预检失败不修改档案。
    --- @param rewardComponent table 框架奖励组件。
    --- @param entry table 服务端校验过的升级 ID 和旧等级。
    --- @param tables table 本次交易待提交的表字段快照。
    --- @return boolean 是否允许整批提交。
    UpgradeWorkshop = function(rewardComponent, entry, tables)
        local levels = tables.UpgradeWorkshop or rewardComponent:GetTable(Fields.UpgradeWorkshop)
        local level = levels[entry.UpgradeId]
        if not WorkshopRules.BasePrices[entry.UpgradeId] or level ~= entry.ExpectedLevel
            or level < 0 or level >= WorkshopRules.MaxLevel or level % 1 ~= 0 then
            return false
        end
        levels[entry.UpgradeId] = level + 1
        tables.UpgradeWorkshop = levels
        return true
    end,
    --- 在同一个库存快照中将原料替换为成品，优先手持原料并保留其变异与幸运值。
    --- @param rewardComponent table 框架奖励组件。
    --- @param entry table 服务端固定的打造条目，无客户端配方。
    --- @param tables table 本次交易待提交的字段快照。
    --- @return boolean 是否可以提交一把成品剑。
    ForgeSword = function(rewardComponent, entry, tables)
        local inventory = rewardComponent:RequireComponent("FSInventoryComp")
        local items = tables.Inventory or rewardComponent:GetTable(Fields.Inventory)
        local grid = inventory:GetEquippedGrid()
        local item = grid and items[tostring(grid)]
        if not item or item.itemId ~= SwordRules.RawItemId then
            grid, item = nil, nil
            for index = 1, inventory:GetTotalCapacity() do
                local candidate = items[tostring(index)]
                if candidate and candidate.itemId == SwordRules.RawItemId then
                    grid, item = index, candidate
                    break
                end
            end
        end
        local traits = item and SwordRules.GetTraits(item.extraData)
        if not traits or item.stackCount ~= 1 then
            return false
        end
        traits.Luck *= WorkshopRules.GetMultiplier(rewardComponent:GetTableView(Fields.UpgradeWorkshop).forge)
        traits.Level, traits.StoredMoney = 1, 0
        items[tostring(grid)] = {itemId = SwordRules.ItemId, stackCount = 1, extraData = traits}
        tables.Inventory = items
        return true
    end,
    --- 初始剑只赠一次，不覆盖第一槽已有物品，标记与物品一起持久化。
    --- @param rewardComponent table 框架奖励组件。
    --- @param entry table 初始剑奖励条目，不接受客户端参数。
    --- @param tables table 本次交易待提交的字段快照。
    --- @return boolean 是否可以提交首次赠送。
    StarterSlotSword = function(rewardComponent, entry, tables)
        local data = tables.BaseData or rewardComponent:GetTable(Fields.BaseData)
        if data.InitialSwordGranted then
            return false
        end
        if not data.SlotData["1"] then
            data.SlotData["1"] = {ItemId = SwordRules.ItemId, Level = 1, StoredMoney = 0}
        end
        data.InitialSwordGranted = true
        tables.BaseData = data
        return true
    end,
    --- 同一批领钱奖励只有与当前累计额完全一致时才可清零。
    --- @param rewardComponent table 框架奖励组件。
    --- @param entry table 服务端读取的 Amount 快照。
    --- @param tables table 本次交易待提交的字段快照。
    --- @return boolean 是否允许发钱并清除本次累计额。
    SlotSwordCollect = function(rewardComponent, entry, tables)
        local data = tables.BaseData or rewardComponent:GetTable(Fields.BaseData)
        local sword = data.SlotData[tostring(entry.SlotId)]
        if not sword or sword.ItemId ~= SwordRules.ItemId or sword.StoredMoney <= 0
            or sword.StoredMoney ~= entry.Amount then
            return false
        end
        sword.StoredMoney = 0
        tables.BaseData = data
        return true
    end,
    --- 只改变剑自身等级；费用和新等级由奖励框架共同预检后提交。
    --- @param rewardComponent table 框架奖励组件。
    --- @param entry table 服务端固定的升级前等级。
    --- @param tables table 本次交易待提交的字段快照。
    --- @return boolean 是否允许升级当前这把剑。
    SlotSwordUpgrade = function(rewardComponent, entry, tables)
        local data = tables.BaseData or rewardComponent:GetTable(Fields.BaseData)
        local sword = data.SlotData[tostring(entry.SlotId)]
        if not sword or sword.ItemId ~= SwordRules.ItemId or sword.Level ~= entry.ExpectedLevel
            or SwordRules.GetIncome(sword.Level + 1) >= math.huge
            or SwordRules.GetUpgradePrice(sword.Level + 1) >= math.huge then
            return false
        end
        sword.Level += 1
        tables.BaseData = data
        return true
    end,
    --- 精确移走本人手持格子的成品剑，连同等级与金币一起转入空槽。
    --- @param rewardComponent table 框架奖励组件。
    --- @param entry table 服务端确定的槽位与手持格号。
    --- @param tables table 本次交易快照，背包与基地由框架共同提交。
    --- @return boolean 是否允许整批放置。
    SlotSwordPlace = function(rewardComponent, entry, tables)
        local inventory = rewardComponent:RequireComponent("FSInventoryComp")
        if inventory:GetEquippedGrid() ~= entry.Grid then
            return false
        end
        local base = rewardComponent:RequireComponent("SBaseComp"):GetBase()
        local data = tables.BaseData or rewardComponent:GetTable(Fields.BaseData)
        local key = tostring(entry.SlotId)
        if not base or not data.UnlockedSlots[key] or data.SlotData[key] then
            return false
        end
        local items = tables.Inventory or rewardComponent:GetTable(Fields.Inventory)
        local item = items[tostring(entry.Grid)]
        if not item or item.itemId ~= SwordRules.ItemId or item.stackCount ~= 1
            or not SwordRules.IsValid(item.extraData) then
            return false
        end
        local traits = SwordRules.GetTraits(item.extraData)
        if not traits then
            return false
        end
        data.SlotData[key] = {
            ItemId = item.itemId, Level = item.extraData.Level, StoredMoney = item.extraData.StoredMoney,
            MutationId = traits.MutationId, Luck = traits.Luck,
        }
        items[tostring(entry.Grid)] = nil
        tables.Inventory, tables.BaseData = items, data
        return true
    end,
    --- 卸下预检与背包容量检查共同执行；失败保留原槽位武器。
    --- @param rewardComponent table 框架奖励组件。
    --- @param entry table 服务端读取的武器快照与槽位编号。
    --- @param tables table 本次交易待提交字段。
    --- @return boolean 是否允许清空该槽位。
    SlotSwordRemove = function(rewardComponent, entry, tables)
        local data = tables.BaseData or rewardComponent:GetTable(Fields.BaseData)
        local key = tostring(entry.SlotId)
        local sword = data.SlotData[key]
        if not sword or sword.ItemId ~= SwordRules.ItemId or sword.Level ~= entry.Level
            or sword.StoredMoney ~= entry.StoredMoney then
            return false
        end
        data.SlotData[key] = nil
        tables.BaseData = data
        return true
    end,
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
