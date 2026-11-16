-- 武器出售、离线领取与同服原料赠送；物品和货币只经公开接口与奖励事务提交。
local HttpService = game:GetService("HttpService")
local FX = _G.FX
local Fields = _G.PlayerDataConfig
local Rules = FX.Loader:RequireShared("Scripts.Game.Shared.SwordRules")
local Utility = FX.Loader:RequireShared("Scripts.Game.Shared.GameUtility")
local Config = _G.GameConfig.CommonConfig
local Texts = FX.Text.Define("WeaponEconomy", {
    Sold = "Weapon sold for ${value}.",
    Offline = "Claimed ${value} offline income.",
    GiftSent = "Raw weapon sent to {name}.",
    GiftReceived = "Received a raw weapon from {name}.",
    Failed = "Action failed. Check your equipped item, distance and backpack space.",
})
local Comp = FX.Class("SEconomyCompClass", "FSPlayerCompClass")

--- 返回协议管理器使用的协作名。
--- @return string 经济组件名。
function Comp:GetCompName()
    return "SEconomyComp"
end

--- 登录后启用交互，所有待确认赠送仅属于当前在线会话。
function Comp:OnPlayerLogin()
    self._active, self._lastRequest = true, -math.huge
end

--- 所有经济请求共用短节流，离服或旧会话不能继续处理。
--- @return boolean 本次请求是否可处理。
function Comp:CanRequest()
    if not self._active or os.clock() - self._lastRequest < 0.4 then
        return false
    end
    self._lastRequest = os.clock()
    return true
end

--- 只出售当前手持的成品，保留手持格和属性作为同一次提交的校验依据。
--- @param grid any 客户端所见的手持格号，必须与服务端一致。
--- @param expected any 玩家确认出售时看到的属性；只用于拒绝换物，不用于计算价格。
function Comp:Sell(grid, expected)
    if not self:CanRequest() or type(grid) ~= "number" or type(expected) ~= "table" then
        return
    end
    local inventory = self:RequireComponent("FSInventoryComp")
    local items = self:GetTable(Fields.Inventory)
    local item = items[tostring(grid)]
    if inventory:GetEquippedGrid() ~= grid or not item or item.itemId ~= Rules.ItemId
        or item.stackCount ~= 1 or not Rules.IsValid(item.extraData) then
        self:GetPlayerObject():ShowLocalizedTips(Texts.Failed)
        return
    end
    for index, key in ipairs({"Quality", "Level", "MutationId", "Luck", "StoredMoney"}) do
        if item.extraData[key] ~= expected[key] then
            self:GetPlayerObject():ShowLocalizedTips(Texts.Failed)
            return
        end
    end
    local price = Rules.GetSellPrice(item.extraData)
    local success = self:GetPlayerObject():RunDataTransaction(function()
        items[tostring(grid)] = nil
        return self:SetTable(Fields.Inventory, items)
            and self:RequireComponent("FSRewardComp"):AddRewards({{Type = "Money", Currency = "Money", Count = price}})
    end)
    self:GetPlayerObject():ShowLocalizedTips(success and Texts.Sold or Texts.Failed,
        success and {value = Utility.NumberToText(price)} or nil)
end

--- 金币入账与待领额清零在一个玩家事务中完成；重试不会重复领取。
--- @param boosted boolean 是否消耗配置钻石领取两倍金币。
--- @return boolean 是否成功扣费并领取本次收益。
function Comp:ClaimOffline(boosted)
    if not self:CanRequest() then
        return false
    end
    local data = self:GetTable(Fields.OfflineIncome)
    local amount = data.Pending
    if amount <= 0 then
        return false
    end
    local costs = {}
    if boosted then
        if Config.OfflineDoubleClaimDiamondCost > 0 then
            costs = {{Type = "Money", Currency = "Diamonds", Count = Config.OfflineDoubleClaimDiamondCost}}
        end
        amount *= 2
    end
    local success = self:GetPlayerObject():RunDataTransaction(function()
        data.Pending = 0
        return self:SetTable(Fields.OfflineIncome, data)
            and self:RequireComponent("FSRewardComp"):ExchangeRewards(costs,
                {{Type = "Money", Currency = "Money", Count = amount}})
    end)
    if success then
        self:GetPlayerObject():ShowLocalizedTips(Texts.Offline, {value = Utility.NumberToText(amount)})
    end
    return success
end

--- 两位存活玩家须在同服且靠近；不接收客户端位置。
--- @param other table 接收方经济组件。
--- @return boolean 是否可进行赠送。
function Comp:IsNear(other)
    local player, target = self:GetPlayerNode(), other:GetPlayerNode()
    local character, targetCharacter = player and player.Character, target and target.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local targetHumanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
    return self._active and other._active and humanoid and targetHumanoid
        and humanoid.Health > 0 and targetHumanoid.Health > 0 and humanoid.RootPart and targetHumanoid.RootPart
        and (humanoid.RootPart.Position - targetHumanoid.RootPart.Position).Magnitude <= Config.GiftDistance
