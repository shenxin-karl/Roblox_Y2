-- 本服锻造台占用管理：只分配现有八台，不克隆模型，不保存跨服占用。
local FX = _G.FX
local FXLoader = FX.Loader
local Settings = FXLoader:RequireShared("Scripts.Game.Shared.ForgeSettings")
local Manager = FX.Class("SForgeManagerClass")

--- 按已核对的桌面朝向缓存中央通道侧落点，避免把玩家放到桌面或桌腿内。
function Manager:Ctor()
    self._area = FXLoader:Workspace(Settings.AreaPath)
    self._stations, self._owners = {}, {}
    self._random = Random.new()
    local forge = FXLoader:Workspace(Settings.StationPath)
    local height = self._area.Position.Y + self._area.Size.Y / 2 + Settings.ArrivalHeight
    for sideIndex, side in ipairs({"Lower", "Upper"}) do
        for index = 1, 4 do
            local model = FXLoader:Here(forge, side .. "_" .. index)
            local desktop = FXLoader:Here(model, "ThickSteelDesktop")
            local front = desktop.CFrame * CFrame.new(0, 0, -desktop.Size.Z / 2 - Settings.StationClearance)
            local position = Vector3.new(front.Position.X, height, front.Position.Z)
            local target = Vector3.new(desktop.Position.X, height, desktop.Position.Z)
            local id = (sideIndex - 1) * 4 + index
            self._stations[id] = {Id = id, Arrival = CFrame.lookAt(position, target)}
        end
    end
    self._exit = self._area.CFrame * CFrame.new(
        -self._area.Size.X / 2 + Settings.ExitInset, self._area.Size.Y / 2 + Settings.ArrivalHeight, 0)
end

--- 服务端按庭院边界校验距离，与客户端按钮范围一致，但不信任客户端判断。
--- @param position Vector3 当前角色根节点位置。
--- @return boolean 是否在锻造区临时交互范围内。
function Manager:IsNear(position)
    local offset = self._area.CFrame:PointToObjectSpace(position)
    return math.abs(offset.X) <= self._area.Size.X / 2 + Settings.ShowDistance
        and math.abs(offset.Z) <= self._area.Size.Z / 2 + Settings.ShowDistance
        and math.abs(offset.Y - self._area.Size.Y / 2) <= Settings.HeightTolerance
end

--- 无让出的分配过程保证多人请求不争用同一台；同一玩家重复分配返回原台。
--- @param userId number 已认证玩家 ID。
--- @return table? 当前台位，满员返回 nil。
function Manager:Allocate(userId)
    if self._owners[userId] then
        return self._owners[userId]
    end
    local free = {}
    for index, station in ipairs(self._stations) do
        if not station.OwnerUserId then
            table.insert(free, station)
        end
    end
    if #free == 0 then
        return nil
    end
    local station = free[self._random:NextInteger(1, #free)]
    station.OwnerUserId = userId
    self._owners[userId] = station
    return station
end

--- 离开、死亡和离服共用幂等释放，不影响其他玩家的台位。
--- @param userId number 要释放的玩家 ID。
function Manager:Release(userId)
    local station = self._owners[userId]
    if station then
        station.OwnerUserId = nil
        self._owners[userId] = nil
    end
end

--- 返回庭院入口内侧的中央通道落点，避开两排桌面和后方火炉。
--- @return CFrame 服务端固定离开落点。
function Manager:GetExit()
    return self._exit
end

return Manager
