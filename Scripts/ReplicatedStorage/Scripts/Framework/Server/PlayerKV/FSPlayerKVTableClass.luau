local FX, FS = _G.FX, _G.FS
local Access = require(script.Parent.FSPlayerDataAccess)
local FSPlayerKVTableClass = FX.Class("FSPlayerKVTableClass")
FS.PlayerKVTableClass = FSPlayerKVTableClass
--- @param db table 持有完整玩家档案的 DB。
--- @param kvType string 数据域名。
function FSPlayerKVTableClass:Ctor(db, kvType)
    self._db = db
    self._kvType = kvType
    self._table = db._data[kvType]
end
--- 只向外部暴露冻结的方法句柄，不能经 GetKVTable 取得 _db/_table。
--- @return table KV 公开接口；Get/GetDeep 返回深拷贝，Shallow 返回安全浅拷贝，View 返回只读代理。
function FSPlayerKVTableClass:GetHandle()
    if not self._handle then
        local handle = {}
        for index, name in ipairs({
            "IsLoaded", "Save", "SaveAsync", "Set", "SetDeep", "Get", "GetDeep",
            "GetShallow", "GetDeepShallow", "GetView", "GetDeepView", "Clear",
        }) do
            -- publicHandle 仅为冒号调用的外部接收者，转发固定使用内部 KV 对象。
            handle[name] = function(publicHandle, ...)
                return self[name](self, ...)
            end
        end
        self._handle = table.freeze(handle)
    end
    return self._handle
end
--- @return boolean 父档案是否可读写。
function FSPlayerKVTableClass:IsLoaded()
    return self._db:IsLoadFinished()
end
--- @return boolean 保存完整玩家档案的结果。
function FSPlayerKVTableClass:Save()
    return self._db:Save(false)
end
FSPlayerKVTableClass.SaveAsync = FSPlayerKVTableClass.Save
--- 复制入参后写入一级字段；不保留调用方的可写引用，释放后的旧句柄拒绝写入。
--- @param key string 不含点号的字段名。
--- @param value any 支持持久化的字段值。
--- @return boolean 是否完成内存写入。
function FSPlayerKVTableClass:Set(key, value)
    if not self:IsLoaded() then
        return false
    end
    if FX.IsDebugMode() and (type(key) ~= "string" or string.find(key, "%.")) then
        FX.ErrorWithTraceback(
            string.format("FSPlayerKVTableClass:Set %s invalid parameter 'key': %s", self._kvType, key)
        )
    end

    self._table[key] = Access.DeepCopy(value)
    self:MakeDataDirty()
    return true
end

