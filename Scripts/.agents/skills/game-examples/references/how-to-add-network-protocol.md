# 新增 Roblox 框架协议

本地路径均以 Scripts 工作区为根。先查现有协议和处理器，避免重复名字与重复注册。

1. 项目 C2S 名称加入 `ReplicatedStorage/Scripts/Game/Shared/NetworkProtocol.luau` 的 ClientMsgID；
   S2C 名称加入 ServerMsgID。FXNetwork 初始化会合并 Provider 与 FrameworkInit 中的框架白名单。
2. 参数注释放在声明附近，写明类型、范围、身份来源、是否 RPC 及实际返回值。
3. 服务端管理器或服务初始化时 RegClientMsgCallback 一次。当前管理器有
   RegForwardFrameworkClientMsg，没有通用 RegForwardClientMsg 自动路由。
4. 回调首参 userId 由 RemoteEvent/RemoteFunction 的 Player.UserId 提供；
   客户端不能另传自己的身份。实例、目标 ID、金额、次数仍必须验证所有权与业务状态。
5. 单向用 SendMsgToServer，有返回值用 InvokeServer；客户端 S2C 订阅 RegServerMsgCallback，
   析构时 UnRegServerMsgCallback。

最小只读 RPC 示例（需先新增白名单 C2S_GetExampleState），注册位置在 FS.PlayerManager 赋值之后、Start 之前：

```lua
local FX, FS = _G.FX, _G.FS
FX.Network:RegClientMsgCallback("C2S_GetExampleState", function(userId)
    local playerObject = FS.PlayerManager:GetPlayerObject(userId)
    return { ready = playerObject ~= nil }
end)
```

客户端框架初始化完成后：

```lua
local FX = _G.FX
local state = FX.Network:InvokeServer("C2S_GetExampleState")
```

真实读写操作仍处理未加载、离服和限速拒绝。网络层 RPC 拒绝会抛错；
UI 请求按实际流程处理失败与异步竞态。不要创建第二套 Remote 协议绕过现有白名单。
