-- 方形环路传送带：服务端设置承载面的物理速度。
local FX = _G.FX
local FXLoader = FX.Loader
local Service = {}

--- 在玩家进入前设置直道及四角的传送方向，不改动玩家 WalkSpeed。
function Service.Init()
    local conveyor = FXLoader:Workspace("Decorations.SquareConveyor")
    local decks = FXLoader:Here(conveyor, "Decks")
    local speed = conveyor:GetAttribute("Speed") * 2
    for index = 1, 8 do
        local deck = FXLoader:Here(decks, string.format("%02d", index))
        local direction = (deck:GetAttribute("PathEnd") - deck:GetAttribute("PathStart")).Unit
        deck.AssemblyLinearVelocity = direction * speed
    end
end

return Service
