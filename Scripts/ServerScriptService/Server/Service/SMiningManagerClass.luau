-- 私人矿场权威状态：每人独立保存整轮矿石，发奖失败不消耗采集次数。
local FX = _G.FX
local Settings = FX.Loader:RequireShared("Scripts.Game.Shared.MiningSettings")
local Config = _G.GameConfig.CommonConfig
local Fields = _G.PlayerDataConfig
local Manager = FX.Class("SMiningManagerClass", "FXObjectBaseClass")

--- 启动前核对配置与矿场几何；服务端只保存矿石数据，不创建共享石头。
function Manager:Ctor()
    Manager.Super.Ctor(self)
    assert(Config.MiningRefreshInterval > 0, "MiningRefreshInterval must be positive")
    assert(Config.MiningSpawnCount > 0 and Config.MiningSpawnCount % 1 == 0, "Invalid MiningSpawnCount")
    assert(Config.MiningRockHits > 0 and Config.MiningRockHits % 1 == 0, "Invalid MiningRockHits")
    assert(Config.MiningSpawnProbability >= 0 and Config.MiningSpawnProbability <= 1, "Invalid MiningSpawnProbability")
    assert(Config.MiningOrePerHit > 0 and Config.MiningOrePerHit % 1 == 0, "Invalid MiningOrePerHit")
    assert(Config.FurnaceOreCost > 0 and Config.FurnaceOreCost % 1 == 0, "Invalid FurnaceOreCost")
    self._mutations = {}
    local probability = 0
    for id, mutation in pairs(_G.GameConfig.MiningMutationData) do
        assert(id == mutation.Id, "Mining mutation ID mismatch")
        assert(mutation.Probability >= 0 and mutation.Probability <= 1, "Invalid mutation probability: " .. id)
        local hits = Config.MiningRockHits * mutation.HitsMultiplier
        local oreCount = Config.MiningOrePerHit * mutation.OreCountMultiplier
        assert(hits > 0 and hits % 1 == 0, "Mutation hits must be a positive integer: " .. id)
        assert(oreCount > 0 and oreCount % 1 == 0, "Mutation reward must be a positive integer: " .. id)
        assert(_G.ItemConfig.Data[mutation.OreItemId].Type == "Ore", "Invalid mutation ore: " .. id)
        assert(mutation.Luck >= 0 and mutation.Luck < math.huge, "Invalid mutation luck: " .. id)
        probability += mutation.Probability
        table.insert(self._mutations, mutation)
    end
    assert(#self._mutations > 0 and math.abs(probability - 1) < 1e-9, "Mining mutation probabilities must sum to 1")
    table.sort(self._mutations, function(left, right)
        return left.Id < right.Id
    end)
    self._ground = FX.Loader:Workspace(Settings.GroundPath)
    self._furnace = FX.Loader:Workspace(Settings.FurnacePath)
    self._rockTypes = {}
    self._rockTemplates = {}
    self._rockWeight = 0
    for id, rockType in pairs(_G.GameConfig.MiningRockData) do
        assert(id == rockType.Id, "Mining rock ID mismatch")
        assert(rockType.SpawnWeight >= 0 and rockType.SpawnWeight < math.huge, "Invalid rock weight")
        assert(rockType.ModelScale > 0 and rockType.ModelScale < math.huge, "Invalid rock scale")
        local template = FX.Loader:Shared(rockType.ModelPath)
        assert(template:IsA("Model") and template.PrimaryPart, "Mining rock requires a model with bounds")
        self._rockTemplates[id] = template
        self._rockWeight += rockType.SpawnWeight
        table.insert(self._rockTypes, rockType)
    end
    assert(self._rockWeight > 0 and self._rockWeight < math.huge, "Mining rock total weight must be positive")
    table.sort(self._rockTypes, function(left, right)
        return left.Id < right.Id
    end)
    self._random = Random.new()
end

--- 按稳定 ID 顺序互斥抽取一次；零概率条目不进入候选区间。
--- @return table 本块矿石整轮固定使用的变异配置。
function Manager:RollMutation()
    local roll = self._random:NextNumber()
    local probability = 0
    local lastCandidate
    for index, mutation in ipairs(self._mutations) do
        if mutation.Probability > 0 then
            lastCandidate = mutation
            probability += mutation.Probability
            if roll < probability then
                return mutation
            end
        end
    end
    -- 总和允许浮点误差；末尾补偿仍只落在非零概率结果上。
    return lastCandidate
end

--- 仅按品质配置权重选择模板，不再随机使用旧的五种普通石头。
--- @return table 本次刷新的矿石品质配置。
function Manager:RollRockType()
    local roll = self._random:NextNumber(0, self._rockWeight)
    local weight = 0
    local lastCandidate
    for index, rockType in ipairs(self._rockTypes) do
        if rockType.SpawnWeight > 0 then
            lastCandidate = rockType
            weight += rockType.SpawnWeight
            if roll < weight then
                return rockType
            end
        end
    end
    return lastCandidate
end

--- 到期后替换请求者的一整轮矿石；重进沿用本轮数据，离线不累计批次。
--- @param player table 已登录的服务端玩家对象。
function Manager:Refresh(player)
    local now = workspace:GetServerTimeNow()
    local previous = player:GetTableView(Fields.MiningData)
    if now < previous.NextRefresh then
        return
    end
    local deadline = previous.NextRefresh > 0
        and previous.NextRefresh + (math.floor((now - previous.NextRefresh) / Config.MiningRefreshInterval) + 1)
            * Config.MiningRefreshInterval
        or now + Config.MiningRefreshInterval
    local data = {NextRefresh = deadline, Rocks = {}}
    local radius = math.min(self._ground.Size.Y, self._ground.Size.Z) / 2 - 4
    local center = self._ground.Position + Vector3.new(0, self._ground.Size.X / 2, 0)
    local phase = self._random:NextNumber(0, math.pi * 2)
    for slot = 1, Config.MiningSpawnCount do
        if self._random:NextNumber() < Config.MiningSpawnProbability then
            local angle = phase + (slot - 1) * math.pi * 2 / Config.MiningSpawnCount
            local distance = self._random:NextNumber(radius * 0.35, radius)
            local rockType = self:RollRockType()
            local position = center + Vector3.new(math.cos(angle) * distance,
                self._rockTemplates[rockType.Id].PrimaryPart.Size.Y * rockType.ModelScale / 2,
                math.sin(angle) * distance)
            local mutation = self:RollMutation()
            local hits = Config.MiningRockHits * mutation.HitsMultiplier
            data.Rocks[tostring(deadline) .. "_" .. slot] = {
                X = position.X, Y = position.Y, Z = position.Z,
                Angle = self._random:NextNumber(0, math.pi * 2),
                Grade = rockType.Id, MutationId = mutation.Id,
                Hits = hits, MaxHits = hits,
            }
        end
    end
    player:SetTable(Fields.MiningData, data)
end

--- 不等待、不让出执行；同一石头的扣次和背包发奖在本次回调中完成。
--- @param player table 已登录的服务端玩家对象。
--- @param position Vector3 服务端读取的当前角色位置。
--- @param rock any 客户端提交的编号，只接受请求者本轮登记的矿石。
--- @return boolean 是否完成一次挖取。
function Manager:Mine(player, position, rock)
    if type(rock) ~= "string" then
        return false
    end
    local data = player:GetTable(Fields.MiningData)
    local state = data.Rocks[rock]
    if not state or state.Hits <= 0 or workspace:GetServerTimeNow() >= data.NextRefresh
        or (position - Vector3.new(state.X, state.Y, state.Z)).Magnitude > Settings.InteractDistance then
        return false
    end
    local reward = player:RequireComponent("FSRewardComp")
    local mutation = _G.GameConfig.MiningMutationData[state.MutationId]
    local oreCount = Config.MiningOrePerHit * mutation.OreCountMultiplier
    if not player:RunDataTransaction(function()
        if not reward:AddRewards({{Type = "Item", ItemId = mutation.OreItemId, Count = oreCount}}) then
            return false
        end
        state.Hits -= 1
        return player:SetTable(Fields.MiningData, data)
    end) then
        return false
    end
    FX.Network:SendMsgToClient(player:GetPlayerId(), "S2C_MiningReward", mutation.OreItemId, oreCount)
    return true
end

--- 优先熔炼手持矿石，否则选择数量足够且幸运值最低的一种，避免默认消耗稀有矿石。
--- @param player table 已登录的服务端玩家对象。
--- @param position Vector3 服务端读取的角色位置。
--- @return boolean 是否扣矿并获得剑。
function Manager:Smelt(player, position)
    if Settings.DistanceToPart(self._furnace, position) > Settings.InteractDistance then
        return false
    end
    local inventory = player:RequireComponent("FSInventoryComp")
    local data = inventory:GetData()
    local held = data[inventory:GetEquippedGrid()]
    local counts = {}
    for grid, item in pairs(data) do
        counts[item.itemId] = (counts[item.itemId] or 0) + item.stackCount
    end
    local selected
    for index, mutation in ipairs(self._mutations) do
        if held and held.itemId == mutation.OreItemId then
            selected = mutation
            break
        elseif (counts[mutation.OreItemId] or 0) >= Config.FurnaceOreCost
            and (not selected or mutation.Luck < selected.Luck) then
            selected = mutation
        end
    end
    if not selected then
        return false
    end
    return player:RequireComponent("FSRewardComp"):ExchangeRewards(
        {{Type = "Item", ItemId = selected.OreItemId, Count = Config.FurnaceOreCost}},
        {{Type = "Item", ItemId = Config.FurnaceSwordItemId, Count = 1,
            ExtraData = {MutationId = selected.Id, Luck = selected.Luck}}}
    )
end

return Manager
