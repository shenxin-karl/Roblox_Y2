local FX = _G.FX
local CUpgradeWorkshopPreview = FX.Class("CUpgradeWorkshopPreview", "CUpgradeWorkshopView")

-- 准备独立演示数据，数值不代表正式游戏平衡。
-- @param owner table 编辑器宿主
function CUpgradeWorkshopPreview:Ctor(owner)
    CUpgradeWorkshopPreview.Super.Ctor(self, owner)
    self._balance = 2000
    self._maxLevel = 5
    self.State = {
        entries = {
            smelt = {
                level = 3,
                currentValue = "×1.20",
                nextValue = "×1.30",
                price = 100,
                canUpgrade = true,
            },
            forge = {
                level = 3,
                currentValue = "×1.20",
                nextValue = "×1.30",
                price = 250,
                canUpgrade = true,
            },
            income = {
                level = 3,
                currentValue = "×1.20",
                nextValue = "×1.30",
                price = 500,
                canUpgrade = true,
            },
        },
    }
end

-- 父绑定完成后刷新并显示。
function CUpgradeWorkshopPreview:OnReady()
    CUpgradeWorkshopPreview.Super.OnReady(self)
    self:BindUIData()
    self:Show()
end

-- 模拟扣款与升级，刷新其他行的余额资格，不执行真实业务。
-- @param action string Upgrade
-- @param payload table 含稳定 upgradeId
function CUpgradeWorkshopPreview:OnUIAction(action, payload)
    assert(action == "Upgrade", "Unknown upgrade action")
    local entry = self.State.entries[payload.upgradeId]
    assert(entry, "Unknown upgrade ID")
    if entry.maxed or entry.pending or not entry.canUpgrade then
        return
    end
    self._balance -= entry.price
    entry.level += 1
    entry.currentValue = entry.nextValue
    entry.nextValue = string.format("×%.2f", 1 + entry.level * 0.1)
    entry.price *= 2
    entry.maxed = entry.level >= self._maxLevel
    for upgradeId, currentEntry in pairs(self.State.entries) do
        currentEntry.canUpgrade = not currentEntry.maxed and self._balance >= currentEntry.price
    end
    self:RefreshUI()
end

return CUpgradeWorkshopPreview