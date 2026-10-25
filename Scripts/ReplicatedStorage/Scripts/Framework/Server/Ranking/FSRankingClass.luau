local DataStoreService = game:GetService("DataStoreService")
local StorageConfig = require(game:GetService("ServerScriptService").Server.Config.StorageConfig)
local memory = game:GetService("RunService"):IsStudio() and StorageConfig.StudioMemory
local Players = game:GetService("Players")
local FX, FS = _G.FX, _G.FS
local FXTask = FX.Task
local FXTime = FX.Time

local FSRankingClass = FX.Class("FSRankingClass")
FS.RankingClass = FSRankingClass

--- 初始化排行榜实例，保留上层榜类型标识，同时根据周期配置维护底层存储 key。
--- @param rankingType table 排行榜配置，Name 作为上层标识，ResetType 控制底层存储周期
--- @return nil
function FSRankingClass:Ctor(rankingType)
    self._rankingType = rankingType
    self._baseRankingName = rankingType.Name
    self._rankingName = ""

    self._isDataLoaded = false

    --[[
        rankNo = 排名,
        rankScore = 分数, 
        playerId = 玩家ID, 
        playerName = 玩家名字,
    ]]
    self._rankingDataCache = {}
    self._roomRankingData = {}

    self._roomRankingDataDirty = false
    self._updateRankingPlayerMap = {}
    self:RefreshRankingName()
end

--- 获取跨周期保留的玩家排行榜持久分 key，用于月榜清理后玩家上线恢复当前周期云榜。
--- @param self table 当前排行榜实例
--- @return string baseRankingName 玩家排行榜持久分 key
function FSRankingClass:GetBaseRankingName()
    return self._baseRankingName
end

function FSRankingClass:GetRankingType()
    return self._rankingType
end

--- 根据当前时间生成底层榜单存储 key，避免不同周期的数据互相覆盖。
--- @param timeStamp number 当前服务器时间戳（秒）
--- @return string rankingName 底层榜单存储 key
function FSRankingClass:BuildRankingName(timeStamp)
    local resetType = self._rankingType.ResetType
    local rankingName = self._baseRankingName
    if resetType == "Weekly" then
        local weekStartTimeStamp = FXTime:GetWeekStartTimeStamp(timeStamp)
        rankingName = string.format("%s_Weekly_%s", rankingName, os.date("%Y%m%d", weekStartTimeStamp))
    elseif resetType == "Monthly" then
        rankingName = string.format("%s_Monthly_%s", rankingName, os.date("%Y%m", timeStamp))
    else
        rankingName = rankingName .. "_Permanent"
    end

    if FX.IsDebugMode() then
        rankingName = rankingName .. "_Dev"
    end
    return rankingName
end

--- 刷新当前底层榜单存储 key；跨周期时重置缓存，避免旧周期数据串到新榜。
--- @param self table 当前排行榜实例
--- @return boolean changed 是否发生 key 切换
function FSRankingClass:RefreshRankingName()
    local rankingName = self:BuildRankingName(os.time())
    if self._rankingName == rankingName then
        return false
    end

    self._rankingName = rankingName
    self._isDataLoaded = false
    self._rankingDataCache = {}
    self._roomRankingData = {}
    self._roomRankingDataDirty = true
    self._updateRankingPlayerMap = {}
    self._memoryScores = {}
    return true
end

--- 加载当前周期的全服排行榜缓存；周期切换由管理器定时器统一触发。
--- @param self table 当前排行榜实例
--- @return nil
function FSRankingClass:LoadRankingData()
    local maxCount = self._rankingType.MaxCount
    local ascending = self._rankingType.Ascending
    local data = {}
    if not memory then
        local success, result = pcall(function()
            return DataStoreService:GetOrderedDataStore(self._rankingName)
                :GetSortedAsync(ascending, math.clamp(maxCount, 1, 100))
                :GetCurrentPage()
        end)
        if not success then
            warn("[Ranking] load failed", self._rankingName, result)
            return
        end
        data = result
    else
        for id, info in pairs(self._memoryScores or {}) do
            table.insert(data, { key = tostring(id), value = info.score, nick = info.name })
        end
        table.sort(data, function(a, b)
            return self:CompareRankingScore(a.value, b.value)
        end)
        while #data > maxCount do
            table.remove(data)
        end
    end
    if data ~= nil then
        self._isDataLoaded = true
    end

    self._rankingDataCache = {}
    for rankNo, info in ipairs(data or {}) do
        local playerId = tonumber(info.key)
        local score = tonumber(info.value) or 0
        local name = info.nick or tostring(playerId)
        if not info.nick then
            local ok, result = pcall(Players.GetNameFromUserIdAsync, Players, playerId)
            if ok then
                name = result
            end
        end
        table.insert(self._rankingDataCache, {
            rankNo = rankNo,
            rankScore = score * (self._rankingType.unit or 1),
            playerId = playerId,
            playerName = name,
        })
    end
