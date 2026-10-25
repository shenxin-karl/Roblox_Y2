# 框架 API 速查

| 任务 | 当前接法 |
| --- | --- |
| 获取公共配置 | GameInit 显式加载独立配置；例如 `_G.PlayerDataConfig`、`_G.ItemConfig` |
| 数值字段 | 服务端 `SetNumber/AddNumber/SubNumber`；两端 `GetNumber` |
| 布尔、表字段 | `SetFlag/GetFlag/SetTable/GetTable`，写入只在服务端 |
| 数据订阅 | `WatchDataChanged(fieldDefinition, callback, owner)`；玩家组件封装会 TrackConnection |
| 拿组件 | `GetComponent/RequireComponent` 使用 GetCompName；`AddComponent` 使用已注册类名 |
| 调组件 | `CallCompMethod("CompName.Method", ...)` |
| 组件事件 | `PublishEvent/SubscribeEvent/UnsubscribeEvent`；组件 SubscribeEvent 回调首参为组件自身 |
| 客户端请求 | `FX.Network:SendMsgToServer` 或有返回值的 `InvokeServer` |
| 服务端协议 | `RegClientMsgCallback(name, callback, owner)`，回调首个业务参数是引擎认证 UserId |
| 客户端协议 | `RegServerMsgCallback(name, callback, owner)`，析构 `UnRegServerMsgCallback` |
| 发消息 | 服务端 `SendMsgToClient(userId, name, ...)/BroadcastMsg(name, ...)` |
| 时间任务 | `FX.Task:Delay/Interval`；保留 thread 句柄并 `FX.Task:Cancel(handle)` |
| 通用奖励 | 玩家 `RequireComponent("FSRewardComp")` |
| 通用弹窗 | `FC.PlayerObject:RequireComponent("FCCommonUIComp")` |

源码依据：`ReplicatedStorage/Scripts/Framework/Shared/Core/FXNetwork.luau`、
`Shared/Object/FXCompBaseClass.luau`（在 Framework 下）以及两端 Framework/Player 基类。
协议名字只能注册一次；不要在每个玩家组件构造时重复注册服务端全局协议。
