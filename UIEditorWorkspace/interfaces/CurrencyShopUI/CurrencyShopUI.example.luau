local FX = _G.FX
local CCurrencyShopPreview = FX.Class("CCurrencyShopPreview", "CCurrencyShopView")

-- 父构造后提供示例商品；所有价格与图标均待业务配置替换。
-- @param owner table 编辑器组件宿主
function CCurrencyShopPreview:Ctor(owner)
    CCurrencyShopPreview.Super.Ctor(self, owner)
    self.Config = {
        products = {
            {
                id = "speed",
                currency = "Diamond",
                title = "Speed Potion",
                description = "Boost your movement speed",
                price = 100,
                cardStyle = "Green",
            },
            {
                id = "luck",
                currency = "Diamond",
                title = "Luck Potion",
                description = "Add luck to your next adventure",
                price = 250,
                cardStyle = "Gold",
            },
            {
                id = "energy",
                currency = "Diamond",
                title = "Energy Pack",
                description = "Refill your energy for exploring",
                price = 150,
                cardStyle = "Cyan",
            },
            {
                id = "chest",
                currency = "Diamond",
                title = "Mystery Chest",
                description = "Discover a mystery reward",
                price = 500,
                cardStyle = "Orange",
            },
            {
                id = "trail",
                currency = "Diamond",
                title = "Star Trail",
                description = "Leave a sparkling trail",
                price = 800,
                cardStyle = "Purple",
            },
            {
                id = "ticket",
                currency = "Diamond",
                title = "Challenge Ticket",
                description = "Unlock an extra challenge",
                price = 200,
                cardStyle = "Pink",
            },
            {
                id = "starter",
                currency = "Robux",
                title = "Starter Pack",
                description = "Supplies to start your adventure",
                price = 49,
                cardStyle = "Green",
            },
            {
                id = "gem_pack",
                currency = "Robux",
                title = "Diamond Pack",
                description = "Get 1,000 diamonds",
                price = 99,
                cardStyle = "Cyan",
            },
            { id = "vip", currency = "Robux", title = "VIP Pass", description = "Unlock exclusive VIP perks", price = 199 },
            {
                id = "outfit",
                currency = "Robux",
                title = "Special Outfit",
                description = "Create your own unique look",
                price = 149,
                cardStyle = "Purple",
            },
            {
                id = "deluxe",
                currency = "Robux",
                title = "Deluxe Pack",
                description = "Stock up on adventure supplies",
                price = 299,
                cardStyle = "Pink",
            },
            {
                id = "pet",
                currency = "Robux",
                title = "Companion Pack",
                description = "Meet your new adventure companion",
                price = 249,
                cardStyle = "Orange",
            },
        },
    }
    self.State = { tab = "Diamond", open = true, pending = {} }
end

-- 父类完成节点绑定后显示商店。
function CCurrencyShopPreview:OnReady()
    CCurrencyShopPreview.Super.OnReady(self)
    self:BindUIData()
    self:Show()
end

-- 只切换模拟状态，购买不执行扣款或发奖。
-- @param action string SelectTab、Purchase 或 Close
-- @param payload table 符合 View 契约的动作参数
function CCurrencyShopPreview:OnUIAction(action, payload)
    if action == "SelectTab" then
        self.State.tab = payload.tab
        self.List.CanvasPosition = Vector2.new(0, 0)
    elseif action == "Close" then
        self.State.open = false
    end
    self:RefreshUI()
end

return CCurrencyShopPreview
