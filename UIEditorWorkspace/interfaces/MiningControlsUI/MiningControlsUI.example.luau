-- 操作台编辑器预览，仅记录动作，不发送游戏请求。
local FX = _G.FX
local Preview = FX.Class("CMiningControlsPreview", "CMiningControlsView")

--- 显示可点击的操作台预览。
function Preview:OnReady()
    Preview.Super.OnReady(self)
    self:Show()
end

--- 在预览日志中显示当前方向与发射动作。
--- @param action string Steer 或 Fire。
--- @param payload table Steer 含方向；Fire 为空。
function Preview:OnUIAction(action, payload)
    print(action, payload.direction)
end

return Preview
