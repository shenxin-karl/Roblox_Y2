local FX, FS = _G.FX, _G.FS
local Players = game:GetService("Players")
local TranslationTexts = FX.Text.Define("GM", {
    Forbidden = "Only developers can use these controls.",
    Unknown = "Something went wrong. Please try again.",
})
local Class = FX.Class("FSPlayerObjectManagerClass", "FSObjectManagerClass")
FS.PlayerMgrClass = Class

--- 接管项目玩家管理器，并在业务服务已创建后自动开放客户端握手。
--- @param playerClassType string 项目玩家类名。
function Class:Ctor(playerClassType)
    Class.Super.Ctor(self, playerClassType)
    self._playerMap, self._clientReady, self._serverReady = {}, {}, {}
    self._connections = {}
    --- GM 协议统一由框架注册，项目只覆写命令处理入口。
    --- @param id number 网络层认证的玩家 ID。
    --- @param action any 项目命令名称，必须为非空字符串。
    --- @param ... any 命令参数，由项目处理函数进一步校验。
    --- @return table 权限校验或项目命令的执行结果。
    FX.Network:RegClientMsgCallback("C2S_GMCommand", function(id, action, ...)
        if not FX.IsDeveloper(id) then
            return {success = false, key = TranslationTexts.Forbidden}
        end
        if type(action) ~= "string" or action == "" then
            return {success = false, key = TranslationTexts.Unknown}
        end
        return self:HandleGMCommand(id, action, ...)
    end)
    --- 握手时补接可能先于管理器创建完成的存档加载结果。
    --- @param id number 引擎认证的玩家 ID。
    FX.Network:RegClientMsgCallback("C2S_ClientReady", function(id)
        self:SetPlayerReady(id, true)
        local db = FS.PlayerKVDataManager._playerDBMap[id]
        if db and db:IsLoadFinished() then
            self:SetPlayerReady(id, false)
        end
    end)

    table.insert(
        self._connections,
        FS.Events.OnPlayerDataLoadFinished.Event:Connect(function(id)
            if not Players:GetPlayerByUserId(id) then
                local db = FS.PlayerKVDataManager._playerDBMap[id]
                if db then
                    db:Save(true)
                    FS.PlayerKVDataManager._playerDBMap[id] = nil
                end

                return
            end

            self:SetPlayerReady(id, false)
        end)
    )
    self._timer = FX.Task:Interval(1, function()
        for _, playerObject in pairs(self._playerMap) do
            local ok, err = pcall(playerObject.OnUpdate, playerObject, os.time())
            if not ok then
                warn(err)
            end
        end
    end)
    FS.PlayerManager = self
    game.ReplicatedStorage.Scripts.Framework.Network:SetAttribute("ServerReady", true)
end

--- 重复 Ready 请求不会重建对象或重复发奖。
--- @param id number 引擎认证的玩家 ID。
--- @param isClient boolean 是否为客户端就绪通知。
function Class:SetPlayerReady(id, isClient)
    if self._playerMap[id] then
        return
    end

    if isClient then
        self._clientReady[id] = true
    else
        self._serverReady[id] = true
    end

    if not self._clientReady[id] or not self._serverReady[id] or not Players:GetPlayerByUserId(id) then
        return
    end

    local object = self:CreateObject(id)
    self._playerMap[id] = object
    FX.SyncManager:OnPlayerLogin(id)
    object:OnPlayerLogin()
    FS.Events.OnPlayerReady:Fire(id)
    FX.Network:SendMsgToClient(id, "S2C_ServerReady")
end

--- @param id number 正在退出的玩家 ID。
function Class:OnPlayerLogout(id)
    self._clientReady[id], self._serverReady[id] = nil, nil
    local object = self._playerMap[id]
    if object then
        object:OnPlayerLogout()
        self:DestroyObject(object)
        self._playerMap[id] = nil
    end
end

--- @param id number Roblox UserId。
--- @return table 已完成握手的玩家对象。
--- 默认不开放任何 GM 动作；项目覆写此函数，不能重复注册协议。
--- @param id number 已通过开发者权限校验的请求者 ID。
--- @param action string 项目命令名。
--- @param ... any 项目命令参数，由覆写函数校验。
--- @return table 默认拒绝结果。
function Class:HandleGMCommand(id, action, ...)
    return {success = false, key = TranslationTexts.Unknown}
end

function Class:GetPlayerObject(id)
    return self._playerMap[id]
end

--- 清理管理器自有连接与每秒任务。
function Class:Dtor()
    FX.Task:Cancel(self._timer)
    FX.Network:UnRegClientMsgCallback("C2S_ClientReady")
    FX.Network:UnRegClientMsgCallback("C2S_GMCommand")
    for _, connection in ipairs(self._connections) do
        connection:Disconnect()
    end

    Class.Super.Dtor(self)
end

return Class
