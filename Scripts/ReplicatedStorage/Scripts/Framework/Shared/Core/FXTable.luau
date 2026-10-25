local FX = _G.FX
local FXTable = {}
_G.FX.Table = FXTable

--- 将表转换为可读的字符串表示（用于调试）
--- @param tbl table 要转换的表
--- @param indent number 当前缩进层级（内部使用）
--- @param visited table 已访问表集合，用于防止循环引用（内部使用）
--- @return string 表的字符串表示
function FXTable:ToString(tbl, indent, visited)
    if type(tbl) ~= "table" then
        return tostring(tbl)
    end

    indent = indent or 0
    visited = visited or {}

    -- 防止循环引用
    if visited[tbl] then
        return "{...}"
    end
    visited[tbl] = true

    local spaces = string.rep("  ", indent)
    local result = "{\n"

    local count = 0
    local numericKeys = 0

    -- 先处理数字键值对（保持顺序）
    for i = 1, #tbl do
        if tbl[i] ~= nil then
            count = count + 1
            numericKeys = numericKeys + 1
            local valueStr = self:ToString(tbl[i], indent + 1, visited)
            result = result .. spaces .. "  " .. valueStr

            if count < self:Length(tbl) then
                result = result .. ","
            end
            result = result .. "\n"
        end
    end

    -- 再处理非数字键值对
    for k, v in pairs(tbl) do
        if type(k) ~= "number" or k < 1 or k > #tbl then
            count = count + 1
            local keyStr = self:FormatKey(k)
            local valueStr = self:ToString(v, indent + 1, visited)
            result = result .. spaces .. "  " .. keyStr .. " = " .. valueStr

            if count < self:Length(tbl) then
                result = result .. ","
            end
            result = result .. "\n"
        end
    end

    result = result .. spaces .. "}"
    visited[tbl] = nil
    return result
end

