local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("GameInit"))
local FX, FC = _G.FX, _G.FC
local FXLoader = FX.Loader
local PlayerClass = require(script.Parent.Player.CPlayerObjectClass)
FXLoader:Require(script.Parent, "Player.CBaseCompClass")
FXLoader:Require(script.Parent, "Player.CBaseOwnerMarkerCompClass")
FXLoader:Require(script.Parent, "UI.CMainUICompClass")

FC.PlayerObject = PlayerClass.New(Players.LocalPlayer.UserId)

-- 在此添加项目客户端组件；UI 子类提供自己的原生节点和模板。
FC.PlayerObject:AddComponent("CBaseCompClass")
FC.PlayerObject:AddComponent("CBaseOwnerMarkerCompClass")
FC.PlayerObject:AddComponent("CMainUICompClass")
FC.WaitServerReady()
