-- 三处武器展示共用模型映射；只克隆模板，不修改导入资源。
local FX = _G.FX
local MutationVisual = FX.Loader:RequireFromParent(script, "MutationVisual")
local Templates = {}
for quality, weapon in pairs(_G.GameConfig.WeaponData) do
    Templates[quality] = FX.Loader:Shared(weapon.ModelPath)
end
local MutationTemplates = {}
for grade, mutation in pairs(_G.GameConfig.MiningRockData) do
    if mutation.EffectPath then
        MutationTemplates[mutation.MutationId] = FX.Loader:Shared(mutation.EffectPath)
    end
end
local Visual = {}
local AuraOffsets = {
    Head = Vector3.new(0, 2, 0),
    Torso = Vector3.new(0, 0.5, 0),
    ["Left Arm"] = Vector3.new(-1.5, 0.5, 0),
    ["Right Arm"] = Vector3.new(1.5, 0.5, 0),
    ["Left Leg"] = Vector3.new(-0.5, -1.5, 0),
    ["Right Leg"] = Vector3.new(0.5, -1.5, 0),
}

--- 复用变异矿石的粒子素材，把角色光环收窄到剑身周围。
--- @param root Part 已按目标高度缩放的武器根部件。
--- @param template Model 对应变异的光环素材。
local function addMutationAura(root, template)
    local heightScale = root.Size.Y / 5
    local offsetScale = Vector3.new(0.35, 1, 0.35) * heightScale
    local particleScale = 0.45 * heightScale
    local aura = Instance.new("Attachment")
    aura.Name = "MutationAura"
    for groupIndex, group in ipairs(template:GetChildren()) do
        local anchor = Instance.new("Attachment")
        anchor.Name = group.Name
        anchor.Position = AuraOffsets[group.Name]
        for childIndex, child in ipairs(group:GetChildren()) do
            child:Clone().Parent = anchor
        end
        anchor.Parent = aura
    end
    for index, node in ipairs(aura:GetDescendants()) do
        if node:IsA("Attachment") then
            node.Position *= offsetScale
        elseif node:IsA("ParticleEmitter") then
            node.Enabled = true
            node.LockedToPart = true
            node.LightEmission = 1
            node.Speed = NumberRange.new(node.Speed.Min * particleScale, node.Speed.Max * particleScale)
            node.Acceleration *= particleScale
            node.Rate *= particleScale
            node.ZOffset *= particleScale
            local points = {}
            for pointIndex, point in ipairs(node.Size.Keypoints) do
                points[pointIndex] = NumberSequenceKeypoint.new(point.Time,
                    point.Value * particleScale, point.Envelope * particleScale)
            end
            node.Size = NumberSequence.new(points)
        end
    end
    aura.Parent = root
end

--- 将任意多零件武器归一到指定高度，返回带真实包围尺寸的透明根部件。
--- @param quality number 配置中存在的武器品质。
--- @param height number 展示高度，单位 stud。
--- @param mutationId string? 武器的变异 ID，用于应用对应材质或光环。
--- @return Part 包含外观模型的可定位根部件，调用方负责挂载和销毁。
function Visual.Create(quality, height, mutationId)
    local model = Templates[quality]:Clone()
    MutationVisual.ApplyWeapon(model, mutationId)
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
    local mutationTemplate = mutationId and MutationTemplates[mutationId]
    if mutationTemplate then
        addMutationAura(root, mutationTemplate)
    end
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
