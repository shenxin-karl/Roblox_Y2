-- 武器出售、离线领取与同服剑胚赠送；物品和货币只经公开接口与奖励事务提交。
local HttpService = game:GetService("HttpService")
local FX, FS = _G.FX, _G.FS
local Fields = _G.PlayerDataConfig
local Rules = FX.Loader:RequireShared("Scripts.Game.Shared.SwordRules")
local Welfare = FX.Loader:RequireShared("Scripts.Game.Shared.WelfareRules")
local Utility = FX.Loader:RequireShared("Scripts.Game.Shared.GameUtility")
local Mailbox = FX.Loader:Require(script.Parent.Parent, "Service.SSwordGiftMailbox")
local Config = _G.GameConfig.CommonConfig
local TranslationTexts = FX.Text.Define("WeaponEconomy", {
    Sold = "Weapon sold for ${value}.",
    Offline = "Claimed ${value} offline income.",
    GiftSent = "Sword blank sent to {name}.",
    PaidGiftSent = "Sword blank sent to {name} for {value} diamonds.",
    GiftReceived = "Received a sword blank from {name}.",
    GiftRequested = "Gift request sent to {name}. Waiting for their reply.",
    GiftAccepted = "{name} accepted your gift. Delivery is pending.",
    GiftBusy = "A gift request is already pending. Please wait for it to finish.",
    GiftDeclined = "{name} declined your gift.",
    GiftExpired = "The gift request expired.",
    GiftUnavailable = "This gift request is no longer available.",
    GiftTooFar = "You are too far apart to complete the gift.",
    GiftItemChanged = "The sword blank offered for this gift is no longer available.",
    GiftBackpackFull = "The recipient's backpack is full. The sword blank was not transferred.",
    GiftCostChanged = "The gift cost changed. Please confirm the new cost.",
    GiftInsufficientDiamonds = "You need {value} diamonds to send this gift.",
    GiftFailed = "Couldn't complete the gift. Please try again.",
    Failed = "Action failed. Check your equipped item, distance and backpack space.",
})
local Comp = FX.Class("SEconomyCompClass", "FSPlayerCompClass")

--- 用持久化的属性重建一件剑胚；重试不重抽幸运或变异。
--- @param gift table 已确认的赠送属性。
--- @return table 接收方的奖励列表。
local function GiftRewards(gift)
    return {{Type = "Item", ItemId = Rules.BlankItemId, Count = 1,
        ExtraData = {MutationId = gift.MutationId, blankLuckLevel = gift.blankLuckLevel}}}
end

--- 返回协议管理器使用的协作名。
--- @return string 经济组件名。
function Comp:GetCompName()
    return "SEconomyComp"
end

--- 登录后启用交互，所有待确认赠送仅属于当前在线会话。
function Comp:OnPlayerLogin()
    self._active, self._lastRequest = true, -math.huge
    self._giftPollAt = 0
end

--- 先保存赠送方的扣费和发件记录，再投递；失败保留记录，重登后继续。
--- @param player table 开始本次处理时的玩家对象。
--- @param userId number 赠送方 UserId。
--- @param session string 开始本次处理时的档案会话。
function Comp:SendPendingGift(player, userId, session)
    local transfer = player:GetTable(Fields.SwordGiftTransfer)
    local gift = transfer.Pending
    local storage = FS.PlayerKVDataManager
    if not gift or not storage:Save(userId, session) or not Mailbox.Publish(userId, gift) then
        return
    end
    local receiver = FS.PlayerManager:GetPlayerObject(gift.ReceiverId)
    if receiver then
        receiver:RequireComponent("SEconomyComp")._giftPollAt = 0
    end
    if not storage:IsSessionActive(userId, session) then
        return
    end
    -- 收件游标可能在保存等待期间变化，清理时读取最新字段。
    local current = player:GetTable(Fields.SwordGiftTransfer)
    if not current.Pending or current.Pending.Sequence ~= gift.Sequence then
        return
    end
    current.Pending = nil
    if player:SetTable(Fields.SwordGiftTransfer, current) then
        player:ShowLocalizedTips(gift.Cost == 0 and TranslationTexts.GiftSent or TranslationTexts.PaidGiftSent,
            {name = gift.ReceiverName, value = Utility.NumberToText(gift.Cost)})
    end
end

