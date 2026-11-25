-- 剑胚赠送入口：复用人物旁动作按钮与通用确认框。
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local FX, FC = _G.FX, _G.FC
local Text = FX.Text
local Fields = _G.PlayerDataConfig
local Rules = FX.Loader:RequireShared("Scripts.Game.Shared.SwordRules")
local ActionButton = FX.Loader:RequireFromParent(script, "CActionButton")
local TranslationTexts = Text.Define("WeaponActions", {
    Gift = "Gift Sword Blank",
    GiftTarget = "Give to {name}",
    ConfirmGift = "Give your equipped sword blank to {name}?",
    ReceiveGift = "{name} wants to give you a {mutation} sword blank with luck level {blankLuckLevel:int}. Accept?",
    Confirm = "Confirm",
    Cancel = "Cancel",
})
local Comp = FX.Class("CWeaponActionsCompClass", "FCUICompClass")

--- 返回玩家对象中的稳定组件名。
--- @return string 武器操作组件名。
function Comp:GetCompName()
    return "CWeaponActionsComp"
end

--- 构造赠送入口并监听语言变化与服务器赠送请求。
function Comp:OnReady()
    self._common = self:GetOwner():RequireComponent("CCommonUICompClass")
    self._gift, self._giftTitle, self._giftDetail = ActionButton.New("GiftRawWeapon")
    self:TrackConnection(self._gift.Activated:Connect(function()
        local target = self:GetNearestPlayer()
        if not target then
            return
        end
        self._common:ShowConfirm({DescKey = TranslationTexts.ConfirmGift,
            ConfirmKey = TranslationTexts.Confirm, CancelKey = TranslationTexts.Cancel,
            Arguments = {name = target.DisplayName}, ConfirmCB = function()
                FX.Network:SendMsgToServer("C2S_OfferRawSword", target.UserId)
            end})
    end))
    FX.Network:RegServerMsgCallback("S2C_RawSwordOffer", function(token, name, mutation, blankLuckLevel)
        self._common:ShowConfirm({DescKey = TranslationTexts.ReceiveGift,
            ConfirmKey = TranslationTexts.Confirm, CancelKey = TranslationTexts.Cancel,
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

--- 赠送入口随手持物品变化，锻造近景隐藏人物操作。
function Comp:Refresh()
    local tool = self:GetEquippedTool()
    local target = self:GetNearestPlayer()
    local visible = self:GetNumber(Fields.ForgeStation) == 0
    self._gift.Visible = visible and tool ~= nil and tool:GetAttribute("FrameworkItemId") == Rules.BlankItemId and target ~= nil
    self._giftTitle.Text = Text.Tr(TranslationTexts.Gift)
    self._giftDetail.Text = target and Text.Tr(TranslationTexts.GiftTarget, {name = target.DisplayName}) or ""
end

--- 清理自有入口与网络回调；共用确认框和画布由通用组件负责。
function Comp:Dtor()
    FX.Network:UnRegServerMsgCallback("S2C_RawSwordOffer")
    Comp.Super.Dtor(self)
    if self._gift then
        self._gift:Destroy()
    end
end

return Comp
