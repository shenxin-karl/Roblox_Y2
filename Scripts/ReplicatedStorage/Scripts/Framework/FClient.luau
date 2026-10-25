local root = script.Parent:WaitForChild("Client")
require(root:WaitForChild("FCEvents"))
require(root:WaitForChild("FCUIAnim"))
local player = root:WaitForChild("Player")
for _, name in ipairs({
    "FCPlayerObjectClass",
    "FCPlayerCompClass",
    "FCUICompClass",
    "FCCommonUICompClass",
    "FCFriendCompClass",
    "FCFriendInviteCompClass",
    "FCSoundCompClass",
    "FCRankingUICompClass",
    "FCTutorialGuideCompClass",
}) do
    require(player:WaitForChild(name))
end

local shop = root:WaitForChild("Shop")
for _, name in ipairs({ "ShopPageBaseClass", "ShopItemBaseClass", "FCShopUICompClass" }) do
    require(shop:WaitForChild(name))
end

for _, name in ipairs({ "FCHoldUIObjectClass", "FCKeyObjectClass" }) do
    require(root:WaitForChild(name))
end

local FX, FC = _G.FX, _G.FC
local Players = game:GetService("Players")

-- 通用服务由框架统一启动；邀请提醒仅注册，是否挂载由项目玩家对象决定。
FC.Localization = require(root:WaitForChild("FCLocalization")).New(Players.LocalPlayer)
FC.ButtonHover = require(root:WaitForChild("FCButtonHover")).New(Players.LocalPlayer:WaitForChild("PlayerGui"))
FC.PickupPrompt = require(root:WaitForChild("FCPickupPrompt"))
FC.PickupPrompt.Init()

FC.NativeBackpack = require(root:WaitForChild("FCNativeBackpack"))
FC.NativeBackpack.Start(Players.LocalPlayer, FX.Network, _G.Provider:GetNativeBackpackConfig())

--- 玩家对象与组件创建完成后发起握手，等待服务端完成初始同步。
function FC.WaitServerReady()
    local network = script.Parent:WaitForChild("Network")
    while not network:GetAttribute("ServerReady") do
        network:GetAttributeChangedSignal("ServerReady"):Wait()
    end

    FX.Network:SendMsgToServer("C2S_ClientReady")
    FC.Events.OnReady.Event:Wait()
end

return _G.FC