--- 写入 KV 表的深层字段；路径中间节点不存在时会创建 table。
--- @param path string 点号分割路径，至少包含两级字段。
--- @param value any 可被 KV V2 序列化的 Lua 值。
--- @return boolean 是否完成内存写入；释放后的旧句柄返回 false。
function FSPlayerKVTableClass:SetDeep(path, value)
    if not self:IsLoaded() then
        return false
    end
    if type(path) ~= "string" then
        FX.ErrorWithTraceback("FSPlayerKVTableClass:SetDeep invalid parameter 'path'")
    end
    -- 分割路径
    local keys = {}
    for key in string.gmatch(path, "[^%.]+") do
        table.insert(keys, key)
    end

    if FX.IsDebugMode() and #keys < 2 then
        FX.ErrorWithTraceback(
            string.format("FSPlayerKVTableClass:SetDeep %s invalid parameter 'path': %s", self._kvType, path)
        )
    end

    local data = self._table
    for i = 1, #keys - 1 do
        local key = keys[i]
        if data[key] == nil then
            data[key] = {}
        end
        data = data[key]
    end
    data[keys[#keys]] = Access.DeepCopy(value)
    self:MakeDataDirty()
    return true
end

--- 读取 KV 表的一级字段；表值返回深拷贝，修改不会写回，必须通过 Set 提交。
--- @param key string 一级字段名，不允许包含点号。
--- @param defVal any 字段不存在时返回的默认值。
--- @return any 字段值或默认值。
function FSPlayerKVTableClass:Get(key, defVal)
    return Access.DeepCopy(self:GetView(key, defVal))
end

--- 只复制一级字段的第一层，嵌套表仍只读；提交规则同 Set。
--- @param key string 一级字段名。
--- @param defVal any 字段不存在时的默认值。
--- @return any 安全浅拷贝或标量。
function FSPlayerKVTableClass:GetShallow(key, defVal)
    return Access.ShallowCopy(self:GetView(key, defVal))
end

--- 读取一级字段的实时只读 View；所有层级写入均报错，不修改存档。
--- @param key string 一级字段名。
--- @param defVal any 字段不存在时的默认值。
--- @return any 只读 View 或标量；View 遍历使用 for key, value in view do。
function FSPlayerKVTableClass:GetView(key, defVal)
    if FX.IsDebugMode() and (type(key) ~= "string" or string.find(key, "%.")) then
        FX.ErrorWithTraceback(
            string.format("FSPlayerKVTableClass:Set %s invalid parameter 'key': %s", self._kvType, key)
        )
    end
    --- 读取一级路径，保留 false 等有效标量。
    --- @return any 字段当前值或默认值。
    local function Read()
        local value = self._table[key]
        if value == nil then
            return defVal
        end
        return value
    end
    local value = Read()
    return type(value) == "table" and Access.View(Read) or value
end

--- 读取 KV 表的深层字段；表值返回深拷贝，修改后必须 SetDeep 提交。
--- @param path string 点号分割路径，至少包含两级字段。
--- @param defVal any 路径不存在时返回的默认值。
--- @return any 字段值或默认值。
function FSPlayerKVTableClass:GetDeep(path, defVal)
    return Access.DeepCopy(self:GetDeepView(path, defVal))
end

--- 只复制深层字段值的第一层；嵌套表返回只读 View。
--- @param path string 至少两级的点分路径。
--- @param defVal any 路径不存在时的默认值。
--- @return any 安全浅拷贝或标量。
function FSPlayerKVTableClass:GetDeepShallow(path, defVal)
    return Access.ShallowCopy(self:GetDeepView(path, defVal))
end

--- 读取深层字段的实时只读 View，不深拷贝；任意层级写入均报错且不修改存档。
--- @param path string 至少两级的点分路径。
--- @param defVal any 路径不存在时的默认值。
--- @return any 只读 View 或标量；View 不支持 pairs/ipairs/next/table.*，使用 Luau 通用遍历。
function FSPlayerKVTableClass:GetDeepView(path, defVal)
    local keys = {}
    for key in string.gmatch(path, "[^%.]+") do
        table.insert(keys, key)
    end

    if FX.IsDebugMode() and #keys < 2 then
        FX.ErrorWithTraceback(
            string.format("FSPlayerKVTableClass:GetDeep %s invalid parameter 'path': %s", self._kvType, path)
        )
    end

    --- 逐层读取当前路径，不缓存可被后续提交替换的嵌套表。
    --- @return any 字段当前值或默认值。
    local function Read()
        local data = self._table
        for index, key in ipairs(keys) do
            if type(data) ~= "table" or data[key] == nil then
                return defVal
            end
            data = data[key]
        end
        return data
    end
    local value = Read()
    return type(value) == "table" and Access.View(Read) or value
end

--- 清空当前 KV 表内容并标记为需要保存。
--- @return boolean 是否已清空；释放后的旧句柄返回 false。
function FSPlayerKVTableClass:Clear()
    if not self:IsLoaded() then
        return false
    end
    table.clear(self._table)
    self:MakeDataDirty()
    return true
end

--- 标记数据已变更，并通知管理器加入保存队列。
--- @return nil
function FSPlayerKVTableClass:MakeDataDirty()
    self._db._revision += 1
end
return FSPlayerKVTableClass