--- 领取按收件顺序推进。游标和发奖同档提交，保存确认前不从收件箱清除。
--- @param player table 开始本次处理时的玩家对象。
--- @param userId number 接收方 UserId。
--- @param session string 开始本次处理时的档案会话。
function Comp:ReceivePendingGift(player, userId, session)
    local success, box = Mailbox.Read(userId)
    local storage = FS.PlayerKVDataManager
    if not success or not box or not storage:IsSessionActive(userId, session) then
        return
    end
    local transfer = player:GetTable(Fields.SwordGiftTransfer)
    local previousCursor = transfer.InboxCursor
    local nextCursor = previousCursor + 1
    local gift = box.Entries[tostring(nextCursor)]
    local received = gift and player:RunDataTransaction(function()
        if not player:RequireComponent("FSRewardComp"):AddRewards(GiftRewards(gift)) then
            return false
        end
        transfer.InboxCursor = nextCursor
        return player:SetTable(Fields.SwordGiftTransfer, transfer)
    end)
    local cursor = if received then nextCursor else previousCursor
    if cursor <= box.Ack or not storage:Save(userId, session) then
        return
    end
    local acknowledged = Mailbox.Acknowledge(userId, cursor)
    if not storage:IsSessionActive(userId, session) then
        return
    end
    if received then
        player:ShowLocalizedTips(TranslationTexts.GiftReceived, {name = gift.SenderName})
    end
    if acknowledged and cursor < box.Tail and received then
        self._giftPollAt = 0
    end
end

--- 复用玩家秒更新处理恢复；网络或存储等待不阻塞其他玩家。
function Comp:OnUpdate()
    if not self._active or self._giftWorker or os.clock() < self._giftPollAt then
        return
    end
    local userId = self:GetPlayerId()
    local session = FS.PlayerKVDataManager:GetSessionToken(userId)
    if not session then
        return
    end
    local player = self:GetPlayerObject()
    self._giftWorker = true
    self._giftPollAt = os.clock() + 30
    task.defer(function()
        local ok, err = xpcall(function()
            if FS.PlayerKVDataManager:IsSessionActive(userId, session) then
                self:SendPendingGift(player, userId, session)
            end
            if FS.PlayerKVDataManager:IsSessionActive(userId, session) then
                self:ReceivePendingGift(player, userId, session)
            end
        end, debug.traceback)
        self._giftWorker = nil
        if not ok then
            warn("[SwordGift] Transfer retry scheduled", userId, err)
        end
    end)
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
        self:GetPlayerObject():ShowLocalizedTips(TranslationTexts.Failed)
        return
    end
    for index, key in ipairs({"Quality", "Level", "MutationId", "blankLuckLevel", "StoredMoney"}) do
        if item.extraData[key] ~= expected[key] then
            self:GetPlayerObject():ShowLocalizedTips(TranslationTexts.Failed)
            return
        end
    end
    local price = Rules.GetSellPrice(item.extraData)
    local success = self:GetPlayerObject():RunDataTransaction(function()
        items[tostring(grid)] = nil
        return self:SetTable(Fields.Inventory, items)
            and self:RequireComponent("FSRewardComp"):AddRewards({{Type = "Money", Currency = "Money", Count = price}})
    end)
    self:GetPlayerObject():ShowLocalizedTips(success and TranslationTexts.Sold or TranslationTexts.Failed,
        success and {value = Utility.NumberToText(price)} or nil)
end

--- 金币入账与待领额清零在一个玩家事务中完成；重试不会重复领取。
--- @param boosted boolean 是否消耗配置钻石领取两倍金币。
--- @return boolean 是否成功扣费并领取本次收益。
--- @return boolean? 是否因钻石不足被拒绝；其他失败不设置此标记。
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
        local diamondCost = Config.OfflineDoubleClaimDiamondCost
        if diamondCost > 0 then
            if self:GetNumber(Fields.Diamonds) < diamondCost then
                return false, true
            end
            costs = {{Type = "Money", Currency = "Diamonds", Count = diamondCost}}
        end
        amount *= 2
    end
    local success = self:GetPlayerObject():RunDataTransaction(function()
        data.Pending = 0
        data.PendingActualSeconds, data.PendingEarnedSeconds = nil, nil
        return self:SetTable(Fields.OfflineIncome, data)
            and self:RequireComponent("FSRewardComp"):ExchangeRewards(costs,
                {{Type = "Money", Currency = "Money", Count = amount}})
    end)
    if success then
        self:GetPlayerObject():ShowLocalizedTips(TranslationTexts.Offline, {value = Utility.NumberToText(amount)})
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

