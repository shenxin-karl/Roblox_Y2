-- 中央矿场交互几何；私人刷新与兑换数值统一由源配置表维护。
local Settings = {
    GroundPath = "Decorations.MiningAreaDecorations.QuarryGround.InnerMiningSurface",
    FurnacePath = "Decorations.Forge.PublicFurnace.ProjectingStoneHearth",
    RockTag = "PublicMiningRock",
    InteractDistance = 9,
    RequestCooldown = 0.4,
}

--- 按物体包围盒判断火炉交互距离，避免使用烟囱抬高后的模型中心。
--- @param part BasePart 已确认的火炉炉台。
--- @param position Vector3 当前角色位置。
--- @return number 到炉台表面的距离。
function Settings.DistanceToPart(part, position)
    local offset = part.CFrame:PointToObjectSpace(position)
    local half = part.Size / 2
    local nearest = Vector3.new(
        math.clamp(offset.X, -half.X, half.X),
        math.clamp(offset.Y, -half.Y, half.Y),
        math.clamp(offset.Z, -half.Z, half.Z)
    )
    return (offset - nearest).Magnitude
end

return Settings
