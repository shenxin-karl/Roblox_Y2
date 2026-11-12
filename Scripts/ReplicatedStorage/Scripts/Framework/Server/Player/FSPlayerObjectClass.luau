local FX, FS = _G.FX, _G.FS
local Provider = _G.Provider
local FXLoader = FX.Loader
local DataAccess = FXLoader:RequireShared("Scripts.Framework.Server.PlayerKV.FSPlayerDataAccess")
local FXNetwork = FX.Network
local FXTask = FX.Task
local FXTime = FX.Time
local FXTable = FX.Table
local FSPlayerKVDataManager = FS.PlayerKVDataManager
local FSRankingManager = FS.RankingManager

--- 服务端玩家对象类：每个在线玩家对应一个实例，负责该玩家的数据读写、持久化、同步与生命周期。
--- 数据字段与默认值由 Game/Shared/PlayerDataConfig 定义；支持临时数据（内存）与 KV 持久数据，带 Sync 的字段会通过 S2C_PlayerStateSync 自动下发客户端。
---
--- @class FSPlayerObjectClass
--- 使用方式：
--- 1. 获取实例：通过 SPlayerObjectManager 等管理类按 playerId 获取，勿自行 new。
--- 2. 读写数据：GetNumber/SetNumber/AddNumber/SubNumber、GetFlag/SetFlag、GetTable/SetTable，入参为 PlayerDataConfig 中的枚举。
--- 3. 监听变化：WatchDataChanged(dataEnum, callback[, this])，数据变更时触发回调。
--- 4. 排行榜：GetRankingScore/UpdateRankingScore/AddRankingScore(rankingType, value)。
--- 5. 生命周期：框架在登录/登出时调用 OnPlayerLogin/OnPlayerLogout，并会 CallAllCompMethod 通知各组件。
--- 6. 子类需实现 MigrateData(dataVersion) 以支持存档版本迁移。
---
local FSPlayerObjectClass = FX.Class("FSPlayerObjectClass", "FXObjectBaseClass")
FS.PlayerObjectClass = FSPlayerObjectClass

--- 绑定创建时的存档会话，旧玩家对象的 View 和事务不能转向重进后的新档案。
--- @param playerId number 已完成存档加载的玩家 ID。
--- @return nil
function FSPlayerObjectClass:Ctor(playerId)
    FSPlayerObjectClass.Super.Ctor(self, playerId)
    self._playerId = playerId
    self._dataSession = FSPlayerKVDataManager:GetSessionToken(playerId)
    self._pendingSyncData = {} -- 需要同步的数据
    self._tempDataMap = {}
    self._syncTimerTask = nil
    self._playerDataListeners = {}

    -- 获取玩家数据版本, 用于数据迁移
    local dataVersion = self:GetNumber(Provider:GetPlayerDataVersionVariantEnum())
    self:MigrateData(dataVersion)
end

--- 取消待发同步并释放玩家组件与监听，防止离服后回调继续访问数据。
function FSPlayerObjectClass:Dtor()
    FXTask:Cancel(self._syncTimerTask)
    for _, event in pairs(self._playerDataListeners) do
        event:Destroy()
    end
    FSPlayerObjectClass.Super.Dtor(self)
end

-- 用于数据迁移
function FSPlayerObjectClass:MigrateData(dataVersion)
    error("FSPlayerObjectClass:MigrateData is not implemented")
end

-- 获取玩家ID
function FSPlayerObjectClass:GetPlayerId()
    return self._playerId
end

-- 拷贝默认数据
function FSPlayerObjectClass:_CopyDefaultData(varEnum)
    if varEnum.Type == "table" and varEnum.DefVal ~= nil then
        return FXTable:DeepCopy(varEnum.DefVal)
    else
        return varEnum.DefVal
    end
end

--- 只读访问默认值时不深拷贝配置表；编辑副本仍由 GetTable 按需创建。
--- @param varEnum table 玩家字段定义。
--- @return any 默认标量或只读 View。
function FSPlayerObjectClass:_GetDefaultDataView(varEnum)
    if type(varEnum.DefVal) == "table" then
        return DataAccess.View(function()
            return varEnum.DefVal
        end)
    end
    return varEnum.DefVal
end

-- 数据变化
function FSPlayerObjectClass:OnDataChanged(varEnum, newData, oldData)
    local customNotify = self._playerDataListeners[varEnum.Key]
    if customNotify then
        customNotify:Fire(newData, oldData, varEnum.Key)
    end
    if varEnum.Sync == false then
        return
    end
    if not self._syncTimerTask then
        self._syncTimerTask = FXTask:Defer(function()
            self:SyncData()
            self._syncTimerTask = nil
        end)
    end
