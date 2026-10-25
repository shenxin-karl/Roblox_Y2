# 模板文件职责与扩展位置

本页约定当前地图模板的扩展位置。路径相对 `Scripts/`；文件当前是否为空、是否挂载，以源码为准，不为了填满预留入口而增加逻辑。

## 服务端扩展

以下路径位于 `ServerScriptService/Server/`。

| 文件 | 职责与添加位置 |
| --- | --- |
| `Main.server.luau` | 唯一服务端入口。只负责初始化、处理器注册、类加载和实例创建，不写玩法结算或协议实现。 |
| `Player/SPlayerObjectClass.luau` | 项目玩家组合：挂载组件、存档版本迁移、必要的玩家级协作。持久化和 Ready 握手沿用框架，不在登录函数堆积独立玩法。 |
| `Player/SPlayerObjectManagerClass.luau` | 项目协议集中注册一次，按认证身份查找玩家并转发业务。GM 协议由框架注册和鉴权，项目覆写 `HandleGMCommand(userId, action, ...)` 接入命令，不重复注册。 |
| `Player/SMiscCompClass.luau` | 少量没有独立领域归属的玩家逻辑。形成完整玩法或独立状态生命周期时新建对应 `SXXXCompClass`，不要把它当作业务集合。 |
| `Handlers/BuyHandlers.luau` | 按购买处理器名返回 `CanBuy/Buy` 实现，由 Provider 接入框架购买上下文；不接管平台回执。 |
| `Handlers/ItemHandlers.luau` | 按道具处理器名返回 `CanUse/Use` 实现，由框架道具上下文调用；不创建另一套客户端直接发奖入口。 |
| `Handlers/RewardHandlers.luau` | 框架 Item/Money 奖励不能表达时注册项目奖励类型，遵循 `FSRewardCompClass` 的预检与提交约定；先查调用契约，不直接写入档案绕过统一奖励流程。 |
| `Player/SGMCompClass.luau` | 已登录开发者本人的调试操作。当前仅 ResetData/SaveNow；新增命令明确白名单、权限、参数与作用范围，不开放任意字段或代码执行。 |
| `Handlers/SGMRecovery.luau` | 存档加载失败时开发者本人的恢复入口，保留会话锁和支付回执保护；普通业务及正常登录不调用它。 |
| `Player/SItemToolVisual.luau` | 为原生 Tool 创建图片外观。只处理显示实例，不承担道具拥有权、使用效果或奖励。 |
| `Player/SAnalyticsCompClass.luau` | 项目事件口径、漏斗和玩家会话统计。上报复用 `FS.AnalyticsManager`，统计故障不阻断核心业务。 |
| `Service/SPurchaseReceiptService.luau` | 项目购买统计等扩展接入。`MarketplaceService.ProcessReceipt` 只由 `FS.ShopService` 接管，不重复注册、不再创建支付去重和存档流程。 |
| `Service/SRankingServiceClass.luau` | 排行榜请求校验与框架查询转发。启用榜单时同时接入 Provider 的榜单定义；分数由所属业务在服务端更新。 |
| `Config/StorageConfig.luau` | 项目私有的存档名称、测试模式、保存周期和会话锁设置。变更时说明对测试与正式数据的影响，不作为玩法配置表。 |

三个 `Handlers` 表由 Main 注册到 Provider。模板当前为空；按实际功能添加处理器，并先读取对应框架上下文的签名、返回值和禁止 yield 等约束。预留的 `BuyHandlers/ItemHandlers/RewardHandlers` 沿用现有固定名称；新建端专属模块仍遵循 AGENTS.md 的 C/FC/S/FS 命名规则。

## 处理器调用契约

处理器接入前核对以下契约，不能混用三种表的形状：

- ItemHandlers：处理器名对应道具配置 UseHandler，值为对象。调用 `handler:CanUse(context)`、`handler:Use(context)`；context 包含 playerObject、itemObject、itemDataConfig、consumeCount 和 extraData。库存消耗与回滚需核对背包调用点，不能在预检中直接发奖或扣库存。
- BuyHandlers：处理器名对应商品配置 BuyHandler，值为对象。调用 `handler:CanBuy(context)`、`handler:Buy(context)`；context 包含 playerObject、devGoodsId、num、goodsConfig 和 extraData。CanBuy 只预检，支付结算 Buy 不得 yield，成功显式返回 true；不通过客户端购买完成通知发奖。
- RewardHandlers：奖励 Type 对应函数，当前签名是 `handler(rewardComponent, entry, tables)`。它在预检阶段验证条目，将待提交表字段快照写入 tables，字段名对应 PlayerDataConfig，成功返回 true。这里不直接改档、发奖或启动异步任务：预检可能重复，整批仍可能失败，最终提交由 FSRewardComp 负责；当前不支持自定义类型作为消耗。

