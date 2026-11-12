-- 服务器共享数据字段：{ Type = "number"/"boolean"/"table", DefVal = 默认值, Key = 唯一键 }。
-- 将字段定义传给 FX.SyncManager 的读写、监听接口；服务端修改后由框架自动同步。
return {
    -- 以字符串基地编号索引本服归属和进度；场景实例、连接与冷却不参与同步。
    Bases = {Type = "table", Key = "Bases", DefVal = {}},
}
