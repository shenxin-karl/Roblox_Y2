local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("GameInit"))
local FC = _G.FC
local PlayerClass = require(script.Parent.Player.CPlayerObjectClass)

FC.PlayerObject = PlayerClass.New(Players.LocalPlayer.UserId)

-- 在此添加项目客户端组件；UI 子类提供自己的原生节点和模板。
FC.WaitServerReady()
