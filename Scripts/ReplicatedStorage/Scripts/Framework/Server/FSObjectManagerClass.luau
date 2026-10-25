local FX, FS = _G.FX, _G.FS
local FXTask = FX.Task

local FSObjectManagerClass = FX.Class("FSObjectManagerClass")
FS.ObjectManagerClass = FSObjectManagerClass

function FSObjectManagerClass:Ctor(objectType)
    self._objectType = objectType
    self._objectMap = {}
end

function FSObjectManagerClass:Dtor()
    self:CleanUp()
end

function FSObjectManagerClass:GetObjectMap()
    return self._objectMap
end

-- 创建对象
function FSObjectManagerClass:CreateObject(...)
    local objectClass = FX.GetClass(self._objectType)
    local object = objectClass.New(...)
    self._objectMap[object:GetObjectId()] = object
    return object
end

-- 创建指定类型的对象
function FSObjectManagerClass:CreateObjectByType(objectType, ...)
    local objectClass = FX.GetClass(objectType)
    local object = objectClass.New(...)
    self._objectMap[object:GetObjectId()] = object
    return object
end

function FSObjectManagerClass:GetObjectById(objectId)
    if not objectId then
        return nil
    end
    return self._objectMap[objectId]
end

-- 销毁对象
function FSObjectManagerClass:DestroyObjectById(objectId)
    local object = self._objectMap[objectId]
    if object then
        object:Dtor()
        self._objectMap[objectId] = nil
    end
end

-- 延迟销毁对象
function FSObjectManagerClass:DestroyObjectDeferredById(objectId)
    if not self._objectMap[objectId] then
        return
    end
    FXTask:Defer(function()
        self:DestroyObjectById(objectId)
    end)
end

function FSObjectManagerClass:DestroyObject(object)
    self:DestroyObjectById(object:GetObjectId())
end

function FSObjectManagerClass:DestroyObjectDeferred(object)
    self:DestroyObjectDeferredById(object:GetObjectId())
end

function FSObjectManagerClass:CleanUp()
    for _, object in pairs(self._objectMap) do
        object:Dtor()
    end
    self._objectMap = {}
end

-- 调用对象方法
function FSObjectManagerClass:CallObjectMethod(objectId, methodName, ...)
    local object = self._objectMap[objectId]
    if not object then
        return false, nil
    end

    if object and type(object[methodName]) == "function" then
        local ret = object[methodName](object, ...)
        return true, ret
    end
    FX.ErrorWithTraceback(string.format("对象 '%s' 没有方法 '%s'", objectId, methodName))
end

-- 调用对象组件方法
function FSObjectManagerClass:CallObjectCompMethod(objectId, compAndMethodName, ...)
    local object = self._objectMap[objectId]
    if not object then
        return false, nil
    end
    return object:CallCompMethod(compAndMethodName, ...)
end
return true