--- 解包列表为多个返回值（兼容 Lua 5.1 无 table.unpack 的情况）
--- @param list table 要解包的列表
--- @param i number 起始索引（可选）
--- @param j number 结束索引（可选）
--- @return any 解包后的多个返回值
function FXTable:Unpack(list, i, j)
    if table.unpack then
        return table.unpack(list, i or 1, j or list.n or #list)
    end
    i = i or 1
    j = j or #list
    if i <= j then
        return list[i], self:Unpack(list, i + 1, j)
    end
end

--- 格式化键值用于字符串显示（合法标识符直接返回，否则用方括号包裹）
--- @param key any 表的键
--- @return string 格式化后的键字符串
function FXTable:FormatKey(key)
    if type(key) == "string" and string.match(key, "^[a-zA-Z_][a-zA-Z0-9_]*$") then
        return key
    else
        return "[" .. tostring(key) .. "]"
    end
end

--- 浅拷贝表（仅复制第一层，引用类型仍共享）
--- @param orig table 原始表
--- @return table 拷贝后的新表
function FXTable:Copy(orig)
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = v
    end
    return copy
end

--- 深拷贝表（递归复制所有层级，包括元表）
--- @param tbl table 原始表
--- @return table 拷贝后的新表
function FXTable:DeepCopy(tbl)
    if type(tbl) ~= "table" then
        return tbl
    end
    local copy = {}
    for key, value in pairs(tbl) do
        copy[self:DeepCopy(key)] = self:DeepCopy(value)
    end
    -- 保持元表
    local mt = getmetatable(tbl)
    if mt then
        setmetatable(copy, self:DeepCopy(mt))
    end
    return copy
end

--- 对表中所有值求和（适用于值为数字的表）
--- @param t table 要求和的表
--- @return number 求和结果
function FXTable:Sum(t)
    local sum = 0
    for k, v in pairs(t) do
        sum = sum + v
    end
    return sum
end

--- 按指定字段求和表中所有元素的该字段值
--- @param t table 表（元素为表，需包含 fieldName 字段）
--- @param fieldName string 要求和数字的字段名
--- @return number 求和结果
function FXTable:SumByField(t, fieldName)
    local sum = 0
    for k, v in pairs(t) do
        sum = sum + v[fieldName]
    end
    return sum
end

--- 追加表格，将 t2 的元素追加到 t1 的末尾（要求两个表都是数组）
--- @param t1 table 目标表（会被修改）
--- @param t2 table 要追加的表
--- @return table 返回 t1
function FXTable:Append(t1, t2)
    for i = 1, #t2 do
        table.insert(t1, t2[i])
    end
    return t1
end

--- 合并两个表，将 t2 的键值对合并到 t1（t2 的值会覆盖 t1 同键值）
--- @param t1 table 目标表（会被修改）
--- @param t2 table 源表
--- @return table 返回 t1
function FXTable:Merge(t1, t2)
    for k, v in pairs(t2) do
        t1[k] = v
    end
    return t1
end

--- 合并表格，仅当 t1 中不存在某键时，才从 t2 赋值过去（不覆盖已有值）
--- @param t1 table 目标表（会被修改）
--- @param t2 table 源表
--- @return table 返回 t1
function FXTable:MergeIfNotExists(t1, t2)
    for k, v in pairs(t2) do
        if t1[k] == nil then
            t1[k] = v
        end
    end
    return t1
end

--- 合并多个表，生成一个包含所有键值对的新表（后面的表会覆盖前面的同键值）
--- @param ... table 可变参数，多个要合并的表
--- @return table 合并后的新表
function FXTable:MergeMultiple(...)
    local result = {}
    for i = 1, select("#", ...) do
        local t = select(i, ...)
        if t then
            for k, v in pairs(t) do
                result[k] = v
            end
        end
    end
    return result
end

--- 清空表的所有键值对（表引用保留，内容清空）
--- @param t table 要清空的表
function FXTable:Clear(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

--- 获取表的元素个数（遍历所有键值对计数，与 #t 可能不同）
--- @param t table 要计数的表
--- @return number 表中键值对的数量
function FXTable:Length(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

--- 原地反转数组（仅对数字索引部分生效）
--- @param t table 要反转的表（会被修改）
--- @return table 返回 t
function FXTable:Reverse(t)
    local n = #t
    for i = 1, math.floor(n / 2) do
        t[i], t[n - i + 1] = t[n - i + 1], t[i]
    end
    return t
end

--- 过滤表，排除值等于 filterValue 的键值对
--- @param t table 原表
--- @param filterValue any 要过滤掉的值
--- @return table 过滤后的新表
function FXTable:Filter(t, filterValue)
    local result = {}
    for k, v in pairs(t) do
        if v ~= filterValue then
            result[k] = v
        end
    end
    return result
end

--- 按条件筛选表，保留 predicate(v, k) 返回 false 的键值对
--- @param t table 原表
--- @param predicate function 谓词函数 (v, k) -> boolean
--- @return table 筛选后的新表
function FXTable:FilterIf(t, predicate)
    local result = {}
    for k, v in pairs(t) do
        if not predicate(v, k) then
            result[k] = v
        end
    end
    return result
end

--- 判断表中是否包含指定值
--- @param t table 要查找的表
--- @param value any 要查找的值
--- @return boolean 是否包含
function FXTable:HasValue(t, value)
    for k, v in pairs(t) do
        if v == value then
            return true
        end
    end
    return false
end

--- 根据值查找对应的键
--- @param t table 要查找的表
--- @param value any 要查找的值
--- @return any 找到的键，未找到返回 nil
function FXTable:FindKeyByValue(t, value)
    for k, v in pairs(t) do
        if v == value then
            return k
        end
    end
    return nil
end

--- 根据条件查找，返回第一个满足 predicate(v, k) 的元素及其键
--- @param t table 要查找的表
--- @param predicate function 谓词函数 (v, k) -> boolean
--- @return any, any 找到的值和键，未找到返回 nil
function FXTable:FindIf(t, predicate)
    for k, v in pairs(t) do
        if predicate(v, k) then
            return v, k
        end
    end
    return nil
end

--- 根据元素的某个字段值查找，返回第一个 fieldName 等于 value 的元素及其键
--- @param t table 要查找的表（元素为表）
--- @param fieldName string 字段名
--- @param value any 要匹配的字段值
--- @return any, any 找到的元素和键，未找到返回 nil
function FXTable:FindByField(t, fieldName, value)
    for k, v in pairs(t) do
        if v[fieldName] == value then
            return v, k
        end
    end
    return nil
end

--- 判断表是否为空（无任何键值对）
--- @param t table 要检查的表
--- @return boolean 是否为空
function FXTable:Empty(t)
    return t ~= nil and next(t) == nil
end

--- 从数组中随机返回一个元素（基于 #t 的索引范围）
--- @param t table 数组表
--- @return any 随机选中的元素
function FXTable:Random(t)
    return t[math.random(1, #t)]
end

--- 按权重随机。表中每个元素为 {x, y} 结构，y 为权重，按权重随机返回一个元素
--- @param t table 数组表，元素需包含 y 字段表示权重
--- @return table 按权重随机选中的元素
function FXTable:RandomByVec2Weight(t)
    if not t or #t == 0 then
        FX.ErrorWithTraceback("FXTable:RandomByVec2Weight - t is nil or empty")
    end
    -- 计算总权重
    local totalWeight = 0
    for i = 1, #t do
        assert(t[i].y and t[i].y > 0, "FXTable:RandomByVec2Weight - t[i].y is nil")
        totalWeight = totalWeight + t[i].y
    end

    local randomValue = math.random(1, totalWeight)
    local currentWeight = 0
    for i = 1, #t do
        currentWeight = currentWeight + (t[i].y or 0)
        if randomValue <= currentWeight then
            return t[i]
        end
    end
    FX.ErrorWithTraceback("FXTable:RandomByVec2Weight - should not reach here") -- should never reach here
end

--- 为表设置 fallback，当访问不存在的键时从 fallback 中查找
--- @param t table 要设置的表
--- @param fallback table 回退表，当 t 中无某键时从此表查找
function FXTable:SetFallback(t, fallback)
    setmetatable(t, { __index = fallback })
    return t
end

return FXTable
