-- 公共矿场的场景路径、矿石标记和刷新规则。
local Settings = {
    GroundPath = "Decorations.MiningAreaDecorations.QuarryGround.InnerMiningSurface",
    BeltPath = "Decorations.MiningAreaDecorations.OreRingConveyor",
    BeltLapTime = 42,
    SeatsPath = "Decorations.MiningAreaDecorations.OreRingSeats",
    SeatAttribute = "IsMiningClawSeat",
    SeatVacantAttribute = "MiningClawSeatVacant",
    ClawHeight = 2,
    ClawEdgeMargin = 5,
    ClawTag = "MiningClawVisual",
    ClawOutSpeed = 82,
    ClawReturnSpeed = 72,
    ClawGripTime = 0.18,
    ClawJawHinge = 0.75,
    RockTag = "PublicMiningRock",
    RequestCooldown = 0.4,
    RefreshAttribute = "PublicOreRefreshAt",
    CarryAttribute = "CarryingMiningOre",
    QuarryVerticalRange = 12,
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