end

--- 临时字段仅在允许同步时加入发送批次。
--- @param varEnum table 字段定义。
--- @param newData any 新值。
--- @param checkEqual boolean 是否跳过相等标量。
function FSPlayerObjectClass:_SetTempData(varEnum, newData, checkEqual)
    local oldData = self._tempDataMap[varEnum.Key]
    if checkEqual and oldData == newData then
        return
    end
    self._tempDataMap[varEnum.Key] = newData
    if varEnum.Sync ~= false then
        self._pendingSyncData[varEnum.Key] = newData
    end
    self:OnDataChanged(varEnum, newData, oldData)
end

--- 写入持久字段并保留 false 旧值；私有字段不进入网络批次。
--- @param varEnum table 字段定义。
--- @param newData any 新值。
--- @param checkEqual boolean 是否跳过相等标量。
--- @return nil
function FSPlayerObjectClass:_SetKVData(varEnum, newData, checkEqual)
    local kvTable = FSPlayerKVDataManager:GetKVTable(self._playerId, varEnum.KVTable)
    local oldData = self:_GetData(varEnum)
    if checkEqual and oldData == newData then
        return
    end
    kvTable:SetDeep(varEnum.Key .. ".LastSaveTime", os.time())
    kvTable:SetDeep(varEnum.Key .. ".RealData", newData)
    if varEnum.Sync ~= false then
        self._pendingSyncData[varEnum.Key] = newData
    end
    self:OnDataChanged(varEnum, newData, oldData)
end

--- 内部读取临时字段，缺失时返回只读默认值；公开接口负责隔离表引用。
--- @param varEnum table 玩家字段定义。
--- @return any 临时数据或只读默认值。
function FSPlayerObjectClass:_GetTempData(varEnum)
    if self._tempDataMap[varEnum.Key] ~= nil then
        return self._tempDataMap[varEnum.Key]
    end
    return self:_GetDefaultDataView(varEnum)
end

function FSPlayerObjectClass:_IsKVDataExpired(resetType, lastSaveTime, currentTime)
    if resetType == "Daily" then
        return FXTime:GetDayStartTimeStamp(lastSaveTime) ~= FXTime:GetDayStartTimeStamp(currentTime)
    end

    if resetType == "Weekly" then
        return FXTime:GetWeekStartTimeStamp(lastSaveTime) ~= FXTime:GetWeekStartTimeStamp(currentTime)
    end

    if resetType == "Monthly" then
        return not FXTime:IsSameMonth(lastSaveTime, currentTime)
    end

    return false
end

--- 检查单个 KV 数据是否已过期，过期后写回默认值并加入当前同步批次。
--- @param varEnum table 玩家数据枚举，要求包含 KVTable 与 KVResetType
--- @param currentTime number 当前时间戳（秒）
--- @return boolean 是否发生重置
function FSPlayerObjectClass:_ResetExpiredKVData(varEnum, currentTime)
    local kvTable = FSPlayerKVDataManager:GetKVTable(self._playerId, varEnum.KVTable)
    local realData = kvTable:GetDeepView(varEnum.Key .. ".RealData")
    if realData == nil then
        return false
    end

    local lastSaveTime = kvTable:GetDeep(varEnum.Key .. ".LastSaveTime")
    if lastSaveTime and not self:_IsKVDataExpired(varEnum.KVResetType, lastSaveTime, currentTime) then
        return false
    end

    self:_SetKVData(varEnum, self:_CopyDefaultData(varEnum), false)
    return true
end

--- 检查所有带重置周期的玩家 KV 数据，过期后自动重置。
--- @param currentTime number 当前时间戳（秒）
--- @return boolean 是否存在至少一个字段被重置
function FSPlayerObjectClass:CheckExpiredPlayerData(currentTime)
    local hasResetData = false
    for _, varEnum in pairs(Provider:GetPlayerDataConfig()) do
        if varEnum.KVTable and varEnum.KVResetType and self:_ResetExpiredKVData(varEnum, currentTime) then
            hasResetData = true
        end
    end
    return hasResetData
end

