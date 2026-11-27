-- 私人工坊的八档配色与短特效；两项升级各用自己的等级。
local Visuals = {}
local RGB = Color3.fromRGB
local White = Color3.new(1, 1, 1)
local Spark = "rbxasset://textures/particles/sparkles_main.dds"
local Smoke = "rbxasset://textures/particles/smoke_main.dds"
local Ring = "rbxasset://textures/particles/explosion01_shockwave_main.dds"
local Tiers = {
    {Level = 1, Color = RGB(255, 138, 36), Accent = RGB(255, 204, 103), Texture = Spark, Speed = 5, Size = 0.3},
    {Level = 4, Color = RGB(245, 56, 77), Accent = RGB(255, 132, 112), Texture = Spark, Speed = 8, Size = 0.45},
    {Level = 8, Color = RGB(50, 117, 255), Accent = RGB(131, 228, 255), Texture = Spark, Speed = 11, Size = 0.4},
    {Level = 12, Color = RGB(239, 113, 61), Accent = RGB(33, 217, 186), Texture = Smoke, Speed = 3, Size = 0.8},
    {Level = 16, Color = RGB(22, 216, 125), Accent = RGB(255, 204, 93), Texture = Spark, Speed = 7, Size = 0.5},
    {Level = 20, Color = RGB(255, 211, 65), Accent = RGB(255, 239, 159), Texture = Ring, Speed = 0, Size = 2.8},
    {Level = 24, Color = RGB(162, 89, 255), Accent = RGB(255, 79, 216), Texture = Spark, Speed = 6, Size = 0.65},
    {Level = 28, Color = RGB(80, 232, 250), Accent = RGB(221, 251, 255), Texture = Smoke, Speed = 2, Size = 0.9},
}
local ForgeBody = {SteelLeg = true, LongApron = true, EndUpperApron = true, LongLowerBeam = true,
    EndLowerBeam = true, ClosedDrawer = true, BlackForgedHammerHead = true}
local ForgeTrim = {MachinedDesktopEdge = true, MachinedDesktopEnd = true, CornerIronStrap = true,
    BlackHammerCollar = true}
local GateBody = {BlueSkirt = true, BlueCrown = true, BackWall = true, GateSteel = true}
local DragonBody = {LowerJaw = true, ChinPlate = true, DragonNeck = true, BrowArmor = true,
    UpperSnout = true, MuzzlePlate = true, UpperLip = true, HoodBridge = true, CrownScale = true}
local DragonFurnaces = {[5] = "EmeraldDragon", [6] = "SolarWingDragon",
    [7] = "AstralOrbitDragon", [8] = "FrostCoilDragon"}

--- 只给可见饰面和火光换色；记录原色供私人基地释放时恢复。
--- @param model Model 现有台面、锤子或炉体。
--- @param tier number 外观档位。
--- @param kind string 设施类别：Forge 或 Furnace。
--- @return table 可还原的原始属性。
function Visuals.ApplyColors(model, tier, kind)
    -- 高阶龙炉使用各自的原生材质和配色，保留眼睛、炉心与鳞片之间的对比。
    if kind == "Furnace" and tier >= 6 then
        return {}
    end
    local style = Tiers[tier]
    local originals = {}
    for index, node in ipairs(model:GetDescendants()) do
        local name = node.Name
        if node:IsA("BasePart") then
            local color
            if kind == "Forge" then
                if ForgeBody[name] then
                    color = style.Color
                elseif ForgeTrim[name] or node.Parent.Name == "BlueNeonOutline" then
                    color = style.Accent
                end
            elseif tier < 3 then
                if name == "ArchKeystone" or name == "HoodIronBelt" or name == "HoodCrownEdge"
                    or name:match("^ArchVoussoir") or name:match("^ArchLowerJamb") then
                    color = style.Color
                end
            elseif tier < 5 then
                if GateBody[name] or name:match("^SideArmor") or name:match("^FaceColumn")
                    or name:match("^Shoulder") then
                    color = style.Color
                elseif name:match("^ColumnStripe") or name:match("^BlueHeat") or name:match("^DuctCap") then
                    color = style.Accent
                end
            elseif DragonBody[name] or name:match("^OuterCheek") or name:match("^TempleScale")
                or name:match("^CheekFin") or name == "JadePlinthBand" then
                color = style.Color
            elseif name:match("^EyeGlow") or name:match("^HornTip") or name == "DragonHeatGlow"
                or name == "CrownGem" then
                color = style.Accent
            end
            if color then
                originals[node] = {Color = node.Color}
                node.Color = color
            end
        elseif kind == "Furnace" and tier ~= 3 then
            if node:IsA("Fire") then
                originals[node] = {Color = node.Color, SecondaryColor = node.SecondaryColor}
                node.Color, node.SecondaryColor = style.Color, style.Accent
            elseif node:IsA("PointLight") then
                originals[node] = {Color = node.Color}
                node.Color = style.Color
            end
        end
    end
    return originals
