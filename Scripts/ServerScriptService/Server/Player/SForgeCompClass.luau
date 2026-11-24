-- 玩家锻造区会话：校验距离与角色，持有一个台位，并在死亡或离服时释放。
local HttpService = game:GetService("HttpService")
local FX = _G.FX
local Fields = _G.PlayerDataConfig
local Settings = FX.Loader:RequireShared("Scripts.Game.Shared.ForgeSettings")
local Rules = FX.Loader:RequireShared("Scripts.Game.Shared.SwordRules")
local WorkshopRules = FX.Loader:RequireShared("Scripts.Game.Shared.UpgradeWorkshopRules")
local TranslationTexts = FX.Text.Define("FinishSword", {
    Success = "Forged weapon added to your backpack.",
    Failed = "Couldn't collect your weapon. Check your backpack space and try again.",
    StationTooFar = "Move closer to a forge to start forging.",
    NeedBlank = "Equip a sword blank before using the forge.",
})
local Comp = FX.Class("SForgeCompClass", "FSPlayerCompClass")

--- 每次登录重新分配会话，不将台位写入存档。
--- @param owner table 当前服务端玩家对象。
function Comp:Ctor(owner)
    Comp.Super.Ctor(self, owner)
    self._manager = _G.SForgeManager
    self._lastRequest = -math.huge
    self._lastForge = -math.huge
    self._lastRecovery = -math.huge
    self._random = Random.new()
end

--- 敲击与主动出炉共用服务端台位校验，离开台位或失去基地归属时拒绝操作。
--- @return boolean 是否仍有权在当前台位操作。
function Comp:CanUseStation()
    local character, humanoid = self:GetLivingCharacter()
    local station = self._station
    local userId = self:GetPlayerId()
    return character ~= nil and station ~= nil and station.OwnerUserId == userId
        and station.Base.OwnerUserId == userId
        and (humanoid.RootPart.Position - station.Arrival.Position).Magnitude <= 8
end

--- 空台只接收角色实际装备的剑胚，库存消耗和锻造进度一起提交。
--- @return boolean 是否成功将该剑胚放上锻造台。
function Comp:PlaceEquippedBlank()
    local inventory = self:RequireComponent("FSInventoryComp")
    local items = self:GetTable(Fields.Inventory)
    local grid = inventory:GetEquippedGrid()
    local item = grid and items[tostring(grid)]
    local traits = item and item.itemId == Rules.BlankItemId and item.stackCount == 1
        and Rules.GetTraits(item.extraData)
    if not traits then
        return false
    end
    local forgeLevel = WorkshopRules.GetLevel(self:GetTableView(Fields.UpgradeWorkshop).forge)
    local data = {Active = true, Finished = false, MutationId = traits.MutationId,
        blankLuckLevel = traits.blankLuckLevel, forgeLevel = forgeLevel,
        Quality = math.max(1, forgeLevel - 4), HammerCount = 0}
    items[tostring(grid)] = nil
    return self:GetPlayerObject():RunDataTransaction(function()
        return self:SetTable(Fields.Inventory, items) and self:SetTable(Fields.ForgeData, data)
    end)
end

--- 只敲台上已有的武器，放剑胚不计作敲击或抽取结果。
function Comp:ForgeSword()
    local station = self._station
    if os.clock() - self._lastForge < Settings.RequestCooldown then
        return
    end
    self._lastForge = os.clock()
    if self:CanUseStation() then
        local data = self:GetTable(Fields.ForgeData)
        if not data.Active then
            return
        end
        if data.Finished then
            self:FinishSword()
            return
        end
        local probabilities = Rules.GetForgeProbabilities(data.blankLuckLevel, data.forgeLevel, data.Quality)
        local roll = self._random:NextNumber(0, 100)
        data.HammerCount += 1
        if self:GetPlayerNode():GetAttribute("GMGuaranteedForge") == true or roll < probabilities.success then
            data.Quality += 1
            data.Outcome = "Success"
            data.Finished = data.Quality >= data.forgeLevel + 4
        elseif roll < probabilities.success + probabilities.unchanged then
            data.Outcome = "Unchanged"
        elseif roll < probabilities.success + probabilities.unchanged + probabilities.broken then
            data.Outcome, data.Finished = "Broken", true
        else
            data.Outcome, data.Active, data.Finished = "Destroyed", false, true
            data.RecoveryId = HttpService:GenerateGUID(false)
        end
        self:SetTable(Fields.ForgeData, data)
        if data.Finished and data.Active then
            self:FinishSword()
        end
        FX.Network:SendMsgToClient(self:GetPlayerId(), "S2C_ForgeSwordResult", station.Id, true)
    end
end

