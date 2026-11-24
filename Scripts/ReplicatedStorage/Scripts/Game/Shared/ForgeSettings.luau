-- 私人锻造工位的场景路径、距离和落点。
local FX = _G.FX
local Settings = {
    StationClearance = 3,
    ArrivalHeight = 3.5,
    RequestCooldown = 0.5,
    RecoveryDiamondCost = 88,
    PersonalStationOffset = 8,
    PersonalGroundPath = "BlockMeshs.ground.营地铺地.草地",
    PersonalForgePart = "ForgeTable.ThickSteelDesktop",
    PersonalFurnacePart = "Furnace.ProjectingStoneHearth",
    PersonalInteractDistance = 9,
}

--- 客户端流送期间允许工位尚未出现；服务端只传入当前玩家已分配的基地编号。
--- @param baseId number 已分配的基地编号，0 表示没有基地。
--- @return Model? 对应的私人小工坊。
function Settings.FindPersonalWorkshop(baseId)
    if baseId <= 0 then
        return nil
    end
    return FX.Loader:FindFromWorkspace("Decorations.PersonalWorkshop_Base" .. baseId)
end

return Settings
