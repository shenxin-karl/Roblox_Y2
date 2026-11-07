local FX, FS = _G.FX, _G.FS
local FXLoader = FX.Loader
local Text = FXLoader:RequireShared("Scripts.Framework.Shared.Core.FXText")
local TranslationTexts = Text.Define("GMRecovery", {
    Forbidden = "Only developers can use these controls.",
    Unknown = "Something went wrong. Please try again.",
    Busy = "An operation is in progress. Please try again shortly.",
    SaveFailed = "Save failed. Please try again.",
    Success = "Operation completed.",
})
local SGMRecovery = {}

--- 加载失败时仅重置开发者本人，并保护正式服其他有效会话锁。
--- @param userId number 网络层认证的请求者 ID。
--- @param action any 客户端请求动作，仅接受 ResetData。
--- @return table 云端重置结果；成功后重新加载并沿正常 Ready 初始化。
function SGMRecovery.Request(userId, action)
    if not FX.IsDeveloper(userId) then
        return {success = false, key = TranslationTexts.Forbidden}
    end
    if action ~= "ResetData" then
        return {success = false, key = TranslationTexts.Unknown}
    end
    local success, status = FS.PlayerKVDataManager:RecoverFailedData(userId)
    return {success = success, key = TranslationTexts[status]}
end

return SGMRecovery
