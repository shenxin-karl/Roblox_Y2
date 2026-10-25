-- 项目配置和框架之间的唯一入口；服务端处理器由服务端注册，永不复制给客户端。
local PlayerDataConfig, ServerDataConfig = _G.PlayerDataConfig, _G.ServerDataConfig
local NetworkProtocol = _G.NetworkProtocol
local ItemConfig, GoodsConfig = _G.ItemConfig, _G.GoodsConfig
local ProjectConfig = require(script.Parent:WaitForChild("Game"):WaitForChild("Shared"):WaitForChild("ProjectConfig"))
local Provider = { ItemHandlers = {}, BuyHandlers = {}, RewardHandlers = {} }

--- 项目设置通过 Provider 提供，框架不读取旧业务配置。
--- @return table 开发者 UserId 列表，模板默认为空。
function Provider:GetDeveloperUserIds()
    return ProjectConfig.DeveloperUserIds
end

--- @return table 客户端可发送的项目协议名。
function Provider:GetClientMsgID()
    return NetworkProtocol.ClientMsgID
end

--- @return table 服务端可发送的项目协议名。
function Provider:GetServerMsgID()
    return NetworkProtocol.ServerMsgID
end

--- @return table 玩家持久化数据域。
function Provider:GetPlayerKVEnum()
    return _G.PlayerKVEnum
end

--- 模板不预设榜单；启用时由项目返回对应榜单定义。
--- @return table 当前启用的排行榜列表。
function Provider:GetRankingEnum()
    return {}
end

--- @return string 排行榜本地分数数据域。
function Provider:GetRankingDataStore()
    return _G.PlayerKVEnum.eActivityData
end

--- @return table 玩家字段定义与默认值。
function Provider:GetPlayerDataConfig()
    return PlayerDataConfig
end

--- 货币白名单由项目维护，避免奖励框架绑定具体字段名称。
--- @param currencyName string? 奖励指定的货币字段名，省略时使用项目默认货币。
--- @return table? 已允许的数值字段，非货币字段返回 nil。
function Provider:GetCurrencyDataConfig(currencyName)
    if currencyName == nil or currencyName == "Money" then
        return PlayerDataConfig.Money
    end
    if currencyName == "Diamonds" then
        return PlayerDataConfig.Diamonds
    end
    return nil
end

--- @return table 供共享数据同步器使用的服务器字段定义。
function Provider:GetServerDataConfig()
    return ServerDataConfig
end

--- 快捷栏与正式背包共用总容量，快捷栏最多占用其中 10 格，不删除已有存档。
--- @return table 快捷栏开关与正式背包总容量（非负整数，0 关闭）。
function Provider:GetNativeBackpackConfig()
    return {
        ShortcutEnabled = true,
        InventoryCapacity = 12, -- 正式背包总容量，包含快捷栏占用的格子。
    }
end

--- @return table 存档版本字段。
function Provider:GetPlayerDataVersionVariantEnum()
    return PlayerDataConfig.DataVersion
end

--- @param itemId number 道具配置 ID。
--- @return table 道具定义；未注册返回 nil。
function Provider:GetItemDataConfig(itemId)
    return ItemConfig.Data[itemId]
end

--- @param itemType string 道具类型。
--- @return table 附加属性定义。
function Provider:GetItemExtraDataSchema(itemType)
    return ItemConfig.ExtraDataSchema[itemType]
end

--- @param handlerType string 已注册处理器名。
--- @return table 权威道具处理器。
function Provider:GetItemHandler(handlerType)
    return self.ItemHandlers[handlerType]
end

--- @param productId number Roblox Developer Product ID。
--- 未注册购买处理器的旧商品不对模板开放。
--- @return table? 已接入处理器的商品定义，未启用时为 nil。
function Provider:GetGoodsConfig(productId)
    for goodsId, config in pairs(GoodsConfig.GoodsData) do
        if config.RobloxProductId and config.RobloxProductId > 0 and config.RobloxProductId == productId
            and self.BuyHandlers[config.BuyHandler] then
            return config
        end
    end
    return nil
end

--- @param handlerType string 已注册处理器名。
--- @return table 权威购买处理器。
function Provider:GetBuyHandler(handlerType)
    return self.BuyHandlers[handlerType]
end

_G.Provider = Provider
return Provider
