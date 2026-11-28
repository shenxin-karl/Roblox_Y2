--[[
矿场操作台 HUD。无 Config/State；首次绑定后保持隐藏，入座 Show，离座 Hide。
游戏子类处理 Steer {direction=-1/0/1} 与 Fire {}。左右同时按住时归中，松开恢复剩余方向。
触屏支持另一根手指同时点发射；隐藏或窗口失焦会清空按住状态。
]]
local FX = _G.FX
local FXLoader = FX.Loader
local View = FX.Class("CMiningControlsView", "CUIView")
View.OpenAnimation = false
View.ScreenAdaptation = false
View.ScreenGuiName = "MiningControlsUI"

--- 按钮以原生触点尺寸锚在左右手附近，不随虚拟画布缩小。
function View:OnReady()
    local root = FXLoader:PlayerGui("MiningControlsUI")
    self._held = {}
    self._direction = 0
    self._left = FXLoader:Here(root, "LeftBtn")
    self._right = FXLoader:Here(root, "RightBtn")
    self:BindArrow(self._left, -1)
    self:BindArrow(self._right, 1)
    local fire = FXLoader:Here(root, "FireBtn")
    self:TrackConnection(fire.Activated:Connect(function()
        self:EmitUIAction("Fire", {})
    end))
    if game then
        local inputs = game:GetService("UserInputService")
        self:TrackConnection(inputs.InputEnded:Connect(function(input)
            self:ReleaseArrow(input)
        end))
        self:TrackConnection(inputs.WindowFocusReleased:Connect(function()
            self:ResetArrows()
        end))
    end
end

--- 仅接受左右按钮上的触摸或鼠标主键；忽略移动、滚轮等输入。
--- @param button ImageButton 源 UI 中的方向按钮。
--- @param direction number 左为 -1，右为 1。
function View:BindArrow(button, direction)
    self:TrackConnection(button.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            self._held[input] = direction
            self:UpdateArrows()
        end
    end))
    self:TrackConnection(button.InputEnded:Connect(function(input)
        self:ReleaseArrow(input)
    end))
end

--- 单独释放对应触点，让发射按钮的触点不影响方向。
--- @param input InputObject 松开的触点或鼠标键。
function View:ReleaseArrow(input)
    if self._held[input] then
        self._held[input] = nil
        self:UpdateArrows()
    end
end

--- 在最后一个方向触点结束时同步归中；两边同时按下时保持中立。
function View:UpdateArrows()
    local left, right = false, false
    for heldInput, direction in pairs(self._held) do
        left = left or direction == -1
        right = right or direction == 1
    end
    self._left.BackgroundColor3 = if left then Color3.fromRGB(52, 111, 132) else Color3.fromRGB(99, 128, 121)
    self._right.BackgroundColor3 = if right then Color3.fromRGB(52, 111, 132) else Color3.fromRGB(99, 128, 121)
    local direction = (if right then 1 else 0) - (if left then 1 else 0)
    if direction ~= self._direction then
        self._direction = direction
        self:EmitUIAction("Steer", {direction = direction})
    end
end

--- 隐藏或失焦时清理触点，不延续上一次转向。
function View:ResetArrows()
    if self._held then
        table.clear(self._held)
        self:UpdateArrows()
    end
end

--- 离开操作台时立即结束按住转向。
function View:OnHide()
    self:ResetArrows()
end

return View
