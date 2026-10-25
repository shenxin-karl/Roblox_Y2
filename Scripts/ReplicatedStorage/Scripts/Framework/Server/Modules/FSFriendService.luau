local FX, FS = _G.FX, _G.FS
local Players = game:GetService("Players")
local Friends = { _entries = {}, _revision = 0 }
FS.FriendService = Friends

-- 仅服务端读取平台列表；必须完成所有分页后才替换缓存。
function Friends:Refresh(player)
    local entry = self._entries[player.UserId]
    if not entry or entry.player ~= player or entry.busy then
        return
    end
    entry.busy = true
    local ok, ids = pcall(function()
        local pages = Players:GetFriendsAsync(player.UserId)
        local result = {}
        while true do
            for _, friend in ipairs(pages:GetCurrentPage()) do
                result[friend.Id] = true
            end
            if pages.IsFinished then
                return result
            end
            pages:AdvanceToNextPageAsync()
        end
    end)
    -- 请求期间离服或重进的结果不得污染新会话。
    if self._entries[player.UserId] ~= entry then
        return
    end
    entry.busy = false
    if ok then
        entry.ids, entry.status = ids, "Ready"
    else
        entry.status = "Unavailable"
        warn("[Friends] platform query failed", player.UserId, ids)
    end
    self:_PublishAll()
end

-- 返回 nil 表示尚未查到可靠结果，不把平台故障解释为非好友。
function Friends:IsFriend(playerId, otherId)
    local entry = self._entries[playerId]
    if not entry or entry.status ~= "Ready" then
        return nil
    end
    return entry.ids[otherId] == true
end

function Friends:GetFriendIds(playerId)
    local entry = self._entries[playerId]
    if not entry or entry.status ~= "Ready" then
        return nil
    end
    local ids = {}
    for id in pairs(entry.ids) do
        table.insert(ids, id)
    end
    table.sort(ids)
    return ids
end

-- 客户端只接收自己的同服好友 ID，不广播完整社交列表。
function Friends:GetState(playerId)
    local entry = self._entries[playerId]
    local ids = {}
    if entry then
        for id in pairs(self._entries) do
            if id ~= playerId and entry.ids[id] then
                table.insert(ids, id)
            end
        end
    end
    table.sort(ids)
    return { ids = ids, status = entry and entry.status or "Loading", revision = self._revision }
end

function Friends:GetFriendCountInRoom(playerId)
    local state = self:GetState(playerId)
    if state.status ~= "Ready" then
        return nil
    end
    return #state.ids
end

function Friends:_PublishAll()
    self._revision += 1
    for id in pairs(self._entries) do
        FX.Network:SendMsgToClient(id, "S2C_FriendState", self:GetState(id))
    end
end

function Friends:_Add(player)
    if self._entries[player.UserId] then
        return
    end
    self._entries[player.UserId] = { player = player, ids = {}, status = "Loading" }
    self:_PublishAll()
    task.spawn(function()
        self:Refresh(player)
    end)
end

function Friends:Init()
    assert(not self._connections, "Friend service already initialized")
    self._connections = {
        Players.PlayerAdded:Connect(function(player)
            self:_Add(player)
        end),
        Players.PlayerRemoving:Connect(function(player)
            local entry = self._entries[player.UserId]
            if entry and entry.player == player then
                self._entries[player.UserId] = nil
                self:_PublishAll()
            end
        end),
    }
    FX.Network:RegClientMsgCallback("C2S_GetFriendState", function(id)
        FX.Network:SendMsgToClient(id, "S2C_FriendState", self:GetState(id))
        return self:GetState(id)
    end)
    for _, player in ipairs(Players:GetPlayers()) do
        self:_Add(player)
    end
    -- 定期刷新处理加好友/解除好友和临时平台故障；客户端无法触发平台请求。
    self._timer = FX.Task:Interval(120, function()
        for _, entry in pairs(self._entries) do
            task.spawn(function()
                self:Refresh(entry.player)
            end)
        end
    end)
end

function Friends:Dtor()
    FX.Task:Cancel(self._timer)
    for _, connection in ipairs(self._connections or {}) do
        connection:Disconnect()
    end
    self._connections = nil
    table.clear(self._entries)
    FX.Network:UnRegClientMsgCallback("C2S_GetFriendState")
end

return Friends
