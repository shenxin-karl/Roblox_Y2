-- 服务端分析接口：调用结果仅代表本地调用完成，不代表 Creator Hub 已入库。
local FS = _G.FS
local AnalyticsService = game:GetService("AnalyticsService")
local RunService = game:GetService("RunService")
local Manager = {_warnings = 0}
FS.AnalyticsManager = Manager

--- 校验平台数值边界，拒绝 NaN、无穷和负值。
--- @param value any 待上报数值。
--- @return boolean 是否为非负有限数。
local function IsAmount(value)
    return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

--- 按三个官方字段槽位转换稳定维度，不接受任意 JSON。
--- @param values table? 按槽位排列的字符串数组。
--- @return table 官方字段字典。
local function Fields(values)
    local result = {}
    if values then
        for index, value in pairs(values) do
            assert(type(index) == "number" and index % 1 == 0 and index >= 1 and index <= 3,
                "Analytics supports three fields")
            assert(type(value) == "string" and #value > 0, "Analytics field must be a string")
            result[Enum.AnalyticsCustomFieldKeys["CustomField0" .. index].Name] = value
        end
    end
    return result
end

--- 校验和平台错误均隔离，整个服务器最多输出五次诊断，不重试。
--- @param player Player Roblox 玩家实例，不能传框架玩家对象。
--- @param callback function 校验并发送一次平台事件。
--- @return boolean 本地调用是否无异常完成；Studio 返回 false。
function Manager:Call(player, callback)
    if RunService:IsStudio() then
        return false
    end
    local ok, message = pcall(function()
        assert(typeof(player) == "Instance" and player:IsA("Player"), "Analytics requires Player")
        callback()
    end)
    if not ok and self._warnings < 5 then
        self._warnings += 1
        warn("[Analytics] call failed", message)
    end
    return ok
end

--- 记录一次性新手到达步骤，平台负责跨会话漏斗去重。
--- @param player Player Roblox 玩家实例。
--- @param step number 从 1 开始的步骤。
--- @param name string 稳定英文步骤名。
--- @param fields table? 最多三个字符串维度。
--- @return boolean 本地调用是否完成。
function Manager:Onboarding(player, step, name, fields)
    return self:Call(player, function()
        assert(IsAmount(step) and step % 1 == 0 and step >= 1 and step <= 100, "Invalid funnel step")
        assert(type(name) == "string" and #name > 0, "Invalid funnel name")
        AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name, Fields(fields))
    end)
end

--- 记录结算后的正数货币流量；不接受零金额或负余额。
--- @param player Player Roblox 玩家实例。
--- @param flow Enum.AnalyticsEconomyFlowType Source 或 Sink。
--- @param currency string 稳定货币名称。
--- @param amount number 正数交易金额。
--- @param balance number 结算后非负余额。
--- @param transaction string 平台交易类型枚举的 Name。
--- @param sku string 稳定商品标识。
--- @param fields table? 最多三个字符串维度。
--- @return boolean 本地调用是否完成。
function Manager:Economy(player, flow, currency, amount, balance, transaction, sku, fields)
    return self:Call(player, function()
        assert(flow == Enum.AnalyticsEconomyFlowType.Source or flow == Enum.AnalyticsEconomyFlowType.Sink,
            "Invalid economy flow")
        assert(IsAmount(amount) and amount > 0 and IsAmount(balance), "Invalid economy amount")
        assert(type(currency) == "string" and #currency > 0 and type(sku) == "string" and #sku > 0,
            "Invalid economy identity")
        assert(type(transaction) == "string" and Enum.AnalyticsEconomyTransactionType[transaction],
            "Invalid economy transaction")
        AnalyticsService:LogEconomyEvent(player, flow, currency, amount, balance, transaction, sku, Fields(fields))
    end)
end

--- 每个事件仅有一个数值，额外维度限三个稳定字符串。
--- @param player Player Roblox 玩家实例。
--- @param name string 稳定事件名。
--- @param value number 非负有限数值。
--- @param fields table? 最多三个字符串维度。
--- @return boolean 本地调用是否完成。
function Manager:Custom(player, name, value, fields)
    return self:Call(player, function()
        assert(type(name) == "string" and #name > 0 and IsAmount(value), "Invalid custom event")
        AnalyticsService:LogCustomEvent(player, name, value, Fields(fields))
    end)
end

return Manager
