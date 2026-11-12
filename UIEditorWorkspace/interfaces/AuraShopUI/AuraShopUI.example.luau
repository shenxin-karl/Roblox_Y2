local FX = _G.FX
local FXLoader = FX.Loader
local CAuraShopPreview = FX.Class("CAuraShopPreview", "CAuraShopView")

-- 准备多条光环与品质颜色，演示固定窗口中的滚动列表，只用于本地模拟。
-- @param owner table 编辑器宿主。
function CAuraShopPreview:Ctor(owner)
    CAuraShopPreview.Super.Ctor(self, owner)
    self.Config = {
        title = "AURAS",
        allowUnequip = true,
        allowUnaffordableAction = true,
        strengthIsMultiplier = true,
        qualities = {
            common = {color = "#A5ADB8", colorEnd = "#68778E"},
            rare = {color = "#73BBEF", colorEnd = "#397BC7"},
            epic = {color = "#BC85E5", colorEnd = "#7242B2"},
            legendary = {color = "#F4BF52", colorEnd = "#C77B20"},
        },
        auras = {
            {id = "calm", name = "Calm Aura", qualityId = "common", strength = 1, price = 0},
            {id = "spark", name = "Spark Aura", qualityId = "rare", strength = 8, price = 700},
            {id = "breeze", name = "Breeze Aura", qualityId = "common", strength = 3, price = 350},
            {id = "frost", name = "Frost Aura", qualityId = "rare", strength = 12, price = 1200},
            {id = "storm", name = "Storm Aura", qualityId = "rare", strength = 18, price = 1800},
            {id = "flame", name = "Flame Aura", qualityId = "epic", strength = 25, price = 2500},
            {id = "shadow", name = "Shadow Aura", qualityId = "epic", strength = 35, price = 3500},
            {id = "radiant", name = "Radiant Aura", qualityId = "epic", strength = 50, price = 5000},
            {id = "celestial", name = "Celestial Aura", qualityId = "legendary", strength = 75, price = 7500},
            {id = "dragon", name = "Dragon Aura", qualityId = "legendary", strength = 100, price = 10000},
        },
    }
    self.State = {
        owned = {calm = true, breeze = true, dragon = true},
        equippedId = "calm",
        coins = 700,
        open = true,
    }
end

-- 绑定展示后刷新。
function CAuraShopPreview:OnReady()
    CAuraShopPreview.Super.OnReady(self)
    self:BindUIData()
    self:Show()
end

-- 模拟购买与装备成功，正式游戏必须替换为服务端结果。
-- @param action string Buy、Equip 或 Close。
-- @param payload table 稳定 auraId，Close 为空表。
function CAuraShopPreview:OnUIAction(action, payload)
    if action == "Close" then
        self.State.open = false
    elseif action == "Buy" then
        for index, aura in ipairs(self.Config.auras) do
            if aura.id == payload.auraId and not self.State.owned[aura.id] and self.State.coins >= aura.price then
                self.State.coins = self.State.coins - aura.price
                self.State.owned[aura.id] = true
            end
        end
    elseif action == "Equip" then
        if self.State.owned[payload.auraId] then
            self.State.equippedId = self.State.equippedId == payload.auraId and "" or payload.auraId
        end
    end
    self:RefreshUI()
end

return CAuraShopPreview
