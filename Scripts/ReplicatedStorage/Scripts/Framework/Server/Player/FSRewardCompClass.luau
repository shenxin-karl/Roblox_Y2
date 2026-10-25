local FX, FS = _G.FX, _G.FS
local ItemConfig = _G.ItemConfig
local Reward = FX.Class("FSRewardCompClass", "FSPlayerCompClass")
FS.RewardCompClass = Reward
local MAX_INTEGER = 9007199254740991

--- 连续经济数值保留小数和大数，只排除负数、NaN 与无穷。
--- @param value any 待校验数值。
--- @return boolean 是否为非负有限数值。
local function Finite(value)
    return type(value) == "number" and value >= 0 and value < math.huge
end

--- 离散数量保持安全整数约束，不用于货币余额。
--- @param value any 道具数量、ID 或列表索引。
--- @return boolean 是否为非负安全整数。
local function Integer(value)
    return type(value) == "number" and value >= 0 and value <= MAX_INTEGER and value % 1 == 0
end

function Reward:GetCompName()
    return "FSRewardComp"
end

-- 服务端入口。先汇总整批货币并检查整个背包容量，再执行；没有客户端领奖协议。
-- Type = Item / Money 或服务端注册的业务奖励；保留 ItemId/Count 和 itemId/count 写法。
--- @param rewards table 本次奖励或消耗列表。
--- @param consume boolean 是否按消耗验证余额。
--- @param previous table? 同一交换中已预检的消耗计划。
--- @return table 校验通过的变更计划，失败返回 nil。
function Reward:_Prepare(rewards, consume, previous)
    if type(rewards) ~= "table" then
        return nil
    end
    local items, money, length = {}, {}, 0
    local tables = previous and FX.Table:DeepCopy(previous.tables) or {}
    local inventory = self:GetComponent("FSInventoryComp")
    for key in pairs(rewards) do
        if not Integer(key) or key < 1 then
            return nil
        end
        length += 1
    end
    for index = 1, length do
        local entry = rewards[index]
        if type(entry) ~= "table" then
            return nil
        end
        local count = entry.Count or entry.count
        if entry.Type == "Item" then
            if not Integer(count) or count == 0 then
                return nil
            end
            local id = entry.ItemId or entry.itemId
            local extra = entry.ExtraData or entry.extraData
            local item = ItemConfig.Data[id]
            if not Integer(id) or not inventory or not item or not Integer(item.MaxStack) or item.MaxStack < 1 then
                return nil
            end
            -- 扣除按 ItemId 汇总，不支持按词条选择；防止调用方误扣其他词条物品。
            if extra ~= nil and (consume or type(extra) ~= "table") then
                return nil
            end
            if extra then
                local schema = ItemConfig.ExtraDataSchema[item.Type]
                if not schema then
                    return nil
                end
                for key in pairs(extra) do
                    if schema[key] == nil then
                        return nil
                    end
                end
            end
            local maxStack = extra and 1 or item.MaxStack
            if count / maxStack > inventory:GetTotalCapacity() then
                return nil
            end
            while count > 0 do
                local stack = math.min(count, maxStack)
                table.insert(items, FS.ItemClass.New(id, stack, extra and FX.Table:DeepCopy(extra)))
                count -= stack
            end
        elseif entry.Type == "Money" then
            if not Finite(count) or count == 0 then
                return nil
            end
            local field = _G.Provider:GetCurrencyDataConfig(entry.Currency)
            if not field or field.Type ~= "number" then
                return nil
            end
            money[field] = (money[field] or 0) + count
            if not Finite(money[field]) then
                return nil
            end
        else
            local handler = _G.Provider.RewardHandlers and _G.Provider.RewardHandlers[entry.Type]
            if consume or not handler or not handler(self, entry, tables) then
                return nil
            end
        end
    end
    local balances = previous and table.clone(previous.balances) or {}
    for field, count in pairs(money) do
        local current = balances[field] or self:GetNumber(field)
        if not Finite(current) then
            return nil
        end
        local value = current + (consume and -count or count)
        if not Finite(value) then
            return nil
        end
        balances[field] = value
    end
    local tableFields = {}
    local fields = _G.Provider:GetPlayerDataConfig()
    for fieldName, value in pairs(tables) do
        local field = fields[fieldName]
        if not field or field.Type ~= "table" or type(value) ~= "table" then
            return nil
        end
        tableFields[fieldName] = field
    end
    if #items > 0 then
        local check = consume and inventory.CanRemoveItems or inventory.CanAddItems
        if not check(inventory, items, previous and previous.items) then
            return nil
        end
    end
    return { items = items, balances = balances, tables = tables, tableFields = tableFields, inventory = inventory }
end

function Reward:CanAddRewards(rewards)
    return self:_Prepare(rewards, false) ~= nil
end

function Reward:CanConsumeRewards(rewards)
    return self:_Prepare(rewards, true) ~= nil
end

--- 整批预检后执行，无 yield；写入期间拒绝同步回调重入。
--- @param rewards table 奖励或消耗列表。
--- @param consume boolean 是否为消耗。
--- @return boolean 是否整批完成。
function Reward:_Apply(rewards, consume)
    if self._applying then
        return false
    end
    local plan = self:_Prepare(rewards, consume)
    if not plan then
        return false
    end
    return self:_Commit(plan, consume)
end

--- 提交已校验的计划；异常仍向调用方报告，但始终释放重入标记。
--- @param plan table 奖励或消耗计划，表字段已在预检时解析。
--- @param consume boolean 是否提交单独的消耗计划。
--- @param cost table? 兑换时先执行的消耗计划。
--- @return boolean 是否完成提交。
function Reward:_Commit(plan, consume, cost)
    local inventoryData = cost and cost.inventory and cost.inventory:_GetData()
    self._applying = true
    local ok, result = pcall(function()
        if cost and #cost.items > 0 and not cost.inventory:RemoveItems(cost.items) then
            return false
        end
        if #plan.items > 0 then
            local apply = consume and plan.inventory.RemoveItems or plan.inventory.AddItems
            if not apply(plan.inventory, plan.items) then
                if cost and #cost.items > 0 then
                    cost.inventory:_SetData(inventoryData)
                end
                return false
            end
        end
        for field, value in pairs(plan.balances) do
            self:SetNumber(field, value)
        end
        for fieldName, value in pairs(plan.tables) do
            self:SetTable(plan.tableFields[fieldName], value)
        end
        return true
    end)
    self._applying = nil
    if not ok then
        error(result, 0)
    end
    return result
end

--- 消耗和奖励先共同预检，数值以扣除后的余额计算，失败不扣款或扣道具。
--- @param costs table 消耗列表，免费交易传空表。
--- @param rewards table 整批业务奖励。
--- @return boolean 是否完成交换。
function Reward:ExchangeRewards(costs, rewards)
    if self._applying then
        return false
    end
    local cost = self:_Prepare(costs, true)
    local plan = cost and self:_Prepare(rewards, false, cost)
    if not plan then
        return false
    end
    return self:_Commit(plan, false, cost)
end

function Reward:AddRewards(rewards)
    return self:_Apply(rewards, false)
end

function Reward:ConsumeRewards(rewards)
    return self:_Apply(rewards, true)
end

return Reward
