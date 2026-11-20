local FX = _G.FX
local CSwordGiftReceivePreview = FX.Class("CSwordGiftReceivePreview", "CSwordGiftReceiveView")

-- 初始化本次运行的模拟数据。
-- @param owner table 编辑器提供的组件宿主，传递给父类
function CSwordGiftReceivePreview:Ctor(owner)
    CSwordGiftReceivePreview.Super.Ctor(self, owner)
    self.Config = {}
    self.State = {}
end

-- 处理展示层动作；只更新模拟数据，再调用 RefreshUI。
-- @param action string 动作名称
-- @param payload table 动作必要参数，例如稳定奖励 ID
function CSwordGiftReceivePreview:OnUIAction(action, payload)
end

return CSwordGiftReceivePreview