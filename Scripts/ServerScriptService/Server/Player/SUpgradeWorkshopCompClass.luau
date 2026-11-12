-- 工坊升级：只接受稳定 ID 与旧等级，扣费和等级提交复用奖励兑换。
local FX = _G.FX
local Fields = _G.PlayerDataConfig
local Rules = FX.Loader:RequireShared("Scripts.Game.Shared.UpgradeWorkshopRules")
local Comp = FX.Class("SUpgradeWorkshopCompClass", "FSPlayerCompClass")

--- 返回管理器转发使用的协作名。
--- @return string 工坊组件名。
function Comp:GetCompName()
    return "SUpgradeWorkshopComp"
end

--- 存档和握手完成后开放升级。
function Comp:OnPlayerLogin()
    self._active = true
    self._lastRequest = -math.huge
end

--- 退出后拒绝尚未处理的升级消息。
function Comp:OnPlayerLogout()
    self._active = false
end

--- 服务端核对旧等级并原子兑换，重复请求不会连续扣费。
--- @param upgradeId any 客户端提交的升级 ID。
--- @param expectedLevel any 客户端看到的旧等级。
--- @return boolean 是否完成本次扣费升级。
function Comp:Upgrade(upgradeId, expectedLevel)
    if not self._active or type(upgradeId) ~= "string" or not Rules.BasePrices[upgradeId]
        or type(expectedLevel) ~= "number" or expectedLevel < 0
        or expectedLevel >= Rules.MaxLevel or expectedLevel % 1 ~= 0
        or os.clock() - self._lastRequest < 0.2 then
        return false
    end
    self._lastRequest = os.clock()
    local levels = self:GetTableView(Fields.UpgradeWorkshop)
    if levels[upgradeId] ~= expectedLevel then
        return false
    end
    -- 先结算升级前累计的在线收益，避免新倍率追溯放大旧收益。
    if upgradeId == "income" then
        self:RequireComponent("SSlotSwordComp"):Accrue()
    end
    return self:RequireComponent("FSRewardComp"):ExchangeRewards(
        {{Type = "Money", Currency = "Money", Count = Rules.GetPrice(upgradeId, expectedLevel)}},
        {{Type = "UpgradeWorkshop", UpgradeId = upgradeId, ExpectedLevel = expectedLevel}}
    )
end

return Comp
