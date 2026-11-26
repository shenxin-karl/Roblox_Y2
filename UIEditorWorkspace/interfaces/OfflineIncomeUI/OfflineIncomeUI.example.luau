local FX = _G.FX
local COfflineIncomePreview = FX.Class("COfflineIncomePreview", "COfflineIncomeView")

--- 准备可领取样例与临时钻石价格，金额不会保存到设计节点。
--- @param owner table 编辑器组件宿主。
function COfflineIncomePreview:Ctor(owner)
    COfflineIncomePreview.Super.Ctor(self, owner)
    self.Config = {
        diamondCost = 10,
    }
    self.State = {
        amount = 12500,
        actualSeconds = 11742,
        earnedSeconds = 7200,
        diamonds = 28,
        pending = false,
        failed = false,
    }
end

--- 绑定已有节点后刷新并显示。
function COfflineIncomePreview:OnReady()
    COfflineIncomePreview.Super.OnReady(self)
    self:BindUIData()
    self:Show()
end

--- 模拟普通或钻石双倍领取，真实游戏另行接入服务端。
--- @param action string Claim或Close。
--- @param payload table Claim包含boosted:boolean。
function COfflineIncomePreview:OnUIAction(action, payload)
    if action == "Close" then
        self:Hide()
        return
    end
    if action ~= "Claim" or self.State.pending or self.State.amount <= 0 then
        return
    end
    if payload.boosted then
        if self.State.diamonds < self.Config.diamondCost then
            return
        end
        self.State.diamonds -= self.Config.diamondCost
    end
    self.State.amount = 0
    self.State.actualSeconds, self.State.earnedSeconds = nil, nil
    self:RefreshUI()
end

return COfflineIncomePreview
