local UserInputService = game:GetService("UserInputService")
local FX = _G.FX
local Drag = {}
Drag.__index = Drag

--- 统一处理各格子的点击和拖拽，拖动后不再触发点击。
--- @param playerGui PlayerGui 用于拾取指针下的格子。
--- @param ghost ImageLabel 拖拽预览。
--- @param ghostName TextLabel 无图标时使用的预览名称。
--- @param getSlot function 根据真实格号取得当前展示快照。
--- @param onClick function 处理点击的真实格号与快照。
--- @param onSwap function 处理拖拽的两个真实格号与源快照。
--- @return table 输入控制器。
function Drag.new(playerGui, ghost, ghostName, getSlot, onClick, onSwap)
    local self = setmetatable({
        _playerGui = playerGui,
        _ghost = ghost,
        _ghostName = ghostName,
        _getSlot = getSlot,
        _onClick = onClick,
        _onSwap = onSwap,
        _gridsByButton = {},
        _connections = {},
    }, Drag)
    table.insert(self._connections, UserInputService.InputChanged:Connect(function(input)
        self:_OnInputChanged(input)
    end))
    table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
        self:_OnInputEnded(input)
    end))
    table.insert(self._connections, UserInputService.WindowFocusReleased:Connect(function()
        self:Cancel()
    end))
    return self
end

--- 回收的格子每次按下或命中时读取其当前绑定。
--- @param button GuiButton 可复用格子。
--- @param getGrid function 返回当前绑定的真实格号或 nil。
--- @param scroll ScrollingFrame? 触屏时允许轻扫列表、长按拖动道具。
function Drag:RegisterSlot(button, getGrid, scroll)
    self._gridsByButton[button] = getGrid
    table.insert(self._connections, button.InputBegan:Connect(function(input)
        local inputType = input.UserInputType
        if self._press or (inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch) then
            return
        end
        local grid = getGrid()
        local slot = grid and self._getSlot(grid)
        if slot then
            local press = {
                input = input,
                start = Vector2.new(input.Position.X, input.Position.Y),
                grid = grid,
                slot = slot,
                size = button.AbsoluteSize,
            }
            self._press = press
            if scroll and inputType == Enum.UserInputType.Touch and scroll.ScrollingEnabled then
                press.waitingForHold = true
                task.delay(0.3, function()
                    if self._press == press and getGrid() == grid then
                        press.waitingForHold = false
                        press.scroll = scroll
                        scroll.ScrollingEnabled = false
                        self:_StartDrag(press, press.start)
                    end
                end)
            end
        end
    end))
end

--- 命中回收按钮时取得当前真实格号，遮挡用按钮不会穿透。
--- @param position Vector3 屏幕输入坐标。
--- @return number? 命中的真实格号。
function Drag:_GetGridAt(position)
    for _, gui in ipairs(self._playerGui:GetGuiObjectsAtPosition(position.X, position.Y)) do
        local getGrid = self._gridsByButton[gui]
        if getGrid then
            return getGrid()
        end
        if gui:IsA("GuiButton") then
            return nil
        end
    end
    return nil
end

--- 用按下时的展示快照绘制拖拽预览。
--- @param press table 当前按下状态。
--- @param point Vector2 屏幕坐标。
function Drag:_StartDrag(press, point)
    press.dragging = true
    self._ghost.Image = press.slot.icon
    self._ghostName.Text = press.slot.icon == "" and FX.Text.TrSource(press.slot.name) or ""
    self._ghost.Size = UDim2.fromOffset(press.size.X, press.size.Y)
    local localPoint = point - self._ghost.Parent.AbsolutePosition
    self._ghost.Position = UDim2.fromOffset(localPoint.X, localPoint.Y)
    self._ghost.Visible = true
end

--- 长按前的触屏滑动交给滚动容器处理。
--- @param input InputObject 移动中的输入。
function Drag:_OnInputChanged(input)
    local press = self._press
    if not press then
        return
    end
    local mouse = press.input.UserInputType == Enum.UserInputType.MouseButton1
    if input ~= press.input and not (mouse and input.UserInputType == Enum.UserInputType.MouseMovement) then
        return
    end
    local point = Vector2.new(input.Position.X, input.Position.Y)
    if not press.dragging and (point - press.start).Magnitude >= 7 then
        if press.waitingForHold then
            self:Cancel()
            return
        end
        self:_StartDrag(press, point)
    end
    if press.dragging then
        local localPoint = point - self._ghost.Parent.AbsolutePosition
        self._ghost.Position = UDim2.fromOffset(localPoint.X, localPoint.Y)
    end
end

--- 将释放位置换算成当前真实落点。
--- @param input InputObject 收尾的输入。
function Drag:_OnInputEnded(input)
    local press = self._press
    if not press or input ~= press.input then
        return
    end
    self:Cancel()
    if input.UserInputState == Enum.UserInputState.Cancel then
        return
    end
    local target = self:_GetGridAt(input.Position)
    if press.dragging then
        if target and target ~= press.grid then
            self._onSwap(press.grid, target, press.slot)
        end
    elseif target == press.grid then
        self._onClick(press.grid, press.slot)
    end
end

--- 待处理的长按通过 press 身份失效，已开始的拖动恢复触屏滚动。
function Drag:Cancel()
    if self._press and self._press.scroll then
        self._press.scroll.ScrollingEnabled = true
    end
    self._press = nil
    self._ghost.Visible = false
end

function Drag:Destroy()
    self:Cancel()
    for _, connection in ipairs(self._connections) do
        connection:Disconnect()
    end
end

return Drag