end

function FSRankingClass:LoadRankingDataAsync()
    FXTask:Spawn(function()
        self:LoadRankingData()
    end)
end

--- 玩家数据加载完成后，用持久排行榜分恢复到当前周期云榜；未上线玩家不会自动恢复。
--- @param playerId number 玩家ID
--- @return nil
function FSRankingClass:OnPlayerDataLoadFinished(playerId)
    local kvTable = FS.PlayerKVDataManager:GetKVTable(playerId, _G.Provider:GetRankingDataStore())
    local value = kvTable:Get(self:GetBaseRankingName())
    if not value then
        return
    end

    self:MakeRoomRankingDataDirty()
    self:UpdatePlayerScore(playerId, value)
end

--- 玩家存档开始时，将当前周期待刷新的榜单数据落到云榜。
--- @param playerId number 玩家ID
--- @return nil
function FSRankingClass:OnPlayerDataSaveStarted(playerId)
    local info = self._updateRankingPlayerMap[playerId]
    if info ~= nil then
        self:SetRankValue(playerId, info)
    end
    self._updateRankingPlayerMap[playerId] = nil
    self:MakeRoomRankingDataDirty()
end

-- 比较分数
function FSRankingClass:CompareRankingScore(lhs, rhs)
    if self._rankingType.Ascending then
        return lhs < rhs
    else
        return lhs > rhs
    end
end

--- 更新玩家在当前周期榜单中的分数。
--- @param playerId number 玩家ID
--- @param newScore number 当前周期的新分数
--- @return boolean success 是否进入榜单刷新流程
function FSRankingClass:UpdatePlayerScore(playerId, newScore)
    -- 生产环境下开发者跳过排行榜
    if not FX.IsDebugMode() and FX.IsDeveloper(playerId) then
        return
    end

    local kvTable = FS.PlayerKVDataManager:GetKVTable(playerId, _G.Provider:GetRankingDataStore())
    local oldScore = kvTable:Get(self:GetBaseRankingName())
    if not self._rankingType.UseHistoricalHighScore or not oldScore or self:CompareRankingScore(newScore, oldScore) then
        kvTable:Set(self:GetBaseRankingName(), newScore)
        self:MakeRoomRankingDataDirty()
    end

    local unit = self._rankingType.unit or 1
    if newScore < unit then
        return
    end

    local lastPlayerScore = nil
    if self._isDataLoaded and self._rankingDataCache[self._rankingType.MaxCount] then
        lastPlayerScore = self._rankingDataCache[self._rankingType.MaxCount].rankScore
    end
    if lastPlayerScore and not self:CompareRankingScore(newScore, lastPlayerScore) then
        return false
    end

    if self._rankingType.UseHistoricalHighScore then -- 比历史分数还低直接返回
        local rankNo, rankScore = self:FindPlayerRank(playerId, true)
        if rankScore and not self:CompareRankingScore(newScore, rankScore) then
            return false
        end
    end

    local player = Players:GetPlayerByUserId(playerId)
    local scorePerUnit = newScore / unit
    self._updateRankingPlayerMap[playerId] = {
        score = scorePerUnit,
        name = player.DisplayName,
    }
    return true
end

function FSRankingClass:MakeRoomRankingDataDirty()
    self._roomRankingDataDirty = true
end

-- 获取房间排名数据
--- 获取当前周期的房间排行榜数据。
--- @param self table 当前排行榜实例
--- @return table roomRankingData 当前周期的房间排行榜数据
function FSRankingClass:GetRoomRankingData()
    self:UpdateRoomRankData()
    return self._roomRankingData
