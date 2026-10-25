-- 两端共同入口：独立配置、项目 Provider、框架、依赖框架的公共模块依次加载。
local Configs = script.Parent:WaitForChild("Game"):WaitForChild("Configs")
_G.ItemConfig = require(Configs:WaitForChild("ItemConfig"))
_G.GoodsConfig = require(Configs:WaitForChild("GoodsConfig"))

local GameShared = script.Parent:WaitForChild("Game"):WaitForChild("Shared")
_G.NetworkProtocol = require(GameShared:WaitForChild("NetworkProtocol"))
_G.PlayerDataConfig = require(GameShared:WaitForChild("PlayerDataConfig"))
_G.ServerDataConfig = require(GameShared:WaitForChild("ServerDataConfig"))

require(script.Parent:WaitForChild("SetupProvider"))
require(script.Parent:WaitForChild("Framework"):WaitForChild("FrameworkInit"))

local FX = _G.FX
local FXLoader = FX.Loader

return {
    GameUtility = FXLoader:Require(GameShared, "GameUtility"),
    GameFormula = FXLoader:Require(GameShared, "GameFormula"),
    GameFunction = FXLoader:Require(GameShared, "GameFunction"),
}
