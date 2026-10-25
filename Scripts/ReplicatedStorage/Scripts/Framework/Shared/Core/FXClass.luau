local classes = {} -- 闭包存放所有类

local function FXClass(name, base)
    assert(classes[name] == nil, "Class already registered: " .. name)
    local cls = {}
    cls.__index = cls
    cls.__name = name

    -- 支持 base 为字符串或表
    if type(base) == "string" then
        base = classes[base]
        if not base then
            error("Base class not found for " .. name)
        end
    end

    cls.__base = base
    if base then
        setmetatable(cls, { __index = base })
        cls.Super = base
    end

    -- 未重写时自动调用基类：子类不写 Ctor/Dtor 也会正确链式调用基类
    cls.Ctor = function(self, ...)
        if base and base.Ctor then
            base.Ctor(self, ...)
        end
    end
    cls.Dtor = function(self)
        if base and base.Dtor then
            base.Dtor(self)
        end
    end

    -- 创建实例
    function cls.New(...)
        local obj = setmetatable({}, cls)
        obj:Ctor(...)
        return obj
    end

    -- 类型判断
    function cls:IsA(target)
        if type(target) == "string" then
            target = classes[target]
            if not target then
                return false
            end
        end
        local mt = getmetatable(self)
        while mt do
            if mt == target then
                return true
            end
            mt = mt.__base
        end
        return false
    end

    -- 获取类名
    function cls:GetClassName()
        return cls.__name
    end

    -- 存入闭包表
    classes[name] = cls
    return cls
end

-- 可选：外部访问类表
function _G.FX.GetClass(name)
    return classes[name]
end

_G.FX.Class = FXClass
return true
