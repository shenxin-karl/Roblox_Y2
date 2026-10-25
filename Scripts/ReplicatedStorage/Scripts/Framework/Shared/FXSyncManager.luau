local FX, MS = _G.FX, _G.Rbx
local FXTask = FX.Task
local FXNetwork = FX.Network
local FXTable = FX.Table

--- 框架层共享数据同步管理器。
--- 统一维护服务端权威数据与客户端镜像数据，服务端按帧合并增量并广播 `S2C_ServerSyncData`，
--- 客户端接收后回放到本地缓存，并通过 `WatchDataChanged` 对外分发键级数据变更事件。
--- 本管理器读写的 `varEnum` 需与 `Game/Shared/ServerDataConfig.lua` 中定义保持一致（`Type/DefVal/Key`）。
--- @class FXSyncManagerClass: FXObjectBaseClass
local FXSyncManagerClass = FX.Class("FXSyncManagerClass", "FXObjectBaseClass")
function FXSyncManagerClass:Ctor()
    FXSyncManagerClass.Super.Ctor(self)
    self._syncData = {}
    self._incrementData = {}
    self._syncDataListeners = {}
    self._deferTask = nil

    if MS.RunService:IsClient() then
        FXNetwork:RegServerMsgCallback("S2C_ServerSyncData", function(incrementData)
            -- incrementData 的 key 来自 ServerDataConfig 中各枚举项的 Key 字段。
            for key, value in pairs(incrementData) do
                local oldData = self._syncData[key]
                self._syncData[key] = value
                self:OnDataChanged(key, value, oldData)
            end
        end)
    end
end

-- 拷贝默认数据
function FXSyncManagerClass:_CopyDefaultData(varEnum)
    if varEnum.Type == "table" and varEnum.DefVal ~= nil then
        return FXTable:DeepCopy(varEnum.DefVal)
    else
        return varEnum.DefVal
    end
end

function FXSyncManagerClass:_GetData(varEnum)
    local value = self._syncData[varEnum.Key]
    if value == nil then
        return self:_CopyDefaultData(varEnum)
    end
    return type(value) == "table" and FXTable:DeepCopy(value) or value
end

-- Get 接口：服务器和客户端共用
function FXSyncManagerClass:GetNumber(numberEnum)
    if numberEnum.Type ~= "number" then
        FX.ErrorWithTraceback("GetNumber: numberEnum type error, expected number, got " .. tostring(numberEnum.Type))
    end
    return self:_GetData(numberEnum)
end

function FXSyncManagerClass:GetFlag(boolEnum)
    if boolEnum.Type ~= "boolean" then
        FX.ErrorWithTraceback("GetFlag: boolEnum type error, expected boolean, got " .. tostring(boolEnum.Type))
    end
    return self:_GetData(boolEnum)
end

function FXSyncManagerClass:GetTable(tableEnum)
    if tableEnum.Type ~= "table" then
        FX.ErrorWithTraceback("GetTable: tableEnum type error, expected table, got " .. tostring(tableEnum.Type))
    end
    return self:_GetData(tableEnum)
end

if MS.RunService:IsServer() then
    function FXSyncManagerClass:_SetData(varEnum, data, checkEqual)
        if data == nil then
            data = self:_CopyDefaultData(varEnum)
        end
        assert(type(data) == varEnum.Type, "Invalid sync data: " .. varEnum.Key)
        if type(data) == "table" then
            data = FXTable:DeepCopy(data)
        elseif type(data) == "number" then
            assert(data == data and math.abs(data) < math.huge, "Sync data must be finite")
        end
        local key = varEnum.Key
        local oldData = self._syncData[key]
        if checkEqual and oldData == data then
            return
        end
        self._syncData[key] = data
        self._incrementData[key] = data
        self:OnDataChanged(key, data, oldData)
        if not self._deferTask then
            self._deferTask = FXTask:Defer(function()
                self._deferTask = nil
                FXNetwork:BroadcastMsg("S2C_ServerSyncData", self._incrementData)
                self._incrementData = {}
            end)
        end
    end

    --[[
        varEnum = {
            Type   = "number" | "boolean" | "table",
            DefVal = default value,
            Key    = "xxx",
        },
    ]]
    function FXSyncManagerClass:SetNumber(numberEnum, number)
        if numberEnum.Type ~= "number" or (type(number) ~= "number" and number ~= nil) then
            FX.ErrorWithTraceback("SetNumber: numberEnum type error, expected number, got " .. type(number))
        end
        self:_SetData(numberEnum, number, true)
        return true
    end

    function FXSyncManagerClass:AddNumber(numberEnum, number)
        if numberEnum.Type ~= "number" or (type(number) ~= "number" and number ~= nil) then
            FX.ErrorWithTraceback("AddNumber: numberEnum type error, expected number, got " .. type(number))
        end
        if number == 0 then
            return false
        end
        local oldNumber = self:GetNumber(numberEnum)
        local newNumber = oldNumber + number
        return self:SetNumber(numberEnum, newNumber)
    end

    function FXSyncManagerClass:SubNumber(numberEnum, number)
        if numberEnum.Type ~= "number" or (type(number) ~= "number" and number ~= nil) then
            FX.ErrorWithTraceback("SubNumber: numberEnum type error, expected number, got " .. type(number))
        end
        if number == 0 then
            return false
        end
        local oldNumber = self:GetNumber(numberEnum)
        if oldNumber < number then
            return false
        end
        local newNumber = oldNumber - number
        return self:SetNumber(numberEnum, newNumber)
    end

    function FXSyncManagerClass:SetFlag(boolEnum, flag)
        if boolEnum.Type ~= "boolean" or (type(flag) ~= "boolean" and flag ~= nil) then
            FX.ErrorWithTraceback("SetFlag: boolEnum type error, expected boolean, got " .. type(flag))
        end
        self:_SetData(boolEnum, flag, true)
        return true
    end

    function FXSyncManagerClass:SetTable(tableEnum, tableData)
        if tableEnum.Type ~= "table" or (type(tableData) ~= "table" and tableData ~= nil) then
            FX.ErrorWithTraceback("SetTable: tableEnum type error, expected table, got " .. type(tableData))
        end
        self:_SetData(tableEnum, tableData, false)
        return true
    end

    function FXSyncManagerClass:OnPlayerLogin(playerId)
        FXNetwork:SendMsgToClient(playerId, "S2C_ServerSyncData", self._syncData)
    end
end

function FXSyncManagerClass:WatchDataChanged(varEnum, callback, this)
    local key = varEnum.Key or varEnum.key
    local customNotify = self._syncDataListeners[key]
    if not customNotify then
        self._syncDataListeners[key] = Instance.new("BindableEvent")
        customNotify = self._syncDataListeners[key]
    end
    if this then
        return customNotify.Event:Connect(function(...)
            callback(this, ...)
        end)
    else
        return customNotify.Event:Connect(callback)
    end
end

function FXSyncManagerClass:OnDataChanged(key, newData, oldData)
    local customNotify = self._syncDataListeners[key]
    if customNotify then
        customNotify:Fire(newData, oldData, key)
    end
end

--- 释放单例持有的字段监听和待发送任务；通常只在关闭整个框架时调用。
function FXSyncManagerClass:Dtor()
    FXTask:Cancel(self._deferTask)
    for _, event in pairs(self._syncDataListeners) do
        event:Destroy()
    end
    if MS.RunService:IsClient() then
        FXNetwork:UnRegServerMsgCallback("S2C_ServerSyncData")
    end
    FXSyncManagerClass.Super.Dtor(self)
end

FX.SyncManager = FXSyncManagerClass.New()
return true