--- 核对赠送方确认过的价格，保存剑胚快照并等待接收方确认。
--- @param targetId any 客户端选择的接收者 UserId。
--- @param expectedCost any 赠送方确认框显示的价格，仅用于检测变化。
function Comp:OfferGift(targetId, expectedCost)
    if not self:CanRequest() or type(targetId) ~= "number" or targetId % 1 ~= 0 or targetId == self:GetPlayerId() then
        return
    end
    local player = _G.SPlayerObjectManager:GetPlayerObject(targetId)
    local other = player and player:GetComponent("SEconomyComp")
    local inventory = self:RequireComponent("FSInventoryComp")
    local grid = inventory:GetEquippedGrid()
    local items = self:GetTable(Fields.Inventory)
    local item = grid and items[tostring(grid)]
    local traits = item and item.itemId == Rules.BlankItemId and Rules.GetTraits(item.extraData)
    local senderPlayer = self:GetPlayerObject()
    if not other or not self:IsNear(other) or not traits or item.stackCount ~= 1 then
        senderPlayer:ShowLocalizedTips(TranslationTexts.Failed)
        return
    end
    if self._outgoing or other._offer or self:GetTableView(Fields.SwordGiftTransfer).Pending then
        senderPlayer:ShowLocalizedTips(TranslationTexts.GiftBusy)
        return
    end
    local cost = Welfare.GetGiftCost(self:GetTableView(Fields.WelfareTasks), Welfare.GetDay(os.time()))
    if expectedCost ~= cost then
        senderPlayer:ShowLocalizedTips(TranslationTexts.GiftCostChanged)
        return
    end
    if self:GetNumber(Fields.Diamonds) < cost then
        senderPlayer:ShowLocalizedTips(TranslationTexts.GiftInsufficientDiamonds, {value = Utility.NumberToText(cost)})
        return
    end
    local offer = {Token = HttpService:GenerateGUID(false), Sender = self, Receiver = other, Grid = grid,
        MutationId = traits.MutationId, blankLuckLevel = traits.blankLuckLevel, Cost = cost, Expires = os.clock() + 30}
    self._outgoing, other._offer = offer, offer
    offer.Timeout = FX.Task:Delay(30, function()
        if self._outgoing == offer and other._offer == offer then
            self._outgoing, other._offer = nil, nil
            senderPlayer:ShowLocalizedTips(TranslationTexts.GiftExpired)
            player:ShowLocalizedTips(TranslationTexts.GiftExpired)
        end
    end)
    FX.Network:SendMsgToClient(targetId, "S2C_RawSwordOffer", offer.Token, self:GetPlayerNode().DisplayName,
        offer.MutationId, offer.blankLuckLevel)
    senderPlayer:ShowLocalizedTips(TranslationTexts.GiftRequested, {name = other:GetPlayerNode().DisplayName})
end

