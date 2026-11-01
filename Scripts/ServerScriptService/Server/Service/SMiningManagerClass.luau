-- 公共矿场权威状态：定时整批替换，玩家共享次数，发奖失败不消耗矿石次数。
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local FX = _G.FX
local Settings = FX.Loader:RequireShared("Scripts.Game.Shared.MiningSettings")
local Config = _G.GameConfig.CommonConfig
local Manager = FX.Class("SMiningManagerClass", "FXObjectBaseClass")

--- 启动前核对配置，所有运行时石头放在 Decorations，不改地图块。
function Manager:Ctor()
    Manager.Super.Ctor(self)
    assert(Config.MiningRefreshInterval > 0, "MiningRefreshInterval must be positive")
    assert(Config.MiningSpawnCount > 0 and Config.MiningSpawnCount % 1 == 0, "Invalid MiningSpawnCount")
    assert(Config.MiningRockHits > 0 and Config.MiningRockHits % 1 == 0, "Invalid MiningRockHits")
    assert(Config.MiningSpawnProbability >= 0 and Config.MiningSpawnProbability <= 1, "Invalid MiningSpawnProbability")
    assert(Config.MiningOrePerHit > 0 and Config.MiningOrePerHit % 1 == 0, "Invalid MiningOrePerHit")
    assert(Config.FurnaceOreCost > 0 and Config.FurnaceOreCost % 1 == 0, "Invalid FurnaceOreCost")
    self._ground = FX.Loader:Workspace(Settings.GroundPath)
    self._furnace = FX.Loader:Workspace(Settings.FurnacePath)
    self._random = Random.new()
    self._rocks = {}
    self._folder = Instance.new("Folder")
    self._folder.Name = "PublicMiningRocks"
    self._folder.Parent = FX.Loader:Workspace("Decorations")
    self:Refresh()
    self._heartbeat = RunService.Heartbeat:Connect(function()
        if workspace:GetServerTimeNow() >= self._nextRefresh then
            self:Refresh()
        end
    end)
end

--- 每轮清掉旧石头；概率独立作用于每个刷新位，不累计残留石头。
function Manager:Refresh()
    table.clear(self._rocks)
    self._folder:ClearAllChildren()
    local radius = math.min(self._ground.Size.Y, self._ground.Size.Z) / 2 - 4
    local center = self._ground.Position + Vector3.new(0, self._ground.Size.X / 2 + 1.5, 0)
    local phase = self._random:NextNumber(0, math.pi * 2)
    for slot = 1, Config.MiningSpawnCount do
        if self._random:NextNumber() < Config.MiningSpawnProbability then
            local angle = phase + (slot - 1) * math.pi * 2 / Config.MiningSpawnCount
            local distance = self._random:NextNumber(radius * 0.35, radius)
            local rock = Instance.new("Part")
            rock.Name = "Rock_" .. slot
            rock.Shape = Enum.PartType.Ball
            rock.Size = Vector3.new(4, 3, 4)
            rock.Position = center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
            rock.Color = Color3.fromRGB(99, 103, 110)
            rock.Material = Enum.Material.Slate
            rock.Anchored = true
            rock.CanTouch = false
            rock:SetAttribute("RemainingHits", Config.MiningRockHits)
            self._rocks[rock] = Config.MiningRockHits
            rock.Parent = self._folder
            CollectionService:AddTag(rock, Settings.RockTag)
        end
    end
    self._nextRefresh = workspace:GetServerTimeNow() + Config.MiningRefreshInterval
    FX.SyncManager:SetNumber(_G.ServerDataConfig.MiningNextRefresh, self._nextRefresh)
end

--- 不等待、不让出执行；同一石头的扣次和背包发奖在本次回调中完成。
--- @param player table 已登录的服务端玩家对象。
--- @param position Vector3 服务端读取的当前角色位置。
--- @param rock any 客户端提交的节点，只接受本轮登记的石头。
--- @return boolean 是否完成一次挖取。
function Manager:Mine(player, position, rock)
    if typeof(rock) ~= "Instance" then
        return false
    end
    local hits = self._rocks[rock]
    if not hits or hits <= 0 or rock.Parent ~= self._folder
        or workspace:GetServerTimeNow() >= self._nextRefresh
        or (position - rock.Position).Magnitude > Settings.InteractDistance then
        return false
    end
    local reward = player:RequireComponent("FSRewardComp")
    if not reward:AddRewards({{Type = "Item", ItemId = Config.MiningOreItemId, Count = Config.MiningOrePerHit}}) then
        return false
    end
    hits -= 1
    if hits == 0 then
        self._rocks[rock] = nil
        rock:Destroy()
    else
        self._rocks[rock] = hits
        rock:SetAttribute("RemainingHits", hits)
    end
    return true
end

--- 火炉只做一次原子兑换，不引入锻造台小游戏或客户端指定配方。
--- @param player table 已登录的服务端玩家对象。
--- @param position Vector3 服务端读取的角色位置。
--- @return boolean 是否扣矿并获得剑。
function Manager:Smelt(player, position)
    if Settings.DistanceToPart(self._furnace, position) > Settings.InteractDistance then
        return false
    end
    return player:RequireComponent("FSRewardComp"):ExchangeRewards(
        {{Type = "Item", ItemId = Config.MiningOreItemId, Count = Config.FurnaceOreCost}},
        {{Type = "Item", ItemId = Config.FurnaceSwordItemId, Count = 1}}
    )
end

--- 关闭矿场时断开刷新并删除本服务创建的节点。
function Manager:Dtor()
    self._heartbeat:Disconnect()
    self._folder:Destroy()
    Manager.Super.Dtor(self)
end

return Manager
