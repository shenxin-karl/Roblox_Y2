-- 项目月榜：本地成绩按月份隔离，云榜继续复用框架的编码、缓存和写入。
local FX = _G.FX
local Players = game:GetService("Players")
local Ranking = FX.Class("SMonthlyRankingClass", "FSRankingClass")

--- 让框架的自动恢复、房间查询和个人成绩都读取当月的本地键。
--- @return string 包含月份的本地成绩键。
function Ranking:GetBaseRankingName()
    return self._rankingName
end

--- 云榜使用整数排序，收益榜保留两位小数用于比较和展示。
--- @param score number 有限的原始分数。
--- @return number 云榜排序整数。
function Ranking:EncodeScore(score)
    local scaled = score * self._rankingType.ScoreScale
    if scaled < 2 ^ 52 then
        scaled = math.floor(scaled + 0.5)
    end
    return Ranking.Super.EncodeScore(self, scaled)
end

--- 在查询时恢复原始单位，在线时长仍以秒为单位。
--- @param score number 云榜排序整数。
--- @return number 解码后的分数。
function Ranking:DecodeScore(score)
    return Ranking.Super.DecodeScore(self, score) / self._rankingType.ScoreScale
end

--- 换月时保留旧榜的待写成绩，避免月底尾数进入新榜或被丢弃。
--- @return boolean 是否切换了月份。
function Ranking:RefreshRankingName()
    if self._rankingName == self:BuildRankingName(os.time()) then
        return false
    end
    if self._rankingName ~= "" then
        self._previousPeriod = setmetatable({
            _rankingName = self._rankingName,
            _memoryScores = self._memoryScores,
            _updateRankingPlayerMap = self._updateRankingPlayerMap,
            _isDataLoaded = false,
        }, {__index = self})
    end
    return Ranking.Super.RefreshRankingName(self)
end

--- 异步拉榜只提交到发起时的月份，防止月底未返回的旧查询覆盖新榜。
function Ranking:LoadRankingData()
    local snapshot = setmetatable({
        _rankingName = self._rankingName,
        _memoryScores = self._memoryScores,
        _isDataLoaded = false,
    }, {__index = self})
    Ranking.Super.LoadRankingData(snapshot)
    if self._rankingName == snapshot._rankingName and snapshot._isDataLoaded then
        self._rankingDataCache = snapshot._rankingDataCache
        self._isDataLoaded = true
    end
end

--- 正常批量写入之外，也继续提交换月时留下的旧榜队列。
function Ranking:UpdateRankingData()
    local previous = self._previousPeriod
    if previous then
        Ranking.Super.UpdateRankingData(previous)
    end
    -- 写请求可能让出执行权，当前批次始终使用开始时的月份和队列。
    local snapshot = setmetatable({
        _rankingName = self._rankingName,
        _memoryScores = self._memoryScores,
        _updateRankingPlayerMap = self._updateRankingPlayerMap,
    }, {__index = self})
    Ranking.Super.UpdateRankingData(snapshot)
end

--- 离服及关服时由框架保存流程提交当前分数和可能存在的上月尾差。
--- @param playerId number 离服玩家 ID。
function Ranking:OnPlayerDataSaveStarted(playerId)
    local previous = self._previousPeriod
    if previous then
        Ranking.Super.OnPlayerDataSaveStarted(previous, playerId)
    end
    Ranking.Super.OnPlayerDataSaveStarted(self, playerId)
end

--- 更新指定月份的最高分；离服时 Player 节点可能已移出 Players。
--- @param period table 当前榜或仍可补写的旧榜。
--- @param playerId number 服务端玩家 ID。
--- @param score number 原始成绩。
--- @return boolean 是否加入云榜写入队列。
function Ranking:QueueScore(period, playerId, score)
    if (not FX.IsDebugMode() and FX.IsDeveloper(playerId)) or score <= 0 or score >= math.huge or score ~= score then
        return false
    end
    local oldScore = period:GetPlayerScore(playerId)
    if oldScore and score < oldScore then
        return false
    end
    if not oldScore or score > oldScore then
        period:SetPlayerScore(playerId, score)
    end
    local data = period._isDataLoaded and period._rankingDataCache
    local cutoff = data and data[period._rankingType.MaxCount]
    local rankNo, rankScore = period:FindPlayerRank(playerId, true)
    if (cutoff and score <= cutoff.rankScore) or (rankScore and score <= rankScore) then
        return false
    end
    local player = Players:GetPlayerByUserId(playerId)
    local pending = period._updateRankingPlayerMap[playerId]
    if not pending or score > pending.score then
        period._updateRankingPlayerMap[playerId] = {score = score, name = player and player.DisplayName or tostring(playerId)}
    end
    return true
end

--- 在投递前核对月份，避免玩家的更新比框架换榜任务更早发生时串榜。
function Ranking:EnsureCurrentPeriod()
    if self:RefreshRankingName() then
        self:LoadRankingDataAsync()
    end
end

--- @return boolean 当前月份是否已经成功加载过全服榜，空榜也属于加载成功。
function Ranking:IsGlobalDataLoaded()
    return self._isDataLoaded
end

--- 接收框架恢复的成绩和项目产生的秒收益。
--- @param playerId number 服务端玩家 ID。
--- @param score number 原始成绩。
--- @return boolean 是否加入云榜写入队列。
function Ranking:UpdatePlayerScore(playerId, score)
    self:EnsureCurrentPeriod()
    return self:QueueScore(self, playerId, score)
end

--- 跨月会话拆成两段，分别累加到各自月份。
--- @param playerId number 服务端玩家 ID。
--- @param seconds number 归属于该月份的在线秒数。
--- @param timestamp number 该段在线时间所在月份内的 Unix 秒。
function Ranking:AddOnlineSeconds(playerId, seconds, timestamp)
    self:EnsureCurrentPeriod()
    local name = self:BuildRankingName(timestamp)
    local period = name == self._rankingName and self or self._previousPeriod
    if period and period._rankingName == name then
        self:QueueScore(period, playerId, (period:GetPlayerScore(playerId) or self._rankingType.DefaultValue) + seconds)
    end
end

--- 先切换月份再执行框架的登录恢复，杜绝读取上一月的分数作为本月成绩。
--- @param playerId number 刚完成存档加载的玩家 ID。
function Ranking:OnPlayerDataLoadFinished(playerId)
    self:EnsureCurrentPeriod()
    Ranking.Super.OnPlayerDataLoadFinished(self, playerId)
end

return Ranking