--- 仅恢复当前彻底损毁的剑；扣款与恢复进度一起提交，同一损毁标识只能成功一次。
--- @param failureId any 客户端看到的损毁标识，不能指定剑、品质或费用。
function Comp:RecoverSword(failureId)
    if type(failureId) ~= "string" or #failureId ~= 36
        or os.clock() - self._lastRecovery < Settings.RequestCooldown or not self:CanUseStation() then
        return
    end
    local data = self:GetTable(Fields.ForgeData)
    if data.Active or not data.Finished or data.Outcome ~= "Destroyed" or data.RecoveryId ~= failureId then
        return
    end
    self._lastRecovery = os.clock()
    if self:GetNumber(Fields.Diamonds) < Settings.RecoveryDiamondCost then
        FX.Network:SendMsgToClient(self:GetPlayerId(), "S2C_ForgeRecoveryInsufficientDiamonds", failureId)
        return
    end
    local rewards = self:RequireComponent("FSRewardComp")
    self:GetPlayerObject():RunDataTransaction(function()
        if not rewards:ConsumeRewards({{Type = "Money", Currency = "Diamonds", Count = Settings.RecoveryDiamondCost}}) then
            return false
        end
        data.RecoveryId = nil
        data.Active, data.Finished, data.Outcome = true, false, "Recovered"
        return self:SetTable(Fields.ForgeData, data)
    end)
end

--- 调试入口沿用自然破损的出炉流程，容量不足时保留原成品待领取。
--- @return boolean 是否已将进行中的锻造标记为破损。
function Comp:BreakCurrentSword()
    if not self:CanUseStation() then
        return false
    end
    local data = self:GetTable(Fields.ForgeData)
    if not data.Active or data.Finished then
        return false
    end
    data.Outcome = "Broken"
    data.Finished = true
    if not self:SetTable(Fields.ForgeData, data) then
        return false
    end
    self:FinishSword()
    return true
end

--- 至少敲过一锤才可主动出炉；已结束成品领取失败时保留原结果。
--- @param showResult boolean? 主动点击时显示结果，自动出炉仍沿用锻造表现。
--- @return boolean 是否成功领取一把成品。
function Comp:FinishSword(showResult)
    if not self:CanUseStation() then
        return false
    end
    local data = self:GetTable(Fields.ForgeData)
    if not data.Active or (data.HammerCount == 0 and not data.Finished) then
        return false
    end
    data.Finished = true
    self:SetTable(Fields.ForgeData, data)
    local player = self:GetPlayerObject()
    local success = player:RunDataTransaction(function()
        if not self:RequireComponent("FSRewardComp"):AddRewards({{Type = "Item", ItemId = Rules.ItemId, Count = 1,
            ExtraData = {MutationId = data.MutationId, blankLuckLevel = data.blankLuckLevel,
                Quality = data.Quality, Level = 1, StoredMoney = 0}}}) then
            return false
        end
        data.Active = false
        data.Outcome = data.Outcome == "Broken" and "Broken" or "Finished"
        return self:SetTable(Fields.ForgeData, data)
    end)
    if showResult then
        player:ShowLocalizedTips(success and TranslationTexts.Success or TranslationTexts.Failed)
    end
    return success
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

--- 先确认台位再放入手持剑胚；已有进度或待修复武器可以直接进入。
function Comp:Enter()
    local character, humanoid = self:GetLivingCharacter()
    if not character or os.clock() - self._lastRequest < Settings.RequestCooldown then
        return
    end
    self._lastRequest = os.clock()
    local data = self:GetTableView(Fields.ForgeData)
    if self._station then
        if not data.Active and self:CanUseStation() and not self:PlaceEquippedBlank() then
            FX.Network:SendMsgToClient(self:GetPlayerId(), "S2C_ForgeSwordResult", self._station.Id, false)
        end
        return
    end
    local position = humanoid.RootPart.Position
    local base = self:RequireComponent("SBaseComp"):GetBase()
    local station = self._manager:GetPersonalStation(base, self:GetPlayerId(), position)
    if not station then
        self:GetPlayerObject():ShowLocalizedTips(TranslationTexts.StationTooFar)
        return
    end
    if not data.Active and not self:PlaceEquippedBlank() and not data.RecoveryId then
        self:GetPlayerObject():ShowLocalizedTips(TranslationTexts.NeedBlank)
        return
    end
    self._station = station
    self._deathConnection = humanoid.Died:Connect(function()
        self:Release()
    end)
    self:Teleport(character, humanoid, station.Arrival)
    self:SetNumber(Fields.ForgeStation, station.Id)
end

--- 退出私人台位并留在原地。
function Comp:Leave()
    local character = self:GetLivingCharacter()
    if not character or not self._station or os.clock() - self._lastRequest < Settings.RequestCooldown then
        return
    end
    self._lastRequest = os.clock()
    self:Release()
end

--- 清理本人台位、死亡监听与同步状态。
function Comp:Release()
    if self._deathConnection then
        self._deathConnection:Disconnect()
        self._deathConnection = nil
    end
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
