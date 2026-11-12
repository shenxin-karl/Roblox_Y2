local FX, FS = _G.FX, _G.FS
local Config = require(game:GetService("ServerScriptService").Server.Config.StorageConfig)
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local memory = game:GetService("RunService"):IsStudio() and Config.StudioMemory
local store = not memory and DataStoreService:GetDataStore(Config.DataStoreName)
local memoryRecords = {}
local DB = FX.Class("FSPlayerKVDBClass")
FS.PlayerKVDBClass = DB

--- 所有 KV 域同属一个玩家记录，购买回执和奖励可在一次更新中落盘。
--- @param playerId number Roblox UserId。
function DB:Ctor(playerId)
    self._playerId = playerId
    self._key = "Player_" .. tostring(playerId)
    self._session = HttpService:GenerateGUID(false)
    self._data, self._database = {}, {}
    self._loaded, self._saving, self._released = false, false, false
    self._loading, self._loadFailed = false, false
    self._revision = 0
end

--- 有效外服锁最多等待 60 秒并退避重试；离服取消等待，其他加载错误不创建空档继续游戏。
--- @return nil
function DB:LoadAsync()
    self._loading, self._loadFailed = true, false
    task.spawn(function()
        local player = Players:GetPlayerByUserId(self._playerId)
        local deadline = os.clock() + 60
        local delay = 1
        local success, record
        while true do
            if self._leaving or not player or Players:GetPlayerByUserId(self._playerId) ~= player then
                self._loading = false
                return
            end
            local locked = false
            success, record = pcall(function()
                return self:_Update(function(old)
                    -- UpdateAsync 可能在等待后重跑回调，必须重新核对原玩家和本次锁判断。
                    locked = false
                    if self._leaving or Players:GetPlayerByUserId(self._playerId) ~= player then
                        return nil
                    end
                    if old ~= nil then
                        assert(type(old) == "table" and type(old.Data) == "table", "Invalid saved profile")
                    end

                    old = old or { Data = {} }
                    if Config.SessionLockEnabled then
                        local lock = old.Session
                        if lock ~= nil then
                            assert(type(lock) == "table" and type(lock.Id) == "string"
                                and type(lock.Time) == "number" and lock.Time == lock.Time
                                and math.abs(lock.Time) < math.huge, "Invalid saved session lock")
                            if lock.Id ~= self._session and os.time() - lock.Time < Config.SessionLeaseSeconds then
                                locked = true
                                return nil
                            end
                        end
                        old.Session = { Id = self._session, Time = os.time() }
                    else
                        old.Session = nil
                    end
                    return old
                end)
            end)
            if not success or record or not locked then
                break
            end
            local remaining = deadline - os.clock()
            if remaining <= 0 then
                break
            end
            -- 短轮询只检查取消条件，不请求云端；避免离服后仍睡满整个退避间隔。
            local retryAt = os.clock() + math.min(delay + math.random() * delay * 0.25, 8, remaining)
            repeat
                task.wait(math.min(0.25, math.max(0, retryAt - os.clock())))
            until os.clock() >= retryAt or self._leaving or Players:GetPlayerByUserId(self._playerId) ~= player
            delay = math.min(delay * 2, 8)
        end

        if (not success or not record)
            and (self._leaving or Players:GetPlayerByUserId(self._playerId) ~= player) then
            self._loading = false
            return
        end

        if not success or not record then
            self._loading, self._loadFailed = false, true
            warn("[Storage] Load failed or session locked", self._playerId, record)
            if not self._leaving then
                FS.Events.OnPlayerDataLoadFailed:Fire(self._playerId)
            end
            return
        end

        self._data = record.Data
        -- 历史分析元数据不再持久化，保留全部 PurchaseId 以防重复发奖。
        if self._data.PurchaseReceipts then
            for purchaseId, receiptRecord in pairs(self._data.PurchaseReceipts) do
                if type(receiptRecord) == "table" then
                    self._data.PurchaseReceipts[purchaseId] = true
                end
            end
        end
        for enumKey, name in pairs(_G.Provider:GetPlayerKVEnum()) do
            local data = self._data[name]
            if data ~= nil and type(data) ~= "table" then
                self._loading, self._loadFailed = false, true
                warn("[Storage] Invalid KV domain", name)
                if not self._leaving then
                    FS.Events.OnPlayerDataLoadFailed:Fire(self._playerId)
                end
                return
            end

            self._data[name] = data or {}
            self._database[name] = FS.PlayerKVTableClass.New(self, name)
        end

        self._loaded, self._loading = true, false
        if self._leaving or Players:GetPlayerByUserId(self._playerId) ~= player then
            return
        end

        FS.Events.OnPlayerDataLoadFinished:Fire(self._playerId)
    end)
end

--- Studio 内存模式使用相同的更新逻辑，只是不调用云服务。
--- @param transform function 无 yield 的原子转换。
--- @return table 更新后的记录，取消时返回 nil。
function DB:_Update(transform)
    if not memory then
        return store:UpdateAsync(self._key, transform)
    end

    local nextRecord = transform(FX.Table:DeepCopy(memoryRecords[self._key]))
    if nextRecord then
        memoryRecords[self._key] = FX.Table:DeepCopy(nextRecord)
    end

    return nextRecord
end

--- 保存异常必须释放保存互斥，锁已被接管时向关闭队列报告不可重试原因。
--- @param release boolean 离服时完成最后一次保存、释放正式服锁并停止后续写入。
--- @return boolean 是否成功持久化本次快照。
--- @return string? 失败原因为 SessionLost / Unavailable / Inactive。
function DB:Save(release)
    while self._saving do
        task.wait()
    end

    if not self._loaded or self._released then
        return false, "Inactive"
    end

    self._saving = true
    local lostSession = false
    local success, result = pcall(function()
        local snapshot = FX.Table:DeepCopy(self._data)
        return self:_Update(function(old)
            lostSession = false
            if not old then
                lostSession = true
                return nil
            end
            if Config.SessionLockEnabled and (not old.Session or old.Session.Id ~= self._session) then
                lostSession = true
                return nil
            end

            local record = { Data = snapshot }
            if Config.SessionLockEnabled and not release then
                record.Session = { Id = self._session, Time = os.time() }
            end
            return record
        end)
    end)

    self._saving = false
    if not success or not result then
        warn("[Storage] Save failed", self._playerId, result)
        return false, success and lostSession and "SessionLost" or "Unavailable"
    end

    self._released = release == true
    return true
end

--- @return boolean 当前保存结果；保留原框架接口。
function DB:SaveAsync()
    return self:Save(false)
end

--- @param name string 已声明的 KV 域。
--- @return table? 冻结的 KV 公开方法句柄，不暴露 DB 或原始数据表。
function DB:GetKVTable(name)
    local kvTable = self._database[name]
    return kvTable and kvTable:GetHandle()
end

--- @return boolean 是否成功加载且仍拥有会话。
function DB:IsLoadFinished()
    return self._loaded and not self._released
end

return DB
