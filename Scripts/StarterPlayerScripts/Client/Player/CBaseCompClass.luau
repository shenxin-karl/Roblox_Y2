-- 基地客户端只展示本人解锁提示与透明预览；不创建楼层，不扣费，不决定传送目标。
local CollectionService = game:GetService("CollectionService")
local FX, FC = _G.FX, _G.FC
local FXLoader = FX.Loader
local Text = FX.Text
local GameUtility = FXLoader:RequireShared("Scripts.Game.Shared.GameUtility")
local Fields = _G.PlayerDataConfig
local Comp = FX.Class("CBaseCompClass", "FCPlayerCompClass")
local TranslationTexts = Text.Define("BaseInteraction", {
    UnlockSlot = "Unlock slot {slot:int}",
    Price = "{value} Coins",
})

--- 复用原生交互与框架数据订阅，支持晚复制到客户端的基地提示。
--- @param owner table 当前客户端玩家对象。
function Comp:Ctor(owner)
    Comp.Super.Ctor(self, owner)
    self._prompts = {}
    self._slots = {}
    self:TrackConnection(CollectionService:GetInstanceAddedSignal("BaseDisplaySlot"):Connect(function(slot)
        self:TrackSlot(slot)
    end))
    self:TrackConnection(CollectionService:GetInstanceRemovedSignal("BaseDisplaySlot"):Connect(function(slot)
        self:RemoveSlot(slot)
    end))
    for index, slot in ipairs(CollectionService:GetTagged("BaseDisplaySlot")) do
        self:TrackSlot(slot)
    end
    --- 接收晚复制的交互节点并立即更新本地显示。
    --- @param prompt ProximityPrompt 带基地解锁标记的新提示。
    self:TrackConnection(CollectionService:GetInstanceAddedSignal("BaseUpgradePrompt"):Connect(function(prompt)
        self._prompts[prompt] = true
        self:RefreshPrompt(prompt)
    end))
    --- 服务端释放基地或流出场景后不再保留提示引用。
    --- @param prompt ProximityPrompt 已移出当前客户端的提示。
    self:TrackConnection(CollectionService:GetInstanceRemovedSignal("BaseUpgradePrompt"):Connect(function(prompt)
        self._prompts[prompt] = nil
    end))
    for index, prompt in ipairs(CollectionService:GetTagged("BaseUpgradePrompt")) do
        self._prompts[prompt] = true
        self:RefreshPrompt(prompt)
    end
    --- 进度同步后隐藏已购买展示台的提示，不使用客户端推测的购买结果。
    self:WatchDataChanged(Fields.BaseData, function()
        self:RefreshPrompts()
        self:RefreshSlots()
    end)
    --- 等待分配与分配成功共用同一套提示显隐规则。
    self:WatchDataChanged(Fields.BaseId, function()
        self:RefreshPrompts()
        self:RefreshSlots()
    end)
    --- 语言改变时只重译文案，不改变购买资格或服务器进度。
    self:TrackConnection(FC.Localization.Changed:Connect(function()
        self:RefreshPrompts()
    end))
end

--- 返回客户端基地交互的稳定协作名。
--- @return string 组件名称。
function Comp:GetCompName()
    return "CBaseComp"
end

--- 仅显示本人所选未解锁展示台的价格，金额统一走公共格式化方法。
--- @param prompt ProximityPrompt 服务端创建并标记的解锁交互。
function Comp:RefreshPrompt(prompt)
    local slotId = prompt:GetAttribute("SlotId")
    local data = self:GetTable(Fields.BaseData)
    local config = _G.GameConfig.BaseSlotData[slotId]
    prompt.Enabled = prompt:GetAttribute("OwnerUserId") == self:GetPlayerId()
        and self:GetNumber(Fields.BaseId) > 0 and config ~= nil
        and not data.UnlockedSlots[tostring(slotId)]
    if prompt.Enabled then
        prompt.AutoLocalize = false
        prompt.ActionText = Text.Tr(TranslationTexts.UnlockSlot, {slot = slotId})
        prompt.ObjectText = Text.Tr(TranslationTexts.Price, {value = GameUtility.NumberToText(config.UnlockPrice)})
    end
end

--- 玩家进度、分配结果或语言变化时刷新已登记提示，不扫描整个场景。
function Comp:RefreshPrompts()
    for prompt in pairs(self._prompts) do
        self:RefreshPrompt(prompt)
    end
end

--- 登记展示台，并覆盖流式加载或晚复制的后代节点。
--- @param slot Model 服务端标记的展示台。
function Comp:TrackSlot(slot)
    if self._slots[slot] then
        return
    end
    self._slots[slot] = slot.DescendantAdded:Connect(function()
        self:RefreshSlot(slot)
    end)
    self:RefreshSlot(slot)
end

--- 只让本人基地的未解锁展示台半透明，其他展示台保持模板原样。
--- @param slot Model 待更新的展示台。
--- @param reset boolean? 移除或销毁时清除本地预览。
function Comp:RefreshSlot(slot, reset)
    local baseId = self:GetNumber(Fields.BaseId)
    local ownSlot = baseId > 0 and slot:GetAttribute("BaseId") == baseId
    local preview = not reset and ownSlot
        and not self:GetTable(Fields.BaseData).UnlockedSlots[tostring(slot:GetAttribute("SlotId"))]
    for index, node in ipairs(slot:GetDescendants()) do
        if node:IsA("BasePart") or node:IsA("Decal") then
            node.LocalTransparencyModifier = preview and 0.65 or 0
        end
    end
end

--- 玩家基地或解锁进度同步后刷新预览，不扫描整个场景。
function Comp:RefreshSlots()
    for slot in pairs(self._slots) do
        self:RefreshSlot(slot)
    end
end

--- 展示台流出或移除时释放监听并恢复本地显示。
--- @param slot Model 不再跟踪的展示台。
function Comp:RemoveSlot(slot)
    local connection = self._slots[slot]
    if connection then
        connection:Disconnect()
        self._slots[slot] = nil
        self:RefreshSlot(slot, true)
    end
end

--- 组件销毁时恢复展示台显示，不影响其他玩家看到的场景。
function Comp:Dtor()
    for slot in pairs(self._slots) do
        self:RemoveSlot(slot)
    end
    Comp.Super.Dtor(self)
end

return Comp
