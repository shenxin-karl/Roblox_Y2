-- GM 面板接入：展示沿用导出 View，所有玩法结果由服务端裁定。
local FX = _G.FX
local FXLoader = FX.Loader
-- GM 面板固定显示中文；服务端仍返回原有文案键，供其他入口继续使用。
local CommandMessages = {
    ["GM.Forbidden"] = "只有开发者可以使用这些功能。",
    ["GM.Unknown"] = "操作失败，请重试。",
    ["GM.Busy"] = "上一条指令还在处理，请稍后重试。",
    ["GM.Success"] = "操作成功。",
    ["GM.InvalidGrant"] = "请检查物品编号和数量。",
    ["GM.GrantFailed"] = "发放失败，请检查背包空间。",
    ["GM.NoNearbySword"] = "请靠近自己摆放的剑，再补足升级材料。",
    ["GM.NoActiveForge"] = "请先开始锻造，再测试锻造损毁。",
}
FXLoader:RequireFromParent(script, "Generated.CGMPanelView")
local Component = FX.Class("CGMPanelUICompClass", "CGMPanelView")

--- 提供主界面按钮使用的组件名。
--- @return string GM 面板组件协作名。
function Component:GetCompName()
    return "CGMPanelUIComp"
end

--- 父类只初始化节点和窗口适配；提供首次渲染的完整状态。
--- @param owner table 当前开发者玩家对象。
function Component:Ctor(owner)
    Component.Super.Ctor(self, owner)
    self.Config = {}
    self.State = {
        pending = false,
        freeUpgrades = false,
        guaranteedForge = false,
    }
end

--- 首次保持关闭。
function Component:OnReady()
    Component.Super.OnReady(self)
    self:BindUIData()
    self:Hide()
end

--- View 拒绝不合法输入时，用通用提示说明格式。
--- @param action string 未提交的表单动作。
function Component:OnInvalidInput(action)
    self:GetPlayerObject():RequireComponent("FCCommonUIComp"):ShowTips("请输入有效编号，数量须为正整数。")
end

--- 等待服务器确认开关状态，失败时恢复操作并展示反馈。
--- @param action string View 发出的稳定命令名。
--- @param payload table View 读取的表单或开关参数。
function Component:OnUIAction(action, payload)
    if self.State.pending then
        return
    end
    self.State.pending = true
    self:RefreshUI()
    self._requestTask = task.defer(function()
        local ok, result = pcall(function()
            return FX.Network:InvokeServer("C2S_GMCommand", action, payload)
        end)
        self._requestTask = nil
        self.State.pending = false
        local message = "指令未完成，请重试。"
        if ok and type(result) == "table" then
            if type(result.key) == "table" then
                message = CommandMessages[result.key.Key] or message
            end
            if result.success and action == "SetFreeUpgrades" then
                self.State.freeUpgrades = result.enabled == true
            elseif result.success and action == "SetGuaranteedForge" then
                self.State.guaranteedForge = result.enabled == true
            end
        end
        self:RefreshUI()
        self:GetPlayerObject():RequireComponent("FCCommonUIComp"):ShowTips(message)
    end)
end

--- 停止当前请求等待，随后由父类清理按钮绑定和显示资源。
function Component:Dtor()
    if self._requestTask then
        task.cancel(self._requestTask)
        self._requestTask = nil
    end
    Component.Super.Dtor(self)
end

return Component
