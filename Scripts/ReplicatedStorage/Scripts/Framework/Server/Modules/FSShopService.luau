local FX, FS = _G.FX, _G.FS
local MarketplaceService = game:GetService("MarketplaceService")
-- 为已付款但尚未结算的回执及后续玩法数据留出空间，不以容量预检拒绝已付款回执。
local PURCHASE_PROFILE_BUDGET = 3 * 1024 * 1024
local Shop = { _busy = {}, _pendingAnalytics = setmetatable({}, {__mode = "k"}) }
FS.ShopService = Shop

--- 商品处理器不得 yield，防止同一档案在结算中交叉修改。
--- @param callback function 无 yield 的业务操作。
--- @return boolean 操作是否成功。
local function Immediate(callback)
    local thread = coroutine.create(callback)
    local ok, result = coroutine.resume(thread)
    if coroutine.status(thread) ~= "dead" then
        task.cancel(thread)
        return false
    end

    return ok and result == true
end

--- 框架可先于业务管理器初始化；未就绪或档案接近容量预算时不再发起新购买。
--- @param playerId number 服务端认证的玩家 ID。
--- @param productId number 已登记的 Developer Product ID。
--- @return boolean 是否允许展示购买窗口；不授予任何奖励。
function Shop:CanBuy(playerId, productId)
    if type(productId) ~= "number" or productId % 1 ~= 0 then
        return false
    end

    local player = FS.PlayerManager and FS.PlayerManager:GetPlayerObject(playerId)
    local storage = FS.PlayerKVDataManager
    local session = storage:GetSessionToken(playerId)
    if not player or not session
        or not _G.Provider:GetGoodsConfig(productId) then
        return false
    end

    local dataSize = storage:GetDataSize(playerId, session)
    if not dataSize or dataSize >= PURCHASE_PROFILE_BUDGET then
        warn("[Shop] profile cannot start a new purchase", playerId, dataSize)
        return false
    end

    return Immediate(function()
        return FX.BuyContextClass.New(player, productId, 1):CanBuy()
    end)
end

--- 只接受 Roblox ProcessReceipt 的购买凭证；去重标记与奖励位于同一玩家档案。
--- 管理器尚未创建时保留凭证，等待 Roblox 后续重试。
--- @param receipt table Roblox 提供的已支付凭证。
--- @return Enum.ProductPurchaseDecision 保存完成后才确认购买。
function Shop:ProcessReceipt(receipt)
    local id = receipt.PlayerId
    local player = FS.PlayerManager and FS.PlayerManager:GetPlayerObject(id)
    local storage = FS.PlayerKVDataManager
    local session = storage:GetSessionToken(id)
    local retry = Enum.ProductPurchaseDecision.NotProcessedYet
    if not player or not session or self._busy[id] then
        return retry
    end

    self._busy[id] = true
    local ok, decision = pcall(function()
        if not storage:HasPurchaseReceipt(id, session, receipt.PurchaseId) then
            local context = FX.BuyContextClass.New(player, receipt.ProductId, 1)
            if not Immediate(function()
                return context:CanBuy()
            end) then
                return retry
            end

            -- 原始档案快照与回滚由存档模块独占，业务回调只使用玩家/KV 公开接口。
            local record
            if not player:RunDataTransaction(function()
                if context:Buy() ~= true then
                    return false
                end
                -- 项目回调只取得收据副本，异常或 yield 不改变已完成的发奖。
                local metadata
                if self.CaptureReceiptAnalytics then
                    Immediate(function()
                        metadata = self.CaptureReceiptAnalytics(player, receipt, storage:GetPurchaseReceipts(id, session))
                        return true
                    end)
                end
                -- 档案只保留最小去重标记，分析元数据保留在当前会话。
                record = {analytics = metadata}
                return storage:RecordPurchaseReceipt(id, session, receipt.PurchaseId, true)
            end) then
                return retry
            end

            local pending = self._pendingAnalytics[player]
            if not pending then
                pending = {}
                self._pendingAnalytics[player] = pending
            end
            pending[receipt.PurchaseId] = record
        end

        if not storage:Save(id, session) then
            return retry
        end

        -- 首次保存失败后保留内存快照，重试保存成功才消费；历史记录不会进入 pending。
        -- 持久标记先于分析副作用，崩溃或平台失败允许漏报，不为分析重试支付。
        local pending = self._pendingAnalytics[player]
        local record = pending and pending[receipt.PurchaseId]
        if record then
            pending[receipt.PurchaseId] = nil
            if record.analytics and self.OnReceiptAnalyticsSaved
                and FS.PlayerManager:GetPlayerObject(id) == player
                and storage:IsSessionActive(id, session) then
                pcall(self.OnReceiptAnalyticsSaved, player, FX.Table:DeepCopy(record.analytics))
            end
        end

        return Enum.ProductPurchaseDecision.PurchaseGranted
    end)

    self._busy[id] = nil
    if not ok then
        warn("[Shop] receipt failed", decision)
        return retry
    end

    return decision
end

--- 项目中只应有一个 ProcessReceipt 所有者。
function Shop:Init()
    MarketplaceService.ProcessReceipt = function(receipt)
        return self:ProcessReceipt(receipt)
    end

    FX.Network:RegClientMsgCallback("C2S_BuyCheck", function(id, productId)
        return self:CanBuy(id, productId)
    end)
end

return Shop
