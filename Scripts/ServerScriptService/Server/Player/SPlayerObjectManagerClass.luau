-- 项目协议接入；Ready 握手、玩家创建与销毁沿用框架。
local FX = _G.FX
local FXLoader = FX.Loader
local SGMRecovery = FXLoader:Require(script.Parent.Parent, "Handlers.SGMRecovery")
local Fields = _G.PlayerDataConfig
local Manager = FX.Class("SPlayerObjectManagerClass", "FSPlayerObjectManagerClass")
_G.SPlayerObjectManagerClass = Manager

--- GM 注册与鉴权沿用框架，项目协议只注册一次并转发给所属组件。
function Manager:Ctor()
    Manager.Super.Ctor(self, "SPlayerObjectClass")
    self:RegSettingsMsg()
    self:RegBaseMsg()
end

--- 回家请求只按引擎认证身份查找本人的组件，不接收目标玩家或坐标。
function Manager:RegBaseMsg()
    --- 未登录或尚未挂载基地组件的请求不进入传送流程。
    --- @param userId number 引擎认证的请求者 ID。
    FX.Network:RegClientMsgCallback("C2S_ReturnHome", function(userId)
        local player = self:GetPlayerObject(userId)
        local base = player and player:GetComponent("SBaseComp")
        if base then
            base:ReturnHome()
        end
    end)
end

--- 项目命令转发；框架已校验开发者身份，组件仍负责具体动作与会话校验。
--- @param userId number 引擎认证的请求者 ID。
--- @param action string ResetData 或 SaveNow。
--- @return table 权威操作结果。
function Manager:HandleGMCommand(userId, action)
    local player = self:GetPlayerObject(userId)
    local gm = player and player:GetComponent("SGMComp")
    if gm then
        return gm:Request(action)
    end
    return SGMRecovery.Request(userId, action)
end

--- 音量只保存到认证请求者的存档，旧玩法偏好不再接收。
function Manager:RegSettingsMsg()
    --- 拒绝非整数、NaN、无穷和越界音量，仅写入约定字段。
    --- @param userId number 引擎认证的玩家 ID。
    --- @param settings any 客户端提交的音量设置快照。
    FX.Network:RegClientMsgCallback("C2S_SaveSettings", function(userId, settings)
        local player = self:GetPlayerObject(userId)
        if not player or type(settings) ~= "table" then
            return
        end
        for index, key in ipairs({"musicVolume", "soundEffectsVolume"}) do
            local value = settings[key]
            if type(value) ~= "number" or value ~= value or value < 0 or value > 100 or value % 1 ~= 0 then
                return
            end
        end
        player:SetTable(Fields.Settings, {
            musicVolume = settings.musicVolume,
            soundEffectsVolume = settings.soundEffectsVolume,
        })
    end)
end

return Manager
