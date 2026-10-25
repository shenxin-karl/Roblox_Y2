local FX = _G.FX

local GUIDE_STATE = {
    Locked = "Locked",
    Running = "Running",
    Finished = "Finished",
}

local EMPTY_GROUP_ID = ""

--- 创建空引导目标，客户端收到该目标时应隐藏引导表现。
---@return table
local function CreateEmptyTarget()
    return {
        type = "None",
    }
end

--- 补齐引导数据的运行时结构，兼容存档默认值为空 table 的项目配置。
---@param guideData table 引导存档数据。
---@return table normalizedGuideData 补齐后的引导数据。
local function NormalizeGuideData(guideData)
    guideData = guideData or {}
    guideData.activeGuideId = guideData.activeGuideId or EMPTY_GROUP_ID
    guideData.guideMap = guideData.guideMap or {}
    guideData.target = guideData.target or CreateEmptyTarget()
    return guideData
end

---@class FSTutorialGuideCompClass: FSPlayerCompClass
--- 服务端新手引导框架组件：按分组 DSL 开始引导，并按当前步骤事件连续推进。
local FSTutorialGuideCompClass = FX.Class("FSTutorialGuideCompClass", "FSPlayerCompClass")

--- 构建服务端新手引导框架组件。
---@param owner table 玩家对象。
---@return nil
function FSTutorialGuideCompClass:Ctor(owner)
    FSTutorialGuideCompClass.Super.Ctor(self, owner)
end

--- 获取新手引导框架配置。
--- 子类返回以分组 ID 为 key 的配置 DSL；每个分组定义怎么开始，以及组内连续步骤怎么推进。
--- 外部业务组件通过 `PublishEvent` 发布事件，框架按 `startEvent` 开始分组，按当前 step 的 `finishEvent` 推进。
--- 格式：
--- {
---     FirstLoginGroup = {
---         startEvent = "PlayerLogin",
---         steps = {
---             {
---                 finishEvent = "BuyEggSuccess",
---                 target = {},
---             },
---             {
---                 finishEvent = "EquipEggSuccess",
---                 target = {},
---             },
---         },
---     },
--- }
---@return table
function FSTutorialGuideCompClass:GetGuideConfig()
    FX.ErrorWithTraceback("FSTutorialGuideCompClass:GetGuideConfig not implemented")
end

--- 获取新手引导数据存储变量。
--- 子类返回 PlayerDataConfig 中定义的新手引导数据变量，例如 `PlayerDataConfig.eTutorialGuideData`。
--- 存档结构使用 `activeGuideId` 记录当前运行分组，`guideMap[groupId]` 记录该分组状态与步骤下标。
--- 对应 DefVal 推荐结构：
--- {
---     activeGuideId = "", -- 当前正在运行的分组 ID；空字符串表示没有引导运行。
---     guideMap = {
---         [groupId] = {
---             state = "Locked", -- 分组状态：Locked / Running / Finished。
---             stepIndex = 0, -- 当前运行到 steps 的下标；0 表示未开始或已结束。
---         },
---     },
---     target = {
---         type = "None", -- 当前步骤同步给客户端的目标 DSL；None 表示隐藏引导表现。
---     },
--- }
---@return table
function FSTutorialGuideCompClass:GetGuideStorage()
    FX.ErrorWithTraceback("FSTutorialGuideCompClass:GetGuideStorage not implemented")
end

--- 接收同一玩家对象上其他组件通过 PublishEvent 发出的事件。
---@param eventName string 事件名。
---@param ... any 事件参数由业务事件提供，底层当前只根据事件名驱动开始和推进。
---@return nil
function FSTutorialGuideCompClass:_OnEvent(eventName, ...)
    FSTutorialGuideCompClass.Super._OnEvent(self, eventName, ...)
    self:OnGuideEvent(eventName)
end

--- 处理引导事件；当前分组优先尝试推进，否则尝试按 startEvent 开始新分组。
---@param eventName string 事件名。
---@return nil
function FSTutorialGuideCompClass:OnGuideEvent(eventName)
    if self:TryFinishCurrentStep(eventName) then
        return
    end

    self:TryStartGroup(eventName)
end

