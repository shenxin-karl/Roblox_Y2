# 模块落位与启动

目录职责见工作区 AGENTS.md。配置接入由 `ReplicatedStorage/Scripts/SetupProvider.luau` 提供；公共配置放 `ReplicatedStorage/Scripts/Game/Configs/` 或 `ReplicatedStorage/Scripts/Game/Shared/`，私有配置放 `ServerScriptService/Server/Config`。

1. Main 加载 GameInit，SetupProvider 在 FrameworkInit 前加载；FrameworkInit 自动加载当前端 FServer/FClient。
2. 框架基类注册后 require 业务类，再实例化或 AddComponent；业务类不会被自动遍历加载。
3. FServer 初始化存档、排行榜、支付和好友服务。服务端 Main 按依赖初始化项目服务；握手前必需的服务先于玩家管理器创建。管理器登记到 FS.PlayerManager 并开放 Ready，无握手依赖的扩展入口可在其后初始化。
4. 客户端创建玩家对象后调用 FC.WaitServerReady()，等待服务注册和初始数据同步。服务端握手会核对存档加载状态。

FClient 自动启动 FC.NativeBackpack，具体配置行为见 [背包参考](../game-examples/references/reference-inventory-component.md)。

FShared 将框架共享文案工具注册为 `FX.Text`。FClient 统一持有 `FC.Localization`、`FC.ButtonHover` 和 `FC.PickupPrompt`；项目组件不重复初始化或销毁这些全局服务。按钮可通过 `HoverEnabled=false` 排除悬停效果；自定义交互提示只接管 `Style=Custom` 且 `CustomPickup=true` 的 ProximityPrompt，不替代服务端交互校验。

`FCFriendInviteCompClass` 由框架注册，项目按需 AddComponent；挂载后沿用进服 60 秒提醒一次的行为，不自动为所有项目挂载。它使用框架翻译服务，不依赖项目通用 UI。组件类名为 `FCFriendInviteCompClass`，协作名为 `FCFriendInviteComp`。