--- 通过 KV 公开句柄读取字段；表值仅以只读 View 传递，副本由取表接口决定。
--- @param varEnum table 玩家字段定义。
--- @return any 标量或只读 View，包含默认值与周期重置后的读取结果。
function FSPlayerObjectClass:_GetKVData(varEnum)
    local kvTable = FSPlayerKVDataManager:GetKVTable(self._playerId, varEnum.KVTable)
    local lastSaveTime = kvTable:GetDeep(varEnum.Key .. ".LastSaveTime")
    local realData = kvTable:GetDeepView(varEnum.Key .. ".RealData")
    if realData == nil then
        return self:_GetDefaultDataView(varEnum)
    end

    local resetType = varEnum.KVResetType
    if not resetType then
        return realData
    end

    if not lastSaveTime then
        return self:_GetDefaultDataView(varEnum)
    end

    if self:_IsKVDataExpired(resetType, lastSaveTime, os.time()) then
        return self:_GetDefaultDataView(varEnum)
    end

    return realData
end

--- 表值以副本返回，要求写入方通过 SetTable 提交。
--- @param varEnum table 玩家字段定义。
--- @return any 当前字段值。
function FSPlayerObjectClass:_GetData(varEnum)
    local data
    if varEnum.KVTable then
        data = self:_GetKVData(varEnum)
    else
        data = self:_GetTempData(varEnum)
    end
    return DataAccess.DeepCopy(data)
end

--- 按字段类型统一校验并路由持久或临时写入；nil 恢复默认值。
--- @param varEnum table 字段定义。
--- @param data any 新值。
--- @param checkEqual boolean 是否忽略相等标量。
--- @return nil
function FSPlayerObjectClass:_SetData(varEnum, data, checkEqual)
    if data == nil then
        data = self:_CopyDefaultData(varEnum)
    end
    assert(type(data) == varEnum.Type, "Invalid player data: " .. varEnum.Key)
    if type(data) == "number" then
        assert(data == data and math.abs(data) < math.huge, "Player data must be finite")
    elseif type(data) == "table" then
        data = DataAccess.DeepCopy(data)
    end
    if varEnum.KVTable then
        self:_SetKVData(varEnum, data, checkEqual)
    else
        self:_SetTempData(varEnum, data, checkEqual)
    end
end

function FSPlayerObjectClass:ShowTips(tips, duration)
    FXNetwork:SendMsgToClient(self._playerId, "S2C_ShowTips", tips, duration)
end

--- 发送完整文案定义和参数，客户端按当前语言显示。
--- @param key table Key/Source 文案定义。
--- @param arguments table? 文案模板参数。
--- @param duration number? 提示显示秒数。
function FSPlayerObjectClass:ShowLocalizedTips(key, arguments, duration)
    FX.Text.ValidateDefinition(key)
    FXNetwork:SendMsgToClient(self._playerId, "S2C_ShowLocalizedTips",
        {Key = key.Key, Source = key.Source}, arguments, duration)
end

-- 玩家登录
function FSPlayerObjectClass:OnPlayerLogin()
    self:CallAllCompMethod("OnPlayerLogin")
    for _, varEnum in pairs(Provider:GetPlayerDataConfig()) do
        local data = self:_GetData(varEnum)
        local sync = varEnum.Sync == nil and true or varEnum.Sync
        if sync then
            self._pendingSyncData[varEnum.Key] = data
        end
        self:OnDataChanged(varEnum, data, nil)
    end
    self:SyncData()
end

-- 玩家登出
function FSPlayerObjectClass:OnPlayerLogout()
    self:CallAllCompMethod("OnPlayerLogout")
end

--- 执行玩家对象的每秒更新，负责驱动组件更新并处理按周期重置的玩家数据。
--- @param serverTime number 当前服务器时间戳（秒）
--- @return nil
function FSPlayerObjectClass:OnUpdate(serverTime)
    self:CheckExpiredPlayerData(serverTime)
    self:CallAllCompMethod("OnUpdate", serverTime)
end

--- 发送当前累计的玩家增量数据。
--- @return nil
function FSPlayerObjectClass:SyncData()
    if FXTable:Empty(self._pendingSyncData) then
        return
    end
    FXNetwork:SendMsgToClient(self._playerId, "S2C_PlayerStateSync", self._pendingSyncData)
    self._pendingSyncData = {}
end

--设置KV数值
--[[
    varEnum = {
        Type        = "number",    -- 数据类型
        DefVal      = 0,           -- 默认值(可选默认0)
        Key         = "xxx",       -- 数据键
        Sync        = true,        -- 是否同步到客户端(可选默认true)
        KVTable     = xxx,         -- 如果有 kvTable 表示持久数据, 否则表示临时数据
        KVResetType = "Daily",     -- KV重置周期(可选): "Daily"(每日) / "Weekly"(每周) / "Monthly"(每月)
    },
]]
function FSPlayerObjectClass:SetNumber(numberEnum, number)
    if type(numberEnum) ~= "table" or numberEnum.Type ~= "number" or (type(number) ~= "number" and number ~= nil) then
        FX.ErrorWithTraceback("SetNumber: numberEnum type error, expected number, got " .. type(number))
    end
    self:_SetData(numberEnum, number, true)
    return true