end

--- 提议只锁定当前手持原料的快照，不提前扣料；每人最多一笔30秒待确认赠送。
--- @param targetId any 客户端选择的接收者 UserId。
function Comp:OfferGift(targetId)
    if not self:CanRequest() or type(targetId) ~= "number" or targetId % 1 ~= 0 or targetId == self:GetPlayerId() then
        return
    end
    local player = _G.SPlayerObjectManager:GetPlayerObject(targetId)
    local other = player and player:GetComponent("SEconomyComp")
    local inventory = self:RequireComponent("FSInventoryComp")
    local grid = inventory:GetEquippedGrid()
    local items = self:GetTable(Fields.Inventory)
    local item = grid and items[tostring(grid)]
    local traits = item and item.itemId == Rules.RawItemId and Rules.GetTraits(item.extraData)
    local now = os.clock()
    if not other or not self:IsNear(other) or not traits or item.stackCount ~= 1
        or (self._outgoing and self._outgoing.Expires > now)
        or (other._offer and other._offer.Expires > now) then
        self:GetPlayerObject():ShowLocalizedTips(Texts.Failed)
        return
    end
    local offer = {Token = HttpService:GenerateGUID(false), Sender = self, Receiver = other, Grid = grid,
        MutationId = traits.MutationId, Luck = traits.Luck, Expires = now + 30}
    self._outgoing, other._offer = offer, offer
    FX.Network:SendMsgToClient(targetId, "S2C_RawSwordOffer", offer.Token, self:GetPlayerNode().DisplayName,
        offer.MutationId, offer.Luck)
end

--- 接收者确认后重新检查会话、距离、物品与容量；两个玩家各自提交，接收失败即恢复发送方。
--- @param token any 服务端生成并发给本接收者的赠送令牌。
--- @param accepted any 接收者的明确确认或拒绝。
function Comp:ReplyGift(token, accepted)
    if not self:CanRequest() or type(token) ~= "string" or type(accepted) ~= "boolean" then
        return
    end
    local offer = self._offer
    if not offer or offer.Token ~= token then
        return
    end
    self._offer = nil
    local sender = offer.Sender
    if sender._outgoing ~= offer then
        return
    end
    sender._outgoing = nil
    if not accepted or offer.Expires < os.clock() or not sender:IsNear(self)
        or _G.SPlayerObjectManager:GetPlayerObject(sender:GetPlayerId()) ~= sender:GetPlayerObject() then
        return
    end
    local items = sender:GetTable(Fields.Inventory)
    local item = items[tostring(offer.Grid)]
    local traits = item and item.itemId == Rules.RawItemId and Rules.GetTraits(item.extraData)
    if not traits or item.stackCount ~= 1 or traits.MutationId ~= offer.MutationId or traits.Luck ~= offer.Luck then
        return
    end
    local rewards = {{Type = "Item", ItemId = Rules.RawItemId, Count = 1,
        ExtraData = {MutationId = traits.MutationId, Luck = traits.Luck}}}
    local reward = self:RequireComponent("FSRewardComp")
    if not reward:CanAddRewards(rewards) then
        self:GetPlayerObject():ShowLocalizedTips(Texts.Failed)
        return
    end
    local remaining = sender:GetTable(Fields.Inventory)
    remaining[tostring(offer.Grid)] = nil
    local removed = sender:GetPlayerObject():RunDataTransaction(function()
        return sender:SetTable(Fields.Inventory, remaining)
    end)
    if not removed then
        return
    end
    local success = self:GetPlayerObject():RunDataTransaction(function()
        return reward:AddRewards(rewards)
    end)
    if not success then
        sender:SetTable(Fields.Inventory, items)
    end
    if success then
        sender:GetPlayerObject():ShowLocalizedTips(Texts.GiftSent, {name = self:GetPlayerNode().DisplayName})
        self:GetPlayerObject():ShowLocalizedTips(Texts.GiftReceived, {name = sender:GetPlayerNode().DisplayName})
    end
end

--- 离服令牌立即失效，不把待确认赠送转移到新会话。
function Comp:OnPlayerLogout()
    self._active = false
    if self._outgoing and self._outgoing.Receiver._offer == self._outgoing then
        self._outgoing.Receiver._offer = nil
    end
    if self._offer and self._offer.Sender._outgoing == self._offer then
        self._offer.Sender._outgoing = nil
    end
    self._outgoing, self._offer = nil, nil
end

return Comp
