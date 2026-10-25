-- 项目声音扩展入口；曲目和触发条件由新项目提供。
local FX = _G.FX

---@class CSoundCompClass: FCSoundCompClass
local CSoundCompClass = FX.Class("CSoundCompClass", "FCSoundCompClass")

--- 初始化通用声音池，不预设曲目或监听玩法字段。
--- @param owner CPlayerObjectClass 当前客户端玩家对象。
function CSoundCompClass:Ctor(owner)
    CSoundCompClass.Super.Ctor(self, owner, 4)
end

--- 提供项目声音组件的稳定协作名称。
--- @return string 组件协作名称。
function CSoundCompClass:GetCompName()
    return "CSoundComp"
end

return CSoundCompClass
