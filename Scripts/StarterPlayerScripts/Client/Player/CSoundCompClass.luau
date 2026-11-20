-- 项目音效：沿用 Y1 出售战利品时的到账音效。
local FX = _G.FX
local Fields = _G.PlayerDataConfig
local MONEY_RECEIVED_SOUND_ID = "rbxassetid://99533862853751"

---@class CSoundCompClass: FCSoundCompClass
local CSoundCompClass = FX.Class("CSoundCompClass", "FCSoundCompClass")

--- 初始化通用声音池，供到账音效使用。
--- @param owner CPlayerObjectClass 当前客户端玩家对象。
function CSoundCompClass:Ctor(owner)
    CSoundCompClass.Super.Ctor(self, owner, 4)
end

--- 提供项目声音组件的稳定协作名称。
--- @return string 组件协作名称。
function CSoundCompClass:GetCompName()
    return "CSoundComp"
end

--- 就绪后监听服务端同步的现金和钻石余额，覆盖各个发奖入口。
function CSoundCompClass:OnReady()
    self:WatchDataChanged(Fields.Money, self.OnCurrencyChanged, self)
    self:WatchDataChanged(Fields.Diamonds, self.OnCurrencyChanged, self)
end

--- 只在余额实际增加时播放，首次同步和消费不播放。
--- @param balance number 当前余额。
--- @param previousBalance number? 同步前的余额，首次同步时为空。
function CSoundCompClass:OnCurrencyChanged(balance, previousBalance)
    if previousBalance ~= nil and balance > previousBalance then
        self:PlayEffectSoundWithBGMDuck(MONEY_RECEIVED_SOUND_ID, 2, 0.2)
    end
end

return CSoundCompClass
