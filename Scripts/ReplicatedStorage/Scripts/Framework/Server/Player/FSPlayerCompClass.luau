--[[
    服务器端玩家组件基类：为玩家组件提供通用的功能支持，包括数据存储、排行榜管理和客户端通信。
    继承自 FXCompBaseClass，专门用于扩展 FSPlayerClass 的功能。所有玩家相关的组件都应该继承此类。
    主要功能：
    1. 玩家信息获取：提供 GetPlayerId() 和 GetPlayer() 方法获取玩家相关信息
    2. 生命周期管理：提供 OnPlayerLogin() 和 OnPlayerLogout() 虚函数，可在子类中重写
    3. 客户端通信：提供 ShowTips() 方法向客户端发送提示消息
    4. KV数据管理：提供完整的KV数据存储和读取功能
       - 数值操作：SetNumber/GetNumber/AddNumber/SubNumber（支持每日数据）
       - 布尔值操作：SetFlag/GetFlag（支持每日数据）
       - 通用操作：Set/Get/SetDeep/GetDeep（支持深层路径）
    5. 排行榜管理：提供 UpdateRankingScore() 和 AddRankingScore() 方法更新排行榜分数
    
    使用方式：
    1. 继承此类创建自定义玩家组件
    2. 重写 OnPlayerLogin() 和 OnPlayerLogout() 方法处理玩家生命周期事件
    3. 使用提供的KV数据管理方法存储和读取玩家数据
    4. 使用排行榜方法更新玩家在排行榜中的分数
    
    数据存储说明：
    - numberEnum/boolEnum 参数格式：{ kvTable = "表名", key = "键名", defVal = 默认值, daily = 是否每日数据 }
    - 每日数据会在每天午夜自动重置为默认值
    - SetDeep/GetDeep 支持使用 "." 分割的深层路径（如 "player.level.exp"）
    
    生命周期方法：
    - OnPlayerLogin(): 玩家登录时调用，可在子类中重写
    - OnPlayerLogout(): 玩家登出时调用，可在子类中重写
]]

local FS, FX = _G.FS, _G.FX
local FXNetwork = FX.Network
local FXTime = FX.Time
local FXTable = FX.Table
local FSPlayerKVDataManager = FS.PlayerKVDataManager
local FSRankingManager = FS.RankingManager
local Players = game:GetService("Players")

local FSPlayerCompClass = FX.Class("FSPlayerCompClass", "FXCompBaseClass")
FS.PlayerCompClass = FSPlayerCompClass

function FSPlayerCompClass:Ctor(owner)
    FSPlayerCompClass.Super.Ctor(self, owner)
    self._playerId = owner:GetPlayerId()
end

function FSPlayerCompClass:GetCompName()
    return "FSPlayerComp"
end

function FSPlayerCompClass:GetPlayerObject()
    return self._owner
end

function FSPlayerCompClass:GetPlayerNode()
    return Players:GetPlayerByUserId(self._playerId)
end

function FSPlayerCompClass:GetPlayerCharacter()
    return self:GetPlayerNode().Character
end

function FSPlayerCompClass:GetPlayerId()
    return self._playerId
end

function FSPlayerCompClass:OnPlayerLogin() end

function FSPlayerCompClass:OnPlayerLogout() end

function FSPlayerCompClass:ShowTips(tips, duration)
    self:GetPlayerObject():ShowTips(tips, duration)
end

function FSPlayerCompClass:SetNumber(numberEnum, number)
    return self:GetPlayerObject():SetNumber(numberEnum, number)
end

--获取KV数值
function FSPlayerCompClass:GetNumber(numberEnum)
    return self:GetPlayerObject():GetNumber(numberEnum)
end

--增加KV数值
function FSPlayerCompClass:AddNumber(numberEnum, number)
    return self:GetPlayerObject():AddNumber(numberEnum, number)
end

--减少KV数值
function FSPlayerCompClass:SubNumber(numberEnum, number)
    return self:GetPlayerObject():SubNumber(numberEnum, number)
end

--设置布尔值
function FSPlayerCompClass:SetFlag(boolEnum, flag)
    return self:GetPlayerObject():SetFlag(boolEnum, flag)
end

--获取布尔值
function FSPlayerCompClass:GetFlag(boolEnum)
    return self:GetPlayerObject():GetFlag(boolEnum)
end

--获取表
function FSPlayerCompClass:GetTable(tableEnum)
    return self:GetPlayerObject():GetTable(tableEnum)
end

-- 设置表
function FSPlayerCompClass:SetTable(tableEnum, data)
    return self:GetPlayerObject():SetTable(tableEnum, data)
end

-- 设置同步数据
function FSPlayerCompClass:SetSyncData(syncDataEnum, data)
    self:GetPlayerObject():SetSyncData(syncDataEnum, data)
end

-- 注册数据变化监听
function FSPlayerCompClass:WatchDataChanged(dataEnum, callback, this)
    return self:TrackConnection(self:GetPlayerObject():WatchDataChanged(dataEnum, callback, this))
end

-- 更新排行榜的值
-- 如果分数有变化, 返回 true
function FSPlayerCompClass:UpdateRankingScore(rankingType, value)
    return self:GetPlayerObject():UpdateRankingScore(rankingType, value)
end

-- 增加排行榜的值
function FSPlayerCompClass:AddRankingScore(rankingType, value)
    return self:GetPlayerObject():AddRankingScore(rankingType, value)
end
return true
