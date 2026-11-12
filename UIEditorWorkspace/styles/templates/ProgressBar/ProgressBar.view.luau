local FX = _G.FX
local FXLoader = FX.Loader
local CProgressBarUIBaseCompClass = FX.Class("CProgressBarUIBaseCompClass", "FCUICompClass")

-- 先用 FXLoader:PlayerGui("实际ScreenGui名") 获取界面，再用 Here(root, "Panel.Button") 查子节点。
function CProgressBarUIBaseCompClass:OnReady()
end

-- 根据接入类数据刷新展示，不在这里创建视觉效果。
-- @param state table 接入类提供的显示状态
function CProgressBarUIBaseCompClass:Render(state)
end

return CProgressBarUIBaseCompClass