-- 升级工坊入口：复用导出 View 的展示、关闭按钮与弹窗动画。
local FX = _G.FX
local FXLoader = FX.Loader
FXLoader:RequireFromParent(script, "Generated.CUpgradeWorkshopView")
local Component = FX.Class("CUpgradeWorkshopUICompClass", "CUpgradeWorkshopView")

--- 尚未接入升级玩法数据，空快照不显示加载提示并禁用升级操作。
--- @param owner table 所属客户端玩家对象。
function Component:Ctor(owner)
    Component.Super.Ctor(self, owner)
    self.State = { entries = {} }
end

--- 绑定导出按钮并刷新一次，界面保持关闭，等待侧栏入口打开。
function Component:OnReady()
    Component.Super.OnReady(self)
    self:BindUIData()
    self:Hide()
end

--- 当前仅接入打开入口；空快照不会产生升级动作，不发送未实现的业务请求。
--- @param action string View 发出的动作名称。
--- @param payload table View 提供的稳定升级 ID。
function Component:OnUIAction(action, payload)
end

return Component