end

-- 获取全服排名数据
--- 获取当前周期的全服排行榜缓存。
--- @param self table 当前排行榜实例
--- @return table globalRankingData 当前周期的全服排行榜数据
function FSRankingClass:GetGlobalRankingData()
    return self._isDataLoaded and self._rankingDataCache or {}
end

-- 更新房间排行榜的排名
--- 重新整理当前周期的房间排行榜缓存，保证读取使用当前底层榜单 key。
--- @param self table 当前排行榜实例
--- @return nil
function FSRankingClass:UpdateRoomRankData()
    if not self._roomRankingDataDirty then
        return
    end

    self._roomRankingDataDirty = false
    local players = Players:GetPlayers()
    self._roomRankingData = {}
    for _, player in ipairs(players) do
        local dbTable = FS.PlayerKVDataManager:GetKVTable(player.UserId, _G.Provider:GetRankingDataStore())
        local value = dbTable and dbTable:IsLoaded() and dbTable:Get(self:GetBaseRankingName())
        if value then
            table.insert(self._roomRankingData, {
                rankScore = value,
                playerId = player.UserId,
                playerName = player.DisplayName,
            })
        end
    end
    table.sort(self._roomRankingData, function(lhs, rhs)
        if lhs.rankScore ~= rhs.rankScore then
            return self:CompareRankingScore(lhs.rankScore, rhs.rankScore)
        end
        -- 分数相同时，按玩家名字排序
        return lhs.playerName < rhs.playerName
    end)
    for rankNo, data in ipairs(self._roomRankingData) do
        data.rankNo = rankNo
    end
end

--- 将待刷新的玩家分数批量写入当前周期的云排行榜。
--- @param self table 当前排行榜实例
--- @return nil
function FSRankingClass:UpdateRankingData()
    for playerId, info in pairs(self._updateRankingPlayerMap) do
        if self:SetRankValue(playerId, info) and self._updateRankingPlayerMap[playerId] == info then
            self._updateRankingPlayerMap[playerId] = nil
        end
    end
end
--- @param playerId number 玩家 ID。
--- @param info table 待写入的分数、昵称。
--- @return boolean 写入是否成功；失败保留队列以供重试。
function FSRankingClass:SetRankValue(playerId, info)
    if memory then
        self._memoryScores[playerId] = info
        return true
    end
    local ok, err = pcall(function()
        DataStoreService:GetOrderedDataStore(self._rankingName):UpdateAsync(tostring(playerId), function(old)
            local score = math.floor(info.score)
            if old and self._rankingType.UseHistoricalHighScore and not self:CompareRankingScore(score, old) then
                return old
            end
            return score
        end)
    end)
    if not ok then
        warn("[Ranking] save failed", err)
    end
    return ok
end

--- 读取玩家在当前周期下的本地排行榜分数。
--- @param playerId number 玩家ID
--- @return any score 当前周期分数，不存在时返回 nil
function FSRankingClass:GetPlayerScore(playerId)
    local kvTable = FS.PlayerKVDataManager:GetKVTable(playerId, _G.Provider:GetRankingDataStore())
    return kvTable:Get(self:GetBaseRankingName())
end

--- 直接写入玩家在当前周期下的本地排行榜分数，保持上层直写接口的语义不变。
--- @param playerId number 玩家ID
--- @param score number 当前周期分数
--- @return boolean success 是否写入成功
function FSRankingClass:SetPlayerScore(playerId, score)
    local kvTable = FS.PlayerKVDataManager:GetKVTable(playerId, _G.Provider:GetRankingDataStore())
    kvTable:Set(self:GetBaseRankingName(), score)
    self:MakeRoomRankingDataDirty()
    return true
end

-- 获取玩家的排名
function FSRankingClass:FindPlayerRank(playerId, isGlobal)
    local rankData = isGlobal and self:GetGlobalRankingData() or self:GetRoomRankingData()
    for _, data in ipairs(rankData) do
        if data.playerId == playerId then
            return data.rankNo, data.rankScore
        end
    end
    return nil, nil
end

return true
