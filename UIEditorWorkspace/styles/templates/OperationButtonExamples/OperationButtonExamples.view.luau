local FX = _G.FX
local FXLoader = FX.Loader
local COperationButtonExamplesUIBaseCompClass = FX.Class("COperationButtonExamplesUIBaseCompClass", "FCUICompClass")

-- 使用稳定操作名发出动作，不执行购买或装备业务。
function COperationButtonExamplesUIBaseCompClass:OnReady()
    local root = FXLoader:PlayerGui("OperationButtonExamplesUI")
    local actions = {ConfirmBtn = "Confirm", CancelBtn = "Cancel", BuyBtn = "Buy", PaidPurchaseBtn = "PaidPurchase", EquipBtn = "Equip", UnequipBtn = "Unequip"}
    for name, action in pairs(actions) do
        local button = FXLoader:Here(root, "ContentImg." .. name)
        self:TrackConnection(button.Activated:Connect(function()
            self:EmitUIAction(action, {})
        end))
    end
end

return COperationButtonExamplesUIBaseCompClass