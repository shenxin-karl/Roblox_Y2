local FX = _G.FX
local CWeaponMutationPreview = FX.Class("CWeaponMutationPreview", "CWeaponMutationView")

local Weapons = {
    {id = "iron", name = "Iron Blade", icon = "rbxassetid://72237625079956"},
    {id = "steel", name = "Steel Blade", icon = "rbxassetid://116034100288426", badgeIcon = "rbxassetid://73943238782407"},
    {id = "greatsword", name = "Greatsword", icon = "rbxassetid://114045323972770", badgeIcon = "rbxassetid://131760910444430"},
}
local Stones = {
    {id = "silver", name = "Silver Mutation Stone", icon = "rbxassetid://85648539250241", count = 2, details = "Applies the Silver mutation."},
    {id = "gold", name = "Gold Mutation Stone", icon = "rbxassetid://131845221291707", count = 3, details = "Applies the Gold mutation."},
    {id = "frost", name = "Frost Mutation Stone", icon = "rbxassetid://89620960090242", details = "Applies the Frost mutation."},
}
local IncomeByWeapon = {iron = 120, steel = 200, greatsword = 350}
local MutationMultiplier = {Normal = 1, Silver = 1.2, Inferno = 1.8}
local MutationByWeapon = {iron = "Normal", steel = "Silver", greatsword = "Inferno"}
local MutationIcons = {
    Silver = "rbxassetid://73943238782407",
    Gold = "rbxassetid://77978837493631",
    Frost = "rbxassetid://106224256982724",
    Inferno = "rbxassetid://131760910444430",
}
local Effects = {
    silver = {name = "Silver", bonusPercent = 20},
    gold = {name = "Gold", bonusPercent = 40},
    frost = {name = "Frost", bonusPercent = 60},
}

function CWeaponMutationPreview:Ctor(owner)
    CWeaponMutationPreview.Super.Ctor(self, owner)
    self.Config = {}
    self.State = {weapons = Weapons, stones = table.clone(Stones)}
end

function CWeaponMutationPreview:OnReady()
    CWeaponMutationPreview.Super.OnReady(self)
    self:BindUIData()
    self:Show()
end

function CWeaponMutationPreview:OnUIAction(action, payload)
    local state = self.State
    if action == "ChooseItem" then
        local items = payload.kind == "weapon" and state.weapons or state.stones
        for _, item in ipairs(items) do
            if item.id == payload.itemId then
                state[payload.kind] = if payload.clear then nil else item
                break
            end
        end
    elseif action == "Mutate" and state.weapon and state.stone
        and payload.weaponId == state.weapon.id and payload.stoneId == state.stone.id then
        local weapon = state.weapon
        local effect = Effects[state.stone.id]
        local baseIncome = IncomeByWeapon[weapon.id]
        local beforeMutation = MutationByWeapon[weapon.id]
        state.result = {
            weapon = {id = weapon.id, name = effect.name .. " " .. weapon.name, icon = weapon.icon},
            beforeMutationName = beforeMutation,
            afterMutationName = effect.name,
            afterMutationId = effect.name,
            beforeMutationIcon = MutationIcons[beforeMutation],
            afterMutationIcon = MutationIcons[effect.name],
            beforeIncomePerSecond = tostring(math.round(baseIncome * MutationMultiplier[beforeMutation])),
            afterIncomePerSecond = tostring(math.round(baseIncome * (100 + effect.bonusPercent) / 100)),
        }
        for index, item in ipairs(state.stones) do
            if item.id == payload.stoneId then
                if (item.count or 1) > 1 then
                    local remaining = table.clone(item)
                    remaining.count -= 1
                    state.stones[index] = remaining
                else
                    table.remove(state.stones, index)
                end
                break
            end
        end
    elseif action == "Done" then
        state.weapon = nil
        state.stone = nil
        state.result = nil
    end
    local weapon, stone = state.weapon, state.stone
    state.preview = nil
    if weapon and stone and not state.result then
        local effect = Effects[stone.id]
        local current = MutationByWeapon[weapon.id]
        local income = IncomeByWeapon[weapon.id]
        local currentIncome = income * MutationMultiplier[current]
        local targetIncome = income * (100 + effect.bonusPercent) / 100
        state.preview = {
            beforeMutationName = current,
            afterMutationName = effect.name,
            beforeIncomePerSecond = tostring(math.round(currentIncome)),
            afterIncomePerSecond = tostring(math.round(targetIncome)),
            incomeDecreases = targetIncome < currentIncome,
            sameMutation = current == effect.name,
        }
    end
    self:RefreshUI()
end

return CWeaponMutationPreview
