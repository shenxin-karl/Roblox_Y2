local FX = _G.FX
local CProgressBarUIPreviewCompClass = FX.Class("CProgressBarUIPreviewCompClass", "CProgressBarUIBaseCompClass")

-- 初始化本次运行的模拟数据。
-- @param owner table 编辑器提供的组件宿主，传递给父类
function CProgressBarUIPreviewCompClass:Ctor(owner)
    CProgressBarUIPreviewCompClass.Super.Ctor(self, owner)
    self.Config = {}
    self.State = {}
end

-- 提供展示配置，业务标识与文案分开保存。
-- @return table 界面配置
function CProgressBarUIPreviewCompClass:GetUIConfig()
    return self.Config
end

-- 提供模拟状态，不能作为真实发奖依据。
-- @return table 当前显示状态
function CProgressBarUIPreviewCompClass:GetUIState()
    return self.State
end

-- 数据就绪后触发首帧展示。
function CProgressBarUIPreviewCompClass:BindUIData()
    self:RefreshUI()
end

-- 处理展示层动作；只更新模拟数据，再调用 RefreshUI。
-- @param action string 动作名称
-- @param payload table 动作必要参数，例如稳定奖励 ID
function CProgressBarUIPreviewCompClass:OnUIAction(action, payload)
end

return CProgressBarUIPreviewCompClass