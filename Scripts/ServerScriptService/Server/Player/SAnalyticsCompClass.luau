-- 项目统计扩展入口；通用上报使用 FS.AnalyticsManager，不预设玩法漏斗。
local FX = _G.FX
local Component = FX.Class("SAnalyticsCompClass", "FSPlayerCompClass")

--- 返回项目统计组件协作名。
--- @return string 统计组件名。
function Component:GetCompName()
    return "SAnalyticsComp"
end

return Component
