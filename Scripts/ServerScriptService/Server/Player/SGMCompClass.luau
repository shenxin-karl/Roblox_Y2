-- 项目开发者操作；所有命令仅处理当前开发者本人的会话和存档。
local FX, FS = _G.FX, _G.FS
local Text = FX.Text
local TranslationTexts = Text.Define("GM", {
    Forbidden = "Only developers can use these controls.",
    Unknown = "Something went wrong. Please try again.",
    Busy = "An operation is in progress. Please try again shortly.",
    SaveFailed = "Save failed. Please try again.",
    Success = "Operation completed.",
    InvalidGrant = "Check the item ID and quantity.",
    GrantFailed = "Could not grant the item. Check your backpack space.",
    NoNearbySword = "Stand near one of your placed swords to top up its upgrade cost.",
    NoActiveForge = "Start forging a sword before testing breakage.",
})
local Fields = _G.PlayerDataConfig
local SwordRules = FX.Loader:RequireShared("Scripts.Game.Shared.SwordRules")
local GameConfig = _G.GameConfig
local SwitchAttributes = {
    SetFreeUpgrades = "GMFreeUpgrades",
    SetGuaranteedForge = "GMGuaranteedForge",
}
local Component = FX.Class("SGMCompClass", "FSPlayerCompClass")

--- 请求状态归属当前玩家会话。
--- @param owner SPlayerObjectClass 当前玩家对象。
function Component:Ctor(owner)
    Component.Super.Ctor(self, owner)
    self._nextSave = 0
    self._busy = false
end

--- 提供管理器协议转发使用的组件名。
--- @return string 玩家内 GM 组件名。
function Component:GetCompName()
    return "SGMComp"
end

--- 完成登录握手后才允许调试玩法；恢复命令保留原有条件。
function Component:OnPlayerLogin()
    self._active = true
end

--- 停止玩法命令，两个开关随本次 Player 会话结束。
function Component:OnPlayerLogout()
    self._active = false
end

--- 限制远程参数为工作范围内的正整数，拒绝非数字及非有限值。
--- @param value any 远程参数。
--- @param maximum number 业务上限。
--- @return boolean 是否可用。
local function IsPositiveInteger(value, maximum)
    return type(value) == "number" and value >= 1 and value <= maximum and value % 1 == 0
end

--- 发放走普通背包容量和奖励校验；原成品剑按钮固定发一个普通剑胚。
--- @param action string 白名单内的发放动作。
--- @param payload table 面板原始发放参数。
--- @return table 操作结果和提示。
function Component:GrantItem(action, payload)
    if action == "GiveSword" then
        action = "GiveBlank"
        payload = {id = SwordRules.BlankItemId, quantity = 1}
    end
    local itemId, count, extraData
    if action == "GiveBlank" and IsPositiveInteger(payload.id, 2147483647)
        and IsPositiveInteger(payload.quantity, 100) then
        local rock = GameConfig.MiningRockData[payload.id]
        if payload.id == SwordRules.BlankItemId then
            rock = SwordRules.GetMutation("Normal")
        end
        if rock then
            itemId = SwordRules.BlankItemId
            count = payload.quantity
            extraData = {MutationId = rock.MutationId, blankLuckLevel = 1}
        end
    elseif action == "GiveOre" and IsPositiveInteger(payload.id, 2147483647)
        and IsPositiveInteger(payload.quantity, 100) then
        for grade, rock in pairs(GameConfig.MiningRockData) do
            if rock.OreItemId == payload.id then
                itemId, count = rock.OreItemId, payload.quantity
                break
            end
        end
    elseif action == "GiveLevelOneSword" then
        local quality = 1
        if GameConfig.WeaponData[quality] then
            extraData = {
                MutationId = "Normal",
                blankLuckLevel = 1,
                Quality = quality,
                Level = 1,
                StoredMoney = 0,
            }
            if SwordRules.IsValid(extraData) then
                itemId, count = SwordRules.ItemId, 1
            end
        end
    end
    if not itemId then
        return {success = false, key = TranslationTexts.InvalidGrant}
    end
    local success = self:RequireComponent("FSRewardComp"):AddRewards({
        {Type = "Item", ItemId = itemId, Count = count, ExtraData = extraData},
    })
    return {success = success, key = success and TranslationTexts.Success or TranslationTexts.GrantFailed}
