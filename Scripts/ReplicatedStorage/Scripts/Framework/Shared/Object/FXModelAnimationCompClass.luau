local FX = _G.FX
local TweenService = game:GetService("TweenService")
local Comp = FX.Class("FXModelAnimationCompClass", "FXCompBaseClass")
FX.ModelAnimationCompClass = Comp

--- @param owner table 所属框架对象。
function Comp:Ctor(owner)
    Comp.Super.Ctor(self, owner)
    self._tweenMap = {}
end

--- @return string 模型动画组件名。
function Comp:GetCompName()
    return "FXModelAnimationComp"
end

--- @param node PVInstance Model 或 BasePart。
--- @param target CFrame 世界坐标目标。
--- @param info TweenInfo 原生插值配置。
--- @param restore boolean 停止时是否恢复原位。
function Comp:_Play(node, target, info, restore)
    self:Stop(node)
    local origin = node:GetPivot()
    local value = Instance.new("CFrameValue")
    value.Value = origin
    local connection = value.Changed:Connect(function(cf)
        node:PivotTo(cf)
    end)

    local tween = TweenService:Create(value, info, { Value = target })
    self._tweenMap[node] = { Tween = tween, Value = value, Connection = connection, Origin = restore and origin }
    tween:Play()
end

--- @param node PVInstance 待机模型。
--- @param height number 浮动 studs。
--- @param duration number 单程秒数。
function Comp:PlayFloat(node, height, duration)
    self:Stop(node)
    self:_Play(
        node,
        node:GetPivot() + Vector3.new(0, height, 0),
        TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, -1, true),
        true
    )
end

--- @param node PVInstance 移动模型。
--- @param position Vector3 目标世界坐标。
--- @param euler Vector3 角度制欧拉角。
--- @param duration number 秒数。
function Comp:MoveToTransform(node, position, euler, duration)
    self:_Play(
        node,
        CFrame.new(position) * CFrame.fromOrientation(math.rad(euler.X), math.rad(euler.Y), math.rad(euler.Z)),
        TweenInfo.new(duration),
        false
    )
end

--- @param node PVInstance 需要停止的节点。
function Comp:Stop(node)
    local entry = self._tweenMap[node]
    if not entry then
        return
    end

    self._tweenMap[node] = nil
    entry.Tween:Cancel()
    entry.Connection:Disconnect()
    entry.Tween:Destroy()
    entry.Value:Destroy()
    if entry.Origin then
        node:PivotTo(entry.Origin)
    end
end

--- 释放所有模型插值句柄。
function Comp:StopAll()
    for node in pairs(self._tweenMap) do
        self:Stop(node)
    end
end

--- 析构组件时恢复漂浮原点并解除连接。
function Comp:Dtor()
    self:StopAll()
    Comp.Super.Dtor(self)
end

return Comp
