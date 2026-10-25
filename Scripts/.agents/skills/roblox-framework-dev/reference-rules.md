# 玩家数据与组件规则

- 默认值统一来自 PlayerDataConfig，不在各组件重复补结构。玩家字段定义为 `{Type, Key, DefVal, Sync, KVTable}`，存在 `PlayerDataConfig`；KVTable 需在 PlayerKV 中声明。
- Type 和读写接口一致，Key 保持稳定；旧存档结构变更在 `SPlayerObjectClass:MigrateData` 中处理，不自动清库。
- Sync=false 的字段不会传给客户端。当前 Inventory 是私有字段，原生 Tool 用服务端实例呈现。
- GetTable 返回副本，修改后必须 SetTable 提交；nil 写入恢复默认值。日/周/月重置使用 KVResetType 和服务器 UTC。
- WatchDataChanged 立即回放当前值，后续变化再通知。组件封装自动持有返回连接，直接从玩家对象订阅时自行清理。
- 服务端组件继承 FSPlayerCompClass，客户端组件继承 FCPlayerCompClass；UI 接入按 [UI 技能](../roblox-ui-components/SKILL.md)。
- GetCompName 是协作名称，和 AddComponent 的注册类名不同。
- 覆盖 Ctor/Dtor 显式调用 Super；未覆盖时类系统自动调用基类。
- 连接用 TrackConnection 持有；任务、输入对象和自建实例在 Dtor 释放，只清理组件拥有或明确接管的对象。
- 服务端协议在管理器或服务初始化时注册一次，再依据已认证 UserId 取得玩家组件。处理离服、未就绪等真实状态。
- 外部异步请求返回时重新确认玩家会话与对象有效，不让旧结果写入重进后的玩家。
- 不绕过 Ready 握手或再创建一套玩家数据同步。
- 玩家组件每秒更新使用 OnUpdate(serverTime)；独立轮询保存任务句柄并在 Dtor 取消。
- 业务协议在 NetworkProtocol.ClientMsgID/ServerMsgID 声明，网络层首次 require 时读取；启动后不能临时追加。
- 接触触发奖励、伤害或传送时，由服务端校验业务资格并处理重复触发。
