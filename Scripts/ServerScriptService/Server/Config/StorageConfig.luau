local RunService = game:GetService("RunService")

return {
    -- 模板默认用内存存档试玩；正式接入云存档时关闭，停止试玩后测试数据清空。
    StudioMemory = true,
    -- 新项目在首次发布前确认名称；与源项目存档隔离，Studio 云存档也单独命名。
    DataStoreName = RunService:IsStudio() and "RobloxTemplate_Player_Studio_v1" or "RobloxTemplate_Player_v1",
    AutoSaveSeconds = RunService:IsStudio() and 60 or 20,
    SessionLockEnabled = not RunService:IsStudio(),
    SessionLeaseSeconds = 60,
}
