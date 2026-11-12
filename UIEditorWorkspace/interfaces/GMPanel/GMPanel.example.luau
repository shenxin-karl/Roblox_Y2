local FX = _G.FX
local CGMPanelPreview = FX.Class("CGMPanelPreview", "CGMPanelView")

-- 准备模拟数据，不连接真实存档。
-- @param owner table 编辑器组件宿主
function CGMPanelPreview:Ctor(owner)
    CGMPanelPreview.Super.Ctor(self, owner)
    self.Config = {}
    self.State = { pending = false }
    self.Data = { SetLevel = 1, SetRebirth = 0, SetMoney = 0, SetDiamonds = 0 }
    self.Items = {}
    self.AllCollectionsUnlocked = false
    -- 沿用重生界面的模拟目标；真实接入从当前重生配置重新计算。
    self.RequiredRebirthLevel = 325
end

-- 父方法绑定完成后初始化并显示。
function CGMPanelPreview:OnReady()
    CGMPanelPreview.Super.OnReady(self)
    self:BindUIData()
    self:Show()
end

-- 模拟命令仅更新内存；保存按钮仅模拟成功反馈。
-- @param action string 稳定命令名
-- @param payload table 设置命令的 value/param2/param3、AddItem 的 itemId/count 或空表
function CGMPanelPreview:OnUIAction(action, payload)
    if action == "Close" then
        return
    elseif action == "ResetData" then
        self.Data = { SetLevel = 1, SetRebirth = 0, SetMoney = 0, SetDiamonds = 0 }
        self.Items = {}
        self.AllCollectionsUnlocked = false
        print("模拟：数据已重置")
    elseif action == "SaveNow" then
        print("模拟：立即保存成功")
    elseif action == "ReachRebirthLevel" then
        self.Data.SetLevel = math.max(self.Data.SetLevel, self.RequiredRebirthLevel)
        print("模拟：等级已达到当前重生要求，当前等级 " .. tostring(self.Data.SetLevel))
    elseif action == "UnlockAllCollections" then
        self.AllCollectionsUnlocked = true
        print("模拟：已解锁全部图鉴（未发放道具）")
    elseif action == "AddItem" then
        self.Items[payload.itemId] = (self.Items[payload.itemId] or 0) + payload.count
        print("模拟：已添加道具 " .. tostring(payload.itemId) .. " × " .. tostring(payload.count))
    else
        self.Data[action] = payload.value
        local labels = { SetLevel = "等级", SetRebirth = "重生", SetMoney = "金钱", SetDiamonds = "钻石" }
        print("模拟：" .. labels[action] .. "已设置为 " .. tostring(payload.value))
    end
    self:RefreshUI()
end

return CGMPanelPreview
