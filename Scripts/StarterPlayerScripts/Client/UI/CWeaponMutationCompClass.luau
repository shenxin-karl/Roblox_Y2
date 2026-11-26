-- 变异界面业务：从背包 Tool 读取材料，预估效果，等待服务端确认成品。
local ProximityPromptService = game:GetService("ProximityPromptService")
local FX, FC = _G.FX, _G.FC
local FXLoader = FX.Loader
local Rules = FXLoader:RequireShared("Scripts.Game.Shared.SwordRules")
local Utility = FXLoader:RequireShared("Scripts.Game.Shared.GameUtility")
FXLoader:RequireFromParent(script, "Generated.CWeaponMutationView")
local Comp = FX.Class("CWeaponMutationCompClass", "CWeaponMutationView")
local Items = _G.ItemConfig
local TranslationTexts = FX.Text.Define("WeaponMutationGame", {
    Failed = "Could not mutate the weapon. Check the materials and try again.",
    SameMutation = "This weapon already has that mutation. No stone was used.",
})

--- 初始化可独立刷新的界面状态。
--- @param owner table 本地玩家对象。
function Comp:Ctor(owner)
    Comp.Super.Ctor(self, owner)
    self.Config, self.State = {}, {weapons = {}, stones = {}}
    self._inventorySlots = {}
    self._windowSession = 0
end

--- 由导出的 View 绑定节点，进入游戏时先隐藏。
function Comp:OnReady()
    Comp.Super.OnReady(self)
    self:BindUIData()
    self:TrackConnection(FC.Localization.Changed:Connect(function()
        if self:GetRootNode().Enabled then
            self:RefreshUI()
        end
    end))
    self:Hide()
    self:TrackConnection(ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
        if player.UserId == self:GetPlayerId() and prompt:GetAttribute("OpensWeaponMutation") == true then
            self:Open()
        end
    end))
end

--- 保留最新同步快照，界面打开时才刷新显示。
--- @param slots table 以真实格号为键的本人背包快照。
function Comp:OnInventoryChanged(slots)
    self._inventorySlots = slots
    if self._opened and not self.State.pending then
        self:RefreshMaterials()
    end
end

--- 只用背包已同步的武器属性和变异石配置预估效果，不发请求或消耗材料。
function Comp:RefreshPreview()
    local state = self.State
    local weapon, stone = state.weapon, state.stone
    state.preview = nil
    if not weapon or not stone or state.result then
        return
    end

    local mutationId = weapon.tool:GetAttribute("MutationId")
    local quality = weapon.tool:GetAttribute("Quality")
    local level = weapon.tool:GetAttribute("WeaponLevel")
    local current = Rules.GetMutation(mutationId)
    local target = Rules.GetStoneMutation(stone.tool:GetAttribute("FrameworkItemId"))
    if not current or not target or type(quality) ~= "number" or not _G.GameConfig.WeaponData[quality]
        or type(level) ~= "number" or not (level >= 1 and level < math.huge and level % 1 == 0) then
        return
    end

    local traits = {Quality = quality, Level = level, MutationId = mutationId}
    local beforeIncome = Rules.GetIncome(traits)
    traits.MutationId = target.MutationId
    local afterIncome = Rules.GetIncome(traits)
    if not (beforeIncome < math.huge and afterIncome < math.huge) then
        return
    end
    state.preview = {
        beforeMutationName = current.MutationName,
        afterMutationName = target.MutationName,
        beforeIncomePerSecond = Utility.NumberToText(beforeIncome),
        afterIncomePerSecond = Utility.NumberToText(afterIncome),
        sameMutation = mutationId == target.MutationId,
        incomeDecreases = afterIncome < beforeIncome,
    }
end

