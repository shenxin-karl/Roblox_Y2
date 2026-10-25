_G.FS.Events = {
    -- 玩家数据加载完成: function(player)
    OnPlayerDataLoadFinished = Instance.new("BindableEvent"),
    -- 玩家数据加载失败: function(playerId)
    OnPlayerDataLoadFailed = Instance.new("BindableEvent"),
    -- 玩家数据保存开始: function(playerId)
    OnPlayerDataSaveStarted = Instance.new("BindableEvent"),

    -- 玩家准备就绪: function(player) 数据加载完成, 客户端准备就绪
    OnPlayerReady = Instance.new("BindableEvent"),
}

return true
