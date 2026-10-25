local FX, FS = _G.FX, _G.FS
local FXNetwork = FX.Network

local FSRankingServiceClass = FX.Class("FSRankingServiceClass")
FS.RankingServiceClass = FSRankingServiceClass

function FSRankingServiceClass:Ctor() end

-- 根据排行榜索引 获取 排行榜的类型
function FSRankingServiceClass:GetRankingType(rankingTypeIndex)
    return _G.Provider:GetRankingEnum()[rankingTypeIndex]
end

--[[
@param playerId 玩家ID
@param scope 排行榜范围, 1: 房间排行榜, 2: 全局排行榜
@param rankingTypeIndex 排行榜类型索引
@param rankingBeginIndex 排行榜开始索引
@param rankingEndIndex 排行榜结束索引
]]
function FSRankingServiceClass:GetRankingData(playerId, scope, rankingTypeIndex, rankingBeginIndex, rankingEndIndex)
    local rankingType = self:GetRankingType(rankingTypeIndex)
    if not rankingType then
        return
    end

    local ranking = FS.RankingManager:GetRanking(rankingType)
    if not ranking then
        return
    end

    local allRankingData = nil
    if scope == 1 then
        allRankingData = ranking:GetRoomRankingData()
    else
        allRankingData = ranking:GetGlobalRankingData()
    end

    local myRank = nil
    local myScore = nil
    local rankItemData = {}
    for i = 1, #allRankingData do
        if playerId == allRankingData[i].playerId then
            myRank = i
            myScore = allRankingData[i].rankScore
        end
        if i >= rankingBeginIndex and i <= rankingEndIndex then
            table.insert(rankItemData, allRankingData[i])
        end
    end

    if not myScore then
        myScore = FS.RankingManager:GetPlayerScore(playerId, rankingType)
    end

    return {
        itemData = rankItemData,
        myNo = myRank,
        myScore = myScore,
    }
end

function FSRankingServiceClass:GetTestData(playerId, scope, rankingTypeIndex, rankingBeginIndex, rankingEndIndex)
    local itemData = {}
    for i = rankingBeginIndex, rankingEndIndex do
        itemData[i] = {
            rankNo = i,
            rankScore = i,
            playerId = playerId,
            playerName = "测试玩家" .. i,
        }
    end

    local myNo = math.random(rankingBeginIndex, rankingEndIndex)
    return {
        itemData = itemData,
        myNo = myNo,
        myScore = itemData[myNo].rankScore,
    }
end
return true