end

--获取KV数值
function FSPlayerObjectClass:GetNumber(numberEnum)
    if type(numberEnum) ~= "table" or numberEnum.Type ~= "number" then
        FX.ErrorWithTraceback("GetNumber: numberEnum type error, expected number, got " .. tostring(numberEnum))
    end
    return self:_GetData(numberEnum)
end

--增加KV数值
function FSPlayerObjectClass:AddNumber(numberEnum, number)
    if numberEnum.Type ~= "number" or (type(number) ~= "number" and number ~= nil) then
        FX.ErrorWithTraceback("AddNumber: numberEnum type error, expected number, got " .. type(number))
    end
    if number == 0 then
        return false
    end
    local oldNumber = self:GetNumber(numberEnum)
    local newNumber = oldNumber + number
    return self:SetNumber(numberEnum, newNumber)
end

--减少KV数值
--- 扣减必须为非负数且余额足够。
--- @param numberEnum table 数值字段定义。
--- @param number number 扣减数量。
--- @return boolean 是否实际完成扣减。
function FSPlayerObjectClass:SubNumber(numberEnum, number)
    assert(type(number) == "number" and number >= 0, "SubNumber requires a non-negative amount")
    if numberEnum.Type ~= "number" or (type(number) ~= "number" and number ~= nil) then
        FX.ErrorWithTraceback("SubNumber: numberEnum type error, expected number, got " .. type(number))
    end
    if number == 0 then
        return false
    end
    local oldNumber = self:GetNumber(numberEnum)
    if oldNumber < number then
        return false
    end
    local newNumber = oldNumber - number
    return self:SetNumber(numberEnum, newNumber)
end

function FSPlayerObjectClass:SetFlag(boolEnum, flag)
    if boolEnum.Type ~= "boolean" or (type(flag) ~= "boolean" and flag ~= nil) then
        FX.ErrorWithTraceback("SetFlag: boolEnum type error, expected boolean, got " .. type(flag))
    end
    self:_SetData(boolEnum, flag, true)
    return true
end

--获取布尔值
function FSPlayerObjectClass:GetFlag(boolEnum)
    if boolEnum.Type ~= "boolean" then
        FX.ErrorWithTraceback("GetFlag: boolEnum type error, expected boolean, got " .. tostring(boolEnum.Type))
    end
    return self:_GetData(boolEnum)
end

--- 提交整表修改；入参深拷贝后写入，后续修改入参不会影响存档。
--- @param tableEnum table 表字段定义。
--- @param tableData table? 普通表、安全浅拷贝或 View；nil 恢复默认值。
--- @return boolean 是否完成内存提交，不表示已持久化。
function FSPlayerObjectClass:SetTable(tableEnum, tableData)
    if tableEnum.Type ~= "table" or (type(tableData) ~= "table" and tableData ~= nil) then
        FX.ErrorWithTraceback("SetTable: tableEnum type error, expected table, got " .. type(tableData))
    end
    self:_SetData(tableEnum, tableData, false)
    return true
end

--- 一次设置多个一级字段，只提交一次并触发一次整字段通知；未提交的一级字段保留。
--- 嵌套表整体复制替换，不递归合并，不接受路径；nil 无法出现在补丁表中，删除使用 GetTable/SetTable。
--- 本接口简化批量修改，提交仍沿用 SetTable 的快照、周期重置、同步和持久化标记，不承诺零深拷贝。
--- @param tableEnum table 玩家表字段定义。
--- @param fields table 一级键到新值的补丁；支持 false，新表值不与存档共享可写引用。
--- @return boolean 是否完成一次内存提交；空补丁或原会话已失效返回 false，不触发通知。
function FSPlayerObjectClass:SetTableFields(tableEnum, fields)
    assert(tableEnum.Type == "table", "SetTableFields: expected table field")
    assert(type(fields) == "table", "SetTableFields: expected fields table")
    if not FSPlayerKVDataManager:IsSessionActive(self._playerId, self._dataSession) then
        return false
    end
    local data = self:GetTableShallow(tableEnum)
    local hasFields = false
    for key, value in fields do
        data[key] = value
        hasFields = true
    end
    if not hasFields then
        return false
    end
    return self:SetTable(tableEnum, data)
end

