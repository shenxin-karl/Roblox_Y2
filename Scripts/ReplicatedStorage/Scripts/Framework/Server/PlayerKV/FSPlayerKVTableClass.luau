local FX, FS = _G.FX, _G.FS
local FSPlayerKVTableClass = FX.Class("FSPlayerKVTableClass")
FS.PlayerKVTableClass = FSPlayerKVTableClass
--- @param db table 持有完整玩家档案的 DB。
--- @param kvType string 数据域名。
function FSPlayerKVTableClass:Ctor(db, kvType)
    self._db = db
    self._kvType = kvType
    self._table = db._data[kvType]
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
--- @param key string 不含点号的字段名。
--- @param value any 支持持久化的字段值。
--- @return boolean 是否完成内存写入。
function FSPlayerKVTableClass:Set(key, value)
    if FX.IsDebugMode() and (type(key) ~= "string" or string.find(key, "%.")) then
        FX.ErrorWithTraceback(
            string.format("FSPlayerKVTableClass:Set %s invalid parameter 'key': %s", self._kvType, key)
        )
    end

    self._table[key] = value
    self:MakeDataDirty()
    return true
end

--- 写入 KV 表的深层字段；路径中间节点不存在时会创建 table。
--- @param path string 点号分割路径，至少包含两级字段。
--- @param value any 可被 KV V2 序列化的 Lua 值。
--- @return nil
function FSPlayerKVTableClass:SetDeep(path, value)
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
    data[keys[#keys]] = value
    self:MakeDataDirty()
end

--- 读取 KV 表的一级字段。
--- @param key string 一级字段名，不允许包含点号。
--- @param defVal any 字段不存在时返回的默认值。
--- @return any 字段值或默认值。
function FSPlayerKVTableClass:Get(key, defVal)
    if FX.IsDebugMode() and (type(key) ~= "string" or string.find(key, "%.")) then
        FX.ErrorWithTraceback(
            string.format("FSPlayerKVTableClass:Set %s invalid parameter 'key': %s", self._kvType, key)
        )
    end
    local val = self._table[key]
    if val == nil then
        return defVal
    end
    return val
end

--- 读取 KV 表的深层字段。
--- @param path string 点号分割路径，至少包含两级字段。
--- @param defVal any 路径不存在时返回的默认值。
--- @return any 字段值或默认值。
function FSPlayerKVTableClass:GetDeep(path, defVal)
    local keys = {}
    for key in string.gmatch(path, "[^%.]+") do
        table.insert(keys, key)
    end

    if FX.IsDebugMode() and #keys < 2 then
        FX.ErrorWithTraceback(
            string.format("FSPlayerKVTableClass:GetDeep %s invalid parameter 'path': %s", self._kvType, path)
        )
    end

    local data = self._table
    for _, key in ipairs(keys) do
        if data[key] == nil then
            return defVal
        end
        data = data[key]
    end
    if data == nil then
        data = defVal
    end
    return data
end

--- 清空当前 KV 表内容并标记为需要保存。
--- @return nil
function FSPlayerKVTableClass:Clear()
    table.clear(self._table)
    self:MakeDataDirty()
end

--- 标记数据已变更，并通知管理器加入保存队列。
--- @return nil
function FSPlayerKVTableClass:MakeDataDirty()
    self._db._revision += 1
end
return FSPlayerKVTableClass
