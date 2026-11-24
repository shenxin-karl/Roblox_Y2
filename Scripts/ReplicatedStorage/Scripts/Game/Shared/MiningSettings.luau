-- 公共矿场的交互距离、搬运状态和木棍规则。
local Settings = {
    GroundPath = "Decorations.MiningAreaDecorations.QuarryGround.InnerMiningSurface",
    RockTag = "PublicMiningRock",
    InteractDistance = 9,
    RequestCooldown = 0.4,
    RefreshAttribute = "PublicOreRefreshAt",
    CarryAttribute = "CarryingMiningOre",
    CarrySpeedMultiplier = 0.75,
    BaseDepositHeight = 9,
    QuarryVerticalRange = 12,
    StickName = "Wooden Stick",
    StickSwingAttribute = "MiningStickSwingAt",
    StickRange = 7,
    StickCooldown = 0.75,
    KnockdownDuration = 1.5,
}

--- 按横放的椭圆矿面判断刷新区，距地太远也不算在矿区内。
--- @param ground BasePart 横放的矿面。
--- @param position Vector3 角色根部位置。
--- @return boolean 是否在矿区内。
function Settings.IsInQuarry(ground, position)
    local offset = ground.CFrame:PointToObjectSpace(position)
    local size = ground.Size
    return math.abs(offset.X) <= Settings.QuarryVerticalRange
        and (offset.Y / (size.Y / 2)) ^ 2 + (offset.Z / (size.Z / 2)) ^ 2 <= 1
end

return Settings
