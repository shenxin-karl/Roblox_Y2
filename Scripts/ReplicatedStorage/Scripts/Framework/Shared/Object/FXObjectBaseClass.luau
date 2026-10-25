local FX = _G.FX
local FXLog = FX.Log

local FXObjectBaseClass = FX.Class("FXObjectBaseClass")
FX.BaseObject = FXObjectBaseClass

function FXObjectBaseClass:Ctor()
    self._components = {}
    self._objectId = FX.GenObjectID()
    self._eventMap = {}
end

function FXObjectBaseClass:Dtor()
    for _, component in pairs(self._components) do
        component:Dtor()
    end
    self._components = nil
end

function FXObjectBaseClass:GetObjectId()
    return self._objectId
end

function FXObjectBaseClass:GetComponent(componentType)
    for _, component in pairs(self._components) do
        if component:IsA(componentType) or component:GetCompName() == componentType then
            return component
        end
    end
    return nil
end

-- 获取组件, 如果组件不存在, 则抛出错误
function FXObjectBaseClass:RequireComponent(componentType)
    local component = self:GetComponent(componentType)
    assert(component ~= nil, string.format("组件 '%s' 不存在", componentType))
    return component
end

-- 添加组件, 如果组件已存在, 则抛出错误
function FXObjectBaseClass:AddComponent(componentName, ...)
    local component = self:GetComponent(componentName)
    if component ~= nil then
        return component
    end

    local componentClass = FX.GetClass(componentName)
    if not componentClass then
        FX.ErrorWithTraceback(string.format("组件 '%s' 不存在", componentName))
    end
    local componentInstance = componentClass.New(self, ...)
    self._components[componentName] = componentInstance
    if self._ready and componentInstance.OnReady then
        componentInstance:OnReady()
    end
    return componentInstance
end

-- 移除组件, 如果组件不存在, 则返回 false
function FXObjectBaseClass:RemoveComponent(componentName)
    local component = self:GetComponent(componentName)
    if component ~= nil then
        component:Dtor()
        for key, instance in pairs(self._components) do
            if instance == component then
                self._components[key] = nil
                break
            end
        end
        return true
    end
    return false
end

-- 调用组件方法, 如果组件不存在, 则抛出错误
function FXObjectBaseClass:CallCompMethod(compAndMethodName, ...)
    local compName, funcName = FX.ParseComponentFuncString(compAndMethodName)
    if not compName or not funcName then
        FX.ErrorWithTraceback(string.format("解析组件函数字符串'%s'失败", compAndMethodName))
    end
    local component = self:RequireComponent(compName)
    if not component[funcName] then
        FX.ErrorWithTraceback(string.format("组件 '%s' 没有方法 '%s'", compName, funcName))
    end
    return component[funcName](component, ...)
end

-- 调用所有组件的方法
-- methodName: 方法名
-- ...: 方法参数
function FXObjectBaseClass:CallAllCompMethod(methodName, ...)
    for _, component in pairs(self._components) do
        if component[methodName] and type(component[methodName]) == "function" then
            component[methodName](component, ...)
        end
    end
end

-- 发布对象事件
-- eventName: 事件名
-- ...: 事件参数
function FXObjectBaseClass:PublishEvent(eventName, ...)
    self:CallAllCompMethod("_OnEvent", eventName, ...)
end

-- 发布事件组件内部使用
function FXObjectBaseClass:_CompPublishEvent(componentType, eventName, ...)
    self:CallAllCompMethod("_OnEvent", eventName, ...)
end
return true
