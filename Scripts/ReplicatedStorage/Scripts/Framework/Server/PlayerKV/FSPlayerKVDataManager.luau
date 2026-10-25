local FX, FS = _G.FX, _G.FS
local Players = game:GetService("Players")
local Config = require(game:GetService("ServerScriptService").Server.Config.StorageConfig)
require(script.Parent.FSPlayerKVTableClass)
require(script.Parent.FSPlayerKVDBClass)
local Manager = { _playerDBMap = {}, _closing = {} }
FS.PlayerKVDataManager = Manager

--- 周期保存玩家数据并续约正式服锁；玩家事件由 FServer 在通用服务初始化后连接。
function Manager:Init()
    self._timer = FX.Task:Interval(Config.AutoSaveSeconds, function()
        for id, db in pairs(self._playerDBMap) do
            if db:IsLoadFinished() and not self._closing[id] then
                task.spawn(function()
                    if not db:Save(false) then
                        local player = Players:GetPlayerByUserId(id)
                        if player and not FX.IsDeveloper(id) then
                            player:Kick("存档暂时不可用，请稍后重试")
                        end
                    end
                end)
            end
        end
    end)
end

--- @param player Player 进入服务器的玩家。
function Manager:PlayerAdded(player)
    if self._playerDBMap[player.UserId] then
        return
    end

    local db = FS.PlayerKVDBClass.New(player.UserId)
    self._playerDBMap[player.UserId] = db
    db:LoadAsync()
end

--- @param player Player 离开服务器的玩家；也用于关闭服务器。
function Manager:PlayerRemoving(player)
    local id = player.UserId
    if self._closing[id] then
        while self._closing[id] do
            task.wait()
        end

        return
    end

    local db = self._playerDBMap[id]
    if not db then
        return
    end

    self._closing[id] = true
    db._leaving = true
    if FS.PlayerManager then
        FS.PlayerManager:OnPlayerLogout(id)
    end

    FS.Events.OnPlayerDataSaveStarted:Fire(id)
    FS.RankingManager:OnPlayerDataSaveStarted(id)
    if db:IsLoadFinished() then
        for attempt = 1, 3 do
            if db:Save(true) then
                break
            end

            task.wait(attempt)
        end
    end

    self._playerDBMap[id] = nil
    self._closing[id] = nil
end

--- @param id number 玩家 ID。
--- @param name string KV 数据域。
--- @return table 已加载的 KV 视图。
function Manager:GetKVTable(id, name)
    local db = self._playerDBMap[id]
    return db and db:GetKVTable(name)
end

return Manager
