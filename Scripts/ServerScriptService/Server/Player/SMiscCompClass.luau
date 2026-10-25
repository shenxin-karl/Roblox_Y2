-- 项目杂项组件预留入口；模板不包含训练、转生或地图传送业务。
local FX = _G.FX
local Component = FX.Class("SMiscCompClass", "FSPlayerCompClass")

--- 保留稳定的项目组件协作名。
--- @return string 杂项组件名。
function Component:GetCompName()
    return "SMiscComp"
end

return Component
