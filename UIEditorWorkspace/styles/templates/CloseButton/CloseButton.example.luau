local FX = _G.FX
local CCloseButtonUIPreviewCompClass = FX.Class("CCloseButtonUIPreviewCompClass", "CCloseButtonUIBaseCompClass")

-- 模拟模板保留按钮，方便重复检查动作。
-- @param action string 动作名
-- @param payload table 必要参数
function CCloseButtonUIPreviewCompClass:OnUIAction(action, payload)
    print("Template preview: " .. action)
end

return CCloseButtonUIPreviewCompClass