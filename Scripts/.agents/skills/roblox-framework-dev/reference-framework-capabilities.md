# 框架能力复用索引

本页回答“是否已有这个能力”；项目文件落位统一见 [模板文件职责](reference-template-extension.md)，不重复维护。表中源码路径以 `ReplicatedStorage/Scripts/Framework/` 为基准。只读本次功能相关实现；签名、返回值和挂载状态以当前源码为准。

| 需求 | 优先复用与扩展方式 | 源码定位 |
| --- | --- | --- |
| 道具效果 | 项目 ItemHandlers 接入道具上下文，库存消耗按背包调用流程处理 | `Shared/FXItemProcessor.luau` |
| 购买效果和平台支付 | 项目 BuyHandlers 实现购买效果；收据、去重、保存与重试沿用 ShopService | `Shared/FXBuyProcessor.luau`、`Server/Modules/FSShopService.luau` |
| 奖励、消耗和交换 | 复用 FSRewardComp 预检、容量和余额校验；内置奖励无法表达时才扩展 RewardHandlers | `Server/Player/FSRewardCompClass.luau` |
| 堆叠、容量与库存 | 项目子类提供 GetConfig，复用背包算法；原生 Tool 展示与装备按项目需要接入 | `Server/Player/FSInventoryCompClass.luau`、`Client/FCNativeBackpack.luau` |
| 玩家存档和生命周期 | 继承玩家与管理器基类，复用 KV；不另建保存循环、会话锁或 Ready 握手 | `Server/Player/FSPlayerObjectClass.luau`、`Server/Player/FSPlayerObjectManagerClass.luau`、`Server/PlayerKV/FSPlayerKVDataManager.luau` |
| 同步和订阅 | 玩家字段走 PlayerDataConfig 与 WatchDataChanged，共享状态走 FXSyncManager，不用业务协议复制同一份字段 | `Client/Player/FCPlayerObjectClass.luau`、`Shared/FXSyncManager.luau` |
| 网络消息和 GM | 使用 FX.Network，先查通用协议；GM 通过 HandleGMCommand 扩展 | `Shared/Core/FXNetwork.luau`、`FrameworkInit.luau` |
| 排行榜 | 项目提供榜单定义和权威分数，复用存储、查询与 UI 基类 | `Server/Ranking/FSRankingManager.luau`、`Server/Modules/FSRankingServiceClass.luau`、`Client/Player/FCRankingUICompClass.luau` |
| 好友和邀请 | 复用服务端缓存及好友组件；邀请组件按需挂载，不在每个 UI 单独查询社交列表 | `Server/Modules/FSFriendService.luau`、`Client/Player/FCFriendCompClass.luau`、`Client/Player/FCFriendInviteCompClass.luau` |
| 新手引导 | 项目提供引导定义、字段和业务事件，复用两端引导基类 | `Server/Player/FSTutorialGuideCompClass.luau`、`Client/Player/FCTutorialGuideCompClass.luau` |
| UI 显隐和动画 | 普通组件继承 FCUICompClass，动画使用 FC.UIAnim；Generated 界面按对应技能接入 | `Client/Player/FCUICompClass.luau`、`Client/FCUIAnim.luau` |
| 提示、确认框和道具说明 | 复用通用 UI 与 FCItemDescription，共享 FCUIRoot 的 ScreenGui，只清理自有子节点 | `Client/Player/FCCommonUICompClass.luau`、`Client/FCItemDescription.luau`、`Client/FCUIRoot.luau` |
| 翻译和按钮悬停 | 复用 FX.Text、FC.Localization 和 FC.ButtonHover，不重复初始化或销毁框架全局实例 | `Shared/Core/FXText.luau`、`Client/FCLocalization.luau`、`Client/FCButtonHover.luau` |
| 自定义交互提示 | 复用 FC.PickupPrompt，业务资格仍在服务端校验 | `Client/FCPickupPrompt.luau` |
| 声音、BGM 和音效池 | 项目子类提供曲目和触发，复用声音基类的播放、池与清理 | `Client/Player/FCSoundCompClass.luau` |
| 按键和长按 | 先查输入对象，不为每个按钮复制同类计时逻辑 | `Client/FCKeyObjectClass.luau`、`Client/FCHoldUIObjectClass.luau` |
| 统计上报 | 项目定义统计口径，平台接入复用 FS.AnalyticsManager | `Server/Modules/FSAnalyticsManager.luau` |
| 节点、任务和通用计算 | 节点用 FX.Loader，任务用 FX.Task，先查 Core 的数学、曲线、表和时间工具；数量文案用项目 GameUtility.NumberToText | `Shared/Core/FXLoader.luau`、`Shared/Core/FXTask.luau`、`Shared/Core/FXMath.luau`、`Shared/Core/FXCurveSampler.luau`、`Shared/Core/FXTable.luau`、`Shared/Core/FXTime.luau` |

框架存在类或协议不代表功能已启用。背包需要项目 GetConfig，排行榜需要榜单定义，提示需要挂载通用 UI；先补齐注册、挂载、生命周期和配置接入，不复制实现来绕过缺失步骤。

实现前确定复用入口与项目扩展位置，完成时简述复用了什么。确需新增基础能力时说明现有实现的缺口，仍遵守框架修改授权边界。不自动清理本次需求以外的历史重复代码。

需要完整接法时按 [game-examples](../game-examples/SKILL.md) 路由到对应参考；本页只索引能力，不维护第二份实现示例。
