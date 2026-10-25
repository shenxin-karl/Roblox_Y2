local FX = _G.FX
local RunService = game:GetService("RunService")

local EMPTY_TARGET_TYPE = "None"

--- 创建空引导目标，客户端收到该目标时应隐藏引导表现。
---@return table
local function CreateEmptyTarget()
    return {
        type = EMPTY_TARGET_TYPE,
    }
end

--- 补齐客户端引导数据结构，兼容存档默认值为空 table 的项目配置。
---@param guideData table 服务端同步的新手引导数据。
---@return table normalizedGuideData 补齐后的引导数据。
local function NormalizeGuideData(guideData)
    guideData = guideData or {}
    guideData.target = guideData.target or CreateEmptyTarget()
    return guideData
end

--- 判断服务端目标是否为空目标，空目标只用于通知客户端清理表现。
---@param guideTarget table 服务端同步的当前引导目标。
---@return boolean
local function IsEmptyGuideTarget(guideTarget)
    return guideTarget == nil or guideTarget.type == EMPTY_TARGET_TYPE
end

---@class FCTutorialGuideCompClass: FCPlayerCompClass
--- 客户端新手引导框架组件：监听服务端引导存储变化，只触发进入/退出回调并提供通用箭头能力。
--- 子类必须重写 `GetGuideConfig`、`GetGuideStorage`、`OnEnterGuide`、`OnExitGuide`。
local FCTutorialGuideCompClass = FX.Class("FCTutorialGuideCompClass", "FCPlayerCompClass")

--- 构建客户端新手引导框架组件。
---@param owner table 玩家对象。
---@return nil
function FCTutorialGuideCompClass:Ctor(owner)
    FCTutorialGuideCompClass.Super.Ctor(self, owner)
    self._guideDataChangedConn = nil
    self._guideTarget = nil
    self._worldTargetPosition = nil
    self._arrowTrans = nil
    self._arrowEffect = nil
    self._renderSteppedConn = nil
end

--- 销毁组件时清理箭头节点和逐帧回调。
---@return nil
function FCTutorialGuideCompClass:Dtor()
    self:UnwatchGuideStorage()
    self:HideGuideArrow()
    FCTutorialGuideCompClass.Super.Dtor(self)
end

--- 客户端准备完成后监听服务端同步的新手引导数据。
---@return nil
function FCTutorialGuideCompClass:OnReady()
    self:WatchGuideStorage()
end

--- 获取新手引导框架配置。
--- 子类返回的配置必须和服务端 `GetGuideConfig()` 使用同一套分组与步骤 DSL，便于客户端按 guideTarget 做表现映射。
---@return table
function FCTutorialGuideCompClass:GetGuideConfig()
    FX.ErrorWithTraceback("FCTutorialGuideCompClass:GetGuideConfig not implemented")
end

--- 获取新手引导数据存储变量。
--- 子类返回 PlayerDataConfig 中定义的新手引导数据变量，必须和服务端 `GetGuideStorage()` 返回同一个变量。
---@return table
function FCTutorialGuideCompClass:GetGuideStorage()
    FX.ErrorWithTraceback("FCTutorialGuideCompClass:GetGuideStorage not implemented")
end

--- 监听服务端同步的新手引导数据。
---@return nil
function FCTutorialGuideCompClass:WatchGuideStorage()
    if self._guideDataChangedConn ~= nil then
        return
    end

    self._guideDataChangedConn = self:WatchDataChanged(self:GetGuideStorage(), function(guideData)
        self:OnGuideDataChanged(guideData)
    end)
end

--- 取消监听服务端同步的新手引导数据。
---@return nil
function FCTutorialGuideCompClass:UnwatchGuideStorage()
    if self._guideDataChangedConn == nil then
        return
    end

    self._guideDataChangedConn:Disconnect()
    self._guideDataChangedConn = nil
end

--- 服务端引导数据变化时触发进入或退出指引回调。
---@param guideData table 服务端同步的新手引导数据。
---@return nil
function FCTutorialGuideCompClass:OnGuideDataChanged(guideData)
    guideData = NormalizeGuideData(guideData)
    local previousGuideTarget = self._guideTarget
    local nextGuideTarget = guideData.target
    if previousGuideTarget == nextGuideTarget then
        return
    end

    if not IsEmptyGuideTarget(previousGuideTarget) then
        self:OnExitGuide(previousGuideTarget)
    end

    self._guideTarget = nextGuideTarget

    if not IsEmptyGuideTarget(nextGuideTarget) then
        self:OnEnterGuide(nextGuideTarget)
    end
