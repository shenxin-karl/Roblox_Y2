local FX, FS = _G.FX, _G.FS
local Ranking = FX.Class("SRankingServiceClass", "FSRankingServiceClass")
_G.SRankingServiceClass = Ranking

local function Integer(value, min, max)
    return type(value) == "number" and value == value and value % 1 == 0 and value >= min and value <= max
end

function Ranking:Ctor()
    Ranking.Super.Ctor(self)
    FX.Network:RegClientMsgCallback("C2S_RankingData", function(id, scope, kind, first, last)
        if
            not FS.PlayerManager:GetPlayerObject(id)
            or not Integer(scope, 1, 2)
            or not Integer(kind, 1, #_G.Provider:GetRankingEnum())
            or not Integer(first, 1, 100)
            or not Integer(last, first, 100)
        then
            return nil
        end

        return self:GetRankingData(id, scope, kind, first, last)
    end)
end

return Ranking
