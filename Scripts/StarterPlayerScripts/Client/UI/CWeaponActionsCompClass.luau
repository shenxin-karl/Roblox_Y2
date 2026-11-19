-- 武器经济入口：复用人物旁动作按钮与通用确认框，不接管托管界面。
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local FX, FC = _G.FX, _G.FC
local Text = FX.Text
local Fields = _G.PlayerDataConfig
local Rules = FX.Loader:RequireShared("Scripts.Game.Shared.SwordRules")
local Utility = FX.Loader:RequireShared("Scripts.Game.Shared.GameUtility")
local ActionButton = FX.Loader:RequireFromParent(script, "CActionButton")
local Texts = Text.Define("WeaponActions", {
    Sell = "出售武器",
    SellPrice = "获得 ${value}",
    ConfirmSell = "确定以 ${value} 出售{name}吗？当前装备的武器将被移除。",
    Gift = "赠送剑胚",
    GiftTarget = "送给 {name}",
    ConfirmGift = "确定将当前装备的剑胚赠送给 {name} 吗？",
    ReceiveGift = "{name} wants to give you a {mutation} sword blank with luck level {blankLuckLevel:int}. Accept?",
    Confirm = "确认",
    Cancel = "取消",
})
local Comp = FX.Class("CWeaponActionsCompClass", "FCUICompClass")

--- 返回玩家对象中的稳定组件名。
--- @return string 武器操作组件名。
function Comp:GetCompName()
    return "CWeaponActionsComp"
end

--- 构造普通动作入口并监听语言、离线余额与服务器赠送请求。
function Comp:OnReady()
    self._common = self:GetOwner():RequireComponent("CCommonUICompClass")
    self._sell, self._sellTitle, self._sellDetail = ActionButton.New("SellWeapon")
    self._gift, self._giftTitle, self._giftDetail = ActionButton.New("GiftRawWeapon")
    self:TrackConnection(self._sell.Activated:Connect(function()
        local tool = self:GetEquippedTool()
        local sword = tool and self:GetSword(tool)
        if not sword then
            return
        end
        local grid = tool:GetAttribute("FrameworkGrid")
        self._common:ShowConfirm({DescKey = Texts.ConfirmSell, ConfirmKey = Texts.Confirm, CancelKey = Texts.Cancel,
            Arguments = {name = tool.Name, value = Utility.NumberToText(Rules.GetSellPrice(sword))},
            ConfirmCB = function()
                FX.Network:SendMsgToServer("C2S_SellSword", grid, sword)
            end})
    end))
    self:TrackConnection(self._gift.Activated:Connect(function()
        local target = self:GetNearestPlayer()
        if not target then
            return
        end
        self._common:ShowConfirm({DescKey = Texts.ConfirmGift, ConfirmKey = Texts.Confirm, CancelKey = Texts.Cancel,
            Arguments = {name = target.DisplayName}, ConfirmCB = function()
                FX.Network:SendMsgToServer("C2S_OfferRawSword", target.UserId)
            end})
    end))
    FX.Network:RegServerMsgCallback("S2C_RawSwordOffer", function(token, name, mutation, blankLuckLevel)
        self._common:ShowConfirm({DescKey = Texts.ReceiveGift, ConfirmKey = Texts.Confirm, CancelKey = Texts.Cancel,
            Arguments = {name = name, mutation = Text.TrSource(Rules.GetMutation(mutation).MutationName),
                blankLuckLevel = blankLuckLevel},
            ConfirmCB = function()
                FX.Network:SendMsgToServer("C2S_ReplyRawSword", token, true)
            end,
            CancelCB = function()
                FX.Network:SendMsgToServer("C2S_ReplyRawSword", token, false)
            end})
    end)
    self:TrackConnection(FC.Localization.Changed:Connect(function()
        self:Refresh()
    end))
    local elapsed = 0
    self:TrackConnection(RunService.Heartbeat:Connect(function(deltaTime)
        elapsed += deltaTime
        if elapsed >= 0.25 then
            elapsed = 0
            self:Refresh()
        end
    end))
end

--- 只读取实际角色中原生背包创建的工具，不把背包选中态当作装备。
--- @return Tool? 当前手持的框架道具。
function Comp:GetEquippedTool()
    local character = self:GetPlayerNode().Character
    local tool = character and character:FindFirstChildOfClass("Tool")
    return tool and tool:GetAttribute("FrameworkItemId") and tool or nil
end

--- 由服务端复制的属性计算展示价格；真正出售仍重新读取服务端存档。
--- @param tool Tool 当前装备工具。
--- @return table? 可展示的成品属性。
function Comp:GetSword(tool)
    if tool:GetAttribute("FrameworkItemId") ~= Rules.ItemId then
        return nil
    end
    local sword = {Quality = tool:GetAttribute("Quality"), Level = tool:GetAttribute("WeaponLevel"),
        MutationId = tool:GetAttribute("MutationId"), blankLuckLevel = tool:GetAttribute("blankLuckLevel"),
        StoredMoney = tool:GetAttribute("StoredMoney")}
    return Rules.IsValid(sword) and sword or nil
end

--- 使用身旁最近的玩家作为候选，发送前在确认框明确显示接收者姓名。
--- @return Player? 赠送距离内最近的其他玩家。
function Comp:GetNearestPlayer()
    local character = self:GetPlayerNode().Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
        return nil
    end
    local nearest, distance = nil, _G.GameConfig.CommonConfig.GiftDistance
    for index, player in ipairs(Players:GetPlayers()) do
        local targetRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if player ~= self:GetPlayerNode() and targetRoot then
            local offset = (root.Position - targetRoot.Position).Magnitude
            if offset <= distance then
                nearest, distance = player, offset
            end
        end
    end
    return nearest
end

--- 出售与赠送入口随手持物品变化，锻造近景隐藏人物操作。
function Comp:Refresh()
    local tool = self:GetEquippedTool()
    local sword = tool and self:GetSword(tool)
    local target = self:GetNearestPlayer()
    local visible = self:GetNumber(Fields.ForgeStation) == 0
    self._sell.Visible = visible and sword ~= nil
    self._gift.Visible = visible and tool ~= nil and tool:GetAttribute("FrameworkItemId") == Rules.BlankItemId and target ~= nil
    self._sellTitle.Text = Text.Tr(Texts.Sell)
    self._sellDetail.Text = sword and Text.Tr(Texts.SellPrice, {value = Utility.NumberToText(Rules.GetSellPrice(sword))}) or ""
    self._giftTitle.Text = Text.Tr(Texts.Gift)
    self._giftDetail.Text = target and Text.Tr(Texts.GiftTarget, {name = target.DisplayName}) or ""
end

--- 清理自有入口与网络回调；共用确认框和画布由通用组件负责。
function Comp:Dtor()
    FX.Network:UnRegServerMsgCallback("S2C_RawSwordOffer")
    Comp.Super.Dtor(self)
    if self._sell then
        self._sell:Destroy()
        self._gift:Destroy()
    end
end

return Comp
