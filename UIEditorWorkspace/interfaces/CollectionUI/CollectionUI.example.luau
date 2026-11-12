local FX = _G.FX
local FXLoader = FX.Loader
local CCollectionPreview = FX.Class("CCollectionPreview", "CCollectionView")

-- 示例每激活一项增加 2% 力量，前三项已激活；不修改真实玩家数据。
-- @param owner table 编辑器组件宿主
function CCollectionPreview:Ctor(owner)
    CCollectionPreview.Super.Ctor(self, owner)
    self.Config = {
        strengthPerEntryPercent = 2,
        items = {
            { id = "wood_sword", name = "Wood Sword" },
            { id = "iron_sword", name = "Iron Sword" },
            { id = "crystal", name = "Crystal" },
            { id = "flame", name = "Flame Blade" },
            { id = "ice", name = "Ice Staff" },
            { id = "star", name = "Star Gem" },
            { id = "ruby", name = "Ruby" },
            { id = "emerald", name = "Emerald" },
            { id = "sapphire", name = "Sapphire" },
            { id = "gold", name = "Gold Ring" },
            { id = "silver", name = "Silver Ring" },
            { id = "shield", name = "Shield" },
            { id = "hammer", name = "Hammer" },
            { id = "axe", name = "Axe" },
            { id = "bow", name = "Bow" },
            { id = "spear", name = "Spear" },
            { id = "helmet", name = "Helmet" },
            { id = "boots", name = "Boots" },
            { id = "amulet", name = "Amulet" },
            { id = "crown", name = "Crown" },
        },
    }
    self.State = {
        open = true,
        totalStrengthPercent = 6,
        entries = {
            wood_sword = { active = true },
            iron_sword = { active = true },
            crystal = { active = true },
            flame = { active = false },
            ice = { active = false },
            star = { active = false },
            ruby = { active = false },
            emerald = { active = false },
            sapphire = { active = false },
            gold = { active = false },
            silver = { active = false },
            shield = { active = false },
            hammer = { active = false },
            axe = { active = false },
            bow = { active = false },
            spear = { active = false },
            helmet = { active = false },
            boots = { active = false },
            amulet = { active = false },
            crown = { active = false },
        },
    }
end

-- 绑定完成后加载数据并显示图鉴。
function CCollectionPreview:OnReady()
    CCollectionPreview.Super.OnReady(self)
    self:BindUIData()
    self:Show()
end

-- 模拟只响应关闭，不再提供领取或发奖行为。
-- @param action string Close
-- @param payload table 空表
function CCollectionPreview:OnUIAction(action, payload)
    assert(action == "Close", "Unsupported collection action: " .. tostring(action))
    self.State.open = false
    self:RefreshUI()
end

return CCollectionPreview