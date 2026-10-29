-- 服务端唯一入口：框架初始化后注册项目扩展，再创建玩家管理器。
local Scripts = game:GetService("ReplicatedStorage"):WaitForChild("Scripts")
require(Scripts:WaitForChild("GameInit"))

local FX = _G.FX
local FXLoader = FX.Loader
local Handlers = FXLoader:Here(script.Parent, "Handlers")
_G.Provider.ItemHandlers = require(Handlers.ItemHandlers)
_G.Provider.BuyHandlers = require(Handlers.BuyHandlers)
_G.Provider.RewardHandlers = require(Handlers.RewardHandlers)

local Player = FXLoader:Here(script.Parent, "Player")
local ConveyorService = FXLoader:Require(script.Parent, "Service.SConveyorService")
ConveyorService.Init()
require(Player.SMiscCompClass)
require(Player.SGMCompClass)
require(Player.SAnalyticsCompClass)
require(Player.SPlayerObjectClass)
local ManagerClass = require(Player.SPlayerObjectManagerClass)
_G.SPlayerObjectManager = ManagerClass.New()

local PurchaseReceiptService = FXLoader:Require(script.Parent, "Service.SPurchaseReceiptService")
PurchaseReceiptService.Init()