end

--- 进入某个引导目标时的回调入口。
--- 子类覆盖该函数，根据 `guideTarget` 决定显示箭头、UI 高亮、文案或其他表现。
---@param guideTarget table 服务端同步的当前引导目标。
---@return nil
function FCTutorialGuideCompClass:OnEnterGuide(guideTarget)
    FX.ErrorWithTraceback("FCTutorialGuideCompClass:OnEnterGuide not implemented")
end

--- 离开某个引导目标时的回调入口。
--- 子类必须覆盖该函数，清理自己在 `OnEnterGuide` 中创建的表现；需要清理通用箭头时调用 `HideGuideArrow()`。
---@param guideTarget table 服务端同步的当前引导目标。
---@return nil
function FCTutorialGuideCompClass:OnExitGuide(guideTarget)
    FX.ErrorWithTraceback("FCTutorialGuideCompClass:OnExitGuide not implemented")
end

--- 显示一个跟随玩家并指向指定世界坐标的引导箭头。
---@param worldPosition Vector3 箭头指向的世界坐标。
---@return nil
function FCTutorialGuideCompClass:ShowGuideArrowToPosition(worldPosition)
    self._worldTargetPosition = worldPosition
    if self._arrowTrans ~= nil then
        self:UpdateGuideArrow()
        return
    end

    local arrowTrans = Instance.new("Part")
    arrowTrans.Name = "TutorialGuideArrow"
    arrowTrans.Size = Vector3.new(0.3, 0.3, 3)
    arrowTrans.Anchored = true
    arrowTrans.CanCollide, arrowTrans.CanTouch, arrowTrans.CanQuery = false, false, false
    arrowTrans.Material = Enum.Material.Neon
    arrowTrans.Color = Color3.fromRGB(255, 215, 60)
    arrowTrans.Parent = workspace
    local arrowEffect = Instance.new("WedgePart")
    arrowEffect.Size = Vector3.new(1.4, 0.3, 1.5)
    arrowEffect.Anchored = true
    arrowEffect.CanCollide, arrowEffect.CanTouch, arrowEffect.CanQuery = false, false, false
    arrowEffect.Color = arrowTrans.Color
    arrowEffect.Material = arrowTrans.Material
    arrowEffect.Parent = arrowTrans
    self._arrowTrans = arrowTrans
    self._arrowEffect = arrowEffect
    self._renderSteppedConn = RunService.RenderStepped:Connect(function()
        self:UpdateGuideArrow()
    end)
    self:UpdateGuideArrow()
end

--- 隐藏引导箭头并释放逐帧回调。
---@return nil
function FCTutorialGuideCompClass:HideGuideArrow()
    self._worldTargetPosition = nil

    if self._renderSteppedConn ~= nil then
        self._renderSteppedConn:Disconnect()
        self._renderSteppedConn = nil
    end

    if self._arrowTrans ~= nil then
        self._arrowTrans:Destroy()
        self._arrowTrans = nil
    end

    self._arrowEffect = nil
end

--- 每帧把箭头放到玩家身边，并朝向当前世界目标。
---@return nil
function FCTutorialGuideCompClass:UpdateGuideArrow()
    if self._arrowTrans == nil or self._worldTargetPosition == nil then
        return
    end

    local character = self:GetPlayerCharacter()
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
        return
    end
    local origin = root.Position + Vector3.new(0, 4, 0)
    if (origin - self._worldTargetPosition).Magnitude < 0.01 then
        return
    end
    self._arrowTrans.CFrame = CFrame.lookAt(origin, self._worldTargetPosition)
    self._arrowEffect.CFrame = self._arrowTrans.CFrame * CFrame.new(0, 0, -2)
end

--- 获取默认引导箭头特效索引；子类可覆盖以替换箭头样式。
---@return number
function FCTutorialGuideCompClass:GetGuideArrowEffectIndex()
    return 32
end

return FCTutorialGuideCompClass
