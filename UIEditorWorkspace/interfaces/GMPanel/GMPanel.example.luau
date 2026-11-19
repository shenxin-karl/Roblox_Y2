local FX = _G.FX
local Preview = FX.Class("CGMPanelPreview", "CGMPanelView")

--- 为面板提供独立的模拟开关。
--- @param owner table 预览宿主。
function Preview:Ctor(owner)
    Preview.Super.Ctor(self, owner)
    self.Config = {}
    self.State = {
        pending = false,
        freeUpgrades = false,
        guaranteedForge = false,
    }
end

--- 节点绑定后显示面板。
function Preview:OnReady()
    Preview.Super.OnReady(self)
    self:BindUIData()
    self:Show()
end

--- 验证动作派发与开关映射，不写真实游戏数据。
--- @param action string 稳定命令名。
--- @param payload table 命令参数。
function Preview:OnUIAction(action, payload)
    if action == "SetFreeUpgrades" then
        self.State.freeUpgrades = payload.enabled
    elseif action == "SetGuaranteedForge" then
        self.State.guaranteedForge = payload.enabled
    end
    print("GM action: " .. action)
    self:RefreshUI()
end

return Preview
