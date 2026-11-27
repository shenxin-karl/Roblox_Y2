-- 武器全表面的变异渐变，以及共用的彩虹轮色。
local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Visual = {}
local RainbowTag = "RainbowMutationPart"
local WeaponFinishTag = "WeaponMutationFinish"
local BladeFlowTag = "WeaponMutationBladeFlow"
local RainbowColors = {
    Color3.fromRGB(255, 38, 88),
    Color3.fromRGB(255, 142, 34),
    Color3.fromRGB(255, 218, 58),
    Color3.fromRGB(54, 238, 84),
    Color3.fromRGB(37, 218, 244),
    Color3.fromRGB(43, 90, 255),
    Color3.fromRGB(150, 51, 255),
    Color3.fromRGB(248, 51, 190),
}
local Finishes = {
    Silver = {Color3.fromRGB(103, 126, 151), Color3.fromRGB(177, 201, 226), Color3.fromRGB(244, 251, 255)},
    Gold = {Color3.fromRGB(179, 95, 7), Color3.fromRGB(255, 176, 22), Color3.fromRGB(255, 231, 127)},
    Diamond = {Color3.fromRGB(31, 129, 209), Color3.fromRGB(67, 217, 249), Color3.fromRGB(219, 255, 255)},
}

--- 给武器副本的完整网格换色，保留几何、棱线和原始武器模板。
--- @param model Model 尚未放入场景的武器副本。
--- @param mutationId string? 当前武器的变异 ID。
--- @return boolean 是否使用整把武器变异材质。
function Visual.ApplyWeaponFinish(model, mutationId)
    local colors = Finishes[mutationId]
    local rainbow = mutationId == "Rainbow"
    if not colors and not rainbow then
        return false
    end
    for index, part in ipairs(model:GetDescendants()) do
        if part:IsA("MeshPart") and part.Transparency < 1 then
            local appearance = part:FindFirstChildOfClass("SurfaceAppearance")
            if appearance then
                appearance:Destroy()
            end
            part.TextureContent = Content.none
            part.MaterialVariant = ""
            part.Material = rainbow and Enum.Material.SmoothPlastic or Enum.Material.Metal
            part.Reflectance = rainbow and 0 or 0.08
            part.Color = rainbow and RainbowColors[1] or colors[2]
            part:SetAttribute("WeaponFinish", mutationId)
            part:AddTag(WeaponFinishTag)
        end
    end
    return true
end

--- 让晶莹闪点跟随武器，并沿用锻造近景的显隐控制。
--- @param aura Attachment 武器变异特效容器。
--- @param size Vector3 武器缩放后的包围尺寸。
function Visual.AddWeaponSparkles(aura, size)
    local anchor = Instance.new("Attachment")
    anchor.Name = "BladeSparkles"
    anchor.Position = Vector3.new(0, size.Y * 0.16, 0)
    local sparkles = Instance.new("ParticleEmitter")
    sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    sparkles.Color = ColorSequence.new(Color3.fromRGB(221, 248, 255))
    sparkles.LightEmission, sparkles.LockedToPart = 1, true
    sparkles.Rate = 5
    sparkles.Lifetime = NumberRange.new(0.45, 0.75)
    sparkles.Speed = NumberRange.new(0.35, 0.75)
    sparkles.SpreadAngle = Vector2.new(60, 60)
    sparkles.Size = NumberSequence.new(0.055 * size.Y, 0)
    sparkles.Parent = anchor
    anchor.Parent = aura
end