--- 按格号整理材料和武器变异角标；仅在同一 Tool 仍占用该格时保留选中。
function Comp:RefreshMaterials()
    local state = self.State
    local weapons, stones = {}, {}
    local weapon, stone
    for grid, slot in pairs(self._inventorySlots) do
        local itemId = slot.tool:GetAttribute("FrameworkItemId")
        local mutation = Rules.GetStoneMutation(itemId)
        if itemId == Rules.ItemId or mutation then
            local item = {id = tostring(grid), grid = grid, tool = slot.tool,
                name = slot.name, icon = slot.icon, count = slot.count}
            if mutation then
                item.details = Items.Display[itemId].Desc
                table.insert(stones, item)
                if state.stone and state.stone.tool == item.tool and state.stone.grid == grid then
                    stone = item
                end
            else
                local mutationId = slot.tool:GetAttribute("MutationId")
                if mutationId and mutationId ~= "Normal" then
                    local weaponMutation = Rules.GetMutation(mutationId)
                    item.badgeIcon = weaponMutation and weaponMutation.IconId
                end
                table.insert(weapons, item)
                if state.weapon and state.weapon.tool == item.tool and state.weapon.grid == grid then
                    weapon = item
                end
            end
        end
    end
    local function byGrid(first, second)
        return first.grid < second.grid
    end
    table.sort(weapons, byGrid)
    table.sort(stones, byGrid)
    state.weapons, state.stones = weapons, stones
    state.weapon, state.stone = weapon, stone
    self:RefreshPreview()
    self:RefreshUI()
end

--- 从商人或背包打开；点击右侧槽位后显示可选材料。
function Comp:Open()
    self._opened = true
    self:RefreshMaterials()
    self:Show()
end

--- 关闭时清理本次展示；保留请求锁，直到服务端回执到达。
function Comp:OnHide()
    self._opened = false
    self._windowSession += 1
    self.State.weapon, self.State.stone, self.State.result, self.State.error = nil, nil, nil, nil
    self.State.preview = nil
end

--- 选材只改变界面；实际扣石和变异由服务端一次提交。
--- @param action string 生成 View 转发的动作名。
--- @param payload table 当前操作的物品标识。
function Comp:OnUIAction(action, payload)
    local state = self.State
    if action == "ChooseItem" then
        local kind = payload.kind
        local list = if kind == "weapon" then state.weapons else state.stones
        for index, item in ipairs(list) do
            if item.id == payload.itemId then
                state[kind] = if payload.clear then nil else item
                state.error = nil
                self:RefreshPreview()
                self:RefreshUI()
                return
            end
        end
    elseif action == "Done" then
        state.weapon, state.stone, state.result, state.error = nil, nil, nil, nil
        self:RefreshMaterials()
    elseif action == "Mutate" then
        local weapon, stone = state.weapon, state.stone
        if state.pending or not weapon or not stone or weapon.id ~= payload.weaponId or stone.id ~= payload.stoneId then
            return
        end
        local windowSession = self._windowSession
        state.pending, state.error = true, nil
        self:RefreshUI()
        local ok, result, reason = pcall(FX.Network.InvokeServer, FX.Network, "C2S_MutateWeapon",
            weapon.grid, stone.grid, weapon.tool, stone.tool)
        if not self.State then
            return
        end
        state.pending = false
        if windowSession ~= self._windowSession then
            if self._opened then
                self:RefreshMaterials()
            end
            return
        end
        if ok and result then
            local display = _G.GameConfig.WeaponData[result.quality]
            local beforeMutationIcon, afterMutation
            for grade, mutation in pairs(_G.GameConfig.MiningRockData) do
                if mutation.MutationName == result.beforeMutationName then
                    beforeMutationIcon = mutation.IconId
                end
                if mutation.MutationName == result.afterMutationName then
                    afterMutation = mutation
                end
            end
            state.result = {
                weapon = {id = weapon.id, name = display.Name, icon = display.IconId},
                beforeMutationName = result.beforeMutationName,
                afterMutationName = result.afterMutationName,
                beforeMutationIcon = beforeMutationIcon,
                afterMutationIcon = afterMutation and afterMutation.IconId,
                afterMutationId = afterMutation and afterMutation.MutationId,
                beforeIncomePerSecond = Utility.NumberToText(result.beforeIncome),
                afterIncomePerSecond = Utility.NumberToText(result.afterIncome),
            }
            state.weapon, state.stone = nil, nil
        else
            local message = if reason == "SameMutation" then TranslationTexts.SameMutation else TranslationTexts.Failed
            state.error = message.Source
        end
        self:RefreshMaterials()
    end
end

--- 使可能晚到的请求回执失效。
function Comp:Dtor()
    self.State = nil
    Comp.Super.Dtor(self)
end

return Comp
