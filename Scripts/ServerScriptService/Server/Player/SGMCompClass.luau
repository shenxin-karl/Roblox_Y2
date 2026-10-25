-- 项目开发者操作；只处理本人默认值恢复和主动保存，不包含旧玩法命令。
local FX, FS = _G.FX, _G.FS
local Text = FX.Text
local TranslationTexts = Text.Define("GM", {
    Forbidden = "Only developers can use these controls.",
    Unknown = "Something went wrong. Please try again.",
    Busy = "An operation is in progress. Please try again shortly.",
    SaveFailed = "Save failed. Please try again.",
    Success = "Operation completed.",
})
local Fields = _G.PlayerDataConfig
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

--- 只恢复已声明字段，保留框架档案中的支付回执去重记录。
function Component:ResetData()
    local player = self:GetPlayerObject()
    for fieldName, field in pairs(Fields) do
        if field.Type == "number" then
            player:SetNumber(field, field.DefVal)
        elseif field.Type == "boolean" then
            player:SetFlag(field, field.DefVal)
        elseif field.Type == "table" then
            player:SetTable(field, nil)
        end
    end
end

--- 权限按所属玩家校验；不接受任意字段、目标玩家或旧业务命令。
--- @param action any ResetData 或 SaveNow。
--- @return table 操作结果与提示定义。
function Component:Request(action)
    local userId = self:GetPlayerId()
    if not FX.IsDeveloper(userId) then
        return {success = false, key = TranslationTexts.Forbidden}
    end
    local player = self:GetPlayerObject()
    local db = FS.PlayerKVDataManager._playerDBMap[userId]
    if (action ~= "ResetData" and action ~= "SaveNow") or not db
        or not db:IsLoadFinished() or db._leaving then
        return {success = false, key = TranslationTexts.Unknown}
    end
    local now = os.clock()
    if self._busy or db._saving or now < self._nextSave then
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
        return db:Save(false)
    end)
    self._busy = false
    if not ok then
        warn("[GM] Save/reset failed", userId, saved)
    end
    if not ok or not saved then
        return {success = false, key = TranslationTexts.SaveFailed}
    end
    if db._leaving or FS.PlayerKVDataManager._playerDBMap[userId] ~= db
        or FS.PlayerManager:GetPlayerObject(userId) ~= player then
        return {success = false, key = TranslationTexts.Unknown}
    end
    return {success = true, key = TranslationTexts.Success}
end

return Component
