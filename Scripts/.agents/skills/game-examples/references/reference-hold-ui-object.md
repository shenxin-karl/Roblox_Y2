# 项目长按封装

FClient 已加载：
- `ReplicatedStorage/Scripts/Framework/Client/FCHoldUIObjectClass.luau`：`FC.HoldUIObjectClass.New(button)`。
- 同目录 `FCKeyObjectClass.luau`：`FC.KeyObjectClass.New(keyCode)`。

两类使用 SetHoldStartCallback、SetHoldCompleteCallback、SetHoldCancelCallback 和 SetProgressCallback；均使用 SetHoldDuration 设置时长，其余方法按具体类实现调用。
隐藏时 StopHold 并按需屏蔽后续输入，析构时调用 Dtor；仅隐藏界面不会禁用键盘长按。

# 场景交互封装

`ReplicatedStorage/Scripts/Framework/Shared/FXProximityPromptObjectClass.luau` 由 FShared 加载：
- `FX.ProximityPromptObjectClass.New(parent)` 创建交互对象。
- SetHoldDuration、SetEnabled 控制交互，SetHoldCompleteCallback 接收 player；传 nil 清除回调。
- GetPrompt 返回原生 ProximityPrompt，文案按 AGENTS.md 本地化规则处理。
- Dtor 清理自建提示与连接，保留 parent；额外连接由调用方清理。

服务端回调仍需校验业务资格和重复操作，Triggered 不证明实际长按时长。
