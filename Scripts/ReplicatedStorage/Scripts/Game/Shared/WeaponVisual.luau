-- 三处武器展示共用模型映射；只克隆模板，不修改导入资源。
local FX = _G.FX
local Templates = {}
for quality, weapon in pairs(_G.GameConfig.WeaponData) do
    Templates[quality] = FX.Loader:Shared(weapon.ModelPath)
end
local Visual = {}

--- 将任意多零件武器归一到指定高度，返回带真实包围尺寸的透明根部件。
--- @param quality number 配置中存在的武器品质。
--- @param height number 展示高度，单位 stud。
--- @return Part 包含外观模型的可定位根部件，调用方负责挂载和销毁。
function Visual.Create(quality, height)
    local model = Templates[quality]:Clone()
    for index, node in ipairs(model:GetDescendants()) do
        if node:IsA("BaseScript") or node:IsA("ModuleScript") then
            node:Destroy()
        end
    end
    local frame, size = model:GetBoundingBox()
    model:ScaleTo(model:GetScale() * height / size.Y)
    frame, size = model:GetBoundingBox()
    model:PivotTo(frame:Inverse() * model:GetPivot())
    local root = Instance.new("Part")
    root.Name, root.Size, root.Transparency = "Sword", size, 1
    root.Anchored, root.CanCollide, root.CanTouch, root.CanQuery = true, false, false, false
    root.Massless = true
    for index, node in ipairs(model:GetDescendants()) do
        if node:IsA("BasePart") then
            node.Anchored, node.CanCollide, node.CanTouch, node.CanQuery = false, false, false, false
            node.Massless = true
            local weld = Instance.new("WeldConstraint")
            weld.Part0, weld.Part1, weld.Parent = root, node, node
        end
    end
    model.Parent = root
    return root
end

--- 挂入场景前同时定位透明根和外观；此时焊接尚未激活，不能只移动根部件。
--- @param root Part Create返回的、尚未挂入场景的武器根部件。
--- @param target CFrame 武器根部件的目标位置和朝向。
function Visual.SetCFrame(root, target)
    local model = root:FindFirstChildOfClass("Model")
    model:PivotTo(target * root.CFrame:Inverse() * model:GetPivot())
    root.CFrame = target
end

return Visual
