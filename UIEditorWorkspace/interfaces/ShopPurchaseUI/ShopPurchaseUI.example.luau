local FX = _G.FX
local CShopPurchasePreview = FX.Class("CShopPurchasePreview", "CShopPurchaseView")

-- 初始化本次运行的模拟数据。
-- @param owner table 编辑器提供的组件宿主，传递给父类
function CShopPurchasePreview:Ctor(owner)
    CShopPurchasePreview.Super.Ctor(self, owner)
    self.Config = {
        itemId = "training_x2",
        name = "2× Training Boost",
        category = "TRAINING BOOST",
        description = "Double your training gains.\nMake every workout count.",
        price = 28,
        icon = "",
    }
    self.State = {
        status = "Ready",
        pending = false,
    }
end

-- 父方法先绑定节点，再初始化数据展示并打开。
function CShopPurchasePreview:OnReady()
    CShopPurchasePreview.Super.OnReady(self)
    self:BindUIData()
    self:Show()
end

-- 模拟购买立即成功；关闭只调用公共显隐接口。
-- @param action string Buy 或 Close
-- @param payload table Buy 的稳定 itemId；Close 为空表
function CShopPurchasePreview:OnUIAction(action, payload)
    if action == "Close" then
        self:Hide()
        return
    end
    assert(action == "Buy", "Unsupported purchase action")
    assert(payload.itemId == self.Config.itemId, "Unknown purchase item")
    if self.State.status ~= "Ready" or self.State.pending then
        return
    end
    self.State.status = "Purchased"
    self.State.error = nil
    self:RefreshUI()
end

return CShopPurchasePreview