--- 让细光沿剑身两面流向剑尖；武器静止或转动时都沿本地剑身移动。
--- @param aura Attachment 武器根部件下用于统一显隐的变异特效容器。
--- @param size Vector3 缩放后的武器包围尺寸。
--- @param color ColorSequence 原有光环的粒子色。
function Visual.AddWeaponFlow(aura, size, color)
    local transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.3, 0.88),
        NumberSequenceKeypoint.new(0.74, 0.24),
        NumberSequenceKeypoint.new(1, 1),
    })
    local width = math.min(size.X * 0.22, size.Y * 0.043)
    for sideIndex, side in ipairs({-1, 1}) do
        local depth = (size.Z * 0.43 + 0.015) * side
        local tail, tip = Instance.new("Attachment"), Instance.new("Attachment")
        tail.Name, tip.Name = "BladeFlowTail", "BladeFlowTip"
        tail.Position, tip.Position = Vector3.new(0, 0, depth), Vector3.new(0, 0, depth)
        tail.Parent, tip.Parent = aura, aura
        local beam = Instance.new("Beam")
        beam.Name = "BladeFlow"
        beam.Attachment0, beam.Attachment1 = tail, tip
        beam.FaceCamera, beam.Segments = true, 12
        beam.LightEmission, beam.LightInfluence = 0.48, 0
        beam.Width0, beam.Width1 = width * 0.35, width
        beam.Color, beam.Transparency = color, transparency
        beam:AddTag(BladeFlowTag)
        beam.Parent = aura
    end
end

