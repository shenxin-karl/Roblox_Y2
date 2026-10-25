local FX = _G.FX
local Provider = _G.Provider

FX.ItemHandlerClass = FX.Class("FXItemHandlerClass")
local FXItemHandlerClass = FX.ItemHandlerClass

function FXItemHandlerClass:CanUse(context)
    return true
end

function FXItemHandlerClass:Use(context)
    error("DefaultHandler:Use not implemented")
end

FX.ItemContextClass = FX.Class("FXItemContextClass")
local FXItemContextClass = FX.ItemContextClass

function FXItemContextClass:Ctor(playerObject, itemObject)
    self.playerObject = playerObject -- 玩家对象(客户端服务器不同)
    self.itemObject = itemObject -- 物品对象
    self.consumeCount = itemObject:GetStackCount() -- 默认消耗数量为物品数量

    local itemDataConfig = _G.Provider:GetItemDataConfig(self.itemObject:GetItemId())
    self.itemDataConfig = itemDataConfig
    self.useHandlerType = itemDataConfig.UseHandler
    self.extraData = nil -- 额外数据, 用于传递给处理器
end

function FXItemContextClass:CanUse()
    if not self.useHandlerType then
        return false
    end

    local handler = Provider:GetItemHandler(self.useHandlerType)
    if not handler then
        return false
    end
    local ok, ret = FX.PCall(function()
        return handler:CanUse(self)
    end)
    return ok and ret
end

function FXItemContextClass:Use()
    local handler = Provider:GetItemHandler(self.useHandlerType)
    if not handler then
        return false
    end
    local ok, ret = FX.PCall(function()
        return handler:Use(self)
    end)
    return ok and ret
end
return true
