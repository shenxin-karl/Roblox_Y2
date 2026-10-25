local FX = _G.FX
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local root = script.Parent.Parent.Parent
local nodes = root:WaitForChild("Network")
local remote = nodes:WaitForChild("RemoteEvent")
local rpc = nodes:WaitForChild("RemoteFunction")
local Network = { ClientCallbackMap = {}, ServerCallbackMap = {} }
FX.Network = Network
local clientNames, serverNames = {}, {}

--- @param target table 协议名集合。
--- @param names table 有序协议名列表。
local function AddNames(target, names)
    for _, name in ipairs(names) do
        assert(not target[name], "Duplicate protocol: " .. name)
        target[name] = true
    end
end

AddNames(clientNames, FX.FrameworkClientMsgID)
AddNames(clientNames, _G.Provider:GetClientMsgID())
AddNames(serverNames, FX.FrameworkServerMsgID)
AddNames(serverNames, _G.Provider:GetServerMsgID())

--- @param map table 当前端回调集合。
--- @param names table 当前端允许的协议。
--- @param name string 协议名。
--- @param callback function 回调；服务端首参数为已认证 UserId。
--- @param owner table 可选的回调所属对象。
local function Register(map, names, name, callback, owner)
    assert(names[name] and not map[name], "Unknown or duplicate protocol: " .. name)
    if owner then
        map[name] = function(...)
            return callback(owner, ...)
        end
    else
        map[name] = callback
    end
end

if RunService:IsServer() then
    local budgets = {}

    --- @param player Player 引擎认证的调用者。
    --- @param name string 客户端请求的协议。
    --- @return boolean 允许该玩家进入已注册处理器。
    local function Allow(player, name)
        if type(name) ~= "string" or not clientNames[name] or not Network.ServerCallbackMap[name] then
            return false
        end

        local now = os.clock()
        local bucket = budgets[player] or { time = now, tokens = 40 }
        bucket.tokens = math.min(40, bucket.tokens + (now - bucket.time) * 20)
        bucket.time = now
        budgets[player] = bucket
        if bucket.tokens < 1 then
            return false
        end

        bucket.tokens -= 1
        return true
    end

    Players.PlayerRemoving:Connect(function(player)
        budgets[player] = nil
    end)

    --- @param msgName string C2S 白名单协议。
    --- @param func function 回调。
    --- @param obj table 可选回调对象。
    function Network:RegClientMsgCallback(msgName, func, obj)
        Register(self.ServerCallbackMap, clientNames, msgName, func, obj)
    end

    --- @param msgName string 需要解除的协议。
    function Network:UnRegClientMsgCallback(msgName)
        self.ServerCallbackMap[msgName] = nil
    end

    --- @param playerId number 服务端确定的接收者。
    --- @param msgName string S2C 白名单协议。
    --- @param ... any Roblox 支持的网络参数。
    function Network:SendMsgToClient(playerId, msgName, ...)
        assert(serverNames[msgName], "Unknown protocol: " .. msgName)
        local player = Players:GetPlayerByUserId(playerId)
        if player then
            remote:FireClient(player, msgName, ...)
        end
    end

    --- @param msgName string S2C 白名单协议。
    --- @param ... any 网络参数。
    function Network:BroadcastMsg(msgName, ...)
        assert(serverNames[msgName], "Unknown protocol: " .. msgName)
        remote:FireAllClients(msgName, ...)
    end

    remote.OnServerEvent:Connect(function(player, name, ...)
        if not Allow(player, name) then
            return
        end

        local ok, err = pcall(Network.ServerCallbackMap[name], player.UserId, ...)
        if not ok then
            warn("[Network]", name, err)
        end
    end)

    rpc.OnServerInvoke = function(player, name, ...)
        if not Allow(player, name) then
            return { ok = false, error = "Request rejected" }
        end

        local results = table.pack(pcall(Network.ServerCallbackMap[name], player.UserId, ...))
        if not results[1] then
            warn("[Network]", name, results[2])
            return { ok = false, error = "Request failed" }
        end

        local values = {}
        for i = 2, results.n do
            values[tostring(i - 1)] = results[i]
        end

        return { ok = true, count = results.n - 1, values = values }
    end
else
    --- @param msgName string S2C 白名单协议。
    --- @param func function 回调。
    --- @param obj table 可选回调对象。
    function Network:RegServerMsgCallback(msgName, func, obj)
        Register(self.ClientCallbackMap, serverNames, msgName, func, obj)
    end

    --- @param msgName string 需要解除的协议。
    function Network:UnRegServerMsgCallback(msgName)
        self.ClientCallbackMap[msgName] = nil
    end

    --- @param msgName string C2S 白名单协议。
    --- @param ... any 网络参数。
    function Network:SendMsgToServer(msgName, ...)
        assert(clientNames[msgName], "Unknown protocol: " .. msgName)
        remote:FireServer(msgName, ...)
    end

    --- @param msgName string C2S 白名单协议。
    --- @param ... any 网络参数。
    --- @return any 服务器返回值，保留中间及末尾 nil。
    function Network:InvokeServer(msgName, ...)
        assert(clientNames[msgName], "Unknown protocol: " .. msgName)
        local response = rpc:InvokeServer(msgName, ...)
        assert(response.ok, response.error)
        local values = {}
        for i = 1, response.count do
            values[i] = response.values[tostring(i)]
        end

        return table.unpack(values, 1, response.count)
    end

    remote.OnClientEvent:Connect(function(name, ...)
        local callback = Network.ClientCallbackMap[name]
        if callback then
            callback(...)
        end
    end)
end

return Network
