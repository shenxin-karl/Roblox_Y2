-- 剑胚赠送收件箱。共享存储只保存交付流水，不读取或修改玩家档案。
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local FXLoader = _G.FX.Loader
local StorageConfig = FXLoader:Require(script.Parent.Parent, "Config.StorageConfig")
local useMemory = RunService:IsStudio() and StorageConfig.StudioMemory
local store = not useMemory and DataStoreService:GetDataStore(StorageConfig.DataStoreName .. "_SwordGifts")
local memory = {}
local Mailbox = {}

--- 更新一位接收者的收件箱；相同 key 的投递和清理由 UpdateAsync 串行合并。
--- @param receiverId number 接收者 UserId。
--- @param transform function 可重复执行且不会让出执行权的更新函数。
--- @return boolean 是否确认处理成功，失败由调用方重试。
local function Update(receiverId, transform)
    if useMemory then
        local value = transform(memory[receiverId])
        if value then
            memory[receiverId] = value
        end
        return true
    end
    local success, result = pcall(store.UpdateAsync, store, tostring(receiverId), transform)
    if not success then
        warn("[SwordGift] Mailbox update failed", receiverId, result)
    end
    return success
end

--- 每个赠送者按顺序投递。保留已见序号，允许发件清理失败后的重试。
--- @param senderId number 赠送者 UserId。
--- @param gift table 已持久化的赠送信息。
--- @return boolean 是否已投递或此前已投递过。
function Mailbox.Publish(senderId, gift)
    local senderKey = tostring(senderId)
    return Update(gift.ReceiverId, function(box)
        box = box or {Tail = 0, Ack = 0, Senders = {}, Entries = {}}
        if gift.Sequence <= (box.Senders[senderKey] or 0) then
            return nil
        end
        box.Tail += 1
        box.Senders[senderKey] = gift.Sequence
        box.Entries[tostring(box.Tail)] = gift
        return box
    end)
end

--- 缓存旧快照只会延迟取件，实际交付仍由档案游标去重。
--- @param receiverId number 接收者 UserId。
--- @return boolean, table? 读取状态和收件箱快照。
function Mailbox.Read(receiverId)
    if useMemory then
        return true, memory[receiverId]
    end
    local success, result = pcall(store.GetAsync, store, tostring(receiverId))
    if not success then
        warn("[SwordGift] Mailbox read failed", receiverId, result)
        return false
    end
    return true, result
end

--- 仅清除接收方已保存游标覆盖的礼物，保留投递去重序号。
--- @param receiverId number 接收者 UserId。
--- @param cursor number 接收方已持久化的收件游标。
--- @return boolean 是否已确认清理。
function Mailbox.Acknowledge(receiverId, cursor)
    return Update(receiverId, function(box)
        if not box or cursor <= box.Ack then
            return nil
        end
        for sequence = box.Ack + 1, math.min(cursor, box.Tail) do
            box.Entries[tostring(sequence)] = nil
        end
        box.Ack = math.min(cursor, box.Tail)
        return box
    end)
end

return Mailbox
