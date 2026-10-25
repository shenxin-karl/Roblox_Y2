local FX, FS = _G.FX, _G.FS
local FXLoader = FX.Loader
local Text = FXLoader:RequireShared("Scripts.Framework.Shared.Core.FXText")
local TranslationTexts = Text.Define("GMRecovery", {
    Forbidden = "Only developers can use these controls.",
    Unknown = "Something went wrong. Please try again.",
    Busy = "An operation is in progress. Please try again shortly.",
    SaveFailed = "Save failed. Please try again.",
    Success = "Operation completed.",
})
local Players = game:GetService("Players")
local Config = FX.Loader:Require(script.Parent.Parent, "Config.StorageConfig")
local SGMRecovery = {}

--- 加载失败时仅重置开发者本人，并保护正式服其他有效会话锁。
--- @param userId number 网络层认证的请求者 ID。
--- @param action any 客户端请求动作，仅接受 ResetData。
--- @return table 云端重置结果；成功后重新加载并沿正常 Ready 初始化。
function SGMRecovery.Request(userId, action)
    if not FX.IsDeveloper(userId) then
        return {success = false, key = TranslationTexts.Forbidden}
    end
    local db = FS.PlayerKVDataManager._playerDBMap[userId]
    if action ~= "ResetData" or not db or not db._loadFailed or db._leaving then
        return {success = false, key = TranslationTexts.Unknown}
    end
    local now = os.clock()
    if db._loading or db._saving or db._recovering or now < (db._nextRecovery or 0) then
        return {success = false, key = TranslationTexts.Busy}
    end
    db._recovering = true
    db._nextRecovery = now + 5
    local ok, record = pcall(function()
        return db:_Update(function(old)
            if db._leaving or FS.PlayerKVDataManager._playerDBMap[userId] ~= db
                or not Players:GetPlayerByUserId(userId) then
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
            -- 仅清空玩家 KV 域，保留可读取的支付回执去重记录等档案元数据。
            local data = type(old) == "table" and type(old.Data) == "table" and FX.Table:DeepCopy(old.Data) or {}
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
        warn("[GM] Profile recovery failed", userId, record)
        return {success = false, key = TranslationTexts.SaveFailed}
    end
    if not db._leaving and FS.PlayerKVDataManager._playerDBMap[userId] == db
        and Players:GetPlayerByUserId(userId) then
        db:LoadAsync()
    end
    return {success = true, key = TranslationTexts.Success}
end

return SGMRecovery
