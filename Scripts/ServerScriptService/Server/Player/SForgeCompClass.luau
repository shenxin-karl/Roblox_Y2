-- 玩家锻造区会话：校验距离与角色，持有一个台位，并在死亡或离服时释放。
local FX = _G.FX
local Fields = _G.PlayerDataConfig
local Settings = FX.Loader:RequireShared("Scripts.Game.Shared.ForgeSettings")
local Rules = FX.Loader:RequireShared("Scripts.Game.Shared.SwordRules")
local WorkshopRules = FX.Loader:RequireShared("Scripts.Game.Shared.UpgradeWorkshopRules")
local Comp = FX.Class("SForgeCompClass", "FSPlayerCompClass")

--- 每次登录重新分配会话，不将台位写入存档。
--- @param owner table 当前服务端玩家对象。
function Comp:Ctor(owner)
    Comp.Super.Ctor(self, owner)
    self._manager = _G.SForgeManager
    self._lastRequest = -math.huge
    self._lastForge = -math.huge
    self._random = Random.new()
end

--- 敲击与主动出炉共用服务端台位校验，离开台位或失去基地归属时拒绝操作。
--- @return boolean 是否仍有权在当前台位操作。
function Comp:CanUseStation()
    local character, humanoid = self:GetLivingCharacter()
    local station = self._station
    local userId = self:GetPlayerId()
    return character ~= nil and station ~= nil and station.OwnerUserId == userId
        and (not station.Base or station.Base.OwnerUserId == userId)
        and (humanoid.RootPart.Position - station.Arrival.Position).Magnitude <= 8
end

--- 每次请求只敲一锤，剑胚先进入持久化进度；所有概率与结果均由服务端裁定。
function Comp:ForgeSword()
    local station = self._station
    if os.clock() - self._lastForge < Settings.RequestCooldown then
        return
    end
    self._lastForge = os.clock()
    if self:CanUseStation() then
        local data = self:GetTable(Fields.ForgeData)
        if not data.Active then
            local inventory = self:RequireComponent("FSInventoryComp")
            local items = self:GetTable(Fields.Inventory)
            local grid = inventory:GetEquippedGrid()
            if not grid or not items[tostring(grid)] or items[tostring(grid)].itemId ~= Rules.BlankItemId then
                grid = inventory:FindItemById(Rules.BlankItemId)
            end
            local item = grid and items[tostring(grid)]
            local traits = item and Rules.GetTraits(item.extraData)
            if not traits or item.stackCount ~= 1 then
                FX.Network:SendMsgToClient(self:GetPlayerId(), "S2C_ForgeSwordResult", station.Id, false)
                return
            end
            local forgeLevel = WorkshopRules.GetLevel(self:GetTableView(Fields.UpgradeWorkshop).forge)
            data = {Active = true, Finished = false, MutationId = traits.MutationId,
                blankLuckLevel = traits.blankLuckLevel, forgeLevel = forgeLevel,
                Quality = math.max(1, forgeLevel - 4), HammerCount = 0}
            items[tostring(grid)] = nil
            if not self:GetPlayerObject():RunDataTransaction(function()
                return self:SetTable(Fields.Inventory, items) and self:SetTable(Fields.ForgeData, data)
            end) then
                return
            end
        end
        if data.Finished then
            self:FinishSword()
            return
        end
        local probabilities = Rules.GetForgeProbabilities(data.blankLuckLevel, data.forgeLevel, data.Quality)
        local roll = self._random:NextNumber(0, 100)
        data.HammerCount += 1
        if roll < probabilities.success then
            data.Quality += 1
            data.Outcome = "Success"
            data.Finished = data.Quality >= data.forgeLevel + 4
        elseif roll < probabilities.success + probabilities.unchanged then
            data.Outcome = "Unchanged"
        elseif roll < probabilities.success + probabilities.unchanged + probabilities.broken then
            data.Outcome, data.Finished = "Broken", true
        else
            data.Outcome, data.Active, data.Finished = "Destroyed", false, true
        end
        self:SetTable(Fields.ForgeData, data)
        if data.Finished and data.Active then
            self:FinishSword()
        end
        FX.Network:SendMsgToClient(self:GetPlayerId(), "S2C_ForgeSwordResult", station.Id, true)
    end
end

