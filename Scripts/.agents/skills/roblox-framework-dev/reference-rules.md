# 玩家数据与组件规则

- 默认值统一来自 PlayerDataConfig，不在各组件重复补结构。玩家字段定义为 `{Type, Key, DefVal, Sync, KVTable}`，存在 `PlayerDataConfig`；KVTable 需在 PlayerKV 中声明。
- Type 和读写接口一致，Key 保持稳定；旧存档结构变更在 `SPlayerObjectClass:MigrateData` 中处理，不自动清库。
- Sync=false 的字段不会传给客户端。当前 Inventory 是私有字段，原生 Tool 用服务端实例呈现。
- 服务端 GetTable 返回深拷贝，修改后必须 SetTable 提交；nil 写入恢复默认值。日/周/月重置使用 KVResetType 和服务器 UTC。
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

## 存档封装与取表接口（关键）

- 原始玩家 DB、映射、KV 表和会话状态仅限 `Framework/Server/PlayerKV/` 内部访问。其他框架模块与业务脚本禁止使用 `_playerDBMap`、`db._data`、`_database`、`kv._db/_table`、`db._session/_leaving/_saving` 等内部成员；不能新增返回 DB/原始表的便捷接口。
- 服务端玩家对象、组件提供三种取表方式：`GetTable(field)` 为可编辑的深拷贝；`GetTableShallow(field)` 仅复制第一层，嵌套表为只读 View，第一层修改也需 SetTable 提交；`GetTableView(field)` 不深拷贝，实时读取当前字段，任意层级写入均报错且不修改存档。嵌套表编辑后整表提交或作为 SetTableFields 的一级值整体替换，不把标准浅拷贝的共享嵌套引用暴露出去。
- 批量修改用 `SetTableFields(field, fields)`，fields 为多个一级键到新值的补丁，一次调用只提交并通知一次。未提供的一级字段保留；嵌套表整体复制替换，不递归合并、不支持路径，不拆成多次逐键提交。空补丁或会话失效返回 false 且不通知，false 为有效值。nil 无法出现在补丁中，删除键用 GetTable 后一次 SetTable。提交仍沿用整字段快照、周期重置和 Sync 控制，不承诺内部零深拷贝。
- View 的代理和元表均冻结，嵌套值继续代理。不能只对原表设置 `__newindex`，它拦不住已有键；不能冻结原表，否则存档模块也无法写入。View 使用 Luau 的 `for key, value in view do` 遍历，支持索引和 `#`；`pairs/ipairs/next/rawget/table.*` 不适用。不要把 View 直接发送网络、序列化或交给通用 DeepCopy；需要普通表重新 GetTable。SetTable 可直接接收安全浅拷贝或 View，内部会转换成隔离的普通表。
- 玩家 GetTableView 在字段替换、周期重置后读取当前值，离服后失效；不得跨会话缓存。只读查询优先 View，编辑取深拷贝，不批量替换不涉及的调用点。
- 底层 GetKVTable 返回冻结的方法句柄，不含 `_db/_table`：Get/GetDeep 深拷贝，GetShallow/GetDeepShallow 安全浅拷贝，GetView/GetDeepView 只读，Set/SetDeep 复制入参后写入。业务层不依赖 RealData/LastSaveTime 存储布局，字段是否写过用玩家 HasStoredData。
- 异步操作前取得 GetSessionToken，返回后 IsSessionActive 校验原会话；GetState 只返回冻结的标量状态快照，Save(playerId, session) 只保存指定会话。加载、离服、失败恢复与释放由存档管理器负责。购买容量预检用 `GetDataSize(id, session)` 取得 JSON 字节数，编码失败或会话失效返回 nil，不暴露原始表。
- 发奖回滚用玩家 RunDataTransaction(callback)：回调无参数、必须无 yield、成功返回 true，只通过公开接口修改本玩家，不保存、发消息或执行外部副作用。存档快照与回滚留在存档模块；收据去重/元数据和加载失败 GM 恢复走管理器专用接口。
- 修改数据接口时同步维护接口注释、AGENTS.md 和本节；完成后定向检索内部成员，核对所有命中是否局限在存档模块，不能仅把直接访问换个名字隐藏起来。
