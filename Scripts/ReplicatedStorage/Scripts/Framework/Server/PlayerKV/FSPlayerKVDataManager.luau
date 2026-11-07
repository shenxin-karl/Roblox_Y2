local FX, FS = _G.FX, _G.FS
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local Config = require(game:GetService("ServerScriptService").Server.Config.StorageConfig)
local Access = require(script.Parent.FSPlayerDataAccess)
require(script.Parent.FSPlayerKVTableClass)
require(script.Parent.FSPlayerKVDBClass)
-- DB 映射只存在于模块闭包；公开接口不得返回 DB、原始表或可写的嵌套引用。
local playerDBMap, closing = {}, {}
local Manager = {}
FS.PlayerKVDataManager = Manager

--- 周期保存玩家数据并续约正式服锁；玩家事件由 FServer 在通用服务初始化后连接。
--- @return nil
function Manager:Init()
    self._timer = FX.Task:Interval(Config.AutoSaveSeconds, function()
        for id, db in pairs(playerDBMap) do
            if db:IsLoadFinished() and not closing[id] then
                task.spawn(function()
                    if not db:Save(false) then
                        local player = Players:GetPlayerByUserId(id)
                        if player and not FX.IsDeveloper(id) then
                            player:Kick("存档暂时不可用，请稍后重试")
                        end
                    end
                end)
            end
        end
    end)
end

--- 创建并加载新玩家会话，不向调用方暴露 DB。
--- @param player Player 进入服务器的玩家。
--- @return nil
function Manager:PlayerAdded(player)
    if playerDBMap[player.UserId] then
        return
    end

    local db = FS.PlayerKVDBClass.New(player.UserId)
    playerDBMap[player.UserId] = db
    db:LoadAsync()
end

--- 保存并释放离服会话，业务层不得自行清理映射或释放 DB。
--- @param player Player 离开服务器的玩家；也用于关闭服务器。
--- @return nil
function Manager:PlayerRemoving(player)
    local id = player.UserId
    if closing[id] then
        while closing[id] do
            task.wait()
        end

        return
    end

    local db = playerDBMap[id]
    if not db then
        return
    end

    closing[id] = true
    db._leaving = true
    if FS.PlayerManager then
        FS.PlayerManager:OnPlayerLogout(id)
    end

    FS.Events.OnPlayerDataSaveStarted:Fire(id)
    FS.RankingManager:OnPlayerDataSaveStarted(id)
    if db:IsLoadFinished() then
        for attempt = 1, 3 do
            if db:Save(true) then
                break
            end

            task.wait(attempt)
        end
    end

    playerDBMap[id] = nil
    closing[id] = nil
end

--- 获取 KV 公开方法句柄；不返回 DB 或原始表，业务玩家字段优先使用玩家对象接口。
--- @param id number 玩家 ID。
--- @param name string KV 数据域。
--- @return table? 冻结的方法句柄；Get/GetDeep 深拷贝，Shallow 安全浅拷贝，View 实时只读。
function Manager:GetKVTable(id, name)
    local db = playerDBMap[id]
    return db and db:GetKVTable(name)
end

--- 获取已加载且尚未离服的会话标识；跨 yield 保存并重新校验它，不能以 UserId 代替。
--- @param id number 玩家 ID。
--- @return string? 不包含 DB 引用的会话标识。
function Manager:GetSessionToken(id)
    local db = playerDBMap[id]
    if db and db:IsLoadFinished() and not db._leaving then
        return db._session
    end
    return nil
end

--- 核对是否仍为同一可写会话，不暴露加载/释放等内部状态引用。
--- @param id number 玩家 ID。
--- @param session string? 操作开始时取得的会话标识。
--- @return boolean 是否仍可继续本会话操作。
function Manager:IsSessionActive(id, session)
    return session ~= nil and self:GetSessionToken(id) == session
end

--- 返回只含标量的冻结状态快照；快照不随异步操作自动更新。
--- @param id number 玩家 ID。
--- @return table? 会话标识和 loaded/leaving/saving 状态，不包含 DB 或存档。
function Manager:GetState(id)
    local db = playerDBMap[id]
    if not db then
        return nil
    end
    return table.freeze({
        session = db._session, loaded = db:IsLoadFinished(),
        leaving = db._leaving == true, saving = db._saving == true,
    })
end

--- 获取指定会话档案的 JSON 字节数，购买容量预检不接触原始存档。
--- @param id number 玩家 ID。
--- @param session string 本次会话标识。
--- @return number? 档案编码字节数；会话失效或无法编码时返回 nil。
function Manager:GetDataSize(id, session)
    if not self:IsSessionActive(id, session) then
        return nil
    end
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode({Data = playerDBMap[id]._data})
    end)
    if not ok then
        warn("[Storage] Profile encoding failed", id, encoded)
        return nil
    end
    return #encoded
end

--- 保存指定会话；保存会 yield，调用方有后续副作用时必须再次 IsSessionActive。
--- @param id number 玩家 ID。
--- @param session string 操作开始时取得的会话标识。
--- @return boolean 是否保存成功；旧会话不能保存新会话的数据。
function Manager:Save(id, session)
    if not self:IsSessionActive(id, session) then
        return false
    end
    return playerDBMap[id]:Save(false)
end

