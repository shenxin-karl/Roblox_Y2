-- 项目通用文字特效：持续流动的彩色渐变与周期性白光扫过。
local RunService = game:GetService("RunService")
local AnimatedText = {}
AnimatedText.__index = AnimatedText

--- 以独立渐变控制文字颜色，调用方负责在移除文字前释放效果。
--- @param label TextLabel 由调用方管理内容、布局和显隐的文字节点。
--- @return table 可通过 Destroy 释放的文字特效。
function AnimatedText.Attach(label)
    local self = setmetatable({}, AnimatedText)
    self._label = label
    self._originalColor = label.TextColor3
    label.TextColor3 = Color3.new(1, 1, 1)
    self._gradient = Instance.new("UIGradient")
    self._gradient.Name = "AnimatedTextGradient"
    self._gradient.Parent = label
    self:Update(0)
    local elapsed = 0
    local pending = 0
    --- 限制渐变重建频率，隐藏时跳过计算，恢复显示后沿用连续动画时间。
    --- @param deltaTime number 本帧经过的秒数。
    self._connection = RunService.RenderStepped:Connect(function(deltaTime)
        elapsed += deltaTime
        pending += deltaTime
        local gui = label:FindFirstAncestorWhichIsA("LayerCollector")
        if pending < 1 / 30 or not label.Visible or (gui and not gui.Enabled) then
            return
        end
        pending = 0
        self:Update(elapsed)
    end)
    return self
end

--- 在彩色渐变中插入移动的纯白峰值；扫光离开后留出停顿再重播。
--- @param elapsed number 特效已持续的秒数。
function AnimatedText:Update(elapsed)
    local center = (elapsed % 2.8) / 1.4 * 1.3 - 0.15
    local times = {0, 0.25, 0.5, 0.75, 1}
    for index, offset in ipairs({-0.09, 0, 0.09}) do
        local position = center + offset
        if position > 0 and position < 1 then
            table.insert(times, position)
        end
    end
    table.sort(times)
    local keypoints = {}
    local previous = -1
    for index, position in ipairs(times) do
        if position > previous then
            local color = Color3.fromHSV((elapsed / 8 + position * 0.35) % 1, 0.65, 1)
            local shine = math.max(0, 1 - math.abs(position - center) / 0.09)
            table.insert(keypoints, ColorSequenceKeypoint.new(position, color:Lerp(Color3.new(1, 1, 1), shine)))
            previous = position
        end
    end
    self._gradient.Color = ColorSequence.new(keypoints)
end

--- 断开动画并恢复原始文字颜色，不销毁调用方持有的文字节点。
function AnimatedText:Destroy()
    self._connection:Disconnect()
    self._gradient:Destroy()
    self._label.TextColor3 = self._originalColor
end

return AnimatedText
