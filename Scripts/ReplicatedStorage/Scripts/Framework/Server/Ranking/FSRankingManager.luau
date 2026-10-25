local FX, FS = _G.FX, _G.FS
local FXLoader = FX.Loader
local FSEvents = FS.Events
local FXTask = FX.Task
local FXTime = FX.Time

FXLoader:RequireFromParent(script, "FSRankingClass")

local FSRankingManager = {}
FS.RankingManager = FSRankingManager

--- 初始化排行榜管理器，创建榜单实例并启动定时写榜、拉榜与跨日切榜检查。
--- @param self table 当前排行榜管理器
--- @return nil
function FSRankingManager:Init()
    self._rankingMap = {}
    if FX.IsDebugMode() then
        self._refreshInterval = 3 -- 3s写入一次排行榜
        self._loadInterval = 20 -- 20s加载一次排行榜
    else
        self._refreshInterval = 30 -- 30s写入一次排行榜
        self._loadInterval = 150 -- 150s加载一次排行榜
    end

    for _, rankingType in pairs(_G.Provider:GetRankingEnum()) do
        local rank = FS.RankingClass.New(rankingType)
        self._rankingMap[rankingType.Name] = rank
        rank:LoadRankingDataAsync()
    end

    FXTask:Spawn(function()
        self:UpdateRankingAsync()
    end)

    FXTask:Spawn(function()
        self:LoadRankingAsync()
    end)

    FXTask:Spawn(function()
        self:WatchRankingPeriodAsync()
    end)

    FSEvents.OnPlayerDataLoadFinished.Event:Connect(function(playerId)
        self:OnPlayerDataLoadFinished(playerId)
    end)
end

function FSRankingManager:OnPlayerDataLoadFinished(playerId)
    for _, ranking in pairs(self._rankingMap) do
        ranking:OnPlayerDataLoadFinished(playerId)
    end
end

function FSRankingManager:OnPlayerDataSaveStarted(playerId)
    for _, ranking in pairs(self._rankingMap) do
        ranking:OnPlayerDataSaveStarted(playerId)
    end
end

function FSRankingManager:GetRanking(rankingType)
    return self._rankingMap[rankingType.Name]
end

-- 返回的数据如下
--[[
    {
        rankNo = 排名,
        rankScore = 分数, 
        playerId = 玩家ID, 
        playerName = 玩家名字,
    }
]]
function FSRankingManager:GetRoomRankingData(rankingType)
    local ranking = self._rankingMap[rankingType.Name]
    if ranking then
        return ranking:GetRoomRankingData()
    end
    return {}
end

function FSRankingManager:GetGlobalRankingData(rankingType)
    local rank = self._rankingMap[rankingType.Name]
    if rank then
        return rank:GetGlobalRankingData()
    end
    return {}
end

function FSRankingManager:UpdateRankingAsync()
    while true do
        for _, ranking in pairs(self._rankingMap) do
            ranking:UpdateRankingData()
        end
        FXTask:Wait(self._refreshInterval)
    end
end

function FSRankingManager:LoadRankingAsync()
    while true do
        for _, ranking in pairs(self._rankingMap) do
            ranking:LoadRankingData()
        end
        FXTask:Wait(self._loadInterval)
    end
end

--- 计算下一次跨日检查时间，统一在次日 0 点检查排行榜底层 key 是否需要切换。
--- @param self table 当前排行榜管理器
--- @param currentTime number 当前服务器时间戳（秒）
--- @return number nextRefreshTimeStamp 下一次跨日检查时间戳
function FSRankingManager:GetNextRankingRefreshTimeStamp(currentTime)
    return FXTime:GetDayStartTimeStamp(currentTime) + 24 * 60 * 60
end

--- 在每天 0 点主动检查排行榜底层 key；发生切换后立即刷新并重载服务器缓存。
--- @param self table 当前排行榜管理器
--- @return nil
function FSRankingManager:WatchRankingPeriodAsync()
    while true do
        local currentTime = os.time()
        local nextRefreshTimeStamp = self:GetNextRankingRefreshTimeStamp(currentTime)
        local waitTime = math.max(1, nextRefreshTimeStamp - currentTime)
        FXTask:Wait(waitTime)
        for _, ranking in pairs(self._rankingMap) do
            if ranking:RefreshRankingName() then
                ranking:LoadRankingData()
            end
        end
    end
end

function FSRankingManager:GetPlayerScore(playerId, rankingType)
    local ranking = self._rankingMap[rankingType.Name]
    if ranking then
        return ranking:GetPlayerScore(playerId)
    end
    assert(false, string.format("FSRankingManager:GetPlayerScore rankingType %s not found", rankingType.Name))
end

--- 按当前周期规则设置玩家排行榜分数，避免绕过底层动态榜单 key。
--- @param playerId number 玩家ID
--- @param rankingType table 排行榜配置
--- @param score number 当前周期分数
--- @return boolean success 是否写入成功
function FSRankingManager:SetPlayerScore(playerId, rankingType, score)
    local ranking = self._rankingMap[rankingType.Name]
    if ranking then
        return ranking:SetPlayerScore(playerId, score)
    end
    assert(false, string.format("FSRankingManager:SetPlayerScore rankingType %s not found", rankingType.Name))
end

return true