end

--- 基地释放或档位变化时恢复场景原件的颜色。
--- @param originals table 原件的颜色快照。
function Visuals.RestoreColors(originals)
    for node, properties in pairs(originals) do
        for property, value in pairs(properties) do
            node[property] = value
        end
    end
end

--- 把显示等级映射成八档外观索引。
--- @param level number 从 1 起算的锻造或熔炉等级。
--- @return number 外观档位。
function Visuals.GetTier(level)
    for index = #Tiers, 2, -1 do
        if level >= Tiers[index].Level then
            return index
        end
    end
    return 1
end

--- 读取指定档位的主体色、辅色和粒子样式。
--- @param tier number 外观档位。
--- @return table 此档外观设置。
function Visuals.GetStyle(tier)
    return Tiers[tier]
end

--- 给私人设备铺上展板式的深色地台和档位亮边，不改变通行或交互。
--- @param parent Model 私人工坊，独立于会被替换的炉体。
--- @param name string 对应设备的地台名称。
--- @param ground CFrame 设备下方地面的中心与朝向。
--- @param size Vector2 地台的宽和深。
--- @param tier number 对应设备的外观档位。
--- @return Folder 可随玩家会话清理的地台。
function Visuals.CreateFloor(parent, name, ground, size, tier)
    local style = Tiers[tier]
    local floor = Instance.new("Folder")
    floor.Name = name
    local rim = Instance.new("Part")
    rim.Name = "ColorRim"
    rim.Anchored = true
    rim.CanCollide = false
    rim.CanTouch = false
    rim.CanQuery = false
    rim.CastShadow = false
    rim.Size = Vector3.new(size.X, 0.08, size.Y)
    rim.CFrame = ground * CFrame.new(0, 0.06, 0)
    rim.Material = Enum.Material.Neon
    rim.Color = style.Color
    local surface = rim:Clone()
    surface.Name = "FloorSurface"
    surface.Size = Vector3.new(size.X - 0.34, 0.08, size.Y - 0.34)
    surface.CFrame = ground * CFrame.new(0, 0.085, 0)
    surface.Material = Enum.Material.SmoothPlastic
    surface.Color = RGB(24, 29, 39):Lerp(style.Color, 0.22)
    rim.Parent = floor
    surface.Parent = floor
    floor.Parent = parent
    return floor
end

--- 前四档沿用现有炉体，后四档各用一套龙炉。
--- @param tier number 熔炉外观档位。
--- @return string? 升级炉体名称；初期用原石炉。
function Visuals.GetFurnaceTemplateName(tier)
    return if tier < 3 then nil elseif tier < 5 then "CobaltGate" else DragonFurnaces[tier]
end

--- 在落锤点或炉口准备一个默认关闭的短粒子发射器。
--- @param origin BasePart|Attachment 粒子的发射位置。
--- @return ParticleEmitter 随父节点清理的发射器。
function Visuals.CreateBurst(origin)
    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "WorkshopBurst"
    emitter.Enabled = false
    emitter.Rate = 0
    emitter.LightInfluence = 0
    emitter.Lifetime = NumberRange.new(0.25, 0.48)
    emitter.Transparency = NumberSequence.new(0.12, 1)
    emitter.Drag = 2
    emitter.Parent = origin
    return emitter
end

--- 设置单次反馈的样式，蒸汽柔和上升，冰雾低散，光环原地扩开。
--- @param emitter ParticleEmitter 短特效发射器。
--- @param tier number 外观档位。
--- @return number 本次采用的粒子数量。
function Visuals.SetBurstStyle(emitter, tier)
    local style = Tiers[tier]
    local mist = style.Texture == Smoke
    local ring = style.Texture == Ring
    local color = if tier == 4 then White else style.Color
    emitter.Texture = style.Texture
    emitter.Color = ColorSequence.new(color, style.Accent)
    emitter.LightEmission = mist and 0.15 or 0.8
    emitter.Speed = NumberRange.new(style.Speed * 0.55, style.Speed)
    emitter.SpreadAngle = if tier == 4 then Vector2.new(28, 28) else Vector2.new(68, 68)
    emitter.Acceleration = Vector3.new(0, if tier == 8 then -3 elseif mist then 3 else 0, 0)
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, style.Size * (ring and 0.3 or 0.7)),
        NumberSequenceKeypoint.new(0.55, style.Size),
        NumberSequenceKeypoint.new(1, style.Size * ((mist or ring) and 1.4 or 0.2)),
    })
    return if ring then 1 elseif mist then 6 else 10
end

return Visuals
