local FX = _G.FX
local Preview = FX.Class("CRebirthPreviewCompClass", "CRebirthUICompClass")

-- 父构造后准备符合展示契约的模拟数据。
-- @param owner table 编辑器组件宿主
function Preview:Ctor(owner)
    Preview.Super.Ctor(self, owner)
    self.State = {
        Open = true,
        Level = 317,
        RequiredLevel = 325,
        Completed = false,
        CurrentStrengthMultiplier = 7,
        NextStrengthMultiplier = 7.5,
        CurrentMoneyMultiplier = 3.4,
        NextMoneyMultiplier = 3.6,
        SkipCost = 60,
        SkipAvailable = true,
    }
end

-- 演示数量缩写；正式游戏使用统一数量格式器，跳过价格仍由业务提供。
-- @param value number 原始数量
-- @return string 不含货币符号的数量，例如 60、1.98K
function Preview:FormatNumber(value)
    local suffixes = { "", "K", "M", "B", "T" }
    local scaled = value
    local index = 1
    while math.abs(scaled) >= 1000 and index < #suffixes do
        scaled = scaled / 1000
        index = index + 1
    end
    if index == 1 then
        return string.format("%.0f", scaled)
    end
    local amount = string.format("%.2f", scaled)
    amount = string.gsub(amount, "0+$", "")
    amount = string.gsub(amount, "%.$", "")
    return amount .. suffixes[index]
end

-- 先绑定节点，再绑定完整数据并显示界面。
function Preview:OnReady()
    Preview.Super.OnReady(self)
    self:BindUIData()
    self:Show()
end

-- 模拟即时成功；拒绝隐藏、未就绪、请求中及完成后的业务动作。
-- @param action string CloseRebirth / RequestSkip / RequestRebirth
-- @param payload table 空表，与展示���约一致
function Preview:OnUIAction(action, payload)
    if action == "CloseRebirth" then
        self.State.Open = false
    elseif action == "RequestSkip" or action == "RequestRebirth" then
        if not self.State.Open or self.State.RequiredLevel <= 0 or self.State.Completed or self.State.Pending or self.State.AtMax then
            return
        end
        if action == "RequestSkip" then
            assert(next(payload) == nil, "RequestSkip payload must be empty")
            -- 先呈现待处理态，价格仍由 State.SkipCost 驱动。
            self.State.Pending = true
            self:RefreshUI()
            print("模拟 Skip Pending：SkipCost=" .. self:FormatNumber(self.State.SkipCost))
            -- 模拟业务完成；随后停用按钮并演示价格变化及长数字缩写。
            self.State.Pending = false
            self.State.Level = self.State.RequiredLevel
            self.State.SkipAvailable = false
            self.State.SkipCost = 1980
            print("模拟 Skip 完成：未执行支付，SkipCost=" .. self:FormatNumber(self.State.SkipCost))
        elseif self.State.Level >= self.State.RequiredLevel then
            -- 仅模拟现有差值成长；真实倍率须由游戏业务提供。
            local strengthIncrease = self.State.NextStrengthMultiplier - self.State.CurrentStrengthMultiplier
            local moneyIncrease = self.State.NextMoneyMultiplier - self.State.CurrentMoneyMultiplier
            self.State.CurrentStrengthMultiplier = self.State.NextStrengthMultiplier
            self.State.CurrentMoneyMultiplier = self.State.NextMoneyMultiplier
            self.State.NextStrengthMultiplier = self.State.CurrentStrengthMultiplier + strengthIncrease
            self.State.NextMoneyMultiplier = self.State.CurrentMoneyMultiplier + moneyIncrease
            self.State.Level = 0
            self.State.Completed = true
            print("模拟重生：力量重置，未修改游戏数据")
        end
    else
        error("Unsupported rebirth action: " .. tostring(action))
    end
    self:RefreshUI()
end

return Preview
