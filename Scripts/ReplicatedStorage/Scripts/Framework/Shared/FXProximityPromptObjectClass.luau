local FX = _G.FX

--- 场景长按交互对象；圆圈进度和跨设备输入由 Roblox 原生提示负责。
--- @class FXProximityPromptObjectClass
---
--- 适用场景：玩家靠近场景物体后，长按完成一次操作，例如开门、开宝箱、拾取物品、启动机关。
--- 提示依附于场景节点，是否显示由原生交互距离、视线等属性决定。
--- 默认长按 1 秒；按满触发完成，提前松手由引擎取消并重置进度。
--- 固定在屏幕上的菜单按钮或技能按钮，使用 FC.HoldUIObjectClass。
---
--- 接入方式：框架启动后直接使用 FX.ProximityPromptObjectClass，无需单独 require。
--- 推荐由服务端业务对象创建，让所有玩家看到同一个提示，完成回调通过 player 区分交互者。
--- 客户端创建的提示只在本地存在，适合本地表现；发奖、扣费、开门等权威结果由服务端业务决定。
--- 完成事件不证明实际长按时长，业务回调仍需检查交互资格、物体状态和重复操作。
---
--- 示例（parent 是业务已经取得的场景 BasePart 或 Attachment）：
---     self._interaction = FX.ProximityPromptObjectClass.New(parent)
---     self._interaction:SetHoldDuration(2)
---     self._interaction:GetPrompt().ActionText = "打开"
---     self._interaction:GetPrompt().ObjectText = "宝箱"
---     self._interaction:GetPrompt().MaxActivationDistance = 10
---     self._interaction:SetHoldCompleteCallback(onOpenChest) -- onOpenChest(player) 处理业务。
---
--- 暂时禁止交互时调用 SetEnabled(false)，恢复时调用 SetEnabled(true)。
--- 业务对象销毁或场景卸载时调用 self._interaction:Dtor()，再将 self._interaction 设为 nil。
--- Dtor 只清理本类创建的提示和连接，保留场景父节点；调用后不再使用此交互对象。
local FXProximityPromptObjectClass = FX.Class("FXProximityPromptObjectClass")
FX.ProximityPromptObjectClass = FXProximityPromptObjectClass

--- 创建并持有独立提示，供业务对象在自身生命周期内管理。
--- @param parent Instance 场景中的 BasePart、Attachment 或已设置 PrimaryPart 的 Model。
function FXProximityPromptObjectClass:Ctor(parent)
    local prompt = Instance.new("ProximityPrompt")
    prompt.Style = Enum.ProximityPromptStyle.Default
    prompt.HoldDuration = 1
    self._prompt = prompt

    --- 转发引擎的完成事件；服务端业务仍需检查交互资格。
    --- @param player Player 引擎提供的交互玩家。
    self._triggeredConn = prompt.Triggered:Connect(function(player)
        if prompt.Enabled and self._holdCompleteCallback then
            self._holdCompleteCallback(player)
        end
    end)
    prompt.Parent = parent
end

--- 断开完成回调并销毁本对象创建的提示，不销毁场景父节点。
function FXProximityPromptObjectClass:Dtor()
    if self._triggeredConn then
        self._triggeredConn:Disconnect()
        self._triggeredConn = nil
    end
    self._holdCompleteCallback = nil
    if self._prompt then
        self._prompt:Destroy()
        self._prompt = nil
    end
end

--- 直接配置原生文字、交互距离和键位，不重复封装引擎属性。
--- @return ProximityPrompt|nil 当前对象持有的原生提示；析构后为 nil。
function FXProximityPromptObjectClass:GetPrompt()
    return self._prompt
end

--- 设置原生长按时长；正数显示圆圈进度，0 为即时交互。
--- @param duration number 非负秒数。
function FXProximityPromptObjectClass:SetHoldDuration(duration)
    self._prompt.HoldDuration = duration
end

--- 根据业务状态控制提示是否可交互。
--- @param enabled boolean 是否启用提示。
function FXProximityPromptObjectClass:SetEnabled(enabled)
    self._prompt.Enabled = enabled
end

--- 绑定原生完成事件；多人共享提示时通过 player 区分交互者。
--- @param callback function|nil 回调签名为 function(player)，nil 清除回调。
function FXProximityPromptObjectClass:SetHoldCompleteCallback(callback)
    self._holdCompleteCallback = callback
end

return FXProximityPromptObjectClass
