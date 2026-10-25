local FX = _G.FX
local FXLog = FX.Log

local FXCompBaseClass = FX.Class("FXCompBaseClass")
FX.BaseCompClass = FXCompBaseClass

function FXCompBaseClass:Ctor(owner)
    self._owner = owner
    self._objectId = FX.GenObjectID()
    self._eventMap = {}
    self._connections = {}
end

function FXCompBaseClass:Dtor()
    for _, connection in ipairs(self._connections) do
        connection:Disconnect()
    end
    table.clear(self._connections)
    table.clear(self._eventMap)
    self._owner = nil
end

function FXCompBaseClass:GetOwner()
    return self._owner
end

function FXCompBaseClass:GetCompName()
    error("Not implemented")
end

function FXCompBaseClass:GetObjectId()
    return self._objectId
end

function FXCompBaseClass:GetComponent(componentType)
    return self._owner:GetComponent(componentType)
end

function FXCompBaseClass:RequireComponent(componentType)
    return self._owner:RequireComponent(componentType)
end

function FXCompBaseClass:AddComponent(componentType, ...)
    return self._owner:AddComponent(componentType, ...)
end

function FXCompBaseClass:CallCompMethod(compAndFuncString, ...)
    return self._owner:CallCompMethod(compAndFuncString, ...)
end

-- 订阅事件
-- eventName: 事件名称
-- callback: 事件回调函数
function FXCompBaseClass:SubscribeEvent(eventName, callback)
    self._eventMap[eventName] = callback
end

-- 取消订阅事件
-- eventName: 事件名称
function FXCompBaseClass:UnsubscribeEvent(eventName)
    self._eventMap[eventName] = nil
end

-- 发送事件
-- eventName: 事件名称
-- ...: 事件参数
function FXCompBaseClass:PublishEvent(eventName, ...)
    self._owner:_CompPublishEvent(self:GetCompName(), eventName, ...)
end

-- 当接受到事件时, 调用此函数
function FXCompBaseClass:_OnEvent(eventName, ...)
    local func = self._eventMap[eventName]
    if func then
        func(self, ...)
    end
end
--- @param connection RBXScriptConnection 组件拥有的连接。
--- @return RBXScriptConnection 同一连接，方便调用方保留句柄。
function FXCompBaseClass:TrackConnection(connection)
    table.insert(self._connections, connection)
    return connection
end
return FXCompBaseClass