end

--- 非存档设置写入当前玩家实例，客户端只读同步结果。
--- @param action string 白名单内的玩法调试动作。
--- @param payload any 客户端发来的原始参数。
--- @return table 操作结果和提示。
function Component:RequestGameplay(action, payload)
    if not self._active or type(payload) ~= "table" then
        return {success = false, key = TranslationTexts.Unknown}
    end
    local attribute = SwitchAttributes[action]
    if attribute then
        if type(payload.enabled) ~= "boolean" then
            return {success = false, key = TranslationTexts.Unknown}
        end
        self:GetPlayerNode():SetAttribute(attribute, payload.enabled)
        return {success = true, enabled = payload.enabled, key = TranslationTexts.Success}
    end
    if action == "GiveBlank" or action == "GiveOre" or action == "GiveSword" or action == "GiveLevelOneSword" then
        return self:GrantItem(action, payload)
    end
    if action == "PrepareUpgrade" then
        local cost = self:RequireComponent("SSlotSwordComp"):GetNearbyUpgradePrice()
        if not cost then
            return {success = false, key = TranslationTexts.NoNearbySword}
        end
        local shortage = cost - self:GetNumber(Fields.Money)
        local success = shortage <= 0 or self:RequireComponent("FSRewardComp"):AddRewards({
            {Type = "Money", Currency = "Money", Count = shortage},
        })
        return {success = success, key = success and TranslationTexts.Success or TranslationTexts.Unknown}
    end
    if action == "BreakSword" then
        local success = self:RequireComponent("SForgeComp"):BreakCurrentSword()
        return {success = success, key = success and TranslationTexts.Success or TranslationTexts.NoActiveForge}
    end
    return {success = false, key = TranslationTexts.Unknown}
end

--- 只恢复已声明字段，保留当前基地分配与框架档案中的支付回执去重记录。
function Component:ResetData()
    local player = self:GetPlayerObject()
    for fieldName, field in pairs(Fields) do
        if field == Fields.BaseId then
            continue
        end
        if field.Type == "number" then
            player:SetNumber(field, field.DefVal)
        elseif field.Type == "boolean" then
            player:SetFlag(field, field.DefVal)
        elseif field.Type == "table" then
            player:SetTable(field, nil)
        end
    end
end

--- 权限按所属玩家校验，玩法命令只作用于已加载的本人会话。
--- @param action string 调试命令名。
--- @param payload any 玩法命令参数；存档操作不读取。
--- @return table 操作结果与提示定义；保存返回后重新校验原会话。
function Component:Request(action, payload)
    local userId = self:GetPlayerId()
    if not FX.IsDeveloper(userId) then
        return {success = false, key = TranslationTexts.Forbidden}
    end
    local player = self:GetPlayerObject()
    local storage = FS.PlayerKVDataManager
    local state = storage:GetState(userId)
    if not state or not state.loaded or state.leaving then
        return {success = false, key = TranslationTexts.Unknown}
    end
    if action ~= "ResetData" and action ~= "SaveNow" then
        if self._busy or state.saving then
            return {success = false, key = TranslationTexts.Busy}
        end
        return self:RequestGameplay(action, payload)
    end
    local now = os.clock()
    if self._busy or state.saving or now < self._nextSave then
        return {success = false, key = TranslationTexts.Busy}
    end
    self._busy = true
    self._nextSave = now + 5
    --- 保存可能让出执行，异常也需释放当前会话的请求锁。
    --- @return boolean 是否成功保存档案。
    local ok, saved = pcall(function()
        if action == "ResetData" then
            self:ResetData()
        end
        return storage:Save(userId, state.session)
    end)
    self._busy = false
    if not ok then
        warn("[GM] Save/reset failed", userId, saved)
    end
    if not ok or not saved then
        return {success = false, key = TranslationTexts.SaveFailed}
    end
    if not storage:IsSessionActive(userId, state.session)
        or FS.PlayerManager:GetPlayerObject(userId) ~= player then
        return {success = false, key = TranslationTexts.Unknown}
    end
    return {success = true, key = TranslationTexts.Success}
end

return Component
