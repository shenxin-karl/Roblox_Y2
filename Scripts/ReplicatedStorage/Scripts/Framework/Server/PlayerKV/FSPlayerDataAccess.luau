-- 玩家数据访问：副本用于编辑，代理 View 用于读取；原始表仅由存档模块持有。
local Access = {}
local readers = setmetatable({}, {__mode = "k"})

--- 在模块内部解开 View；绝不把原始表作为公开接口返回。
--- @param value any 数据或 View。
--- @return any View 当前指向的数据。
local function Resolve(value)
    while type(value) == "table" and readers[value] do
        value = readers[value]()
    end
    return value
end

--- 深拷贝数据，也支持把 View 或安全浅拷贝转成可提交的普通表。
--- @param value any 数据值。
--- @return any 与存档完全隔离的副本。
function Access.DeepCopy(value)
    value = Resolve(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, child in pairs(value) do
        copy[key] = Access.DeepCopy(child)
    end
    return copy
end

--- 创建实时只读代理，不复制原表；嵌套访问继续返回代理，写入报错且不影响存档。
--- 支持索引、#、Luau 的 for key, value in view do；不要用 pairs/ipairs/next/rawget/table.* 读取代理。
--- @param read function 无 yield 的内部读取函数；字段替换后 View 读取新值。
--- @return table 空代理及其元表均冻结，均不包含原表或 DB 引用。
function Access.View(read)
    local children = {}
    --- 读取当前路径，并按键复用嵌套 View。
    --- @param key string|number 数据键。
    --- @return any 标量或嵌套只读代理。
    local function ReadChild(key)
        local data = Resolve(read())
        local value
        if type(data) == "table" then
            value = data[key]
        end
        if type(value) ~= "table" then
            return value
        end
        if not children[key] then
            children[key] = Access.View(function()
                local current = Resolve(read())
                return type(current) == "table" and current[key] or nil
            end)
        end
        return children[key]
    end
    local proxy = setmetatable({}, table.freeze({
        -- proxyTable 是元方法收到的空代理，读取始终经内部路径解析。
        __index = function(proxyTable, key)
            return ReadChild(key)
        end,
        __len = function()
            local data = Resolve(read())
            return type(data) == "table" and #data or 0
        end,
        __iter = function()
            local key
            return function()
                local data = Resolve(read())
                if type(data) ~= "table" then
                    return nil
                end
                key = next(data, key)
                if key ~= nil then
                    return key, ReadChild(key)
                end
                return nil
            end
        end,
    }))
    readers[proxy] = read
    return table.freeze(proxy)
end

--- 只复制第一层；嵌套表使用只读 View，避免标准浅拷贝泄露可写存档引用。
--- 第一层修改仅影响副本；要生效必须 SetTable/Set 提交，嵌套编辑请使用深拷贝。
--- @param value any 字段当前值或 View。
--- @return any 第一层可编辑、嵌套只读的副本；标量原样返回。
function Access.ShallowCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local view = readers[value] and value or Access.View(function()
        return value
    end)
    local copy = {}
    for key, child in view do
        copy[key] = child
    end
    return copy
end

return Access
