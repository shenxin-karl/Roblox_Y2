-- 项目支付扩展入口；支付回执由 FS.ShopService 唯一接管。
local HttpService = game:GetService("HttpService")
local FX, FS = _G.FX, _G.FS
local Fields = _G.PlayerDataConfig
local Multiplier = FX.Loader:RequireShared("Scripts.Game.Shared.MoneyMultiplierRules")
local Service = {}
local Names = {"看到商品价格", "发起购买", "支付成功", "商品已发放"}
local AttemptsByPlayer = setmetatable({}, {__mode = "k"})

--- 上报同一购买尝试的实际步骤。
--- @param analytics table 玩家统计组件。
--- @param attempt table 此次尝试的服务端快照。
--- @param step number 已处理的节点。
local function Report(analytics, attempt, step)
    analytics:NamedFunnel("Y2_" .. attempt.Currency .. "Purchase", attempt.Id, step, Names[step], attempt.Segment)
end

--- 记录经过商品白名单和服务端价格确认的展示或客户端动作。
--- @param analytics table 玩家统计组件。
--- @param action string 统计回执动作。
--- @param product number Robux 商品 ID，负值表示倍率档位。
--- @param entry string 已接入的商店入口。
local function Track(analytics, action, product, entry)
    local currency, price
    if product > 0 and entry == "CurrencyShop" then
        local goods = _G.Provider:GetGoodsConfig(product)
        if goods then
            currency, price = "Robux", goods.Price
        end
    elseif product == -analytics:GetNumber(Fields.PaidMultiplierTier) and (entry == "HUD" or entry == "CurrencyShop") then
        currency, price = "Diamond", Multiplier.GetNextPrice(-product)
    end
    if not price then
        return
    end
    local player = analytics:GetPlayerObject()
    local attempts = AttemptsByPlayer[player]
    if not attempts then
        attempts = {}
        AttemptsByPlayer[player] = attempts
    end
    local attempt = attempts[product]
    if action == "Seen" then
        if not attempt or (not attempt.Requested and (attempt.Entry ~= entry or os.clock() - attempt.Clock >= 30)) then
            attempt = {Id = HttpService:GenerateGUID(false), Currency = currency,
                Segment = tostring(product) .. "/" .. entry, Entry = entry, Clock = os.clock()}
            attempts[product] = attempt
            Report(analytics, attempt, 1)
            analytics:Event("PurchaseQuote", nil, attempt.Id .. "/" .. attempt.Segment .. "/" .. price)
        end
    elseif action == "Request" and currency == "Robux" and attempt and not attempt.Requested
        and attempt.Entry == entry then
        attempt.Requested = true
        Report(analytics, attempt, 2)
    elseif attempt and attempt.Requested and (action == "Canceled" or action == "PromptFailed") and currency == "Robux" then
        analytics:Event("Purchase" .. action, nil, attempt.Id .. "/" .. attempt.Segment)
        attempts[product] = nil
    end
end

--- 取本次确认页绑定的倍率报价，不接受客户端指定价格。
--- @param player table 服务端玩家对象。
--- @param expectedTier number 请求的稳定档位。
--- @return table? 当前尝试。
function Service.GetMultiplierAttempt(player, expectedTier)
    local attempts = AttemptsByPlayer[player]
    return attempts and attempts[-expectedTier]
end

--- 用权威钻石扣款结果结束倍率尝试。
--- @param player table 服务端玩家对象。
--- @param expectedTier number 请求的档位。
--- @param result string 服务端已完成的结算结果。
--- @param attempt table? 本次兑换前捕获的报价。
function Service.ReportMultiplier(player, expectedTier, result, attempt)
    if not attempt or attempt.Requested then
        return
    end
    local analytics = player:RequireComponent("SAnalyticsComp")
    attempt.Requested = true
    Report(analytics, attempt, 2)
    if result == "Purchased" then
        Report(analytics, attempt, 3)
        Report(analytics, attempt, 4)
    else
        analytics:Event("Purchase" .. result, nil, attempt.Id .. "/" .. attempt.Segment)
    end
    AttemptsByPlayer[player][-expectedTier] = nil
end

--- 注册展示统计及已保存的真实收据回调，不接管支付。
function Service.Init()
    FX.Network:RegClientMsgCallback("C2S_CommerceAnalytics", function(userId, action, product, entry)
        if type(product) ~= "number" or product % 1 ~= 0 or type(entry) ~= "string" then
            return
        end
        local player = FS.PlayerManager:GetPlayerObject(userId)
        if player then
            Track(player:RequireComponent("SAnalyticsComp"), action, product, entry)
        end
    end)
    FS.ShopService.CaptureReceiptAnalytics = function(player, receipt)
        local attempts = AttemptsByPlayer[player]
        local attempt = attempts and attempts[receipt.ProductId]
        return {Attempt = attempt and attempt.Requested and attempt or nil,
            Product = receipt.ProductId, Id = receipt.PurchaseId}
    end
    FS.ShopService.OnReceiptAnalyticsSaved = function(player, record)
        local analytics = player:RequireComponent("SAnalyticsComp")
        local attempt = record.Attempt
        analytics:Event("RobuxDeliverySaved", nil, record.Id .. "/" .. record.Product .. "/" .. (attempt and attempt.Id or "Unattributed"))
        if attempt then
            Report(analytics, attempt, 3)
            Report(analytics, attempt, 4)
            local current = AttemptsByPlayer[player][record.Product]
            if current and current.Id == attempt.Id then
                AttemptsByPlayer[player][record.Product] = nil
            end
        end
    end
end

return Service
