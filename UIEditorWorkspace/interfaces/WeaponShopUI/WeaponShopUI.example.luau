local FX = _G.FX
local FXLoader = FX.Loader
local CWeaponShopPreview = FX.Class("CWeaponShopPreview", "CWeaponShopView")

-- 准备多条武器与品质颜色，演示固定窗口中的滚动列表，只用于本地模拟。
-- @param owner table 编辑器宿主。
function CWeaponShopPreview:Ctor(owner)
    CWeaponShopPreview.Super.Ctor(self, owner)
    self.Config = {
        title = "WEAPONS",
        strengthIsMultiplier = true,
        allowUnaffordableAction = true,
        qualities = {
            common = {color = "#A5ADB8", colorEnd = "#68778E"},
            rare = {color = "#73BBEF", colorEnd = "#397BC7"},
            epic = {color = "#BC85E5", colorEnd = "#7242B2"},
            legendary = {color = "#F4BF52", colorEnd = "#C77B20"},
        },
        weapons = {
            {id = "sickle", name = "Sickle", qualityId = "common", strength = 1, price = 0},
            {id = "knife", name = "Knife", qualityId = "rare", strength = 8, price = 700},
            {id = "saw", name = "Saw Blade", qualityId = "common", strength = 3, price = 350},
            {id = "axe", name = "Battle Axe", qualityId = "rare", strength = 12, price = 1200},
            {id = "spear", name = "Steel Spear", qualityId = "rare", strength = 18, price = 1800},
            {id = "katana", name = "Katana", qualityId = "epic", strength = 25, price = 2500},
            {id = "hammer", name = "War Hammer", qualityId = "epic", strength = 35, price = 3500},
            {id = "greatsword", name = "Greatsword", qualityId = "epic", strength = 50, price = 5000},
            {id = "flameblade", name = "Flame Blade", qualityId = "legendary", strength = 75, price = 7500},
            {id = "dragonblade", name = "Dragon Blade", qualityId = "legendary", strength = 100, price = 10000},
        },
    }
    self.State = {
        owned = {sickle = true, saw = true, dragonblade = true},
        equippedId = "sickle",
        coins = 700,
        open = true,
    }
end

-- 绑定展示后刷新。
function CWeaponShopPreview:OnReady()
    CWeaponShopPreview.Super.OnReady(self)
    self:BindUIData()
    self:Show()
end

-- 模拟购买与装备成功，正式游戏必须替换为服务端结果。
-- @param action string Buy、Equip 或 Close。
-- @param payload table 稳定 weaponId，Close 为空表。
function CWeaponShopPreview:OnUIAction(action, payload)
    if action == "Close" then
        self.State.open = false
    elseif action == "Buy" then
        for index, weapon in ipairs(self.Config.weapons) do
            if weapon.id == payload.weaponId and not self.State.owned[weapon.id] and self.State.coins >= weapon.price then
                self.State.coins = self.State.coins - weapon.price
                self.State.owned[weapon.id] = true
            end
        end
    elseif action == "Equip" then
        if self.State.owned[payload.weaponId] then
            self.State.equippedId = payload.weaponId
        end
    end
    self:RefreshUI()
end

return CWeaponShopPreview
