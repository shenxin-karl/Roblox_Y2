local FX, FC, MS = _G.FX, _G.FC, _G.Rbx
local FXNetwork = FX.Network

local FCPlayerCompClass = FX.Class("FCPlayerCompClass", "FXCompBaseClass")
FC.PlayerCompClass = FCPlayerCompClass

function FCPlayerCompClass:Ctor(owner)
    FCPlayerCompClass.Super.Ctor(self, owner)
end

-- 获取玩家ID
function FCPlayerCompClass:GetPlayerId()
    return self:GetPlayerNode().UserId
end

-- 获取组件名称
function FCPlayerCompClass:GetCompName()
    return "FCPlayerComp"
end

-- 获取玩家对象
function FCPlayerCompClass:GetPlayerObject()
    return self:GetOwner()
end

-- 获取玩家节点
function FCPlayerCompClass:GetPlayerNode()
    return MS.Players.LocalPlayer
end

-- 获取玩家角色
function FCPlayerCompClass:GetPlayerCharacter()
    return self:GetPlayerNode().Character
end

function FCPlayerCompClass:GetNumber(numberEnum)
    return self:GetPlayerObject():GetNumber(numberEnum)
end

function FCPlayerCompClass:GetFlag(boolEnum)
    return self:GetPlayerObject():GetFlag(boolEnum)
end

function FCPlayerCompClass:GetTable(tableEnum)
    return self:GetPlayerObject():GetTable(tableEnum)
end

-- 注册玩家数据变化监听
function FCPlayerCompClass:WatchDataChanged(dataEnum, callback, this)
    return self:TrackConnection(self:GetPlayerObject():WatchDataChanged(dataEnum, callback, this))
end

-- 准备就绪
function FCPlayerCompClass:OnReady() end

return FCPlayerCompClass
