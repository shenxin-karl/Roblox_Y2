local FX, FS = _G.FX, _G.FS
local MonthlyRanking = FX.Loader:RequireFromParent(script, "SMonthlyRankingClass")
local Ranking = FX.Class("SRankingServiceClass", "FSRankingServiceClass")
_G.SRankingServiceClass = Ranking

--- 限制客户端可查的榜单和分页范围。
--- @param value any 客户端参数。
--- @param min number 下界。
--- @param max number 上界。
--- @return boolean 是否为范围内的整数。
local function Integer(value, min, max)
    return type(value) == "number" and value == value and value % 1 == 0 and value >= min and value <= max
end

--- 沿用 Y1 的项目榜单替换入口，由框架继续管理写入、查询和离服保存。
function Ranking:Ctor()
    Ranking.Super.Ctor(self)
    for index, config in ipairs(_G.Provider:GetRankingEnum()) do
        local ranking = MonthlyRanking.New(config)
        FS.RankingManager._rankingMap[config.Name] = ranking
        ranking:LoadRankingDataAsync()
    end
    FX.Network:RegClientMsgCallback("C2S_RankingData", function(id, scope, kind, first, last)
        if
            not FS.PlayerManager
            or not FS.PlayerManager:GetPlayerObject(id)
            or not Integer(scope, 1, 2)
            or not Integer(kind, 1, #_G.Provider:GetRankingEnum())
            or not Integer(first, 1, 100)
            or not Integer(last, first, 100)
        then
            return nil
        end

        local config = self:GetRankingType(kind)
        local ranking = FS.RankingManager:GetRanking(config)
        ranking:EnsureCurrentPeriod()
        if scope == 2 and not ranking:IsGlobalDataLoaded() then
            return nil
        end
        local data = self:GetRankingData(id, scope, kind, first, last)
        data.myScore = ranking:GetPlayerScore(id) or data.myScore
        return data
    end)
end

return Ranking
