local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local FX = _G.FX

function FX.IsDebugMode()
    return RunService:IsStudio()
end

function FX.IsLocalMode()
    return RunService:IsStudio() and RunService:IsClient() and RunService:IsServer()
end

--- 成功条件不产生日志；开发时中断，线上记录失败。
--- @param condition boolean 待验证条件。
--- @param message string 错误上下文。
function FX.DebugAssert(condition, message)
    if condition then
        return
    end
    if FX.IsDebugMode() then
        assert(condition, message)
    else
        FX.Log:Error(message)
    end
end

--- @param playerId number Roblox UserId；默认没有额外管理员。
--- @return boolean 是否在项目管理员白名单中。
function FX.IsDeveloper(playerId)
    local ids = _G.Provider:GetDeveloperUserIds()
    return table.find(ids, playerId) ~= nil
end

--- 为对象和组件生成独立身份，不依赖 MiniStudio UtilService。
--- @return string GUID。
function FX.GenObjectID()
    return HttpService:GenerateGUID(false)
end

--[[
    解析模块名.函数名格式的字符串
    参数:
        componentFuncStr: 格式为 "组件名.函数名" 的字符串
    返回值:
        compName: 组件名
        funcName: 函数名
        如果格式不正确，返回 nil, nil
--]]
function FX.ParseComponentFuncString(componentFuncStr)
    if not componentFuncStr or type(componentFuncStr) ~= "string" then
        return nil, nil
    end
    local dotIndex = string.find(componentFuncStr, "%.")
    if not dotIndex then
        return nil, nil
    end
    local moduleName = string.sub(componentFuncStr, 1, dotIndex - 1)
    local funcName = string.sub(componentFuncStr, dotIndex + 1)
    if moduleName == "" or funcName == "" then
        return nil, nil
    end
    return moduleName, funcName
end

-- 重置节点的局部变换
--- Roblox 模型以 Pivot 表示变换；不存在通用 LocalScale 属性。
--- @param node PVInstance 待重置节点。
function FX.ResetNodeLocalTrans(node)
    node:PivotTo(CFrame.identity)
end
--- @param dstNode PVInstance 目标模型或 Part。
--- @param srcNode PVInstance 来源模型或 Part。
function FX.CopyNodeLocalTrans(dstNode, srcNode)
    dstNode:PivotTo(srcNode:GetPivot())
end

--[[
    params:
        text: 文本,
        (optional) color: 颜色 "#ffffff"
        (optional) size: 字体大小
        (optional) bold: 是否加粗
        (optional) italic: 是否斜体
        (optional) underline: 是否下划线
]]
function FX.GetRichText(text, params)
    params = params or {}
    local result = text
    if params.color or params.size then
        local attrs = ""
        if params.color then
            attrs = attrs .. string.format(" color='%s'", params.color)
        end
        if params.size then
            attrs = attrs .. string.format(" size='%s'", params.size)
        end
        result = string.format("<font%s>%s</font>", attrs, result)
    end
    if params.bold then
        result = string.format("<b>%s</b>", result)
    end
    if params.italic then
        result = string.format("<i>%s</i>", result)
    end
    if params.underline then
        result = string.format("<u>%s</u>", result)
    end
    return result
end

-- 安全调用函数，返回是否成功和返回值
--- 保持处理器失败返回值契约，Studio 与正式服务器语义一致。
--- @param func function 待调用处理器。
--- @param ... any 处理器参数。
--- @return boolean 是否成功。
--- @return any 结果或错误。
function FX.PCall(func, ...)
    return pcall(func, ...)
end

-- 获取堆栈
--- @return table Roblox 支持的调用栈文本。
function FX.GetTraceback()
    return { debug.traceback(nil, 2) }
end

-- 报错, 并且打印堆栈
function FX.ErrorWithTraceback(message)
    local traceback = FX.GetTraceback()
    local strTraceback = table.concat(traceback, "\n")
    print(strTraceback)
    error(message)
end

--- 尝试通过节点事件的触发间隔检查，检查成功时记录本次触发时间。
---@param node SandboxNode 需要记录事件触发时间的节点。
---@param eventKey string 用于区分事件的唯一 Key。
---@param interval number 两次事件之间要求的最小毫秒数。
---@return boolean canTrigger 达到触发间隔时返回 true。
function FX.TryPassEventInterval(node, eventKey, interval)
    local now = (os.clock() * 1000)
    local lastTime = node:GetAttribute(eventKey)
    if type(lastTime) ~= "number" then
        node:SetAttribute(eventKey, now)
        return true
    end

    if now - lastTime >= interval then
        node:SetAttribute(eventKey, now)
        return true
    end

    return false
end

--- 尝试通过 TriggerBox 进入事件的触发间隔检查。
--- 玩家事件记录在 Player 节点上，玩家离线后由引擎随节点自动清理。
---@param triggerBox TriggerBox 触发进入事件的触发盒。
---@param node SandboxNode 进入触发盒的节点。
---@param interval number 两次进入事件之间要求的最小毫秒数。
---@return boolean canTrigger 达到触发间隔时返回 true。
function FX.TryPassTriggerBoxTouchedInterval(triggerBox, node, interval)
    local id = triggerBox:GetAttribute("FXTriggerId")
    if not id then
        id = FX.GenObjectID()
        triggerBox:SetAttribute("FXTriggerId", id)
    end
    local character = node:FindFirstAncestorOfClass("Model")
    local player = character and Players:GetPlayerFromCharacter(character)
    return FX.TryPassEventInterval(player or node, "FXEnter_" .. id, interval)
end
--- @param triggerBox BasePart Roblox 触发区域。
--- @param node BasePart 发生接触的角色部件。
--- @param interval number 最小毫秒间隔。
--- @return boolean 本次是否可以处理。
function FX.TryPassTriggerBoxTouchEndedInterval(triggerBox, node, interval)
    local id = triggerBox:GetAttribute("FXTriggerId")
    if not id then
        id = FX.GenObjectID()
        triggerBox:SetAttribute("FXTriggerId", id)
    end
    local character = node:FindFirstAncestorOfClass("Model")
    local player = character and Players:GetPlayerFromCharacter(character)
    return FX.TryPassEventInterval(player or node, "FXLeave_" .. id, interval)
end
return FX
