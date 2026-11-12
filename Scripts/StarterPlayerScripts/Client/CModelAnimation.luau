-- 模型踩压动画：仅供客户端表现，压下后弹起，结束或取消后恢复原始形状。
local RunService = game:GetService("RunService")
local Animation = {}
local Active = {}

--- 停止当前踩压并恢复，重复触发不会累积缩放误差。
--- @param node Model|BasePart 正在播放动画的节点。
function Animation.Stop(node)
    local state = Active[node]
    if not state then
        return
    end
    Active[node] = nil
    state.Connection:Disconnect()
    for part, original in pairs(state.Parts) do
        if part.Parent then
            part.Size = original.Size
            part.CFrame = original.CFrame
        end
    end
end

--- 快速压下后衰减回弹；用于静止、锚定的装饰模型或按钮，不用于角色和活动关节。
--- @param node Model|BasePart 要踩压的模型或零件。
function Animation.PlayPress(node)
    Animation.Stop(node)
    local pivot, bounds
    if node:IsA("Model") then
        pivot, bounds = node:GetBoundingBox()
    else
        pivot, bounds = node.CFrame, node.Size
    end
    local parts = node:IsA("Model") and node:GetDescendants() or {node}
    local state = {Parts = {}}
    for index, part in ipairs(parts) do
        if part:IsA("BasePart") then
            state.Parts[part] = {
                Size = part.Size,
                CFrame = part.CFrame,
                Offset = pivot:ToObjectSpace(part.CFrame),
            }
        end
    end
    Active[node] = state
    local elapsed = 0
    state.Connection = RunService.Heartbeat:Connect(function(deltaTime)
        elapsed += deltaTime
        if not node.Parent or elapsed >= 0.7 then
            Animation.Stop(node)
            return
        end
        local height, lift
        if elapsed < 0.12 then
            local press = 1 - (1 - elapsed / 0.12) ^ 2
            height = 1 - 0.65 * press
            lift = -0.06 * press
        else
            local release = (elapsed - 0.12) / 0.58
            height = 1 - 0.65 * math.exp(-3.5 * release) * math.cos(3 * math.pi * release)
            -- 薄按钮仅缩放厚度难以辨认，增加短促弹起突出踩压反馈。
            lift = 1.1 * math.sin(math.pi * release) * math.exp(-3 * release)
                - 0.06 * (1 - release) ^ 2
        end
        local scale = Vector3.new(1 + (1 - height) * 0.34, height, 1 + (1 - height) * 0.34)
        for part, original in pairs(state.Parts) do
            if part.Parent then
                local offset = original.Offset
                -- 按包围盒坐标压缩位置；旋转零件按各轴投影缩放尺寸。
                local axisX = (offset.RightVector * scale).Magnitude
                local axisY = (offset.UpVector * scale).Magnitude
                local axisZ = (offset.LookVector * scale).Magnitude
                part.Size = original.Size * Vector3.new(axisX, axisY, axisZ)
                local position = offset.Position * scale + Vector3.new(0, bounds.Y * (height - 1) / 2 + lift, 0)
                part.CFrame = pivot * (CFrame.new(position) * offset.Rotation)
            end
        end
    end)
end

return Animation