if RunService:IsClient() then
    local PaletteWidth = 128
    local PaletteSize = Vector2.new(PaletteWidth, 1)
    local parts, flows, weapons = {}, {}, {}
    local palettes = {}
    local projectedMeshes = setmetatable({}, {__mode = "v"})
    local stepConnection
    local elapsed = 0

    --- 从深色到亮色取样，亮色随时间从剑柄向剑尖移动。
    --- @param colors table 深色、中间色、亮色。
    --- @param position number 从剑柄底端到剑尖的相对位置。
    --- @param phase number 当前动画相位。
    --- @return Color3 该位置当前的颜色。
    local function sampleGradient(colors, position, phase)
        local blend = 1 - math.cos((position - phase) * 2 * math.pi)
        if blend < 1 then
            return colors[1]:Lerp(colors[2], blend)
        end
        return colors[2]:Lerp(colors[3], blend - 1)
    end

    --- 同变异的所有武器共用一条动态贴图，避免按武器更新像素。
    --- @param palette table 贴图和可复用的 RGBA 缓冲。
    --- @param colors table 当前变异的渐变色板。
    --- @param phase number 当前动画相位。
    local function writeGradient(palette, colors, phase)
        for index = 0, PaletteWidth - 1 do
            local color = sampleGradient(colors, index / (PaletteWidth - 1), phase)
            local offset = index * 4
            buffer.writeu8(palette.Pixels, offset, math.round(color.R * 255))
            buffer.writeu8(palette.Pixels, offset + 1, math.round(color.G * 255))
            buffer.writeu8(palette.Pixels, offset + 2, math.round(color.B * 255))
            buffer.writeu8(palette.Pixels, offset + 3, 255)
        end
        palette.Image:WritePixelsBuffer(Vector2.zero, PaletteSize, palette.Pixels)
    end

    --- 动态贴图不可用时继续使用覆盖整个网格的变异底色。
    --- @param mutation string 当前武器的变异 ID。
    --- @return table? 可用的共享色带。
    local function getPalette(mutation)
        if palettes[mutation] == nil then
            local image
            local ok, palette = pcall(function()
                image = AssetService:CreateEditableImage({Size = PaletteSize})
                if not image then
                    return nil
                end
                local created = {Image = image, Content = Content.fromObject(image), Pixels = buffer.create(PaletteWidth * 4)}
                writeGradient(created, Finishes[mutation], 0)
                return created
            end)
            if not ok or not palette then
                if image then
                    image:Destroy()
                end
                palettes[mutation] = false
                return nil
            end
            palettes[mutation] = palette
        end
        return palettes[mutation] or nil
    end

    --- 把每个三角面的贴图坐标按顶点高度统一投影，正反面和侧刃因此使用同一渐变。
    --- @param source Content 武器原始网格，不修改其顶点、法线或资产。
    --- @return MeshPart? 可供武器副本复用的投影网格。
    local function createProjectedMesh(source)
        local editable
        local ok, template = pcall(function()
            editable = AssetService:CreateEditableMeshAsync(source, {FixedSize = false})
            if not editable then
                return nil
            end
            local vertices = editable:GetVertices()
            local heights, low, high = {}, math.huge, -math.huge
            for index, vertex in ipairs(vertices) do
                local y = editable:GetPosition(vertex).Y
                heights[vertex], low, high = y, math.min(y, low), math.max(y, high)
            end
            local uvIds = {}
            for index = 0, PaletteWidth - 1 do
                uvIds[index] = editable:AddUV(Vector2.new((index + 0.5) / PaletteWidth, 0.5))
            end
            for index, vertex in ipairs(vertices) do
                heights[vertex] = uvIds[math.round((heights[vertex] - low) / (high - low) * (PaletteWidth - 1))]
            end
            for index, face in ipairs(editable:GetFaces()) do
                local corners = editable:GetFaceVertices(face)
                editable:SetFaceUVs(face, {heights[corners[1]], heights[corners[2]], heights[corners[3]]})
                if index % 2048 == 0 then
                    task.wait()
                end
            end
            local result, content = AssetService:CreateDataModelContentAsync(Content.fromObject(editable))
            if result == Enum.CreateContentResult.Success then
                return AssetService:CreateMeshPartAsync(content, {CollisionFidelity = Enum.CollisionFidelity.Box})
            end
            return nil
        end)
        if editable then
            editable:Destroy()
        end
        return ok and template or nil
    end

    --- 贴图就绪后替换本地渲染网格，保留武器尺寸与原有焊接。
    --- @param part MeshPart 副本中正在渲染的武器网格。
    --- @param state table 该网格的变异表现状态。
    --- @param template MeshPart? 已投影的同款网格。
    local function applyProjection(part, state, template)
        if not template or weapons[part] ~= state then
            return
        end
        local size = part.Size
        part:ApplyMesh(template)
        part.Size = size
        part.Color = Color3.new(1, 1, 1)
        part.TextureContent = state.Palette.Content
        state.Projected = true
    end

    --- 同款武器共用投影网格；未显示的背包武器不会提前创建网格。
    --- @param part MeshPart 当前进入可见场景的武器网格。
    --- @param state table 客户端记录的变异表现状态。
    --- @param mutation string 当前武器的变异 ID。
    local function requestProjection(part, state, mutation)
        state.Requested = true
        state.Palette = getPalette(mutation)
        if not state.Palette then
            return
        end
        local meshId = part.MeshId
        local entry = projectedMeshes[meshId]
        if entry then
            state.Mesh = entry
            if entry.Waiting then
                entry.Waiting[part] = state
            else
                applyProjection(part, state, entry.Template)
            end
            return
        end

        local source = part.MeshContent
        entry = {Waiting = {[part] = state}}
        projectedMeshes[meshId], state.Mesh = entry, entry
        task.spawn(function()
            entry.Template = createProjectedMesh(source)
            local waiting = entry.Waiting
            entry.Waiting = nil
            for target, targetState in pairs(waiting) do
                applyProjection(target, targetState, entry.Template)
            end
        end)
    end

    --- 同步彩虹、武器全表面渐变和其余变异的短光带。
    --- @param deltaTime number 上一帧消耗的秒数。
    local function updateVisuals(deltaTime)
        elapsed += deltaTime
        if elapsed < 1 / 30 then
            return
        end
        elapsed %= 1 / 30
        local now = workspace:GetServerTimeNow()
        local phase = (now % 3) * #RainbowColors / 3
        local index = math.floor(phase)
        local rainbow = RainbowColors[index + 1]:Lerp(RainbowColors[(index + 1) % #RainbowColors + 1], phase - index)
        local gradientPhase = (now % 1.9) / 1.9
        local active, fallback = {}, {}
        for part in pairs(parts) do
            if part:IsDescendantOf(workspace) or part:FindFirstAncestorWhichIsA("ViewportFrame") then
                part.Color = rainbow
            end
        end
        for part, state in pairs(weapons) do
            if part:IsDescendantOf(workspace) or part:FindFirstAncestorWhichIsA("ViewportFrame") then
                local mutation = part:GetAttribute("WeaponFinish")
                local colors = Finishes[mutation]
                if mutation == "Rainbow" then
                    part.Color = rainbow
                elseif colors then
                    if not state.Requested then
                        requestProjection(part, state, mutation)
                    end
                    if state.Projected then
                        active[mutation] = state.Palette
                    else
                        fallback[mutation] = fallback[mutation] or sampleGradient(colors, 0.5, gradientPhase)
                        part.Color = fallback[mutation]
                    end
                end
            end
        end
        for mutation, palette in pairs(active) do
            writeGradient(palette, Finishes[mutation], gradientPhase)
        end
        for beam in pairs(flows) do
            local tail, tip = beam.Attachment0, beam.Attachment1
            local aura = beam.Parent
            local root = aura and aura.Parent
            if beam.Enabled and root and root:IsDescendantOf(workspace) and tail and tip then
                local progress = (now % 1.65) / 1.15
                local head = math.clamp(-0.13 + progress * 0.8, -0.13, 0.49)
                local trail = math.clamp(-0.13 + progress * 0.8 - 0.18, -0.13, 0.49)
                tail.Position = Vector3.new(0, trail * root.Size.Y, tail.Position.Z)
                tip.Position = Vector3.new(0, head * root.Size.Y, tip.Position.Z)
            end
        end
    end

    --- 在首次出现变异表现时启动客户端刷新。
    local function startIfIdle()
        if not stepConnection then
            stepConnection = RunService.Heartbeat:Connect(updateVisuals)
        end
    end

    --- 注册矿石等复用原有标签的彩虹部件。
    --- @param part Instance 添加彩虹标签的实例。
    local function trackPart(part)
        if part:IsA("BasePart") and not part:IsDescendantOf(ReplicatedStorage) then
            parts[part] = true
            startIfIdle()
        end
    end

    --- 注册整把武器的变异网格，投影网格在第一次显示时加载。
    --- @param part Instance 添加武器变异标签的实例。
    local function trackWeapon(part)
        if part:IsA("MeshPart") then
            weapons[part] = {}
            startIfIdle()
        end
    end

    --- 注册其他变异的短光带。
    --- @param beam Beam 原有光环搭配的移动光带。
    local function trackFlow(beam)
        flows[beam] = true
        startIfIdle()
    end

    --- 没有变异表现时停止客户端刷新。
    local function stopIfIdle()
        if stepConnection and not next(parts) and not next(flows) and not next(weapons) then
            stepConnection:Disconnect()
            stepConnection = nil
        end
    end

    CollectionService:GetInstanceAddedSignal(RainbowTag):Connect(trackPart)
    CollectionService:GetInstanceRemovedSignal(RainbowTag):Connect(function(part)
        parts[part] = nil
        stopIfIdle()
    end)
    CollectionService:GetInstanceAddedSignal(WeaponFinishTag):Connect(trackWeapon)
    CollectionService:GetInstanceRemovedSignal(WeaponFinishTag):Connect(function(part)
        weapons[part] = nil
        stopIfIdle()
    end)
    CollectionService:GetInstanceAddedSignal(BladeFlowTag):Connect(trackFlow)
    CollectionService:GetInstanceRemovedSignal(BladeFlowTag):Connect(function(beam)
        flows[beam] = nil
        stopIfIdle()
    end)
    for index, part in ipairs(CollectionService:GetTagged(RainbowTag)) do
        trackPart(part)
    end
    for index, part in ipairs(CollectionService:GetTagged(WeaponFinishTag)) do
        trackWeapon(part)
    end
    for index, beam in ipairs(CollectionService:GetTagged(BladeFlowTag)) do
        trackFlow(beam)
    end
end

return Visual
