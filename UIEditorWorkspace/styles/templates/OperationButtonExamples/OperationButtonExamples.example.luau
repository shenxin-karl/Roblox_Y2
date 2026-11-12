local FX = _G.FX
local COperationButtonExamplesUIPreviewCompClass = FX.Class("COperationButtonExamplesUIPreviewCompClass", "COperationButtonExamplesUIBaseCompClass")

-- 模拟动作只输出日志，不触发真实业务。
-- @param action string 稳定操作名
-- @param payload table 必要动作参数
function COperationButtonExamplesUIPreviewCompClass:OnUIAction(action, payload)
    print("Template preview: " .. action)
end

return COperationButtonExamplesUIPreviewCompClass