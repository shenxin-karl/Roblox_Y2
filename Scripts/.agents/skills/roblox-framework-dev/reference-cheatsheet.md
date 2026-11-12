# 框架 API 速查

| 任务 | 当前接法 |
| --- | --- |
| 获取公共配置 | GameInit 显式加载独立配置；例如 `_G.PlayerDataConfig`、`_G.ItemConfig` |
| 数值字段 | 服务端 `SetNumber/AddNumber/SubNumber`；两端 `GetNumber` |
| 布尔、表字段 | `SetFlag/GetFlag/SetTable/GetTable`，写入只在服务端 |
| 服务端只读取表 | `GetTableView(field)`；实时只读代理，不深拷贝，任意层级写入报错；使用 Luau 通用遍历 |
| 服务端编辑表 | `GetTable(field)` 深拷贝；`GetTableShallow(field)` 第一层副本、嵌套只读；均需 `SetTable` 提交 |
| 服务端批量设置字段 | `SetTableFields(field, {key = value, ...})`；一级字段合并、嵌套表整体复制替换，一次提交通知一次；不支持路径 |
| 会话与保存 | `FS.PlayerKVDataManager:GetSessionToken/IsSessionActive/GetState/Save`，禁止直接取 DB 或内部映射 |
| 购买容量预检 | `FS.PlayerKVDataManager:GetDataSize(id, session)` 返回 JSON 字节数；只限制新购买，不拦已付款回执 |
| 货币和开发者名单 | `Provider:GetCurrencyDataConfig(currencyName)`、`Provider:GetDeveloperUserIds()`，由项目定义白名单 |
| 发奖事务 | 玩家 `RunDataTransaction(callback)`；无 yield、成功返回 true，内部回滚，不执行持久化 |
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
