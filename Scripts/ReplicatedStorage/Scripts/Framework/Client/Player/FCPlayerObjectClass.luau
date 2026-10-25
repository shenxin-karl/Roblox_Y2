local FX, FC = _G.FX, _G.FC
local Player = FX.Class("FCPlayerObjectClass", "FXObjectBaseClass")
FC.PlayerObjectClass = Player

--- @param playerId number 本地玩家 UserId。
function Player:Ctor(playerId)
    Player.Super.Ctor(self)
    self._playerId = playerId
    self._playerData, self._playerDataListeners = {}, {}
    self._ready = false
    FX.Network:RegServerMsgCallback("S2C_PlayerStateSync", function(data)
        for key, value in pairs(data) do
            local old = self._playerData[key]
            self._playerData[key] = value
            if self._playerDataListeners[key] then
                self._playerDataListeners[key]:Fire(value, old, key)
            end
        end
    end)

    FX.Network:RegServerMsgCallback("S2C_ServerReady", function()
        if self._ready then
            return
        end

        self._ready = true
        self:CallAllCompMethod("OnReady")
        FC.Events.OnReady:Fire()
        self._timer = FX.Task:Interval(1, function()
            self:CallAllCompMethod("OnUpdate", os.time())
        end)

        print("[Roblox_Y1] 客户端与服务端已就绪")
    end)
end

--- @return number 本地玩家 ID。
function Player:GetPlayerId()
    return self._playerId
end

--- @param field table 数据字段定义。
--- @return any 当前值；false 是有效数据。
function Player:_GetData(field)
    local value = self._playerData[field.Key]
    if value == nil then
        value = field.DefVal
    end

    if type(value) == "table" then
        return FX.Table:DeepCopy(value)
    end

    return value
end

Player.GetNumber, Player.GetFlag, Player.GetTable = Player._GetData, Player._GetData, Player._GetData

--- 注册时回放当前值，晚创建的 UI 也可直接响应已有状态。
--- @param field table 数据字段定义。
--- @param callback function 变化回调。
--- @param owner table 可选回调所属对象。
--- @return RBXScriptConnection 由组件持有并清理的连接。
function Player:WatchDataChanged(field, callback, owner)
    local event = self._playerDataListeners[field.Key]
    if not event then
        event = Instance.new("BindableEvent")
        self._playerDataListeners[field.Key] = event
    end

    local invoke = callback
    if owner then
        invoke = function(...)
            callback(owner, ...)
        end
    end

    local connection = event.Event:Connect(invoke)
    invoke(self:_GetData(field), nil, field.Key)
    return connection
end

--- 释放网络回调、每秒更新和字段监听。
function Player:Dtor()
    FX.Task:Cancel(self._timer)
    for _, name in ipairs({ "S2C_PlayerStateSync", "S2C_ServerReady" }) do
        FX.Network:UnRegServerMsgCallback(name)
    end

    for _, event in pairs(self._playerDataListeners) do
        event:Destroy()
    end

    Player.Super.Dtor(self)
end

return Player