--- 核验接收确认后，将扣费、任务进度与可恢复的发件记录一起提交。
--- @param token any 服务端生成并发给本接收者的赠送令牌。
--- @param accepted any 接收者的明确确认或拒绝。
function Comp:ReplyGift(token, accepted)
    if not self:CanRequest() or type(token) ~= "string" or type(accepted) ~= "boolean" then
        return
    end
    local offer = self._offer
    local receiverPlayer = self:GetPlayerObject()
    if not offer or offer.Token ~= token then
        if accepted then
            receiverPlayer:ShowLocalizedTips(TranslationTexts.GiftUnavailable)
        end
        return
    end
    self._offer = nil
    local sender = offer.Sender
    if sender._outgoing ~= offer then
        receiverPlayer:ShowLocalizedTips(TranslationTexts.GiftUnavailable)
        return
    end
    sender._outgoing = nil
    FX.Task:Cancel(offer.Timeout)
    local senderPlayer = sender:GetPlayerObject()
    if _G.SPlayerObjectManager:GetPlayerObject(sender:GetPlayerId()) ~= senderPlayer then
        receiverPlayer:ShowLocalizedTips(TranslationTexts.GiftUnavailable)
        return
    end
    if offer.Expires <= os.clock() then
        senderPlayer:ShowLocalizedTips(TranslationTexts.GiftExpired)
        receiverPlayer:ShowLocalizedTips(TranslationTexts.GiftExpired)
        return
    end
    if not accepted then
        senderPlayer:ShowLocalizedTips(TranslationTexts.GiftDeclined, {name = self:GetPlayerNode().DisplayName})
        return
    end
    if not sender:IsNear(self) then
        senderPlayer:ShowLocalizedTips(TranslationTexts.GiftTooFar)
        receiverPlayer:ShowLocalizedTips(TranslationTexts.GiftTooFar)
        return
    end
    local items = sender:GetTable(Fields.Inventory)
    local item = items[tostring(offer.Grid)]
    local traits = item and item.itemId == Rules.BlankItemId and Rules.GetTraits(item.extraData)
    if not traits or item.stackCount ~= 1 or traits.MutationId ~= offer.MutationId
        or traits.blankLuckLevel ~= offer.blankLuckLevel then
        senderPlayer:ShowLocalizedTips(TranslationTexts.GiftItemChanged)
        receiverPlayer:ShowLocalizedTips(TranslationTexts.GiftItemChanged)
        return
    end
    local day = Welfare.GetDay(os.time())
    local tasks = sender:GetTable(Fields.WelfareTasks)
    local cost = Welfare.GetGiftCost(tasks, day)
    local diamonds = sender:GetNumber(Fields.Diamonds)
    if cost ~= offer.Cost or diamonds < cost then
        senderPlayer:ShowLocalizedTips(cost ~= offer.Cost and TranslationTexts.GiftCostChanged
            or TranslationTexts.GiftInsufficientDiamonds, {value = Utility.NumberToText(cost)})
        receiverPlayer:ShowLocalizedTips(TranslationTexts.GiftUnavailable)
        return
    end
    local transfer = sender:GetTable(Fields.SwordGiftTransfer)
    if transfer.Pending then
        senderPlayer:ShowLocalizedTips(TranslationTexts.GiftBusy)
        receiverPlayer:ShowLocalizedTips(TranslationTexts.GiftUnavailable)
        return
    end
    local gift = {
        Sequence = transfer.Sequence + 1,
        Cost = cost,
        ReceiverId = self:GetPlayerId(),
        ReceiverName = self:GetPlayerNode().DisplayName,
        SenderName = sender:GetPlayerNode().DisplayName,
        MutationId = traits.MutationId,
        blankLuckLevel = traits.blankLuckLevel,
    }
    local reward = self:RequireComponent("FSRewardComp")
    if not reward:CanAddRewards(GiftRewards(gift)) then
        senderPlayer:ShowLocalizedTips(TranslationTexts.GiftBackpackFull)
        receiverPlayer:ShowLocalizedTips(TranslationTexts.GiftBackpackFull)
        return
    end
    items[tostring(offer.Grid)] = nil
    transfer.Sequence, transfer.Pending = gift.Sequence, gift
    local progress = Welfare.AdvanceTask(tasks, day, "gift")
    local acceptedForDelivery = senderPlayer:RunDataTransaction(function()
        return sender:SetTable(Fields.Inventory, items)
            and (not progress or sender:SetTable(Fields.WelfareTasks, progress))
            and (cost == 0 or sender:RequireComponent("FSRewardComp"):ConsumeRewards({
                {Type = "Money", Currency = "Diamonds", Count = cost},
            }))
            and sender:SetTable(Fields.SwordGiftTransfer, transfer)
    end)
    if not acceptedForDelivery then
        senderPlayer:ShowLocalizedTips(TranslationTexts.GiftFailed)
        receiverPlayer:ShowLocalizedTips(TranslationTexts.GiftFailed)
        return
    end
    senderPlayer:ShowLocalizedTips(TranslationTexts.GiftAccepted, {name = gift.ReceiverName})
    sender._giftPollAt = 0
    sender:OnUpdate()
end

--- 离服时立即取消旧会话的赠送，并告知另一方请求失效。
function Comp:OnPlayerLogout()
    self._active = false
    if self._outgoing and self._outgoing.Receiver._offer == self._outgoing then
        local receiver = self._outgoing.Receiver
        FX.Task:Cancel(self._outgoing.Timeout)
        receiver._offer = nil
        receiver:GetPlayerObject():ShowLocalizedTips(TranslationTexts.GiftUnavailable)
    end
    if self._offer and self._offer.Sender._outgoing == self._offer then
        local sender = self._offer.Sender
        FX.Task:Cancel(self._offer.Timeout)
        sender._outgoing = nil
        sender:GetPlayerObject():ShowLocalizedTips(TranslationTexts.GiftUnavailable)
    end
    self._outgoing, self._offer = nil, nil
end

return Comp
