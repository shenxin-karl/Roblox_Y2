local FX = _G.FX
local CWindowUIPreviewCompClass = FX.Class("CWindowUIPreviewCompClass", "CWindowUIBaseCompClass")

-- 模板无业务接入，动作仅输出模拟记录。
-- @param action string 操作名
-- @param payload table 动作参数
function CWindowUIPreviewCompClass:OnUIAction(action, payload)
    print("Template preview: " .. action)
end

return CWindowUIPreviewCompClass