具体项目处理器仅在服务端注册。写实现前读取 FXItemProcessor、FXBuyProcessor、FSInventoryCompClass 或 FSRewardCompClass 的实际调用点，不把项目处理器 require 到框架共享模块。

## 公共接入

| 文件（相对 `ReplicatedStorage/Scripts/`） | 职责 |
| --- | --- |
| `GameInit.luau` | 两端共用的初始化编排；只加载当前项目需要的配置、Provider 与框架，不恢复旧项目的整套业务加载。 |
| `SetupProvider.luau` | 项目向框架提供配置和处理器的接入边界；字段、道具、商品、管理员和榜单等差异由此提供，不把项目模块 require 写进框架。 |
| `Game/Shared/ProjectConfig.luau` | 手写项目设置，当前提供管理员 UserId 列表。模板默认空名单，新项目显式配置，不复制其他项目账户。客户端可见，不放秘密或服务器私有配置。 |
| `Game/Shared/PlayerDataConfig.luau` | 玩家字段类型、默认值、存档域与同步策略。新增字段在此声明，组件不重复补默认结构；是否迁移由项目存档版本决定。 |
| `Game/Shared/NetworkProtocol.luau` | 初始化前声明项目消息名，模板当前仅声明音量保存。框架已有的 GM、本地化提示、握手、同步、好友和购买预检协议不重复声明。 |

`Game/Configs/` 是生成产物。新增道具、商品和玩法配置通过配置技能操作源 XLSX 后导出，不直接修改生成文件。当前残留生成配置不代表功能已经启用，仍需处理器、组件和服务接入。

通用协议统一声明在 `Framework/FrameworkInit.luau`：`C2S_GMCommand` 由 `FSPlayerObjectManagerClass` 注册，先按认证身份调用 `FX.IsDeveloper` 鉴权，再交给项目覆写的 `HandleGMCommand`；框架默认拒绝未实现命令。项目命令仍需校验参数、所属会话和动作范围，异步返回重新确认会话。

`S2C_ShowLocalizedTips` 由 `FSPlayerObjectClass:ShowLocalizedTips(key, arguments, duration)` 发送，`FCCommonUICompClass` 挂载后自动接收。框架负责翻译、计时、语言刷新和回调清理；项目文案仍在所属脚本用 `FX.Text.Define` 定义，项目玩家或通用 UI 子类无需重复实现收发方法。只在通用 UI 未挂载时不会显示提示，不能把声明协议当作界面已启用。

## 添加功能时的判断

- 状态属于单个玩家：优先新增或扩展对应玩家组件；需要跨玩家共享的地图状态、刷新器或服务放 `Service/`。独立业务不得因为存在空文件就塞入杂项、GM 或统计组件。
- 新类先由 Main require 注册，再由玩家对象 AddComponent 或由 Main 创建服务。启动依赖按实际关系排序；握手前需要的服务必须先于玩家管理器就绪，不依赖目录自动扫描。
- 项目业务使用 `S/C`；跨项目可复用且不依赖项目配置或节点的能力才考虑 `FS/FC/FX`。普通项目功能通过现有 Provider、回调或子类接入；迁移框架仍需用户明确授权。
- 模板预留文件保留不等于功能启用。当前没有项目背包实现，排行榜默认关闭。主界面只保留原生 Tool 装备说明接入；通用 UI 和声音项目子类仍有停用的旧业务，启用前按新需求检查，不批量取消注释。
- `Game/Shared` 的 GameEnum、RankingDataConfig、TutorialGuideConfig 保留为空的项目扩展入口；旧玩法共享模块已经移除。节点查找复用 FX.Loader，不恢复 InstancePath 或另建重复路径工具；包含特殊字符的节点名用原生节点 API 查询。

验证遵循 AGENTS.md：默认编译与同步核对；用户授权试玩时再验证加载、Ready、数据同步和本次功能，不把空入口已加载当成功能已实现。