--- 处理加载完成时玩家已离线的情况；释放和映射清理由存档模块独占。
--- @param id number 已完成加载的玩家 ID。
--- @return nil
function Manager:ReleaseOfflinePlayer(id)
    if Players:GetPlayerByUserId(id) or closing[id] then
        return
    end
    local db = playerDBMap[id]
    if db then
        db._leaving = true
        db:Save(true)
        if playerDBMap[id] == db then
            playerDBMap[id] = nil
        end
    end
end

--- 在内部快照上执行无 yield 的内存事务；失败、异常或 yield 均回滚，不执行持久化。
--- 回调只能通过玩家/KV 公开接口修改本玩家，不得发送消息、保存或修改其他会话。
--- @param id number 玩家 ID。
--- @param session string 本次会话标识。
--- @param callback function 无参数、成功时返回 true 的业务操作，不接收原始数据。
--- @return boolean 是否完整提交内存修改；保存失败后的重试由上层业务处理。
function Manager:RunTransaction(id, session, callback)
    if not self:IsSessionActive(id, session) then
        return false
    end
    local db = playerDBMap[id]
    local before = Access.DeepCopy(db._data)
    local revision = db._revision
    local thread = coroutine.create(callback)
    local ok, result = coroutine.resume(thread)
    local finished = coroutine.status(thread) == "dead"
    if not finished then
        task.cancel(thread)
    end
    if ok and finished and result == true then
        return true
    end
    for name in pairs(db._data) do
        if before[name] == nil then
            db._data[name] = nil
        end
    end
    for name, values in pairs(before) do
        if db._data[name] then
            table.clear(db._data[name])
            for key, value in pairs(values) do
                db._data[name][key] = value
            end
        else
            db._data[name] = values
        end
    end
    db._revision = revision
    return false
end

--- 判断本会话是否已在内存中发放指定收据；保存失败后保留标记，重试只保存。
--- @param id number 玩家 ID。
--- @param session string 本次会话标识。
--- @param purchaseId string Roblox 收据 ID。
--- @return boolean 是否存在发奖记录。
function Manager:HasPurchaseReceipt(id, session, purchaseId)
    if not self:IsSessionActive(id, session) then
        return false
    end
    local receipts = playerDBMap[id]._data.PurchaseReceipts
    return receipts ~= nil and receipts[purchaseId] ~= nil
end

--- 为收据分析回调提供隔离副本，允许 next/pairs，不暴露底层档案。
--- @param id number 玩家 ID。
--- @param session string 本次会话标识。
--- @return table? 历史收据深拷贝；会话失效返回 nil。
function Manager:GetPurchaseReceipts(id, session)
    if not self:IsSessionActive(id, session) then
        return nil
    end
    return Access.DeepCopy(playerDBMap[id]._data.PurchaseReceipts or {})
end

--- 仅在发奖内存事务内登记收据；元数据复制后持有，与奖励在同一档案保存。
--- @param id number 玩家 ID。
--- @param session string 本次会话标识。
--- @param purchaseId string Roblox 收据 ID。
--- @param record boolean|table 去重标记或兼容的收据元数据，复制后持有。
--- @return boolean 是否首次登记成功。
function Manager:RecordPurchaseReceipt(id, session, purchaseId, record)
    if not self:IsSessionActive(id, session) or self:HasPurchaseReceipt(id, session, purchaseId) then
        return false
    end
    local db = playerDBMap[id]
    db._data.PurchaseReceipts = db._data.PurchaseReceipts or {}
    db._data.PurchaseReceipts[purchaseId] = Access.DeepCopy(record)
    db._revision += 1
    return true
end

--- 仅重置加载失败的开发者本人；保留支付元数据并保护其他服务器的有效会话锁。
--- @param id number 已由网络层认证的玩家 ID。
--- @return boolean 是否成功重置云端存档。
--- @return string Unknown/Busy/SaveFailed/Success，供业务层映射翻译 Key。
function Manager:RecoverFailedData(id)
    local db = playerDBMap[id]
    if not FX.IsDeveloper(id) or not db or not db._loadFailed or db._leaving then
        return false, "Unknown"
    end
    local now = os.clock()
    if db._loading or db._saving or db._recovering or now < (db._nextRecovery or 0) then
        return false, "Busy"
    end
    db._recovering = true
    db._nextRecovery = now + 5
    local ok, record = pcall(function()
        return db:_Update(function(old)
            if db._leaving or playerDBMap[id] ~= db or not Players:GetPlayerByUserId(id) then
                return nil
            end
            if Config.SessionLockEnabled and type(old) == "table" and old.Session ~= nil then
                local lock = old.Session
                if type(lock) ~= "table" or type(lock.Id) ~= "string" or type(lock.Time) ~= "number"
                    or lock.Time ~= lock.Time or lock.Time == math.huge or lock.Time == -math.huge then
                    return nil
                end
                if lock.Id ~= db._session and os.time() - lock.Time < Config.SessionLeaseSeconds then
                    return nil
                end
            end
            local data = type(old) == "table" and type(old.Data) == "table" and Access.DeepCopy(old.Data) or {}
            for enumKey, name in pairs(_G.Provider:GetPlayerKVEnum()) do
                data[name] = {}
            end
            local recovered = {Data = data}
            if Config.SessionLockEnabled then
                recovered.Session = {Id = db._session, Time = os.time()}
            end
            return recovered
        end)
    end)
    db._recovering = false
    if not ok or not record then
        warn("[GM] Profile recovery failed", id, record)
        return false, "SaveFailed"
    end
    if not db._leaving and playerDBMap[id] == db and Players:GetPlayerByUserId(id) then
        db:LoadAsync()
    end
    return true, "Success"
end

return Manager