--- 当前没有运行分组时，按 startEvent 开始匹配分组。
---@param eventName string 事件名。
---@return boolean
function FSTutorialGuideCompClass:TryStartGroup(eventName)
    local guideData = self:GetGuideData()
    if guideData.activeGuideId ~= EMPTY_GROUP_ID then
        return false
    end

    local groupId, groupConfig = self:GetGroupConfigByStartEvent(eventName)
    if groupConfig == nil then
        return false
    end

    local groupStateData = self:GetGroupStateData(guideData, groupId)
    if groupStateData.state == GUIDE_STATE.Finished then
        return false
    end

    self:EnterGroupStep(guideData, groupId, groupConfig, 1)
    return true
end

--- 当前运行分组的当前步骤命中 finishEvent 时，推进到下一步或结束分组。
---@param eventName string 事件名。
---@return boolean
function FSTutorialGuideCompClass:TryFinishCurrentStep(eventName)
    local guideData = self:GetGuideData()
    local groupId = guideData.activeGuideId
    if groupId == EMPTY_GROUP_ID then
        return false
    end

    local groupConfig = self:GetGuideConfig()[groupId]
    local groupStateData = self:GetGroupStateData(guideData, groupId)
    local stepConfig = groupConfig.steps[groupStateData.stepIndex]
    if stepConfig.finishEvent ~= eventName then
        return false
    end

    local nextStepIndex = groupStateData.stepIndex + 1
    if groupConfig.steps[nextStepIndex] == nil then
        self:FinishGroup(guideData, groupId)
        return true
    end

    self:EnterGroupStep(guideData, groupId, groupConfig, nextStepIndex)
    return true
end

--- 进入分组内指定步骤，并同步该步骤目标。
---@param guideData table 完整引导数据。
---@param groupId string 引导分组 ID。
---@param groupConfig table 分组配置。
---@param stepIndex number 步骤下标，从 1 开始。
---@return nil
function FSTutorialGuideCompClass:EnterGroupStep(guideData, groupId, groupConfig, stepIndex)
    local groupStateData = self:GetGroupStateData(guideData, groupId)

    guideData.activeGuideId = groupId
    guideData.target = groupConfig.steps[stepIndex].target or CreateEmptyTarget()
    groupStateData.state = GUIDE_STATE.Running
    groupStateData.stepIndex = stepIndex

    self:SetGuideData(guideData)
end

--- 结束当前分组并同步空目标。
---@param guideData table 完整引导数据。
---@param groupId string 引导分组 ID。
---@return nil
function FSTutorialGuideCompClass:FinishGroup(guideData, groupId)
    local groupStateData = self:GetGroupStateData(guideData, groupId)

    guideData.activeGuideId = EMPTY_GROUP_ID
    guideData.target = CreateEmptyTarget()
    groupStateData.state = GUIDE_STATE.Finished
    groupStateData.stepIndex = 0

    self:SetGuideData(guideData)
end

--- 通过开始事件查找分组配置。
---@param eventName string 事件名。
---@return string
---@return table
function FSTutorialGuideCompClass:GetGroupConfigByStartEvent(eventName)
    for groupId, groupConfig in pairs(self:GetGuideConfig()) do
        if groupConfig.startEvent == eventName then
            return groupId, groupConfig
        end
    end

    return nil, nil
end

--- 读取完整引导数据。
---@return table
function FSTutorialGuideCompClass:GetGuideData()
    return NormalizeGuideData(self:GetTable(self:GetGuideStorage()))
end

--- 写入完整引导数据。
---@param guideData table 完整引导数据。
---@return boolean
function FSTutorialGuideCompClass:SetGuideData(guideData)
    return self:SetTable(self:GetGuideStorage(), guideData)
end

--- 读取或创建单个分组的存档状态。
---@param guideData table 完整引导数据。
---@param groupId string 引导分组 ID。
---@return table
function FSTutorialGuideCompClass:GetGroupStateData(guideData, groupId)
    local groupStateData = guideData.guideMap[groupId]
    if groupStateData ~= nil then
        return groupStateData
    end

    groupStateData = {
        state = GUIDE_STATE.Locked,
        stepIndex = 0,
    }
    guideData.guideMap[groupId] = groupStateData
    return groupStateData
end

FSTutorialGuideCompClass.GUIDE_STATE = GUIDE_STATE

return FSTutorialGuideCompClass