--- 主动出炉或领取已结束成品；满背包时保留原结果，不能再次抽取概率。
--- @return boolean 是否成功领取一把成品。
function Comp:FinishSword()
    if not self:CanUseStation() then
        return false
    end
    local data = self:GetTable(Fields.ForgeData)
    if not data.Active then
        return false
    end
    data.Finished = true
    self:SetTable(Fields.ForgeData, data)
    return self:GetPlayerObject():RunDataTransaction(function()
        if not self:RequireComponent("FSRewardComp"):AddRewards({{Type = "Item", ItemId = Rules.ItemId, Count = 1,
            ExtraData = {MutationId = data.MutationId, blankLuckLevel = data.blankLuckLevel,
                Quality = data.Quality, Level = 1, StoredMoney = 0}}}) then
            return false
        end
        data.Active = false
        data.Outcome = data.Outcome == "Broken" and "Broken" or "Finished"
        return self:SetTable(Fields.ForgeData, data)
    end)
end

--- 返回玩家组件协作名。
--- @return string 锻造组件名称。
function Comp:GetCompName()
    return "SForgeComp"
end

--- 握手完成后才接受交互，换角色时释放旧角色的台位。
function Comp:OnPlayerLogin()
    self._active = true
    self:TrackConnection(self:GetPlayerNode().CharacterRemoving:Connect(function()
        self:Release()
    end))
end

--- 只允许当前会话的存活角色发起传送，不等待或复用旧角色节点。
--- @return Model? 当前有效角色。
--- @return Humanoid? 当前存活角色控制器。
function Comp:GetLivingCharacter()
    local player = self:GetPlayerNode()
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if self._active and humanoid and humanoid.Health > 0 and humanoid.RootPart then
        return character, humanoid
    end
    return nil
end

--- 传送后清除原角色速度，避免高速进入时撞上台面或滑出通道。
--- @param character Model 服务端校验过的当前角色。
--- @param humanoid Humanoid 当前角色控制器。
--- @param target CFrame 服务端固定的目标落点。
function Comp:Teleport(character, humanoid, target)
    humanoid.Sit = false
    character:PivotTo(target)
    humanoid.RootPart.AssemblyLinearVelocity = Vector3.zero
    humanoid.RootPart.AssemblyAngularVelocity = Vector3.zero
end

--- 顶部导航前往庭院入口，复用角色校验、节流与固定落点，并释放原台位。
function Comp:TeleportToArea()
    local character, humanoid = self:GetLivingCharacter()
    if not character or os.clock() - self._lastRequest < Settings.RequestCooldown then
        return
    end
    self._lastRequest = os.clock()
    self:Teleport(character, humanoid, self._manager:GetExit())
    self:Release()
end

--- 优先进入身旁的本人锻造台；公共庭院仍随机分配空台位。
function Comp:Enter()
    local character, humanoid = self:GetLivingCharacter()
    if not character or self._station or os.clock() - self._lastRequest < Settings.RequestCooldown then
        return
    end
    self._lastRequest = os.clock()
    local position = humanoid.RootPart.Position
    local base = self:RequireComponent("SBaseComp"):GetBase()
    local station = self._manager:GetPersonalStation(base, self:GetPlayerId(), position)
    if not station and self._manager:IsNear(position) then
        station = self._manager:Allocate(self:GetPlayerId())
    end
    if not station then
        return
    end
    self._station = station
    self._deathConnection = humanoid.Died:Connect(function()
        self:Release()
    end)
    self:Teleport(character, humanoid, station.Arrival)
    self:SetNumber(Fields.ForgeStation, station.Id)
end

--- 私人台退出后留在原地；公共台退出时回庭院入口并归还空台位。
function Comp:Leave()
    local character, humanoid = self:GetLivingCharacter()
    if not character or not self._station or os.clock() - self._lastRequest < Settings.RequestCooldown then
        return
    end
    self._lastRequest = os.clock()
    if not self._station.Base then
        self:Teleport(character, humanoid, self._manager:GetExit())
    end
    self:Release()
end

--- 清理台位、死亡监听与同步状态；多次调用不会释放别人的台位。
function Comp:Release()
    if self._deathConnection then
        self._deathConnection:Disconnect()
        self._deathConnection = nil
    end
    self._manager:Release(self:GetPlayerId())
    if self._station then
        self._station = nil
        self:SetNumber(Fields.ForgeStation, 0)
    end
end

--- 停止交互并释放台位，不在离服时传送角色。
function Comp:OnPlayerLogout()
    self._active = false
    self:Release()
end

--- 覆盖异常销毁路径，仍由基类清理其余连接。
function Comp:Dtor()
    self:OnPlayerLogout()
    Comp.Super.Dtor(self)
end

return Comp