--- 获取可独立编辑的深拷贝；任意层级修改均不影响存档，必须 SetTable 提交。
--- @param tableEnum table 表字段定义。
--- @return table 表字段的深拷贝。
function FSPlayerObjectClass:GetTable(tableEnum)
    if tableEnum.Type ~= "table" then
        FX.ErrorWithTraceback("GetTable: tableEnum type error, expected table, got " .. tostring(tableEnum.Type))
    end
    return self:_GetData(tableEnum)
end

--- 获取安全浅拷贝：只复制第一层，嵌套表为只读 View；第一层修改必须 SetTable 提交。
--- @param tableEnum table 表字段定义。
--- @return table 第一层可编辑、嵌套只读的表；嵌套编辑请使用 GetTable。
function FSPlayerObjectClass:GetTableShallow(tableEnum)
    return DataAccess.ShallowCopy(self:GetTableView(tableEnum))
end

--- 获取实时只读 View，不深拷贝；字段替换/周期重置后继续读取当前值。
--- 所有层级写入均报错且不改变存档；遍历用 for key, value in view do，不用 pairs/ipairs/next/table.*。
--- View 离服后失效，不会转向重进后的新会话；不要直接发送网络或序列化，需普通表时用 GetTable。
--- @param tableEnum table 表字段定义。
--- @return table 不含原始表引用的冻结代理。
function FSPlayerObjectClass:GetTableView(tableEnum)
    assert(tableEnum.Type == "table", "GetTableView: expected table field")
    local session = self._dataSession
    return DataAccess.View(function()
        if not FSPlayerKVDataManager:IsSessionActive(self._playerId, session) then
            return nil
        end
        if tableEnum.KVTable then
            return self:_GetKVData(tableEnum)
        end
        return self:_GetTempData(tableEnum)
    end)
end

--- 检查持久字段是否曾写入；不使用默认值推断，也不向业务暴露 RealData 存储结构。
--- @param varEnum table 带 KVTable 的玩家字段定义。
--- @return boolean 原始存档中是否存在该字段值。
function FSPlayerObjectClass:HasStoredData(varEnum)
    assert(varEnum.KVTable ~= nil, "HasStoredData: expected persistent field")
    local kv = FSPlayerKVDataManager:GetKVTable(self._playerId, varEnum.KVTable)
    return kv:GetDeepView(varEnum.Key .. ".RealData") ~= nil
end

--- 在存档内存事务中执行玩家操作；失败时同时恢复待同步字段并重建背包呈现。
--- 回调必须无 yield、只通过公开接口修改本玩家数据，成功返回 true；本接口不保存存档。
--- @param callback function 无参数的业务操作，不接收 DB 或原始数据表。
--- @return boolean 是否完整提交内存操作。
function FSPlayerObjectClass:RunDataTransaction(callback)
    local session = self._dataSession
    if not FSPlayerKVDataManager:IsSessionActive(self._playerId, session) then
        return false
    end
    local pending = DataAccess.DeepCopy(self._pendingSyncData)
    if FSPlayerKVDataManager:RunTransaction(self._playerId, session, callback) then
        return true
    end
    self._pendingSyncData = pending
    local inventory = self:GetComponent("FSInventoryComp")
    if inventory then
        inventory:OnAllChanged()
    end
    return false
end

-- 获取排行榜分数
function FSPlayerObjectClass:GetRankingScore(rankingType)
    local ranking = FSRankingManager:GetRanking(rankingType)
    return ranking:GetPlayerScore(self._playerId)
end

-- 更新排行榜的值
-- 如果分数有变化, 返回 true
function FSPlayerObjectClass:UpdateRankingScore(rankingType, value)
    local ranking = FSRankingManager:GetRanking(rankingType)
    return ranking:UpdatePlayerScore(self._playerId, value)
end

-- 增加排行榜的值
function FSPlayerObjectClass:AddRankingScore(rankingType, value)
    local ranking = FSRankingManager:GetRanking(rankingType)
    local oldScore = FSRankingManager:GetPlayerScore(self._playerId, rankingType) or rankingType.DefaultValue
    return ranking:UpdatePlayerScore(self._playerId, oldScore + value)
end

-- 注册玩家数据变化监听
function FSPlayerObjectClass:WatchDataChanged(dataEnum, callback, this)
    local key = dataEnum.Key
    local customNotify = self._playerDataListeners[key]
    if not customNotify then
        self._playerDataListeners[key] = Instance.new("BindableEvent")
        customNotify = self._playerDataListeners[key]
    end
    if this then
        return customNotify.Event:Connect(function(...)
            return callback(this, ...)
        end)
    else
        return customNotify.Event:Connect(callback)
    end
end

return FSPlayerObjectClass
