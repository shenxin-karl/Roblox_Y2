-- 按钮踩压只移动本地外观，原按钮继续提供稳定的碰撞面。
local Animation = {}
local Active = {}

--- 销毁本地外观并恢复原按钮显示。
--- @param node BasePart 原按钮。
function Animation.Stop(node)
    local state = Active[node]
    if not state then
        return
    end
    Active[node] = nil
    state.Visual:Destroy()
    if node.Parent and node.LocalTransparencyModifier == 1 then
        node.LocalTransparencyModifier = state.OriginalTransparency
    end
end

--- 踩住时保持压下，离开时平滑复位；底边不动，避免按钮穿进底座或向上弹。
--- @param node BasePart 原按钮。
--- @param display Model 持有本地外观的运行时容器。
--- @param pressed boolean 角色是否踩住原按钮。
--- @param deltaTime number 距离上一帧的秒数。
--- @return BasePart? 当前按钮外观；复位完成时返回 nil。
function Animation.UpdatePress(node, display, pressed, deltaTime)
    local state = Active[node]
    if not state then
        if not pressed then
            return nil
        end
        local visual = node:Clone()
        visual.Name = "PressedButtonVisual"
        visual.CanCollide, visual.CanTouch, visual.CanQuery = false, false, false
        state = {Visual = visual, OriginalTransparency = node.LocalTransparencyModifier, Progress = 0}
        Active[node] = state
        visual.Parent = display
    end
    local progress = math.clamp(state.Progress + (pressed and deltaTime / 0.09 or -deltaTime / 0.16), 0, 1)
    if progress == 0 and not pressed then
        Animation.Stop(node)
        return nil
    end
    if node.LocalTransparencyModifier ~= 1 then
        node.LocalTransparencyModifier = 1
    end
    if progress ~= state.Progress then
        state.Progress = progress
        local depth = node.Size.Y * 0.75 * progress ^ 2 * (3 - 2 * progress)
        state.Visual.Size = node.Size - Vector3.new(0, depth, 0)
        state.Visual.CFrame = node.CFrame * CFrame.new(0, -depth / 2, 0)
    end
    return state.Visual
end

return Animation
