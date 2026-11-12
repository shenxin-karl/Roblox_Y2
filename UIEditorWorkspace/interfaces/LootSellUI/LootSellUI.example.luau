local FX = _G.FX
local CLootSellPreview = FX.Class("CLootSellPreview", "CLootSellView")

-- 准备十二条模拟数据以验证满容量��滚动列表。
-- @param owner table 编辑器宿主
function CLootSellPreview:Ctor(owner)
    CLootSellPreview.Super.Ctor(self, owner)
    self.Config = {
        capacity = 12,
        doubleSaleGemCost = 40,
        qualities = {
            common = "#E5E9EF",
            uncommon = "#D8F2CF",
            rare = "#D7EDFC",
            epic = "#EADCF7",
            legendary = "#FCEBC8",
        },
        qualityGradientEnds = {
            common = "#C8D1DD",
            uncommon = "#B0DC9E",
            rare = "#A9D4F4",
            epic = "#CFB3E9",
            legendary = "#F3D396",
        },
    }
    local qualities = {"common", "uncommon", "rare", "epic", "legendary"}
    self.State = {isOpen = true, items = {}, pending = false, doubleSaleCards = 1, gems = 120, isVip = true}
    for index = 1, 12 do
        local item = {id = "sample_" .. index, name = "Sample Item " .. index, value = 1000000}
        if index == 1 then
            item.name = "Ancient Scroll"
            item.value = 18200000
        end
        item.qualityId = qualities[(index - 1) % #qualities + 1]
        table.insert(self.State.items, item)
    end
end

-- 父层绑定后初次展示。
function CLootSellPreview:OnReady()
    CLootSellPreview.Super.OnReady(self)
    self:BindUIData()
    self:Show()
end

-- 校验稳定实例 ID 后模拟出售整个列表。
-- @param action string Sell 或 Close
-- @param payload table entryIds 和 multiplier，关闭时为空表
function CLootSellPreview:OnUIAction(action, payload)
    if action == "Close" then
        self.State.isOpen = false
    elseif action == "Sell" then
        if self.State.pending or #self.State.items == 0 then
            return
        end
        local multiplier = 1
        if payload.method == "Card" then
            assert(self.State.doubleSaleCards > 0, "No double-sale cards")
            self.State.doubleSaleCards = self.State.doubleSaleCards - 1
            multiplier = 2
        elseif payload.method == "Gems" then
            assert(self.State.gems >= self.Config.doubleSaleGemCost, "Not enough gems")
            self.State.gems = self.State.gems - self.Config.doubleSaleGemCost
            multiplier = 2
        elseif payload.method == "Vip" then
            assert(self.State.isVip, "VIP required")
            multiplier = 2
        else
            assert(payload.method == nil, "Unknown sale method")
        end
        if self.State.isVip and (payload.method == "Card" or payload.method == "Gems") then
            multiplier = 4
        end
        assert(payload.multiplier == multiplier, "Invalid multiplier")
        assert(#payload.entryIds == #self.State.items, "Inventory changed")
        local total = 0
        for index, item in ipairs(self.State.items) do
            assert(payload.entryIds[index] == item.id, "Unknown inventory entry")
            total = total + item.value
        end
        self.State.items = {}
        self.State.message = nil
        self.State.soldAmount = total * payload.multiplier
    else
        error("Unknown action: " .. tostring(action))
    end
    self:RefreshUI()
end

return CLootSellPreview
